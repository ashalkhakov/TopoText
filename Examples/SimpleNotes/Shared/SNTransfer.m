/* AppKit before Core Data, as SNRichText.m: gnustep-gui's headers clash otherwise. */
#import "SNRichText.h"
#import "SNTransfer.h"
#import "SNMarkdown.h"
#import "SNZip.h"

static NSString * const SNTransferErrorDomain = @"SNTransfer";
static NSString * const SNAttachmentsFolder = @"_attachments";

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

#pragma mark - Export

/* What export writes: files by path, and when each was last edited. */
@interface SNExport : NSObject
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSData *> *files;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDate *> *dates;
@property (nonatomic, strong) NSMutableArray<NSString *> *order;
@end

@implementation SNExport
- (instancetype)init {
    self = [super init];
    _files = [NSMutableDictionary dictionary];
    _dates = [NSMutableDictionary dictionary];
    _order = [NSMutableArray array];
    return self;
}
- (void)write:(NSData *)data at:(NSString *)path date:(NSDate *)date {
    if (!_files[path]) [_order addObject:path];
    _files[path] = data;
    if (date) _dates[path] = date;
}
@end

/* A note's attachments, as export writes them. */
@interface SNNoteExporter : NSObject <SNMarkdownExporting>
@property (nonatomic, weak) SNNotes *notes;
@property (nonatomic, weak) SNExport *export;
@property (nonatomic, copy) NSString *dir;    /* the note's folder's path */
@property (nonatomic, copy) NSString *stem;   /* the note's file's name, less .md */
@property (nonatomic, strong) NSDate *date;
@property (nonatomic, strong) NSMutableSet<NSString *> *taken;
@end

@implementation SNNoteExporter

- (NSString *)markdownOfAttachment:(NSString *)attachmentID {
    SNNotes *notes = _notes;
    SNAttachment *a = [notes attachmentWithID:attachmentID];
    if (!a.data) return nil;
    if ([a.kind isEqual:SNAttachmentKindTable]) {
        TTTable *table = [notes tableOfAttachment:a];
        return table ? SNMarkdownOfTableRows(table.strings) : nil;
    }
    BOOL image = [a.kind isEqual:SNAttachmentKindImage];
    NSString *name = [a.entity.attributesByName objectForKey:@"name"] ? a.name.lastPathComponent : nil;
    NSString *extension = name.pathExtension;
    if (image) {
        name = @"image";
        extension = [a.type isEqual:@"image/png"] ? @"png" : @"jpg";
    }
    if (!name.length) name = @"File";
    if (!_taken) _taken = [NSMutableSet set];
    NSString *file = SNUniqueName(SNFileName(name.stringByDeletingPathExtension), extension, _taken);
    NSString *relative = [NSString stringWithFormat:@"%@/%@/%@", SNAttachmentsFolder, _stem, file];
    [_export write:a.data at:SNJoin(_dir, relative) date:_date];
    return image ? [NSString stringWithFormat:@"![](%@)", SNLinkPath(relative)]
                 : [NSString stringWithFormat:@"[%@](%@)", [file stringByReplacingOccurrencesOfString:@"]" withString:@"\\]"], SNLinkPath(relative)];
}

@end

#pragma mark - Import

/* Where import reads from: a zip's files, or a folder's. */
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

/* A note's attachments, as import makes them. */
@interface SNNoteImporter : NSObject <SNMarkdownImporting>
@property (nonatomic, weak) SNNotes *notes;
@property (nonatomic, strong) SNNote *note;
@property (nonatomic, strong) SNImportSource *source;
@property (nonatomic, copy) NSString *dir;   /* the note's file's folder */
@end

@implementation SNNoteImporter

- (NSString *)attachmentForPath:(NSString *)path title:(NSString *)title image:(BOOL)image {
    NSString *resolved = SNResolvePath(_dir, path);
    NSData *data = resolved ? [_source dataAtPath:resolved] : nil;
    if (!data.length || data.length > SNAttachmentMaxFileBytes) return nil;
    SNNotes *notes = _notes;
    NSString *type = nil;
    double w = 0, h = 0;
    NSData *picture = SNImageDataForAttachment(data, &type, &w, &h);
    if (picture) return [notes addImageToNote:_note data:picture type:type width:w height:h].id;
    NSString *name = resolved.lastPathComponent;
    return [notes addFileToNote:_note data:data name:name type:SNTypeOfFileNamed(name)].id;
}

- (NSString *)attachmentForTableRows:(NSArray<NSArray<NSString *> *> *)rows {
    NSUInteger columns = 0;
    for (NSArray *row in rows) columns = MAX(columns, row.count);
    if (!rows.count || !columns) return nil;
    SNNotes *notes = _notes;
    SNAttachment *a = [notes addTableToNote:_note rows:rows.count columns:columns];
    TTTable *table = [notes tableOfAttachment:a];
    for (NSUInteger r = 0; r < rows.count; r++) {
        for (NSUInteger c = 0; c < rows[r].count; c++) {
            if (rows[r][c].length) [[table textAtRow:r column:c] insertString:rows[r][c] atIndex:0 attributes:nil];
        }
    }
    if (table) [notes saveTable:table toAttachment:a];
    return a.id;
}

@end

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

@implementation SNNotes (Transfer)

#pragma mark Export

- (void)export:(SNExport *)export folder:(SNFolder *)folder dir:(NSString *)dir {
    NSMutableSet *taken = [NSMutableSet setWithObject:SNAttachmentsFolder.lowercaseString];
    NSMutableArray *notes = [NSMutableArray array];
    for (SNNote *note in [self notesInFolder:folder matching:nil]) {
        if (folder || !note.folder) [notes addObject:note];
    }
    for (SNNote *note in notes) {
        NSString *file = SNUniqueName(SNFileName(note.title ?: @""), @"md", taken);
        SNNoteExporter *exporter = [[SNNoteExporter alloc] init];
        exporter.notes = self;
        exporter.export = export;
        exporter.dir = dir;
        exporter.stem = file.stringByDeletingPathExtension;
        exporter.date = note.lastEdited;
        NSString *markdown = SNMarkdownOfText(note.text, exporter);
        [export write:[markdown dataUsingEncoding:NSUTF8StringEncoding] at:SNJoin(dir, file) date:note.lastEdited];
    }
    for (SNFolder *child in [self foldersInFolder:folder]) {
        if ([self isSmartFolder:child]) continue;
        NSString *name = SNUniqueName(SNFileName(child.name ?: @""), nil, taken);
        [self export:export folder:child dir:SNJoin(dir, name)];
    }
}

- (SNExport *)markdownExport {
    [self saveAll];
    SNExport *export = [[SNExport alloc] init];
    [self export:export folder:nil dir:@""];
    return export;
}

- (NSData *)markdownZip {
    SNExport *export = [self markdownExport];
    SNZipWriter *zip = [[SNZipWriter alloc] init];
    for (NSString *path in export.order) [zip addData:export.files[path] atPath:path date:export.dates[path]];
    return zip.data;
}

- (BOOL)exportMarkdownToURL:(NSURL *)url error:(NSError **)error {
    if ([url.pathExtension.lowercaseString isEqual:@"zip"]) return [self.markdownZip writeToURL:url options:NSDataWritingAtomic error:error];
    SNExport *export = [self markdownExport];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    for (NSString *path in export.order) {
        NSURL *file = [url URLByAppendingPathComponent:path];
        if (![fm createDirectoryAtURL:file.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:error]) return NO;
        if (![export.files[path] writeToURL:file options:NSDataWritingAtomic error:error]) return NO;
        NSDate *date = export.dates[path];
        if (date) [fm setAttributes:@{ NSFileModificationDate: date } ofItemAtPath:file.path error:NULL];
    }
    return YES;
}

#pragma mark Import

- (SNNote *)importNoteTitled:(NSString *)title text:(NSString *)markdown dir:(NSString *)dir
                      source:(SNImportSource *)source folder:(SNFolder *)folder date:(NSDate *)date {
    SNNote *note = [self addNoteInFolder:folder];
    SNNoteImporter *importer = [[SNNoteImporter alloc] init];
    importer.notes = self;
    importer.note = note;
    importer.source = source;
    importer.dir = dir;
    note.text = SNTextOfMarkdown(markdown, title, importer);
    if (date) {
        note.created = date;
        note.lastEdited = date;
    }
    [self save];
    return note;
}

/* A file's note: Markdown, plain text or HTML. */
- (SNNote *)importFile:(NSString *)path title:(NSString *)title source:(SNImportSource *)source folder:(SNFolder *)folder {
    NSData *data = [source dataAtPath:path];
    if (!data) return nil;
    NSString *text = SNStringOfData(data);
    NSString *e = path.pathExtension.lowercaseString;
    if ([e isEqual:@"html"] || [e isEqual:@"htm"]) text = SNMarkdownOfHTML(text);
    return [self importNoteTitled:title text:text dir:path.stringByDeletingLastPathComponent source:source folder:folder date:[source dateAtPath:path]];
}

/* A note of a code file's text (Trilium's code notes): its title, then the
   code, each line a mono paragraph. */
- (SNNote *)importCode:(NSString *)path title:(NSString *)title source:(SNImportSource *)source folder:(SNFolder *)folder {
    NSData *data = [source dataAtPath:path];
    if (!data) return nil;
    SNNote *note = [self addNoteInFolder:folder];
    TopoText *text = [TopoText textWithReplica:0];
    [text insertString:[title stringByAppendingString:@"\n"] atIndex:0 attributes:@{ SNStyleKey: SNStyleTitle }];
    NSString *code = [SNStringOfData(data) stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    if (code.length) [text insertString:code atIndex:text.length attributes:@{ SNStyleKey: SNStyleMono }];
    note.text = text;
    [self save];
    return note;
}

/* A note holding a file (Trilium's image and file notes). */
- (SNNote *)importAttachment:(NSString *)path title:(NSString *)title source:(SNImportSource *)source folder:(SNFolder *)folder {
    SNNote *note = [self addNoteInFolder:folder];
    SNNoteImporter *importer = [[SNNoteImporter alloc] init];
    importer.notes = self;
    importer.note = note;
    importer.source = source;
    importer.dir = @"";
    NSString *attachment = [importer attachmentForPath:path title:title image:YES];
    TopoText *text = [TopoText textWithReplica:0];
    [text insertString:title atIndex:0 attributes:@{ SNStyleKey: SNStyleTitle }];
    if (attachment) {
        [text insertString:@"\n" atIndex:text.length attributes:@{ SNStyleKey: SNStyleTitle }];
        [text insertString:@"￼" atIndex:text.length attributes:@{ SNAttachmentKey: attachment }];
    }
    note.text = text;
    [self save];
    return note;
}

/* Trilium's export: what its !!!meta.json says, a level of it. */
- (void)importTrilium:(NSArray *)files dir:(NSString *)dir source:(SNImportSource *)source
               folder:(SNFolder *)folder into:(NSMutableArray<SNNote *> *)made {
    NSArray *sorted = [files sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [@([a[@"notePosition"] integerValue]) compare:@([b[@"notePosition"] integerValue])];
    }];
    for (NSDictionary *f in sorted) {
        if (![f isKindOfClass:[NSDictionary class]] || [f[@"isClone"] boolValue]) continue;
        NSString *title = [f[@"title"] isKindOfClass:[NSString class]] && [f[@"title"] length] ? f[@"title"] : @"Untitled";
        NSString *type = f[@"type"];
        NSString *data = [f[@"dataFileName"] isKindOfClass:[NSString class]] ? SNJoin(dir, f[@"dataFileName"]) : nil;
        NSArray *children = [f[@"children"] isKindOfClass:[NSArray class]] ? f[@"children"] : @[];
        NSUInteger real = 0;
        for (NSDictionary *c in children) {
            if ([c isKindOfClass:[NSDictionary class]] && ![c[@"isClone"] boolValue]) real++;
        }
        SNFolder *target = folder;
        if (real) {
            /* Notes under it: a folder, its own text a note in it. */
            target = [self addFolderNamed:title inFolder:folder];
            NSString *sub = [f[@"dirFileName"] isKindOfClass:[NSString class]] ? SNJoin(dir, f[@"dirFileName"]) : dir;
            [self importTrilium:children dir:sub source:source folder:target into:made];
            if (![type isEqual:@"text"] || !data) continue;
            NSData *own = [source dataAtPath:data];
            NSString *text = own ? SNStringOfData(own) : @"";
            if ([data.pathExtension.lowercaseString hasPrefix:@"htm"]) text = SNMarkdownOfHTML(text);
            if (![text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length) continue;
        }
        if (!data) continue;
        SNNote *note = nil;
        if ([type isEqual:@"text"]) note = [self importFile:data title:title source:source folder:target];
        else if ([type isEqual:@"code"]) note = [self importCode:data title:title source:source folder:target];
        else if ([type isEqual:@"image"] || [type isEqual:@"file"]) note = [self importAttachment:data title:title source:source folder:target];
        if (note) [made addObject:note];
    }
}

/* A folder of notes (or a zip of one): its .md files notes, its folders
   with notes in them folders; the rest what notes link to. */
- (void)importFolder:(NSString *)dir paths:(NSArray<NSString *> *)paths source:(SNImportSource *)source
              folder:(SNFolder *)folder into:(NSMutableArray<SNNote *> *)made {
    NSString *prefix = dir.length ? [dir stringByAppendingString:@"/"] : @"";
    NSMutableArray *files = [NSMutableArray array];
    NSMutableOrderedSet *subdirs = [NSMutableOrderedSet orderedSet];
    for (NSString *path in paths) {
        if (prefix.length && ![path hasPrefix:prefix]) continue;
        NSString *rest = [path substringFromIndex:prefix.length];
        NSRange slash = [rest rangeOfString:@"/"];
        if (slash.location == NSNotFound) {
            if (SNIsNoteFile(rest)) [files addObject:path];
        } else if (SNIsNoteFile(rest)) {
            /* Only folders with notes somewhere in them. */
            NSString *sub = [rest substringToIndex:slash.location];
            if (![sub isEqual:SNAttachmentsFolder]) [subdirs addObject:sub];
        }
    }
    [files sortUsingSelector:@selector(localizedStandardCompare:)];
    for (NSString *path in files) {
        SNNote *note = [self importFile:path title:path.lastPathComponent.stringByDeletingPathExtension source:source folder:folder];
        if (note) [made addObject:note];
    }
    for (NSString *sub in [subdirs.array sortedArrayUsingSelector:@selector(localizedStandardCompare:)]) {
        SNFolder *child = [self addFolderNamed:sub inFolder:folder];
        [self importFolder:SNJoin(dir, sub) paths:paths source:source folder:child into:made];
    }
}

- (NSArray<SNNote *> *)importFromURL:(NSURL *)url intoFolder:(SNFolder *)folder error:(NSError **)error {
    if ([self isSmartFolder:folder]) folder = nil;
    BOOL directory = NO;
    [[NSFileManager defaultManager] fileExistsAtPath:url.path isDirectory:&directory];
    SNImportSource *source = [[SNImportSource alloc] init];
    NSString *name = url.lastPathComponent.stringByDeletingPathExtension;
    NSMutableArray<SNNote *> *made = [NSMutableArray array];
    if (!directory && SNIsNoteFile(url.path)) {
        /* One file: a note, straight in. */
        source.folder = url.URLByDeletingLastPathComponent;
        SNNote *note = [self importFile:url.lastPathComponent title:name source:source folder:folder];
        if (!note) {
            if (error) *error = SNTransferError([NSString stringWithFormat:@"“%@” could not be read.", url.lastPathComponent]);
            return nil;
        }
        return @[ note ];
    }
    if (directory) {
        source.folder = url;
    } else {
        NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:error];
        if (!data) return nil;
        source.zip = [[SNZipReader alloc] initWithData:data];
        if (!source.zip) {
            if (error) *error = SNTransferError([NSString stringWithFormat:@"“%@” is not a zip archive, a folder or a Markdown file.", url.lastPathComponent]);
            return nil;
        }
        /* A zip of one folder: that folder's. */
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
        if (one && top) source.root = [top stringByAppendingString:@"/"];
    }
    NSArray<NSString *> *paths = [source paths];
    SNFolder *into = [self addFolderNamed:name.length ? name : @"Imported" inFolder:folder];
    NSData *meta = [paths containsObject:@"!!!meta.json"] ? [source dataAtPath:@"!!!meta.json"] : nil;
    NSDictionary *trilium = meta ? [NSJSONSerialization JSONObjectWithData:meta options:0 error:NULL] : nil;
    if ([trilium isKindOfClass:[NSDictionary class]] && [trilium[@"files"] isKindOfClass:[NSArray class]]) {
        [self importTrilium:trilium[@"files"] dir:@"" source:source folder:into into:made];
    } else {
        [self importFolder:@"" paths:paths source:source folder:into into:made];
    }
    if (!made.count) {
        [self deleteFolder:into];
        if (error) *error = SNTransferError([NSString stringWithFormat:@"“%@” has no notes in it.", url.lastPathComponent]);
        return nil;
    }
    return made;
}

@end
