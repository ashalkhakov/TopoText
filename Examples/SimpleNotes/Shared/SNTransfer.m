/* AppKit before Core Data, as SNRichText.m: gnustep-gui's headers clash otherwise. */
#import "SNRichText.h"
#import "SNTransfer.h"
#import "SNModel.h"
#import "SNMarkdown.h"
#import "SNZip.h"

static NSString * const SNTransferErrorDomain = @"SNTransfer";
static NSString * const SNAttachmentsFolder = @"_attachments";
/* Notes made (or written) between two saves of the transfer's context,
   which is emptied after each: what stays in memory. */
static const NSUInteger SNTransferBatch = 200;

static NSError *SNTransferError(NSString *message) {
    return [NSError errorWithDomain:SNTransferErrorDomain code:1 userInfo:@{ NSLocalizedDescriptionKey: message }];
}

/* A name a file can have: no slashes and the like, not hidden, not too long. */
static NSString *SNFileName(NSString *name) {
    NSCharacterSet *bad = [NSCharacterSet characterSetWithCharactersInString:@"/\\:*?\"<>|\n\r\t"];
    name = [[name componentsSeparatedByCharactersInSet:bad] componentsJoinedByString:@"-"];
    name = [name stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" ."]];
    if (name.length > 100) name = [name substringToIndex:100];
    return name.length ? name : @"Untitled";
}

/* name, or "name 2", "name 3"…: one not taken yet (case aside), now taken. */
static NSString *SNUniqueName(NSString *name, NSString *extension, NSMutableSet<NSString *> *taken) {
    for (NSUInteger k = 1;; k++) {
        NSString *base = k == 1 ? name : [NSString stringWithFormat:@"%@ %lu", name, (unsigned long)k];
        NSString *full = extension.length ? [base stringByAppendingPathExtension:extension] : base;
        if (![taken containsObject:full.lowercaseString]) {
            [taken addObject:full.lowercaseString];
            return full;
        }
    }
}

/* A path as a link has it. */
static NSString *SNLinkPath(NSString *path) {
    NSMutableCharacterSet *allowed = [[NSCharacterSet URLPathAllowedCharacterSet] mutableCopy];
    [allowed removeCharactersInString:@"()"];
    return [path stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: path;
}

static NSString *SNJoin(NSString *dir, NSString *name) {
    return dir.length ? [dir stringByAppendingFormat:@"/%@", name] : name;
}

static NSString *SNStringOfData(NSData *data) {
    NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
                      ?: [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    if ([s hasPrefix:@"﻿"]) s = [s substringFromIndex:1];
    return s ?: @"";
}

static BOOL SNIsNoteFile(NSString *path) {
    NSString *e = path.pathExtension.lowercaseString;
    return [e isEqual:@"md"] || [e isEqual:@"markdown"] || [e isEqual:@"txt"] || [e isEqual:@"html"] || [e isEqual:@"htm"];
}

#pragma mark - Where import reads from

/* A zip's files, or a folder's. */
@interface SNImportSource : NSObject
@property (nonatomic, strong) SNZipReader *zip;
@property (nonatomic, strong) NSURL *folder;
@property (nonatomic, copy) NSString *root;   /* a zip's one top folder, left out */
@end

@implementation SNImportSource

- (NSArray<NSString *> *)paths {
    if (_zip) {
        NSMutableArray *paths = [NSMutableArray array];
        for (NSString *p in _zip.paths) {
            if (_root.length && ![p hasPrefix:_root]) continue;
            NSString *relative = [p substringFromIndex:_root.length];
            if ([relative hasPrefix:@"__MACOSX/"] || [relative.lastPathComponent hasPrefix:@"."]) continue;
            [paths addObject:relative];
        }
        return paths;
    }
    /* By path: GNUstep's URL enumerator has no resource values. */
    NSMutableArray *paths = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *path in [fm enumeratorAtPath:_folder.path]) {
        BOOL hidden = NO, directory = NO;
        for (NSString *c in path.pathComponents) hidden = hidden || [c hasPrefix:@"."];
        if (hidden || ![fm fileExistsAtPath:[_folder.path stringByAppendingPathComponent:path] isDirectory:&directory] || directory) continue;
        [paths addObject:path];
    }
    return paths;
}

- (NSData *)dataAtPath:(NSString *)path {
    if (_zip) return [_zip dataAtPath:[(_root ?: @"") stringByAppendingString:path]];
    return [NSData dataWithContentsOfURL:[_folder URLByAppendingPathComponent:path]];
}

- (NSDate *)dateAtPath:(NSString *)path {
    if (_zip) return [_zip dateAtPath:[(_root ?: @"") stringByAppendingString:path]];
    return [[NSFileManager defaultManager] attributesOfItemAtPath:[_folder.path stringByAppendingPathComponent:path] error:NULL].fileModificationDate;
}

@end

/* A path another links to, from dir: its own (nil: outside, or a URL). */
static NSString *SNResolvePath(NSString *dir, NSString *link) {
    if ([link rangeOfString:@"://"].location != NSNotFound || [link hasPrefix:@"/"] || [link hasPrefix:@"data:"]) return nil;
    NSRange hash = [link rangeOfString:@"#"];
    if (hash.location != NSNotFound) link = [link substringToIndex:hash.location];
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *c in [SNJoin(dir, link) componentsSeparatedByString:@"/"]) {
        if (!c.length || [c isEqual:@"."]) continue;
        if ([c isEqual:@".."]) {
            if (!parts.count) return nil;
            [parts removeLastObject];
        } else {
            [parts addObject:c];
        }
    }
    return parts.count ? [parts componentsJoinedByString:@"/"] : nil;
}

#pragma mark - The transfer

@interface SNTransfer ()
@property (atomic, readwrite) NSUInteger done;
@property (atomic, readwrite) NSUInteger total;
@property (atomic, readwrite, copy) NSString *status;
@property (atomic, readwrite, getter=isFinished) BOOL finished;
@property (atomic, readwrite, getter=isCancelled) BOOL cancelled;
@property (atomic, readwrite, nullable) NSError *error;
@property (atomic, readwrite, copy) NSArray<NSManagedObjectID *> *madeNotes;
@property (atomic, readwrite, copy) NSArray<NSString *> *skipped;
@property (atomic, readwrite, copy) NSString *summary;
/* The note being made (import), for its attachments. */
@property (nonatomic, strong) SNNote *note;
@property (nonatomic, copy) NSString *noteDir;
@property (nonatomic, strong) SNImportSource *source;
- (void)skip:(NSString *)what;
- (SNAttachment *)attachmentOf:(SNNote *)note kind:(NSString *)kind type:(NSString *)type data:(NSData *)data;
@end

/* A note's attachments, as import makes them (the transfer's note). */
@interface SNNoteImporter : NSObject <SNMarkdownImporting>
@property (nonatomic, weak) SNTransfer *transfer;
@end

/* A note's attachments, as export writes them. */
@interface SNNoteExporter : NSObject <SNMarkdownExporting>
@property (nonatomic, weak) SNTransfer *transfer;
@property (nonatomic, copy) NSDictionary<NSString *, SNAttachment *> *attachments;   /* by id */
@property (nonatomic, copy) NSString *dir;    /* the note's folder's path */
@property (nonatomic, copy) NSString *stem;   /* the note's file's name, less .md */
@property (nonatomic, strong) NSDate *date;
@property (nonatomic, strong) NSMutableSet<NSString *> *taken;
@end

@implementation SNTransfer {
    SNNotes *_notes;
    NSPersistentStoreCoordinator *_coordinator;
    NSManagedObjectID *_folderID;      /* import: where into (nil: the top) */
    NSManagedObjectContext *_context;  /* the transfer's own */
    NSUInteger _unsaved;
    NSMutableArray<SNNote *> *_batch;  /* made since the last save */
    NSMutableArray<NSManagedObjectID *> *_made;
    NSMutableArray<NSString *> *_skips;
    NSDate *_reported;
    NSString *_intoName;               /* import: the folder made, or given */
    SNZipWriter *_zip;                 /* export: into a zip, or */
}

+ (instancetype)exportOfNotes:(SNNotes *)notes toURL:(NSURL *)url {
    return [[self alloc] initWithNotes:notes URL:url import:NO folder:nil];
}

+ (instancetype)importIntoNotes:(SNNotes *)notes fromURL:(NSURL *)url folder:(SNFolder *)folder {
    return [[self alloc] initWithNotes:notes URL:url import:YES folder:folder];
}

- (instancetype)initWithNotes:(SNNotes *)notes URL:(NSURL *)url import:(BOOL)import folder:(SNFolder *)folder {
    if (!(self = [super init])) return nil;
    _notes = notes;
    _coordinator = notes.context.persistentStoreCoordinator;
    _URL = [url copy];
    _import = import;
    /* Into a real folder: a smart one's notes are others'. */
    if (folder && ![notes isSmartFolder:folder]) {
        [notes.context obtainPermanentIDsForObjects:@[ folder ] error:NULL];
        _folderID = folder.objectID;
        _intoName = folder.name;
    }
    _batch = [NSMutableArray array];
    _made = [NSMutableArray array];
    _skips = [NSMutableArray array];
    self.status = import ? @"Reading…" : @"Counting the notes…";
    self.summary = @"";
    self.madeNotes = @[];
    self.skipped = @[];
    return self;
}

- (void)start {
    /* What the editors have, written first: it goes out too. */
    if (!_import) [_notes saveAll];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self run];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self finishOnMain];
        });
    });
}

- (BOOL)runAndWait:(NSError **)error {
    if (!_import) [_notes saveAll];
    [self run];
    [self finishOnMain];
    if (error) *error = self.error;
    return self.error == nil;
}

- (void)cancel {
    self.cancelled = YES;
}

- (void)run {
    _context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    _context.persistentStoreCoordinator = _coordinator;
    _context.undoManager = nil;
    [_context performBlockAndWait:^{
        @autoreleasepool {
            if (self->_import) [self runImport];
            else [self runExport];
        }
    }];
    _context = nil;
}

- (void)finishOnMain {
    self.finished = YES;
    self.madeNotes = _made;
    self.skipped = _skips;
    self.summary = [self summaryNow];
    /* What was imported goes to the server: once, now. */
    if (_import && _made.count && _notes.serviceRoot) [_notes sync];
    id<SNTransferDelegate> delegate = _delegate;
    [delegate transferDidFinish:self];
}

- (NSString *)summaryNow {
    NSString *notes = [NSString stringWithFormat:@"%@ note%@", SNCount(self.done), self.done == 1 ? @"" : @"s"];
    NSString *where = _intoName.length ? [NSString stringWithFormat:@" into “%@”", _intoName] : @"";
    NSString *s;
    if (_import) {
        if (self.error) s = [NSString stringWithFormat:@"The import stopped: %@ %@ imported%@ before are kept.", self.error.localizedDescription, notes, where];
        else if (self.cancelled) s = [NSString stringWithFormat:@"Stopped: %@ imported%@ are kept.", notes, where];
        else s = [NSString stringWithFormat:@"%@ imported%@.", [notes stringByReplacingCharactersInRange:NSMakeRange(0, 1) withString:[notes substringToIndex:1].uppercaseString], where];
    } else {
        if (self.error) s = [NSString stringWithFormat:@"The export stopped: %@", self.error.localizedDescription];
        else if (self.cancelled) s = [NSString stringWithFormat:@"Stopped after %@.", notes];
        else s = [NSString stringWithFormat:@"%@ exported to “%@”.", [notes stringByReplacingCharactersInRange:NSMakeRange(0, 1) withString:[notes substringToIndex:1].uppercaseString], _URL.lastPathComponent];
    }
    if (_skips.count) s = [s stringByAppendingFormat:@" %@ left out.", SNCount(_skips.count)];
    return s;
}

#pragma mark progress

- (void)skip:(NSString *)what {
    [_skips addObject:what];
}

/* A note done: told now and then, saved every batch. */
- (BOOL)step {
    self.done = self.done + 1;
    [self report:NO];
    if (++_unsaved >= SNTransferBatch && ![self saveBatch]) return NO;
    return !self.cancelled;
}

- (void)report:(BOOL)now {
    NSDate *date = [NSDate date];
    if (!now && _reported && date.timeIntervalSinceReferenceDate - _reported.timeIntervalSinceReferenceDate < 0.2) return;
    _reported = date;
    NSString *verb = _import ? @"Importing" : @"Exporting";
    self.status = self.total ? [NSString stringWithFormat:@"%@ %@ of %@ notes…", verb, SNCount(self.done), SNCount(self.total)]
                             : [NSString stringWithFormat:@"%@ %@ notes…", verb, SNCount(self.done)];
    dispatch_async(dispatch_get_main_queue(), ^{
        id<SNTransferDelegate> delegate = self->_delegate;
        [delegate transferDidProgress:self];
    });
}

/* What was made, saved; the context emptied (folders are kept by ID). */
- (BOOL)saveBatch {
    _unsaved = 0;
    if (_context.hasChanges) {
        NSError *error = nil;
        if (![_context save:&error]) {
            self.error = error ?: SNTransferError(@"the notes could not be saved.");
            return NO;
        }
    }
    for (SNNote *n in _batch) [_made addObject:n.objectID];
    [_batch removeAllObjects];
    self.note = nil;
    [_context reset];
    return YES;
}

#pragma mark - Export

- (BOOL)write:(NSData *)data at:(NSString *)path date:(NSDate *)date {
    if (_zip) {
        if ([_zip addData:data atPath:path date:date]) return YES;
        self.error = SNTransferError([NSString stringWithFormat:@"“%@” could not be written (is the disk full?).", _URL.lastPathComponent]);
        return NO;
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *file = [_URL URLByAppendingPathComponent:path];
    NSError *error = nil;
    if (![fm createDirectoryAtURL:file.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&error] ||
        ![data writeToURL:file options:NSDataWritingAtomic error:&error]) {
        self.error = error;
        return NO;
    }
    if (date) [fm setAttributes:@{ NSFileModificationDate: date } ofItemAtPath:file.path error:NULL];
    return YES;
}

- (NSPredicate *)notDeleted {
    NSEntityDescription *note = _coordinator.managedObjectModel.entitiesByName[SNNoteEntity];
    return note.attributesByName[@"deletedAt"] ? [NSPredicate predicateWithFormat:@"deletedAt == nil"] : nil;
}

/* The folders (not smart), each one's parent as shown: folders in each
   other round in a circle are cut at the one whose id sorts first, as
   SNNotes does. By ID: name, and the IDs of those in each (nil: the top). */
- (NSDictionary<id<NSCopying>, NSArray<NSManagedObjectID *> *> *)folderTreeNames:(NSMutableDictionary<NSManagedObjectID *, NSString *> *)names {
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:SNFolderEntity];
    NSArray<SNFolder *> *folders = [_context executeFetchRequest:fetch error:NULL] ?: @[];
    NSMutableDictionary<NSManagedObjectID *, SNFolder *> *byID = [NSMutableDictionary dictionary];
    for (SNFolder *f in folders) {
        NSString *filter = f.entity.attributesByName[@"filter"] ? [f valueForKey:@"filter"] : nil;
        if (filter.length) continue;
        byID[f.objectID] = f;
        names[f.objectID] = f.name ?: @"";
    }
    NSMutableDictionary<id<NSCopying>, NSMutableArray *> *children = [NSMutableDictionary dictionary];
    for (SNFolder *f in byID.allValues) {
        SNFolder *parent = f.entity.relationshipsByName[@"parent"] ? [f valueForKey:@"parent"] : nil;
        if (parent && !byID[parent.objectID]) parent = nil;   /* a smart one's: at the top */
        /* In a circle: cut at the one whose id sorts first. */
        if (parent) {
            NSMutableArray *ring = [NSMutableArray arrayWithObject:f];
            SNFolder *up = parent;
            while (up && ![ring containsObject:up]) {
                [ring addObject:up];
                SNFolder *next = up.entity.relationshipsByName[@"parent"] ? [up valueForKey:@"parent"] : nil;
                up = next && byID[next.objectID] ? next : nil;
            }
            if (up == f) {
                SNFolder *first = f;
                for (SNFolder *r in ring)
                    if ([r.id compare:first.id] == NSOrderedAscending) first = r;
                if (first == f) parent = nil;
            }
        }
        id<NSCopying> key = parent ? (id<NSCopying>)parent.objectID : (id<NSCopying>)[NSNull null];
        if (!children[key]) children[key] = [NSMutableArray array];
        [children[key] addObject:f.objectID];
    }
    for (NSMutableArray *list in children.allValues)
        [list sortUsingComparator:^NSComparisonResult(NSManagedObjectID *a, NSManagedObjectID *b) {
            return [names[a] localizedStandardCompare:names[b]];
        }];
    return children;
}

/* A folder's notes (nil: those in none), then its folders. */
- (BOOL)exportFolder:(NSManagedObjectID *)folderID dir:(NSString *)dir tree:(NSDictionary *)tree names:(NSDictionary *)names {
    NSMutableSet *taken = [NSMutableSet setWithObject:SNAttachmentsFolder.lowercaseString];
    NSMutableArray *conditions = [NSMutableArray array];
    [conditions addObject:folderID ? [NSPredicate predicateWithFormat:@"folder == %@", [_context objectWithID:folderID]]
                                   : [NSPredicate predicateWithFormat:@"folder == nil"]];
    if ([self notDeleted]) [conditions addObject:[self notDeleted]];
    /* A page at a time, by id, the context emptied after each. */
    for (NSUInteger offset = 0;; offset += SNTransferBatch) {
        NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:SNNoteEntity];
        fetch.predicate = [NSCompoundPredicate andPredicateWithSubpredicates:conditions];
        fetch.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:@"id" ascending:YES] ];
        fetch.fetchOffset = offset;
        fetch.fetchLimit = SNTransferBatch;
        NSError *error = nil;
        NSArray<SNNote *> *notes = [_context executeFetchRequest:fetch error:&error];
        if (!notes) {
            self.error = error;
            return NO;
        }
        for (SNNote *note in notes) {
            @autoreleasepool {
                NSString *file = SNUniqueName(SNFileName(note.title ?: @""), @"md", taken);
                SNNoteExporter *exporter = [[SNNoteExporter alloc] init];
                exporter.transfer = self;
                NSMutableDictionary *attachments = [NSMutableDictionary dictionary];
                for (SNAttachment *a in note.attachments)
                    if (a.id) attachments[a.id] = a;
                exporter.attachments = attachments;
                exporter.dir = dir;
                exporter.stem = file.stringByDeletingPathExtension;
                exporter.date = note.lastEdited;
                NSString *markdown = SNMarkdownOfText(note.text, exporter);
                if (self.error || ![self write:[markdown dataUsingEncoding:NSUTF8StringEncoding] at:SNJoin(dir, file) date:note.lastEdited]) return NO;
                self.done = self.done + 1;
                [self report:NO];
                if (self.cancelled) return NO;
            }
        }
        [_context reset];
        if (notes.count < SNTransferBatch) break;
    }
    for (NSManagedObjectID *child in tree[folderID ?: [NSNull null]]) {
        NSString *name = SNUniqueName(SNFileName(names[child]), nil, taken);
        if (![self exportFolder:child dir:SNJoin(dir, name) tree:tree names:names]) return NO;
    }
    return YES;
}

- (void)runExport {
    NSFetchRequest *count = [NSFetchRequest fetchRequestWithEntityName:SNNoteEntity];
    count.predicate = [self notDeleted];
    self.total = [_context countForFetchRequest:count error:NULL];
    [self report:YES];
    BOOL zip = [_URL.pathExtension.lowercaseString isEqual:@"zip"];
    NSError *error = nil;
    if (zip) {
        _zip = [[SNZipWriter alloc] initWithURL:_URL error:&error];
        if (!_zip) {
            self.error = error;
            return;
        }
    } else if (![[NSFileManager defaultManager] createDirectoryAtURL:_URL withIntermediateDirectories:YES attributes:nil error:&error]) {
        self.error = error;
        return;
    }
    NSMutableDictionary *names = [NSMutableDictionary dictionary];
    NSDictionary *tree = [self folderTreeNames:names];
    BOOL ok = [self exportFolder:nil dir:@"" tree:tree names:names];
    if (zip) {
        if (ok && ![_zip finish:&error]) {
            self.error = error;
            ok = NO;
        }
        if (!ok) {
            [_zip finish:NULL];
            /* A zip that stopped part way is no good: not left. */
            [[NSFileManager defaultManager] removeItemAtURL:_URL error:NULL];
        }
        _zip = nil;
    }
}

#pragma mark - Import

- (SNFolder *)folderWithID:(NSManagedObjectID *)folderID {
    return folderID ? (SNFolder *)[_context objectWithID:folderID] : nil;
}

/* A folder made, in parent (nil: the top), and saved at once: kept by its
   (permanent) ID while the context is emptied between batches. */
- (NSManagedObjectID *)addFolderNamed:(NSString *)name in:(NSManagedObjectID *)parentID {
    SNFolder *f = [NSEntityDescription insertNewObjectForEntityForName:SNFolderEntity inManagedObjectContext:_context];
    f.id = [NSUUID UUID].UUIDString;
    f.created = [NSDate date];
    f.name = name;
    if (parentID && f.entity.relationshipsByName[@"parent"]) [f setValue:[self folderWithID:parentID] forKey:@"parent"];
    NSError *error = nil;
    if (![_context save:&error]) {
        self.error = error ?: SNTransferError(@"a folder could not be saved.");
        return nil;
    }
    return f.objectID;
}

- (SNNote *)newNoteIn:(NSManagedObjectID *)folderID date:(NSDate *)date {
    SNNote *n = [NSEntityDescription insertNewObjectForEntityForName:SNNoteEntity inManagedObjectContext:_context];
    n.id = [NSUUID UUID].UUIDString;
    n.created = date ?: [NSDate date];
    n.lastEdited = n.created;
    n.title = @"New Note";
    n.body = @"";
    n.pinned = @NO;
    n.folder = [self folderWithID:folderID];
    [_batch addObject:n];
    return n;
}

- (SNAttachment *)attachmentOf:(SNNote *)note kind:(NSString *)kind type:(NSString *)type data:(NSData *)data {
    SNAttachment *a = [NSEntityDescription insertNewObjectForEntityForName:SNAttachmentEntity inManagedObjectContext:_context];
    a.id = [NSUUID UUID].UUIDString;
    a.created = [NSDate date];
    a.kind = kind;
    a.type = type;
    a.data = data;
    a.note = note;
    return a;
}

/* A Markdown (or HTML) file's note. */
- (BOOL)importFile:(NSString *)path title:(NSString *)title into:(NSManagedObjectID *)folderID {
    NSData *data = [_source dataAtPath:path];
    if (!data) {
        [self skip:[NSString stringWithFormat:@"%@: could not be read", path]];
        return !self.cancelled;
    }
    NSString *text = SNStringOfData(data);
    NSString *e = path.pathExtension.lowercaseString;
    if ([e isEqual:@"html"] || [e isEqual:@"htm"]) text = SNMarkdownOfHTML(text);
    SNNote *note = [self newNoteIn:folderID date:[_source dateAtPath:path]];
    self.note = note;
    self.noteDir = path.stringByDeletingLastPathComponent;
    SNNoteImporter *importer = [[SNNoteImporter alloc] init];
    importer.transfer = self;
    note.text = SNTextOfMarkdown(text, title, importer);
    self.note = nil;
    return [self step];
}

/* A code file's note (Trilium's code notes): its title, then the code,
   each line a mono paragraph. */
- (BOOL)importCode:(NSString *)path title:(NSString *)title into:(NSManagedObjectID *)folderID {
    NSData *data = [_source dataAtPath:path];
    if (!data) {
        [self skip:[NSString stringWithFormat:@"%@: could not be read", path]];
        return !self.cancelled;
    }
    SNNote *note = [self newNoteIn:folderID date:[_source dateAtPath:path]];
    TopoText *text = [TopoText textWithReplica:0];
    [text insertString:[title stringByAppendingString:@"\n"] atIndex:0 attributes:@{ SNStyleKey: SNStyleTitle }];
    NSString *code = [SNStringOfData(data) stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    if (code.length) [text insertString:code atIndex:text.length attributes:@{ SNStyleKey: SNStyleMono }];
    note.text = text;
    return [self step];
}

/* A note holding a file (Trilium's image and file notes). */
- (BOOL)importAttachment:(NSString *)path title:(NSString *)title into:(NSManagedObjectID *)folderID {
    SNNote *note = [self newNoteIn:folderID date:[_source dateAtPath:path]];
    self.note = note;
    self.noteDir = @"";
    SNNoteImporter *importer = [[SNNoteImporter alloc] init];
    importer.transfer = self;
    NSString *attachment = [importer attachmentForPath:path title:title image:YES];
    self.note = nil;
    TopoText *text = [TopoText textWithReplica:0];
    [text insertString:title atIndex:0 attributes:@{ SNStyleKey: SNStyleTitle }];
    if (attachment) {
        [text insertString:@"\n" atIndex:text.length attributes:@{ SNStyleKey: SNStyleTitle }];
        [text insertString:@"￼" atIndex:text.length attributes:@{ SNAttachmentKey: attachment }];
    }
    note.text = text;
    return [self step];
}

static NSArray *SNTriliumChildren(NSDictionary *f) {
    NSMutableArray *real = [NSMutableArray array];
    for (NSDictionary *c in [f[@"children"] isKindOfClass:[NSArray class]] ? f[@"children"] : @[])
        if ([c isKindOfClass:[NSDictionary class]] && ![c[@"isClone"] boolValue]) [real addObject:c];
    return real;
}

/* How many notes Trilium's files make. */
static NSUInteger SNTriliumCount(NSArray *files) {
    NSUInteger n = 0;
    for (NSDictionary *f in files) {
        if (![f isKindOfClass:[NSDictionary class]] || [f[@"isClone"] boolValue]) continue;
        NSString *type = f[@"type"];
        if ([f[@"dataFileName"] isKindOfClass:[NSString class]] &&
            ([type isEqual:@"text"] || [type isEqual:@"code"] || [type isEqual:@"image"] || [type isEqual:@"file"])) n++;
        n += SNTriliumCount(SNTriliumChildren(f));
    }
    return n;
}

/* Trilium's export: what its !!!meta.json says, a level of it. */
- (BOOL)importTrilium:(NSArray *)files dir:(NSString *)dir into:(NSManagedObjectID *)folderID {
    NSArray *sorted = [files sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [@([a[@"notePosition"] integerValue]) compare:@([b[@"notePosition"] integerValue])];
    }];
    for (NSDictionary *f in sorted) {
        if (![f isKindOfClass:[NSDictionary class]] || [f[@"isClone"] boolValue]) continue;
        NSString *title = [f[@"title"] isKindOfClass:[NSString class]] && [f[@"title"] length] ? f[@"title"] : @"Untitled";
        NSString *type = f[@"type"];
        NSString *data = [f[@"dataFileName"] isKindOfClass:[NSString class]] ? SNJoin(dir, f[@"dataFileName"]) : nil;
        NSArray *children = SNTriliumChildren(f);
        NSManagedObjectID *target = folderID;
        if (children.count) {
            /* Notes under it: a folder, its own text a note in it. */
            target = [self addFolderNamed:title in:folderID];
            if (!target) return NO;
            NSString *sub = [f[@"dirFileName"] isKindOfClass:[NSString class]] ? SNJoin(dir, f[@"dirFileName"]) : dir;
            if (![self importTrilium:children dir:sub into:target]) return NO;
            if (![type isEqual:@"text"] || !data) continue;
            NSData *own = [_source dataAtPath:data];
            NSString *text = own ? SNStringOfData(own) : @"";
            if ([data.pathExtension.lowercaseString hasPrefix:@"htm"]) text = SNMarkdownOfHTML(text);
            if (![text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length) {
                /* Counted, not made: it is the folder. */
                self.total = self.total > 0 ? self.total - 1 : 0;
                continue;
            }
        }
        BOOL ok = YES;
        if (!data) {
            if (!children.count && [type isEqual:@"book"]) continue;
            if (!children.count) [self skip:[NSString stringWithFormat:@"%@: no file", title]];
            continue;
        }
        if ([type isEqual:@"text"]) ok = [self importFile:data title:title into:target];
        else if ([type isEqual:@"code"]) ok = [self importCode:data title:title into:target];
        else if ([type isEqual:@"image"] || [type isEqual:@"file"]) ok = [self importAttachment:data title:title into:target];
        else [self skip:[NSString stringWithFormat:@"%@: a %@ note, which SimpleNotes has no kind of", title, type ?: @"?"]];
        if (!ok) return NO;
    }
    return YES;
}

/* The folders under dir that have notes in them, somewhere. */
static NSArray<NSString *> *SNSubfoldersWithNotes(NSArray<NSString *> *paths, NSString *dir) {
    NSString *prefix = dir.length ? [dir stringByAppendingString:@"/"] : @"";
    NSMutableOrderedSet *subdirs = [NSMutableOrderedSet orderedSet];
    for (NSString *path in paths) {
        if (prefix.length && ![path hasPrefix:prefix]) continue;
        NSString *rest = [path substringFromIndex:prefix.length];
        NSRange slash = [rest rangeOfString:@"/"];
        if (slash.location == NSNotFound || !SNIsNoteFile(rest)) continue;
        NSString *sub = [rest substringToIndex:slash.location];
        if (![sub isEqual:SNAttachmentsFolder]) [subdirs addObject:sub];
    }
    return [subdirs.array sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}

/* A folder of notes (or a zip of one): its .md files notes, its folders
   with notes in them folders; the rest what notes link to. */
- (BOOL)importFolder:(NSString *)dir paths:(NSArray<NSString *> *)paths into:(NSManagedObjectID *)folderID {
    NSString *prefix = dir.length ? [dir stringByAppendingString:@"/"] : @"";
    NSMutableArray *files = [NSMutableArray array];
    for (NSString *path in paths) {
        if (prefix.length && ![path hasPrefix:prefix]) continue;
        NSString *rest = [path substringFromIndex:prefix.length];
        if ([rest rangeOfString:@"/"].location == NSNotFound && SNIsNoteFile(rest)) [files addObject:path];
    }
    [files sortUsingSelector:@selector(localizedStandardCompare:)];
    for (NSString *path in files)
        if (![self importFile:path title:path.lastPathComponent.stringByDeletingPathExtension into:folderID]) return NO;
    for (NSString *sub in SNSubfoldersWithNotes(paths, dir)) {
        NSManagedObjectID *child = [self addFolderNamed:sub in:folderID];
        if (!child || ![self importFolder:SNJoin(dir, sub) paths:paths into:child]) return NO;
    }
    return YES;
}

- (void)runImport {
    BOOL directory = NO;
    [[NSFileManager defaultManager] fileExistsAtPath:_URL.path isDirectory:&directory];
    SNImportSource *source = [[SNImportSource alloc] init];
    self.source = source;
    NSString *name = _URL.lastPathComponent.stringByDeletingPathExtension;
    if (!directory && SNIsNoteFile(_URL.path)) {
        /* One file: a note, straight in. */
        source.folder = _URL.URLByDeletingLastPathComponent;
        self.total = 1;
        if ([self importFile:_URL.lastPathComponent title:name into:_folderID]) [self saveBatch];
        if (!self.done && !self.error) self.error = SNTransferError([NSString stringWithFormat:@"“%@” could not be read.", _URL.lastPathComponent]);
        return;
    }
    if (directory) {
        source.folder = _URL;
    } else {
        NSError *error = nil;
        NSData *data = [NSData dataWithContentsOfURL:_URL options:NSDataReadingMappedIfSafe error:&error];
        if (!data) {
            self.error = error;
            return;
        }
        source.zip = [[SNZipReader alloc] initWithData:data];
        if (!source.zip) {
            self.error = SNTransferError([NSString stringWithFormat:@"“%@” is not a zip archive, a folder or a Markdown file.", _URL.lastPathComponent]);
            return;
        }
        /* A zip of one folder: that folder's, named after it. */
        NSString *top = nil;
        BOOL one = YES;
        for (NSString *p in source.zip.paths) {
            if ([p hasPrefix:@"__MACOSX/"]) continue;
            NSRange slash = [p rangeOfString:@"/"];
            NSString *first = slash.location == NSNotFound ? nil : [p substringToIndex:slash.location];
            if (!first || (top && ![top isEqual:first])) {
                one = NO;
                break;
            }
            top = first;
        }
        if (one && top) {
            source.root = [top stringByAppendingString:@"/"];
            name = top;
        }
    }
    NSArray<NSString *> *paths = [source paths];
    NSData *meta = [paths containsObject:@"!!!meta.json"] ? [source dataAtPath:@"!!!meta.json"] : nil;
    NSDictionary *trilium = meta ? [NSJSONSerialization JSONObjectWithData:meta options:0 error:NULL] : nil;
    NSArray *files = [trilium isKindOfClass:[NSDictionary class]] && [trilium[@"files"] isKindOfClass:[NSArray class]] ? trilium[@"files"] : nil;
    NSMutableArray *tops = [NSMutableArray array];
    for (NSDictionary *f in files)
        if ([f isKindOfClass:[NSDictionary class]] && ![f[@"isClone"] boolValue]) [tops addObject:f];
    BOOL ok;
    NSManagedObjectID *into = nil;
    if (files) {
        self.total = SNTriliumCount(files);
        [self report:YES];
        if (tops.count == 1 && SNTriliumChildren(tops[0]).count) {
            /* One note and those under it (Trilium exports a subtree so): it
               is the folder, not one more around it. */
            NSString *title = tops[0][@"title"];
            _intoName = [title isKindOfClass:[NSString class]] && title.length ? title : @"Untitled";
            ok = [self importTrilium:tops dir:@"" into:_folderID];
        } else {
            into = [self addFolderNamed:name.length ? name : @"Imported" in:_folderID];
            _intoName = name;
            ok = into && [self importTrilium:files dir:@"" into:into];
        }
    } else {
        NSUInteger n = 0;
        for (NSString *p in paths)
            if (SNIsNoteFile(p) && ![p hasPrefix:[SNAttachmentsFolder stringByAppendingString:@"/"]] &&
                [p rangeOfString:[NSString stringWithFormat:@"/%@/", SNAttachmentsFolder]].location == NSNotFound) n++;
        self.total = n;
        [self report:YES];
        into = [self addFolderNamed:name.length ? name : @"Imported" in:_folderID];
        _intoName = name;
        ok = into && [self importFolder:@"" paths:paths into:into];
    }
    if (ok || self.cancelled) [self saveBatch];
    if (!self.done && !self.error && !self.cancelled) {
        /* Nothing in it: the folder made for it goes again. */
        if (into) {
            [_context deleteObject:[self folderWithID:into]];
            [_context save:NULL];
        }
        self.error = SNTransferError([NSString stringWithFormat:@"“%@” has no notes in it.", _URL.lastPathComponent]);
    }
}

@end

@implementation SNNoteImporter

- (NSString *)attachmentForPath:(NSString *)path title:(NSString *)title image:(BOOL)image {
    SNTransfer *transfer = _transfer;
    NSString *resolved = SNResolvePath(transfer.noteDir, path);
    NSData *data = resolved ? [transfer.source dataAtPath:resolved] : nil;
    if (!data.length) {
        if (resolved) [transfer skip:[NSString stringWithFormat:@"%@: not in the export", resolved]];
        return nil;
    }
    if (data.length > SNAttachmentMaxFileBytes) {
        [transfer skip:[NSString stringWithFormat:@"%@: larger than 25 MB", resolved]];
        return nil;
    }
    NSString *type = nil;
    double w = 0, h = 0;
    NSData *picture = SNImageDataForAttachment(data, &type, &w, &h);
    SNAttachment *a;
    if (picture) {
        a = [transfer attachmentOf:transfer.note kind:SNAttachmentKindImage type:type data:picture];
        a.width = @(w);
        a.height = @(h);
    } else {
        NSString *name = resolved.lastPathComponent;
        a = [transfer attachmentOf:transfer.note kind:SNAttachmentKindFile type:SNTypeOfFileNamed(name) data:data];
        if (a.entity.attributesByName[@"name"]) a.name = name;
    }
    return a.id;
}

- (NSString *)attachmentForTableRows:(NSArray<NSArray<NSString *> *> *)rows {
    NSUInteger columns = 0;
    for (NSArray *row in rows) columns = MAX(columns, row.count);
    if (!rows.count || !columns) return nil;
    TTTable *table = [TTTable tableWithRows:rows.count columns:columns replica:0];
    for (NSUInteger r = 0; r < rows.count; r++)
        for (NSUInteger c = 0; c < rows[r].count; c++)
            if (rows[r][c].length) [[table textAtRow:r column:c] insertString:rows[r][c] atIndex:0 attributes:nil];
    SNTransfer *transfer = _transfer;
    return [transfer attachmentOf:transfer.note kind:SNAttachmentKindTable type:SNTableType data:table.data].id;
}

@end

@implementation SNNoteExporter

- (NSString *)markdownOfAttachment:(NSString *)attachmentID {
    SNAttachment *a = _attachments[attachmentID];
    if (!a.data) return nil;
    if ([a.kind isEqual:SNAttachmentKindTable]) {
        TTTable *table = [TTTable tableWithData:a.data replica:0 error:NULL];
        return table ? SNMarkdownOfTableRows(table.strings) : nil;
    }
    BOOL image = [a.kind isEqual:SNAttachmentKindImage];
    NSString *name = a.entity.attributesByName[@"name"] ? a.name.lastPathComponent : nil;
    NSString *extension = name.pathExtension;
    if (image) {
        name = @"image";
        extension = [a.type isEqual:@"image/png"] ? @"png" : @"jpg";
    }
    if (!name.length) name = @"File";
    if (!_taken) _taken = [NSMutableSet set];
    NSString *file = SNUniqueName(SNFileName(name.stringByDeletingPathExtension), extension, _taken);
    NSString *relative = [NSString stringWithFormat:@"%@/%@/%@", SNAttachmentsFolder, _stem, file];
    SNTransfer *transfer = _transfer;
    if (![transfer write:a.data at:SNJoin(_dir, relative) date:_date]) return nil;
    return image ? [NSString stringWithFormat:@"![](%@)", SNLinkPath(relative)]
                 : [NSString stringWithFormat:@"[%@](%@)", [file stringByReplacingOccurrencesOfString:@"]" withString:@"\\]"], SNLinkPath(relative)];
}

@end
