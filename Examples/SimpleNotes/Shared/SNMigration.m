#import "SNMigration.h"
#import "SNModel.h"

NSArray<NSManagedObjectModel *> *SNModelVersions(NSURL *momdURL) {
    NSMutableArray *versions = [NSMutableArray array];
    NSArray *files = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:momdURL.path error:NULL]
                         sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *f in files) {
        if (![f.pathExtension isEqual:@"mom"]) continue;
        NSManagedObjectModel *m = SNModelAt([momdURL URLByAppendingPathComponent:f]);
        if (m) [versions addObject:m];
    }
    return versions;
}

/* A SQLite store's files: the database, its write-ahead log and shared
   memory, and the folder of the Binary values it keeps outside itself
   (.<name>_SUPPORT beside it, as Apple's and FreeCoreData's stores make). */
static NSArray<NSString *> *SNStoreFiles(NSURL *url) {
    NSString *support = [NSString stringWithFormat:@".%@_SUPPORT", url.lastPathComponent.stringByDeletingPathExtension];
    return @[ url.path, [url.path stringByAppendingString:@"-wal"], [url.path stringByAppendingString:@"-shm"],
              [url.path.stringByDeletingLastPathComponent stringByAppendingPathComponent:support] ];
}

/* A version's model as the store was made: with the bookkeeping its users
   add, less what the bookkeeping has gained since the store was made (an
   entity the store has none of: ODataSync's ODSMergeSeen, say), which the
   migration then adds. */
static NSManagedObjectModel *SNVersionAsStored(NSManagedObjectModel *version, Class<SNBookkeeper> bookkeeper, NSDictionary *metadata) {
    NSSet *own = [NSSet setWithArray:[version.entities valueForKey:@"name"]];
    [bookkeeper addBookkeepingToModel:version configuration:nil];
    NSDictionary *hashes = metadata[NSStoreModelVersionHashesKey];
    if (![hashes isKindOfClass:[NSDictionary class]]) return version;
    NSMutableArray *kept = [NSMutableArray array];
    for (NSEntityDescription *entity in version.entities)
        if ([own containsObject:entity.name] || hashes[entity.name]) [kept addObject:entity];
    if (kept.count != version.entities.count) version.entities = kept;
    return version;
}

/* A version's model as a store was made before ODataSync let synced Binary
   values be kept outside the store (allowsExternalBinaryDataStorage, which
   is part of an entity's version hash): none allowed. */
static NSManagedObjectModel *SNWithoutExternalStorage(NSManagedObjectModel *model) {
    NSManagedObjectModel *before = [model copy];
    for (NSEntityDescription *entity in before.entities)
        for (NSPropertyDescription *property in entity.properties)
            if ([property isKindOfClass:[NSAttributeDescription class]])
                ((NSAttributeDescription *)property).allowsExternalBinaryDataStorage = NO;
    return before;
}

BOOL SNMigrateStore(NSURL *storeURL, NSURL *momdURL, Class<SNBookkeeper> bookkeeper, NSError **error) {
    if (![[NSFileManager defaultManager] fileExistsAtPath:storeURL.path]) return YES;
    NSDictionary *options = @{ NSPersistentHistoryTrackingKey: @YES };
    NSDictionary *metadata = [NSPersistentStoreCoordinator metadataForPersistentStoreOfType:NSSQLiteStoreType URL:storeURL
                                                                                    options:options error:error];
    if (!metadata) return NO;
    NSManagedObjectModel *current = SNModelAt(momdURL);
    if (!current) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadNoSuchFileError
                                            userInfo:@{ NSLocalizedDescriptionKey: @"No compiled model to migrate to." }];
        return NO;
    }
    [bookkeeper addBookkeepingToModel:current configuration:nil];
    if ([current isConfiguration:nil compatibleWithStoreMetadata:metadata]) return YES;

    NSManagedObjectModel *source = nil;
    for (NSManagedObjectModel *version in SNModelVersions(momdURL)) {
        NSManagedObjectModel *stored = SNVersionAsStored(version, bookkeeper, metadata);
        if ([stored isConfiguration:nil compatibleWithStoreMetadata:metadata]) source = stored;
        else {
            NSManagedObjectModel *before = SNWithoutExternalStorage(stored);
            if ([before isConfiguration:nil compatibleWithStoreMetadata:metadata]) source = before;
        }
    }
    if (!source) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSPersistentStoreIncompatibleVersionHashError
                                            userInfo:@{ NSLocalizedDescriptionKey: @"The notes were made by a version of SimpleNotes this one does not know." }];
        return NO;
    }

    NSMappingModel *mapping = [NSMappingModel inferredMappingModelForSourceModel:source destinationModel:current error:error];
    if (!mapping) return NO;
    /* Made under the store's own name, in a folder beside it: the values it
       keeps outside itself go where they belong once it is moved over. */
    NSURL *migrating = [[storeURL URLByDeletingLastPathComponent] URLByAppendingPathComponent:[NSString stringWithFormat:@".%@.migrating", storeURL.lastPathComponent] isDirectory:YES];
    [[NSFileManager defaultManager] removeItemAtURL:migrating error:NULL];
    if (![[NSFileManager defaultManager] createDirectoryAtURL:migrating withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    NSURL *migrated = [migrating URLByAppendingPathComponent:storeURL.lastPathComponent];
    NSMigrationManager *manager = [[NSMigrationManager alloc] initWithSourceModel:source destinationModel:current];
    if (![manager migrateStoreFromURL:storeURL type:NSSQLiteStoreType options:options withMappingModel:mapping
                     toDestinationURL:migrated destinationType:NSSQLiteStoreType destinationOptions:options error:error])
        return NO;
    /* The migrated store in the old one's place; the old kept beside it, as
       .old, until the next migration. */
    NSArray *from = SNStoreFiles(migrated), *to = SNStoreFiles(storeURL);
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *p in to) {
        NSString *kept = [p stringByAppendingString:@".old"];
        [fm removeItemAtPath:kept error:NULL];
        if ([fm fileExistsAtPath:p]) [fm moveItemAtPath:p toPath:kept error:NULL];
    }
    for (NSUInteger i = 0; i < from.count; i++)
        if ([fm fileExistsAtPath:from[i]] && ![fm moveItemAtPath:from[i] toPath:to[i] error:error]) return NO;
    [fm removeItemAtURL:migrating error:NULL];
    return YES;
}

/* Whether the store at url has no rows of model's (opened, then closed). */
static BOOL SNStoreIsEmpty(NSPersistentStoreCoordinator *coordinator, NSManagedObjectModel *model, NSString *type, NSURL *url,
                           NSDictionary *options, BOOL *empty, NSError **error) {
    NSPersistentStore *store = [coordinator addPersistentStoreWithType:type configuration:nil URL:url options:options error:error];
    if (!store) return NO;
    NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    context.persistentStoreCoordinator = coordinator;
    __block BOOL none = YES;
    [context performBlockAndWait:^{
        for (NSEntityDescription *entity in model.entities) {
            if (entity.isAbstract) continue;
            NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:entity.name];
            fetch.includesSubentities = NO;
            if ([context countForFetchRequest:fetch error:NULL] > 0) {
                none = NO;
                break;
            }
        }
        [context reset];
    }];
    *empty = none;
    return [coordinator removePersistentStore:store error:error];
}

BOOL SNMoveStore(NSManagedObjectModel *model, NSString *fromType, NSURL *from, NSDictionary *fromOptions,
                 NSString *toType, NSURL *to, NSDictionary *toOptions, BOOL *moved, NSError **error) {
    *moved = NO;
    NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    /* No store at to yet: moved into a new one (which FreeCoreData fills a
       batch at a time, and destroys again if the copy fails). One there
       already is opened to see whether it has anything in it. */
    BOOL there = [NSPersistentStoreCoordinator metadataForPersistentStoreOfType:toType URL:to options:toOptions error:NULL] != nil;
    if (there) {
        BOOL empty = NO;
        if (!SNStoreIsEmpty(coordinator, model, toType, to, toOptions, &empty, error)) return NO;
        if (!empty) return YES;
    }
    NSPersistentStore *source = [coordinator addPersistentStoreWithType:fromType configuration:nil URL:from options:fromOptions error:error];
    if (!source) return NO;
    NSPersistentStore *made = [coordinator migratePersistentStore:source toURL:to options:toOptions withType:toType error:error];
    if (!made) {
        [coordinator removePersistentStore:source error:NULL];
        return NO;
    }
    [coordinator removePersistentStore:made error:NULL];
    *moved = YES;
    return YES;
}
