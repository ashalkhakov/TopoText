#import "SNNotes.h"
#import "SNModel.h"
#import "SNResolver.h"

NSNotificationName const SNNotesDidChangeNotification = @"SNNotesDidChange";

NSString *SNDateText(NSDate *date) {
    if (!date) return @"";
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *a = [calendar components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:date];
    NSDateComponents *b = [calendar components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:[NSDate date]];
    BOOL today = a.year == b.year && a.month == b.month && a.day == b.day;
    f.dateStyle = today ? NSDateFormatterNoStyle : NSDateFormatterShortStyle;
    f.timeStyle = today ? NSDateFormatterShortStyle : NSDateFormatterNoStyle;
    return [f stringFromDate:date];
}

@interface SNNoteEditor ()
- (instancetype)initWithNotes:(SNNotes *)notes note:(SNNote *)note;
@end

@interface SNNotes ()
- (void)forgetEditor:(SNNoteEditor *)editor;
@end

@implementation SNNotes {
    NSPersistentStoreCoordinator *_coordinator;
    NSHashTable<SNNoteEditor *> *_editors;
    BOOL _savePending;
    NSTimer *_timer;
}

+ (NSURL *)defaultStoreURLNamed:(NSString *)name {
    NSURL *support = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *dir = [support URLByAppendingPathComponent:name isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    return [dir URLByAppendingPathComponent:@"Notes.sqlite"];
}

- (instancetype)initWithStoreURL:(NSURL *)storeURL error:(NSError **)error {
    return [self initWithStoreURL:storeURL modelURL:nil error:error];
}

- (instancetype)initWithStoreURL:(NSURL *)storeURL modelURL:(NSURL *)modelURL error:(NSError **)error {
    if (!(self = [super init])) return nil;
    NSManagedObjectModel *model = modelURL ? SNModelAt(modelURL) : SNModel();
    if (!model) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadNoSuchFileError
                                            userInfo:@{ NSLocalizedDescriptionKey: @"SimpleNotes.momd is not in the app." }];
        return nil;
    }
    [ODataSyncEngine addBookkeepingToModel:model configuration:nil];
    _coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    /* History: the outbox is read from it, so no change is missed. */
    if (![_coordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL
                                          options:@{ NSPersistentHistoryTrackingKey: @YES } error:error])
        return nil;
    _context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    _context.persistentStoreCoordinator = _coordinator;
    _context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy;
    _engine = [[ODataSyncEngine alloc] initWithCoordinator:_coordinator];
    _engine.resolver = [[SNResolver alloc] init];
    _editors = [NSHashTable weakObjectsHashTable];
    _status = @"Not synced yet.";
    return self;
}

- (void)dealloc {
    [_timer invalidate];
}

- (void)say:(NSString *)status synced:(BOOL)synced {
    _status = [status copy];
    [[NSNotificationCenter defaultCenter] postNotificationName:SNNotesDidChangeNotification object:self
                                                      userInfo:@{ @"status": _status, @"synced": @(synced) }];
}

#pragma mark the server

- (void)setServiceRoot:(NSURL *)serviceRoot {
    if ([serviceRoot isEqual:_serviceRoot]) return;
    for (ODataSyncRemote *r in _engine.remotes) [_engine removeRemote:r];
    _serviceRoot = [serviceRoot copy];
    if (_serviceRoot) {
        ODataSyncRemote *remote = [ODataSyncRemote remoteWithServiceRoot:_serviceRoot];
        if (_transport) remote.transport = _transport;
        if (_configuration) remote.configuration = _configuration;
        [_engine addRemote:remote];
    }
    [self say:_serviceRoot ? [NSString stringWithFormat:@"Syncs with %@.", _serviceRoot.host] : @"On this device only." synced:NO];
}

- (void)setTransport:(id<ODataTransport>)transport {
    _transport = transport;
    for (ODataSyncRemote *r in _engine.remotes) r.transport = transport;
}

- (void)setConfiguration:(ODataConfiguration *)configuration {
    _configuration = configuration;
    for (ODataSyncRemote *r in _engine.remotes) if (configuration) r.configuration = configuration;
}

- (void)setSyncInterval:(NSTimeInterval)syncInterval {
    _syncInterval = syncInterval;
    [_timer invalidate];
    _timer = syncInterval > 0 ? [NSTimer scheduledTimerWithTimeInterval:syncInterval target:self selector:@selector(tick:)
                                                               userInfo:nil repeats:YES] : nil;
}

- (void)tick:(NSTimer *)timer {
    [self sync];
}

- (NSUInteger)pendingCount {
    return _engine.pendingChanges.count;
}

#pragma mark syncing

/* Before a sync: what the editors have, written; what waits, saved. */
- (void)prepareToSync {
    for (SNNoteEditor *e in _editors.allObjects) [e flush];
    [self saveNow];
}

/* After one: the views' objects read again from the store (keeping what
   they changed meanwhile), the editors merged, what waited saved. */
- (void)finishSync:(BOOL)ok result:(ODataSyncResult *)result error:(NSError *)error {
    _syncing = NO;
    for (NSManagedObject *o in _context.registeredObjects.allObjects) [_context refreshObject:o mergeChanges:YES];
    for (SNNoteEditor *e in _editors.allObjects) [e flush];
    if (_savePending) [self saveNow];
    if (!ok) {
        [self say:[NSString stringWithFormat:@"Not synced: %@ Changes wait here.", error.localizedDescription ?: @"no answer."] synced:NO];
        return;
    }
    _lastSync = [NSDate date];
    BOOL moved = result.downloaded || result.removed || result.uploaded;
    NSUInteger waiting = [self pendingCount];
    NSString *status = [NSString stringWithFormat:@"Synced %@.", SNDateText(_lastSync)];
    if (waiting) status = [status stringByAppendingFormat:@" %lu change%@ waiting.", (unsigned long)waiting, waiting == 1 ? @"" : @"s"];
    if (_engine.issues.count) status = [status stringByAppendingFormat:@" %lu refused.", (unsigned long)_engine.issues.count];
    [self say:status synced:moved];
}

- (void)sync {
    if (_syncing || !_serviceRoot) return;
    [self prepareToSync];
    _syncing = YES;
    [self say:@"Syncing…" synced:NO];
    ODataSyncEngine *engine = _engine;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error = nil;
        BOOL ok = [engine syncWithError:&error];
        ODataSyncResult *result = engine.lastResult;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self finishSync:ok result:result error:error];
        });
    });
}

- (BOOL)syncAndWait:(NSError **)error {
    if (_syncing || !_serviceRoot) return NO;
    [self prepareToSync];
    _syncing = YES;
    /* Off this thread, as the engine wants; this one's run loop turning
       meanwhile, for what answers on it. */
    /* Done is said from that thread, not through the main queue: this may
       be running in a block of the main queue's, which drains no other
       until it returns. */
    __block NSError *failure = nil;
    __block BOOL ok = NO;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    ODataSyncEngine *engine = _engine;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *e = nil;
        ok = [engine syncWithError:&e];
        failure = e;
        dispatch_semaphore_signal(done);
    });
    while (dispatch_semaphore_wait(done, DISPATCH_TIME_NOW))
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    [self finishSync:ok result:_engine.lastResult error:failure];
    if (error) *error = failure;
    return ok;
}

#pragma mark reading

- (NSArray *)fetch:(NSString *)entity where:(NSPredicate *)predicate sortedBy:(NSArray *)sort {
    NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:entity];
    f.predicate = predicate;
    f.sortDescriptors = sort;
    return [_context executeFetchRequest:f error:NULL] ?: @[];
}

- (NSArray<SNFolder *> *)folders {
    NSArray *all = [self fetch:SNFolderEntity where:nil sortedBy:nil];
    return [all sortedArrayUsingComparator:^NSComparisonResult(SNFolder *a, SNFolder *b) {
        return [a.name ?: @"" localizedCaseInsensitiveCompare:b.name ?: @""];
    }];
}

- (NSPredicate *)predicateForFolder:(SNFolder *)folder matching:(NSString *)text {
    NSMutableArray *parts = [NSMutableArray array];
    if (folder) [parts addObject:[NSPredicate predicateWithFormat:@"folder == %@", folder]];
    NSString *t = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (t.length) [parts addObject:[NSPredicate predicateWithFormat:@"body CONTAINS[c] %@ OR title CONTAINS[c] %@", t, t]];
    return parts.count ? [NSCompoundPredicate andPredicateWithSubpredicates:parts] : nil;
}

- (NSArray<SNNote *> *)notesInFolder:(SNFolder *)folder matching:(NSString *)text {
    NSArray *notes = [self fetch:SNNoteEntity where:[self predicateForFolder:folder matching:text] sortedBy:nil];
    /* Sorted here: the same on every Core Data, nil dates and all. */
    return [notes sortedArrayUsingComparator:^NSComparisonResult(SNNote *a, SNNote *b) {
        BOOL pa = a.isPinned, pb = b.isPinned;
        if (pa != pb) return pa ? NSOrderedAscending : NSOrderedDescending;
        NSDate *da = a.updated ?: [NSDate distantPast], *db = b.updated ?: [NSDate distantPast];
        return [db compare:da];
    }];
}

- (NSUInteger)countOfNotesInFolder:(SNFolder *)folder {
    NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:SNNoteEntity];
    f.predicate = [self predicateForFolder:folder matching:nil];
    NSUInteger n = [_context countForFetchRequest:f error:NULL];
    return n == NSNotFound ? 0 : n;
}

#pragma mark changing

- (void)saveNow {
    _savePending = NO;
    if (!_context.hasChanges) return;
    NSError *error = nil;
    if (![_context save:&error]) {
        NSLog(@"SimpleNotes: not saved: %@", error);
        [self say:[NSString stringWithFormat:@"Not saved: %@", error.localizedDescription] synced:NO];
        return;
    }
    [self say:_status synced:NO];
    /* A little after a change, it goes to the server. */
    if (_serviceRoot && _syncInterval > 0) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(sync) object:nil];
        [self performSelector:@selector(sync) withObject:nil afterDelay:3];
    }
}

- (void)save {
    if (_syncing) {
        _savePending = YES;
        return;
    }
    [self saveNow];
}

- (void)saveAll {
    for (SNNoteEditor *e in _editors.allObjects) [e flush];
    [self save];
}

- (id)insert:(NSString *)entity {
    NSManagedObject *o = [NSEntityDescription insertNewObjectForEntityForName:entity inManagedObjectContext:_context];
    [o setValue:[NSUUID UUID].UUIDString forKey:@"id"];
    [o setValue:[NSDate date] forKey:@"created"];
    return o;
}

- (SNFolder *)addFolderNamed:(NSString *)name {
    SNFolder *f = [self insert:SNFolderEntity];
    f.name = name;
    [self save];
    return f;
}

- (void)renameFolder:(SNFolder *)folder to:(NSString *)name {
    if ([folder.name isEqual:name]) return;
    folder.name = name;
    [self save];
}

- (void)deleteFolder:(SNFolder *)folder {
    /* Its notes stay: each changed (no folder), and sent so. */
    for (SNNote *n in folder.notes.allObjects) n.folder = nil;
    [_context deleteObject:folder];
    [self save];
}

- (SNNote *)addNoteInFolder:(SNFolder *)folder {
    SNNote *n = [self insert:SNNoteEntity];
    n.updated = n.created;
    n.title = @"New Note";
    n.body = @"";
    n.pinned = @NO;
    n.folder = folder;
    [self save];
    return n;
}

- (void)deleteNote:(SNNote *)note {
    for (SNNoteEditor *e in _editors.allObjects)
        if ([e.noteID isEqual:note.objectID]) [e close];
    [_context deleteObject:note];
    [self save];
}

- (void)setNote:(SNNote *)note pinned:(BOOL)pinned {
    note.pinned = @(pinned);
    [self save];
}

- (void)moveNote:(SNNote *)note toFolder:(SNFolder *)folder {
    note.folder = folder;
    [self save];
}

#pragma mark editing

- (SNNoteEditor *)editorForNote:(SNNote *)note {
    if (note.objectID.isTemporaryID) [self saveNow];
    SNNoteEditor *e = [[SNNoteEditor alloc] initWithNotes:self note:note];
    [_editors addObject:e];
    return e;
}

- (void)forgetEditor:(SNNoteEditor *)editor {
    [_editors removeObject:editor];
}

@end

@implementation SNNoteEditor {
    __weak SNNotes *_notes;
    NSData *_seen;   /* the stored state last merged in */
    BOOL _dirty;
    BOOL _closed;
}

- (instancetype)initWithNotes:(SNNotes *)notes note:(SNNote *)note {
    if (!(self = [super init])) return nil;
    _notes = notes;
    _noteID = note.objectID;
    /* This session's own replica: two editors never write as one. */
    _text = note.text;
    _seen = note.bodyText;
    return self;
}

- (SNNote *)note {
    SNNote *n = (SNNote *)[_notes.context existingObjectWithID:_noteID error:NULL];
    return n.isDeleted ? nil : n;
}

- (void)textDidChange {
    _dirty = YES;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(flush) object:nil];
    [self performSelector:@selector(flush) withObject:nil afterDelay:1];
}

- (void)vanish {
    if (_gone) return;
    _gone = YES;
    [self close];
    if (_didVanish) _didVanish();
}

- (void)flush {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(flush) object:nil];
    SNNotes *notes = _notes;
    if (_closed || !notes) return;
    /* While a sync runs the store is the engine's: what was typed waits in
       the text, and is written after, merged with what came. */
    if (notes.syncing) return;
    SNNote *note = [self note];
    if (!note) {
        [self vanish];
        return;
    }
    NSData *stored = note.bodyText;
    if ([stored isKindOfClass:[NSData class]] && ![stored isEqual:_seen]) {
        NSArray *edits = [_text applyData:stored error:NULL];
        _seen = stored;
        if (edits.count && _didMerge) _didMerge(edits);
    }
    if (!_dirty) return;
    _dirty = NO;
    note.text = _text;
    note.updated = [NSDate date];
    _seen = note.bodyText;
    [notes save];
}

- (void)close {
    if (_closed) return;
    if (!_gone) [self flush];
    _closed = YES;
    [_notes forgetEditor:self];
}

@end
