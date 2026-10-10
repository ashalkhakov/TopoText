#import "SNNotes.h"
#import "SNModel.h"
#import "SNResolver.h"
#import "SNMigration.h"

NSNotificationName const SNNotesDidChangeNotification = @"SNNotesDidChange";
const NSInteger SNRecentlyDeletedDays = 30;
/* Notes deleted for good a save at a time. */
static const NSUInteger SNRemoveBatch = 200;

NSInteger SNDaysLeft(SNNote *note) {
    if (!note.deletedAt) return SNRecentlyDeletedDays;
    NSTimeInterval gone = -[note.deletedAt timeIntervalSinceNow];
    return MAX(0, SNRecentlyDeletedDays - (NSInteger)floor(gone / 86400));
}

static NSString * const SNSortOrderDefaultsKey = @"SNSortOrder";
static NSString * const SNGroupByDateDefaultsKey = @"SNGroupByDate";

/* Pinned first, then by order. */
static NSComparisonResult SNCompareNotes(SNNote *a, SNNote *b, SNSortOrder order) {
    BOOL pa = a.isPinned, pb = b.isPinned;
    if (pa != pb) return pa ? NSOrderedAscending : NSOrderedDescending;
    if (order == SNSortByTitle) {
        NSComparisonResult r = [a.title ?: @"" localizedStandardCompare:b.title ?: @""];
        if (r != NSOrderedSame) return r;
    }
    NSDate *da = (order == SNSortByDateCreated ? a.created : a.lastEdited) ?: [NSDate distantPast];
    NSDate *db = (order == SNSortByDateCreated ? b.created : b.lastEdited) ?: [NSDate distantPast];
    return [db compare:da];
}

static NSInteger SNCompareNotesWithOrder(id a, id b, void *order) {
    return SNCompareNotes(a, b, *(SNSortOrder *)order);
}

static NSArray<SNNote *> *SNSortNotes(NSArray<SNNote *> *notes, SNSortOrder order) {
    /* Sorted here: the same on every Core Data, nil dates and all. */
    NSMutableArray *sorted = [notes mutableCopy];
    [sorted sortUsingFunction:SNCompareNotesWithOrder context:&order];
    return sorted;
}

@implementation SNNoteGroup
- (instancetype)initWithTitle:(NSString *)title notes:(NSArray *)notes {
    if ((self = [super init])) {
        _title = [title copy];
        _notes = [notes copy];
    }
    return self;
}
@end

/* The heading of a date in a list grouped by date, at now. */
static NSString *SNDateGroupTitle(NSDate *date, NSDate *now) {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *c = [cal components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:now];
    NSDate *today = [cal dateFromComponents:c];
    NSDateComponents *back = [[NSDateComponents alloc] init];
    back.day = -1;
    NSDate *yesterday = [cal dateByAddingComponents:back toDate:today options:0];
    back.day = -7;
    NSDate *week = [cal dateByAddingComponents:back toDate:today options:0];
    back.day = -30;
    NSDate *month = [cal dateByAddingComponents:back toDate:today options:0];
    if (!date) return @"Earlier";
    if ([date compare:today] != NSOrderedAscending) return @"Today";
    if ([date compare:yesterday] != NSOrderedAscending) return @"Yesterday";
    if ([date compare:week] != NSOrderedAscending) return @"Previous 7 Days";
    if ([date compare:month] != NSOrderedAscending) return @"Previous 30 Days";
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    NSInteger year = [cal components:NSCalendarUnitYear fromDate:date].year;
    f.dateFormat = year == c.year ? @"LLLL" : @"yyyy";
    return [f stringFromDate:date];
}

/* Where a list grouped by date can change heading (SNDateGroupTitle's
   edges), latest first, down to the year of oldest. */
static NSArray<NSDate *> *SNDateGroupEdges(NSDate *now, NSDate *oldest) {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *c = [cal components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:now];
    NSDate *today = [cal dateFromComponents:c];
    NSMutableArray *edges = [NSMutableArray arrayWithObject:today];
    NSDateComponents *back = [[NSDateComponents alloc] init];
    for (NSNumber *days in @[ @-1, @-7, @-30 ]) {
        back.day = days.integerValue;
        [edges addObject:[cal dateByAddingComponents:back toDate:today options:0]];
    }
    NSDateComponents *first = [[NSDateComponents alloc] init];
    first.day = 1;
    first.year = c.year;
    for (NSInteger month = c.month; month >= 1; month--) {
        first.month = month;
        [edges addObject:[cal dateFromComponents:first]];
    }
    first.month = 1;
    NSInteger last = [cal components:NSCalendarUnitYear fromDate:oldest].year;
    for (NSInteger year = c.year - 1; year >= last; year--) {
        first.year = year;
        [edges addObject:[cal dateFromComponents:first]];
    }
    return [edges sortedArrayUsingComparator:^NSComparisonResult(NSDate *a, NSDate *b) {
        return [b compare:a];
    }];
}

NSArray<SNNoteGroup *> *SNGroupNotes(NSArray<SNNote *> *notes, SNSortOrder order, BOOL byDate, NSDate *now) {
    NSArray *sorted = SNSortNotes(notes, order);
    NSMutableArray *groups = [NSMutableArray array];
    NSMutableArray *pinned = [NSMutableArray array], *rest = [NSMutableArray array];
    for (SNNote *n in sorted) [(n.isPinned ? pinned : rest) addObject:n];
    if (pinned.count) [groups addObject:[[SNNoteGroup alloc] initWithTitle:@"Pinned" notes:pinned]];
    if (!byDate || order == SNSortByTitle) {
        if (rest.count) [groups addObject:[[SNNoteGroup alloc] initWithTitle:pinned.count ? @"Notes" : nil notes:rest]];
        return groups;
    }
    NSString *title = nil;
    NSMutableArray *group = nil;
    for (SNNote *n in rest) {
        NSString *t = SNDateGroupTitle(order == SNSortByDateCreated ? n.created : n.lastEdited, now);
        if (![t isEqualToString:title]) {
            if (group.count) [groups addObject:[[SNNoteGroup alloc] initWithTitle:title notes:group]];
            title = t;
            group = [NSMutableArray array];
        }
        [group addObject:n];
    }
    if (group.count) [groups addObject:[[SNNoteGroup alloc] initWithTitle:title notes:group]];
    return groups;
}

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

@interface SNNotes () <ODataSyncDelegate>
- (void)forgetEditor:(SNNoteEditor *)editor;
@end

@implementation SNNotes {
    NSPersistentStoreCoordinator *_coordinator;
    NSHashTable<SNNoteEditor *> *_editors;
    BOOL _deletes;   /* the model has Recently Deleted (version 2 on) */
    BOOL _nests;     /* the model has folders in folders (version 3 on) */
    BOOL _attaches;  /* the model has attachments (version 4 on) */
    BOOL _five;      /* smart folders, a folder's order, files (version 5 on) */
    BOOL _savePending;
    /* Whom the sync running is with, in its status (nil: the server). */
    NSString *_syncingWith;
    /* A sync asked for while one ran: what changed meanwhile, sent after. */
    BOOL _syncAgain;
    /* Saved by another context of the store's, not shown yet. */
    BOOL _changedElsewhere;
    /* Notes being deleted for good, off the main thread; all of Recently
       Deleted's (emptying). */
    NSUInteger _removing;
    BOOL _emptying;
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
    /* An older version's store, brought to this one, history and all. */
    NSURL *momd = modelURL ?: SNModelURLInBundle([NSBundle mainBundle]);
    if ([momd.pathExtension isEqual:@"momd"] &&
        !SNMigrateStore(storeURL, momd, [ODataSyncEngine class], error))
        return nil;
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
    NSEntityDescription *note = model.entitiesByName[SNNoteEntity];  /* typed: FreeCoreData's dictionaries are not */
    _deletes = [note.attributesByName objectForKey:@"deletedAt"] != nil;
    NSEntityDescription *folderEntity = model.entitiesByName[SNFolderEntity];
    _nests = [folderEntity.relationshipsByName objectForKey:@"parent"] != nil;
    _attaches = [model.entitiesByName objectForKey:SNAttachmentEntity] != nil;
    _five = [folderEntity.attributesByName objectForKey:@"filter"] != nil;
    _engine = [[ODataSyncEngine alloc] initWithCoordinator:_coordinator];
    _engine.delegate = self;
    _engine.resolver = [[SNResolver alloc] init];
    /* The note's text moves as deltas (a merged attribute). */
    SNRegisterMergers(_engine);
    _editors = [NSHashTable weakObjectsHashTable];
    _status = @"Not synced yet.";
    /* Written by others on this store (a peer, through the peer server):
       shown as a sync's would be. */
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(storeDidSave:)
                                                 name:NSManagedObjectContextDidSaveNotification object:nil];
    [self removeExpiredNotes];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_timer invalidate];
}

- (void)say:(NSString *)status synced:(BOOL)synced {
    [self say:status synced:synced edited:nil];
}

/* A save of notes' text alone (edited): those notes' IDs said with it. */
- (void)say:(NSString *)status synced:(BOOL)synced edited:(NSSet<NSManagedObjectID *> *)edited {
    _status = [status copy];
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithDictionary:@{ @"status": _status, @"synced": @(synced) }];
    if (edited) info[@"edited"] = edited;
    [[NSNotificationCenter defaultCenter] postNotificationName:SNNotesDidChangeNotification object:self userInfo:info];
}

/* The status alone changed (a sync begun, how far it is): nothing for
   the views to read again. */
- (void)sayOnly:(NSString *)status {
    _status = [status copy];
    [[NSNotificationCenter defaultCenter] postNotificationName:SNNotesDidChangeNotification object:self
                                                      userInfo:@{ @"status": _status, @"synced": @NO, @"statusOnly": @YES }];
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
    _syncingWith = nil;
    for (NSManagedObject *o in _context.registeredObjects.allObjects) [_context refreshObject:o mergeChanges:YES];
    for (SNNoteEditor *e in _editors.allObjects) [e flush];
    if (_savePending) [self saveNow];
    [self removeExpiredNotes];
    BOOL again = _syncAgain;
    _syncAgain = NO;
    if (!ok) {
        [self say:[NSString stringWithFormat:@"Not synced: %@ Changes wait here.", error.localizedDescription ?: @"no answer."] synced:NO];
        return;
    }
    _lastSync = [NSDate date];
    BOOL moved = result.downloaded || result.removed || result.uploaded;
    /* Nothing came: nothing here to read again. */
    BOOL came = result.downloaded || result.removed || result.conflicts;
    NSUInteger waiting = [self pendingCount];
    NSString *status = [NSString stringWithFormat:@"Synced %@.", SNDateText(_lastSync)];
    if (waiting) status = [status stringByAppendingFormat:@" %lu change%@ waiting.", (unsigned long)waiting, waiting == 1 ? @"" : @"s"];
    if (_engine.issues.count) status = [status stringByAppendingFormat:@" %lu refused.", (unsigned long)_engine.issues.count];
    if (came) [self say:status synced:moved];
    else [self sayOnly:status];
    if (again) [self sync];
}

/* How far the sync is, in its status: "Sending 3,000 of 25,000 changes…".
   Told on the engine's thread; said on the main one, while it runs. */
- (void)syncEngine:(ODataSyncEngine *)engine didProgress:(ODataSyncProgress *)progress {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self->_syncing) return;
        NSString *what = nil;
        switch (progress.phase) {
            case ODataSyncPhaseReceiving:
                if (progress.completed) what = [NSString stringWithFormat:@"Receiving changes: %@ so far…", SNCount(progress.completed)];
                break;
            case ODataSyncPhaseSending:
                if (progress.total) what = [NSString stringWithFormat:@"Sending %@ of %@ changes…", SNCount(progress.completed), SNCount(progress.total)];
                break;
            case ODataSyncPhaseMerging:
                if (progress.total) what = [NSString stringWithFormat:@"Merging %@ of %@ notes' text…", SNCount(progress.completed), SNCount(progress.total)];
                break;
        }
        if (!what) return;
        if (self->_syncingWith) what = [NSString stringWithFormat:@"With %@: %@", self->_syncingWith, what];
        [self sayOnly:what];
    });
}

- (ODataSyncRemote *)serverRemote {
    return _serviceRoot ? _engine.remotes.firstObject : nil;
}

#pragma mark written elsewhere

/* On the saving context's thread: only another context of this store's,
   and only for the notes' own entities (not the engine's bookkeeping). */
- (void)storeDidSave:(NSNotification *)n {
    NSManagedObjectContext *saved = n.object;
    if (saved == _context || saved.persistentStoreCoordinator != _coordinator) return;
    BOOL ours = NO;
    for (NSString *key in @[ NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey ])
        for (NSManagedObject *o in n.userInfo[key])
            if ([@[ SNNoteEntity, SNFolderEntity, SNAttachmentEntity ] containsObject:o.entity.name]) ours = YES;
    if (!ours) return;
    /* Once for many saves close together. */
    @synchronized (self) {
        if (_changedElsewhere) return;
        _changedElsewhere = YES;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [self performSelector:@selector(showChangesMadeElsewhere) withObject:nil afterDelay:0.1];
    });
}

- (void)showChangesMadeElsewhere {
    @synchronized (self) {
        _changedElsewhere = NO;
    }
    /* A sync of ours shows them when it finishes. */
    if (_syncing) return;
    for (NSManagedObject *o in _context.registeredObjects.allObjects) [_context refreshObject:o mergeChanges:YES];
    for (SNNoteEditor *e in _editors.allObjects) [e flush];
    [self say:_status synced:YES];
}

#pragma mark syncing one remote

- (BOOL)syncWithRemote:(ODataSyncRemote *)remote named:(NSString *)name {
    if (_syncing) return NO;
    [self prepareToSync];
    _syncing = YES;
    _syncingWith = [name copy];
    [self sayOnly:[NSString stringWithFormat:@"Syncing with %@…", name]];
    ODataSyncEngine *engine = _engine;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error = nil;
        BOOL ok = [engine syncWithRemote:remote error:&error];
        ODataSyncResult *result = engine.lastResult;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self finishSync:ok result:result error:error];
        });
    });
    return YES;
}

- (BOOL)syncWithRemote:(ODataSyncRemote *)remote andWait:(NSError **)error {
    if (_syncing) return NO;
    [self prepareToSync];
    _syncing = YES;
    __block NSError *failure = nil;
    __block BOOL ok = NO;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    ODataSyncEngine *engine = _engine;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *e = nil;
        ok = [engine syncWithRemote:remote error:&e];
        failure = e;
        dispatch_semaphore_signal(done);
    });
    while (dispatch_semaphore_wait(done, DISPATCH_TIME_NOW))
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    [self finishSync:ok result:_engine.lastResult error:failure];
    if (error) *error = failure;
    return ok;
}

#pragma mark syncing the server

- (void)sync {
    if (!_serviceRoot) return;
    if (_syncing) {
        _syncAgain = YES;
        return;
    }
    [self prepareToSync];
    _syncing = YES;
    _syncingWith = nil;
    [self sayOnly:@"Syncing…"];
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

/* The notes the predicate takes, sorted by the store: their IDs alone
   read, each note a fault until it is shown. */
- (NSArray<SNNote *> *)faultsOf:(NSPredicate *)predicate sortedBy:(NSArray *)sort {
    NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:SNNoteEntity];
    f.predicate = predicate;
    f.sortDescriptors = sort;
    f.resultType = NSManagedObjectIDResultType;
    NSMutableArray *notes = [NSMutableArray array];
    for (NSManagedObjectID *i in [_context executeFetchRequest:f error:NULL] ?: @[]) [notes addObject:[_context objectWithID:i]];
    return notes;
}

- (NSString *)editedKey {
    NSEntityDescription *note = _coordinator.managedObjectModel.entitiesByName[SNNoteEntity];
    return note.attributesByName[@"edited"] ? @"edited" : @"updated";
}

- (NSArray<SNFolder *> *)folders {
    NSArray *all = [self fetch:SNFolderEntity where:nil sortedBy:nil];
    return [all sortedArrayUsingComparator:^NSComparisonResult(SNFolder *a, SNFolder *b) {
        return [a.name ?: @"" localizedCaseInsensitiveCompare:b.name ?: @""];
    }];
}

- (NSPredicate *)predicateForFolder:(SNFolder *)folder matching:(NSString *)text deleted:(BOOL)deleted {
    NSMutableArray *parts = [NSMutableArray array];
    if (_deletes) [parts addObject:[NSPredicate predicateWithFormat:deleted ? @"deletedAt != nil" : @"deletedAt == nil"]];
    else if (deleted) return [NSPredicate predicateWithValue:NO];
    if (folder) [parts addObject:[NSPredicate predicateWithFormat:@"folder == %@", folder]];
    NSString *t = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (t.length) [parts addObject:[NSPredicate predicateWithFormat:@"body CONTAINS[c] %@ OR title CONTAINS[c] %@", t, t]];
    return parts.count ? [NSCompoundPredicate andPredicateWithSubpredicates:parts] : nil;
}

- (NSArray<SNNote *> *)notesInFolder:(SNFolder *)folder matching:(NSString *)text {
    SNSmartFilter *filter = folder ? [self filterOfFolder:folder] : nil;
    if (filter) {
        /* Every note, then those its rules take. */
        NSDate *now = [NSDate date];
        NSMutableArray *taken = [NSMutableArray array];
        for (SNNote *n in [self fetch:SNNoteEntity where:[self predicateForFolder:nil matching:text deleted:NO] sortedBy:nil])
            if ([filter matchesNote:n now:now]) [taken addObject:n];
        return SNSortNotes(taken, [self sortOrderForFolder:folder]);
    }
    return SNSortNotes([self fetch:SNNoteEntity where:[self predicateForFolder:folder matching:text deleted:NO] sortedBy:nil],
                       [self sortOrderForFolder:folder]);
}

#pragma mark smart folders

- (SNFolder *)addSmartFolderNamed:(NSString *)name filter:(SNSmartFilter *)filter inFolder:(SNFolder *)parent {
    SNFolder *f = [self addFolderNamed:name inFolder:[self isSmartFolder:parent] ? nil : parent];
    [self setFilter:filter ofFolder:f];
    return f;
}

- (SNSmartFilter *)filterOfFolder:(SNFolder *)folder {
    return _five ? [SNSmartFilter filterWithString:folder.filter] : nil;
}

- (void)setFilter:(SNSmartFilter *)filter ofFolder:(SNFolder *)folder {
    NSString *s = filter.string;
    if (!_five || [folder.filter isEqual:s]) return;
    folder.filter = s;
    [self save];
}

- (BOOL)isSmartFolder:(SNFolder *)folder {
    return folder && [self filterOfFolder:folder] != nil;
}

#pragma mark folders in folders

- (SNFolder *)parentOfFolder:(SNFolder *)folder {
    if (!_nests) return nil;
    SNFolder *parent = folder.parent;
    if (!parent || parent.isDeleted) return nil;
    /* On a circle? Then cut at the folder whose id sorts first. */
    NSMutableArray<SNFolder *> *circle = [NSMutableArray arrayWithObject:folder];
    for (SNFolder *f = parent; f; f = f.parent) {
        if (f == folder) {
            SNFolder *first = folder;
            for (SNFolder *c in circle)
                if ([c.id ?: @"" compare:first.id ?: @""] == NSOrderedAscending) first = c;
            return first == folder ? nil : parent;
        }
        /* Into a circle it is not on. */
        if ([circle containsObject:f]) break;
        [circle addObject:f];
    }
    return parent;
}

- (NSUInteger)depthOfFolder:(SNFolder *)folder {
    NSUInteger depth = 0;
    for (SNFolder *f = [self parentOfFolder:folder]; f; f = [self parentOfFolder:f]) depth++;
    return depth;
}

- (BOOL)folder:(SNFolder *)folder isInFolder:(SNFolder *)ancestor {
    for (SNFolder *f = [self parentOfFolder:folder]; f; f = [self parentOfFolder:f])
        if (f == ancestor) return YES;
    return NO;
}

/* Every folder by the folder it is in, as shown (NSNull: the top), by
   name: one fetch, and each folder's parent found once. (Asked of each
   folder in turn, as each level of a tree is, it was a fetch of every
   folder each time: with hundreds, seconds, and on FreeCoreData hundreds
   of MB allocated and freed.) */
- (NSDictionary<id<NSCopying>, NSArray<SNFolder *> *> *)foldersByParent {
    NSMutableDictionary *children = [NSMutableDictionary dictionary];
    for (SNFolder *f in [self folders]) {
        SNFolder *parent = [self parentOfFolder:f];
        id key = parent ? (id)parent.objectID : (id)[NSNull null];
        NSMutableArray *in = children[key] ?: (children[key] = [NSMutableArray array]);
        [in addObject:f];
    }
    return children;
}

- (NSArray<SNFolder *> *)foldersInFolder:(SNFolder *)folder {
    return [self foldersByParent][folder ? (id)folder.objectID : (id)[NSNull null]] ?: @[];
}

- (void)addTreeOf:(SNFolder *)folder from:(NSDictionary *)children to:(NSMutableArray *)tree {
    for (SNFolder *f in children[folder ? (id)folder.objectID : (id)[NSNull null]]) {
        [tree addObject:f];
        [self addTreeOf:f from:children to:tree];
    }
}

- (NSArray<SNFolder *> *)folderTree {
    NSMutableArray *tree = [NSMutableArray array];
    [self addTreeOf:nil from:[self foldersByParent] to:tree];
    return tree;
}

#pragma mark tags

- (NSDictionary<NSString *, NSNumber *> *)tagCounts {
    NSMutableDictionary *counts = [NSMutableDictionary dictionary];
    for (SNNote *n in [self fetch:SNNoteEntity where:[self predicateForFolder:nil matching:@"#" deleted:NO] sortedBy:nil])
        for (NSString *tag in [NSSet setWithArray:SNTagsInText(n.body ?: @"")]) counts[tag] = @([counts[tag] unsignedIntegerValue] + 1);
    return counts;
}

- (NSArray<NSString *> *)tags {
    return [[self tagCounts].allKeys sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}

- (NSArray<SNNote *> *)notesTagged:(NSString *)tag matching:(NSString *)text {
    tag = tag.lowercaseString;
    NSPredicate *base = [self predicateForFolder:nil matching:text deleted:NO];
    NSPredicate *mentions = [NSPredicate predicateWithFormat:@"body CONTAINS[c] %@", [@"#" stringByAppendingString:tag]];
    NSPredicate *where = base ? [NSCompoundPredicate andPredicateWithSubpredicates:@[ base, mentions ]] : mentions;
    NSMutableArray *tagged = [NSMutableArray array];
    for (SNNote *n in [self fetch:SNNoteEntity where:where sortedBy:nil])
        if ([SNTagsInText(n.body ?: @"") containsObject:tag]) [tagged addObject:n];
    return SNSortNotes(tagged, self.sortOrder);
}

- (NSUInteger)countOfNotesTagged:(NSString *)tag {
    return [[self tagCounts][tag.lowercaseString] unsignedIntegerValue];
}

#pragma mark sorting and grouping

- (SNSortOrder)sortOrder {
    NSInteger order = [[NSUserDefaults standardUserDefaults] integerForKey:SNSortOrderDefaultsKey];
    return order >= SNSortByDateEdited && order <= SNSortByTitle ? (SNSortOrder)order : SNSortByDateEdited;
}

- (void)setSortOrder:(SNSortOrder)order {
    [[NSUserDefaults standardUserDefaults] setInteger:order forKey:SNSortOrderDefaultsKey];
    [self say:_status synced:NO];
}

- (BOOL)groupsByDate {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:SNGroupByDateDefaultsKey];
    return v ? [v boolValue] : YES;
}

- (void)setGroupsByDate:(BOOL)groups {
    [[NSUserDefaults standardUserDefaults] setBool:groups forKey:SNGroupByDateDefaultsKey];
    [self say:_status synced:NO];
}

- (BOOL)movesCheckedToBottom {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"SNMoveCheckedToBottom"];
}

- (void)setMovesCheckedToBottom:(BOOL)moves {
    [[NSUserDefaults standardUserDefaults] setBool:moves forKey:@"SNMoveCheckedToBottom"];
}

- (NSArray<SNNoteGroup *> *)groupsOfNotes:(NSArray<SNNote *> *)notes {
    return SNGroupNotes(notes, self.sortOrder, self.groupsByDate, [NSDate date]);
}

- (NSArray<SNNoteGroup *> *)groupsOfNotes:(NSArray<SNNote *> *)notes sortedBy:(SNSortOrder)order {
    return SNGroupNotes(notes, order, self.groupsByDate, [NSDate date]);
}

- (NSNumber *)sortOrderOfFolder:(SNFolder *)folder {
    if (!_five || !folder) return nil;
    NSNumber *order = folder.sortOrder;
    NSInteger o = order.integerValue;
    return order && o >= SNSortByDateEdited && o <= SNSortByTitle ? order : nil;
}

- (void)setSortOrder:(NSNumber *)order ofFolder:(SNFolder *)folder {
    if (!_five || !folder || order == folder.sortOrder || [order isEqual:folder.sortOrder]) return;
    folder.sortOrder = order;
    [self save];
}

- (SNSortOrder)sortOrderForFolder:(SNFolder *)folder {
    NSNumber *own = folder ? [self sortOrderOfFolder:folder] : nil;
    return own ? (SNSortOrder)own.integerValue : self.sortOrder;
}

- (NSUInteger)count:(NSPredicate *)predicate {
    NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:SNNoteEntity];
    f.predicate = predicate;
    NSUInteger n = [_context countForFetchRequest:f error:NULL];
    return n == NSNotFound ? 0 : n;
}

static NSPredicate *SNAnd(NSPredicate *a, NSPredicate *b) {
    return a ? [NSCompoundPredicate andPredicateWithSubpredicates:@[ a, b ]] : b;
}

- (NSArray<SNNoteGroup *> *)groupsInFolder:(SNFolder *)folder tag:(NSString *)tag matching:(NSString *)text {
    SNSortOrder order = [self sortOrderForFolder:tag ? nil : folder];
    if (tag || order == SNSortByTitle || [self isSmartFolder:folder])
        return [self groupsOfNotes:tag ? [self notesTagged:tag matching:text] : [self notesInFolder:folder matching:text] sortedBy:order];
    /* Sorted as SNCompareNotes sorts: the pinned, then the rest, each the
       latest first (the store puts no date last, as distantPast). */
    NSString *key = order == SNSortByDateCreated ? @"created" : [self editedKey];
    NSArray *sort = @[ [NSSortDescriptor sortDescriptorWithKey:key ascending:NO] ];
    NSPredicate *base = [self predicateForFolder:folder matching:text deleted:NO];
    NSArray *pinned = [self faultsOf:SNAnd(base, [NSPredicate predicateWithFormat:@"pinned == YES"]) sortedBy:sort];
    NSPredicate *unpinned = SNAnd(base, [NSPredicate predicateWithFormat:@"pinned == nil OR pinned == NO"]);
    NSArray *rest = [self faultsOf:unpinned sortedBy:sort];
    NSMutableArray *groups = [NSMutableArray array];
    if (pinned.count) [groups addObject:[[SNNoteGroup alloc] initWithTitle:@"Pinned" notes:pinned]];
    if (!self.groupsByDate) {
        if (rest.count) [groups addObject:[[SNNoteGroup alloc] initWithTitle:pinned.count ? @"Notes" : nil notes:rest]];
        return groups;
    }
    /* Where each heading's notes end: found by halves, a few notes read
       for it (let go again after). Neighbours of one heading are one. */
    NSMutableArray *read = [NSMutableArray array];
    NSUInteger dated = [self indexIn:rest from:0 key:key before:nil read:read];
    NSDate *now = [NSDate date];
    NSString *title = nil;
    NSUInteger start = 0, end = 0;
    if (dated) {
        NSDate *oldest = [self dateOf:rest[dated - 1] key:key read:read];
        for (NSDate *edge in SNDateGroupEdges(now, oldest)) {
            NSUInteger upTo = [self indexIn:rest from:end key:key before:edge read:read];
            if (upTo <= end) continue;
            NSString *t = SNDateGroupTitle(edge, now);
            if (![t isEqualToString:title]) {
                if (end > start) [groups addObject:[[SNNoteGroup alloc] initWithTitle:title notes:[rest subarrayWithRange:NSMakeRange(start, end - start)]]];
                title = t;
                start = end;
            }
            end = upTo;
        }
        if (end > start) [groups addObject:[[SNNoteGroup alloc] initWithTitle:title notes:[rest subarrayWithRange:NSMakeRange(start, end - start)]]];
    }
    if (rest.count > dated)
        [groups addObject:[[SNNoteGroup alloc] initWithTitle:SNDateGroupTitle(nil, now) notes:[rest subarrayWithRange:NSMakeRange(dated, rest.count - dated)]]];
    for (NSManagedObject *o in read) [_context refreshObject:o mergeChanges:NO];
    return groups;
}

/* A note's date, read; a fault read for it, kept to be let go. */
- (NSDate *)dateOf:(SNNote *)note key:(NSString *)key read:(NSMutableArray *)read {
    if (note.isFault) [read addObject:note];
    return [note valueForKey:key];
}

/* In notes sorted latest first (no date last), from start on: the first
   whose date is before edge (nil: the first with none). */
- (NSUInteger)indexIn:(NSArray<SNNote *> *)notes from:(NSUInteger)start key:(NSString *)key before:(NSDate *)edge read:(NSMutableArray *)read {
    NSUInteger lo = start, hi = notes.count;
    while (lo < hi) {
        NSUInteger mid = lo + (hi - lo) / 2;
        NSDate *date = [self dateOf:notes[mid] key:key read:read];
        BOOL before = edge ? (!date || [date compare:edge] == NSOrderedAscending) : !date;
        if (before) hi = mid;
        else lo = mid + 1;
    }
    return lo;
}

- (NSUInteger)countOfNotesInFolder:(SNFolder *)folder {
    if ([self isSmartFolder:folder]) return [self notesInFolder:folder matching:nil].count;
    return [self count:[self predicateForFolder:folder matching:nil deleted:NO]];
}

- (NSURL *)fileURLOfAttachment:(SNAttachment *)attachment {
    if (![attachment.kind isEqual:SNAttachmentKindFile] || !attachment.data || !attachment.id) return nil;
    NSString *name = _five && attachment.name.length ? attachment.name.lastPathComponent : @"File";
    NSString *dir = [[NSTemporaryDirectory() stringByAppendingPathComponent:@"SimpleNotes Files"] stringByAppendingPathComponent:attachment.id];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    NSURL *url = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:name]];
    return [attachment.data writeToURL:url atomically:YES] ? url : nil;
}

- (SNAttachment *)addFileToNote:(SNNote *)note data:(NSData *)data name:(NSString *)name type:(NSString *)type {
    SNAttachment *a = [self insert:SNAttachmentEntity];
    a.kind = SNAttachmentKindFile;
    a.type = type.length ? type : @"application/octet-stream";
    if (_five) a.name = name;
    a.data = data;
    a.note = note;
    [self save];
    return a;
}

- (SNAttachment *)addImageToNote:(SNNote *)note data:(NSData *)data type:(NSString *)type width:(double)width height:(double)height {
    SNAttachment *a = [self insert:SNAttachmentEntity];
    a.kind = SNAttachmentKindImage;
    a.type = type;
    a.data = data;
    a.width = @(width);
    a.height = @(height);
    a.note = note;
    [self save];
    return a;
}

- (SNAttachment *)addTableToNote:(SNNote *)note rows:(NSUInteger)rows columns:(NSUInteger)columns {
    SNAttachment *a = [self insert:SNAttachmentEntity];
    a.kind = SNAttachmentKindTable;
    a.type = SNTableType;
    a.data = [TTTable tableWithRows:rows columns:columns replica:0].data;
    a.note = note;
    [self save];
    return a;
}

- (TTTable *)tableOfAttachment:(SNAttachment *)attachment {
    if (![attachment.kind isEqual:SNAttachmentKindTable] || !attachment.data) return nil;
    return [TTTable tableWithData:attachment.data replica:0 error:NULL];
}

- (void)saveTable:(TTTable *)table toAttachment:(SNAttachment *)attachment {
    TTTable *stored = attachment.data ? [TTTable tableWithData:attachment.data replica:table.replica error:NULL] : nil;
    if (stored) [stored mergeTable:table];
    NSData *data = (stored ?: table).data;
    if ([data isEqual:attachment.data]) return;
    attachment.data = data;
    [self save];
}

- (SNAttachment *)attachmentWithID:(NSString *)attachmentID {
    if (!attachmentID.length || !_attaches) return nil;
    return [self fetch:SNAttachmentEntity where:[NSPredicate predicateWithFormat:@"id == %@", attachmentID] sortedBy:nil].firstObject;
}

- (SNNote *)noteWithID:(NSString *)noteID {
    if (!noteID.length) return nil;
    return [self fetch:SNNoteEntity where:[NSPredicate predicateWithFormat:@"id == %@", noteID] sortedBy:nil].firstObject;
}

- (NSArray<SNNote *> *)deletedNotesMatching:(NSString *)text {
    /* Being emptied: none, at once. */
    if (_emptying) return @[];
    return [self faultsOf:[self predicateForFolder:nil matching:text deleted:YES]
                 sortedBy:@[ [NSSortDescriptor sortDescriptorWithKey:@"deletedAt" ascending:NO] ]];
}

- (NSUInteger)countOfDeletedNotes {
    if (_emptying) return 0;
    return [self count:[self predicateForFolder:nil matching:nil deleted:YES]];
}

#pragma mark changing

/* What a save is to change, when it is notes' text alone and their tags
   stay: those notes' IDs (nil: anything else). */
- (NSSet<NSManagedObjectID *> *)notesOnlyEdited {
    if (_context.insertedObjects.count || _context.deletedObjects.count) return nil;
    NSSet *text = [NSSet setWithObjects:@"title", @"body", @"bodyText", [self editedKey], nil];
    NSMutableSet *edited = [NSMutableSet set];
    for (NSManagedObject *o in _context.updatedObjects) {
        if (![o isKindOfClass:[SNNote class]]) return nil;
        NSDictionary *changed = o.changedValues;
        if (![[NSSet setWithArray:changed.allKeys] isSubsetOfSet:text]) return nil;
        if (changed[@"body"]) {
            id was = [o committedValuesForKeys:@[ @"body" ]][@"body"];
            NSSet *before = [NSSet setWithArray:SNTagsInText([was isKindOfClass:[NSString class]] ? was : @"")];
            if (![before isEqualToSet:[NSSet setWithArray:SNTagsInText(((SNNote *)o).body ?: @"")]]) return nil;
        }
        [edited addObject:o.objectID];
    }
    return edited;
}

- (void)saveNow {
    _savePending = NO;
    if (!_context.hasChanges) return;
    NSSet *edited = [self notesOnlyEdited];
    NSError *error = nil;
    if (![_context save:&error]) {
        NSLog(@"SimpleNotes: not saved: %@", error);
        [self say:[NSString stringWithFormat:@"Not saved: %@", error.localizedDescription] synced:NO];
        return;
    }
    [self say:_status synced:NO edited:edited];
    [self syncSoon];
}

/* A little after a change, it goes to the server. */
- (void)syncSoon {
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
    return [self addFolderNamed:name inFolder:nil];
}

- (SNFolder *)addFolderNamed:(NSString *)name inFolder:(SNFolder *)parent {
    SNFolder *f = [self insert:SNFolderEntity];
    f.name = name;
    /* Not in a smart folder: beside it. */
    if ([self isSmartFolder:parent]) parent = [self parentOfFolder:parent];
    if (_nests) f.parent = parent;
    [self save];
    return f;
}

- (BOOL)moveFolder:(SNFolder *)folder toFolder:(SNFolder *)parent {
    if (!_nests || parent == folder || (parent && [self folder:parent isInFolder:folder]) || [self isSmartFolder:parent]) return NO;
    /* A circle cut as shown (parentOfFolder:) is cut so in the store
       first: moving one of its folders must not close it again. */
    for (SNFolder *f in [self folders])
        if (f.parent && !f.parent.isDeleted && ![self parentOfFolder:f]) f.parent = nil;
    folder.parent = parent;
    [self save];
    return YES;
}

- (void)renameFolder:(SNFolder *)folder to:(NSString *)name {
    if ([folder.name isEqual:name]) return;
    folder.name = name;
    [self save];
}

- (void)deleteFolder:(SNFolder *)folder {
    /* The folders in it too, each deleted (and sent so); all their notes
       to Recently Deleted. */
    NSMutableArray<SNFolder *> *gone = [NSMutableArray arrayWithObject:folder];
    [self addTreeOf:folder from:[self foldersByParent] to:gone];
    NSDate *now = [NSDate date];
    for (SNFolder *f in gone) {
        for (SNNote *n in f.notes.allObjects) {
            n.folder = nil;
            if (_deletes && !n.deletedAt) n.deletedAt = now;
        }
        [_context deleteObject:f];
    }
    [self save];
}

- (SNNote *)addNoteInFolder:(SNFolder *)folder {
    SNNote *n = [self insert:SNNoteEntity];
    n.lastEdited = n.created;
    n.title = @"New Note";
    n.body = @"";
    n.pinned = @NO;
    n.folder = [self isSmartFolder:folder] ? nil : folder;
    [self save];
    return n;
}

- (void)closeEditorsOf:(SNNote *)note {
    for (SNNoteEditor *e in _editors.allObjects)
        if ([e.noteID isEqual:note.objectID]) [e close];
}

- (void)deleteNote:(SNNote *)note {
    if (note.deletedAt) return;
    [self closeEditorsOf:note];
    note.deletedAt = [NSDate date];
    note.pinned = @NO;
    [self save];
}

- (void)recoverNote:(SNNote *)note {
    if (!note.deletedAt) return;
    note.deletedAt = nil;
    if (note.folder.isDeleted) note.folder = nil;
    [self save];
}

- (void)deleteNoteImmediately:(SNNote *)note {
    [self closeEditorsOf:note];
    [_context deleteObject:note];
    [self save];
}

- (BOOL)isRemoving {
    return _removing > 0;
}

- (void)emptyRecentlyDeleted {
    if (_emptying || ![self countOfDeletedNotes]) return;
    _emptying = YES;
    [self removeNotesWhere:[self predicateForFolder:nil matching:nil deleted:YES]];
    /* Shown empty now. */
    [self say:_status synced:NO];
}

/* Notes gone for good, many maybe: off the main thread, by a context of
   the store's own, a batch at a time, how far said as it goes. The views
   read them gone as it saves (-storeDidSave:). */
- (void)removeNotesWhere:(NSPredicate *)predicate {
    for (SNNoteEditor *e in _editors.allObjects) {
        NSManagedObject *n = [_context existingObjectWithID:e.noteID error:NULL];
        if (n && [predicate evaluateWithObject:n]) [e close];
    }
    [self save];
    _removing++;
    [self sayOnly:@"Deleting notes…"];
    NSPersistentStoreCoordinator *coordinator = _coordinator;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        context.persistentStoreCoordinator = coordinator;
        context.undoManager = nil;
        __block NSError *error = nil;
        __block NSUInteger removed = 0;
        [context performBlockAndWait:^{
            NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:SNNoteEntity];
            f.predicate = predicate;
            f.resultType = NSManagedObjectIDResultType;
            NSArray *ids = [context executeFetchRequest:f error:&error] ?: @[];
            while (removed < ids.count && !error) {
                @autoreleasepool {
                    NSRange batch = NSMakeRange(removed, MIN(SNRemoveBatch, ids.count - removed));
                    for (NSManagedObjectID *i in [ids subarrayWithRange:batch]) [context deleteObject:[context objectWithID:i]];
                    NSError *failed = nil;
                    if (![context save:&failed]) {
                        error = failed ?: [NSError errorWithDomain:NSCocoaErrorDomain code:NSPersistentStoreSaveError userInfo:nil];
                        break;
                    }
                    [context reset];
                    removed = NSMaxRange(batch);
                }
                NSString *what = [NSString stringWithFormat:@"Deleting %@ of %@ notes…", SNCount(removed), SNCount(ids.count)];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self sayOnly:what];
                });
            }
        }];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self finishRemoving:removed error:error];
        });
    });
}

- (void)finishRemoving:(NSUInteger)removed error:(NSError *)error {
    if (--_removing == 0) _emptying = NO;
    for (NSManagedObject *o in _context.registeredObjects.allObjects) [_context refreshObject:o mergeChanges:YES];
    if (error) {
        NSLog(@"SimpleNotes: not deleted: %@", error);
        [self say:[NSString stringWithFormat:@"Not deleted: %@", error.localizedDescription] synced:NO];
        return;
    }
    [self say:[NSString stringWithFormat:@"%@ note%@ deleted.", SNCount(removed), removed == 1 ? @"" : @"s"] synced:NO];
    [self syncSoon];
}

- (NSUInteger)removeNotesDeletedBefore:(NSDate *)date {
    if (!_deletes) return 0;
    NSArray *expired = [self fetch:SNNoteEntity where:[NSPredicate predicateWithFormat:@"deletedAt != nil AND deletedAt < %@", date] sortedBy:nil];
    for (SNNote *n in expired) {
        [self closeEditorsOf:n];
        [_context deleteObject:n];
    }
    if (expired.count) [self save];
    return expired.count;
}

/* Those deleted 30 days ago and more: gone, off the main thread. */
- (void)removeExpiredNotes {
    if (!_deletes) return;
    NSDate *date = [NSDate dateWithTimeIntervalSinceNow:-(NSTimeInterval)SNRecentlyDeletedDays * 86400];
    NSPredicate *expired = [NSPredicate predicateWithFormat:@"deletedAt != nil AND deletedAt < %@", date];
    if ([self count:expired]) [self removeNotesWhere:expired];
}

- (void)setNote:(SNNote *)note pinned:(BOOL)pinned {
    note.pinned = @(pinned);
    [self save];
}

- (void)moveNote:(SNNote *)note toFolder:(SNFolder *)folder {
    if ([self isSmartFolder:folder]) return;
    note.folder = folder;
    note.deletedAt = nil;
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

- (NSString *)addImageData:(NSData *)data type:(NSString *)type width:(double)width height:(double)height {
    SNNotes *notes = _notes;
    SNNote *note = [self note];
    if (!notes || !note) return nil;
    return [notes addImageToNote:note data:data type:type width:width height:height].id;
}

- (NSString *)addFileData:(NSData *)data name:(NSString *)name type:(NSString *)type {
    SNNotes *notes = _notes;
    SNNote *note = [self note];
    if (!notes || !note) return nil;
    return [notes addFileToNote:note data:data name:name type:type].id;
}

- (NSString *)addTableWithRows:(NSUInteger)rows columns:(NSUInteger)columns {
    SNNotes *notes = _notes;
    SNNote *note = [self note];
    if (!notes || !note) return nil;
    return [notes addTableToNote:note rows:rows columns:columns].id;
}

- (SNAttachment *)attachmentWithID:(NSString *)attachmentID {
    return [_notes attachmentWithID:attachmentID];
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
    id<SNNoteEditorDelegate> delegate = _delegate;
    if ([delegate respondsToSelector:@selector(noteEditorDidVanish:)]) [delegate noteEditorDidVanish:self];
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
        if (edits.count) [_delegate noteEditor:self didMergeEdits:edits];
    }
    if (!_dirty) return;
    _dirty = NO;
    note.text = _text;
    note.lastEdited = [NSDate date];
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
