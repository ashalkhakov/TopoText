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

static NSArray<NSString *> *SNStoreFiles(NSURL *url) {
    return @[ url.path, [url.path stringByAppendingString:@"-wal"], [url.path stringByAppendingString:@"-shm"] ];
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
    }
    if (!source) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSPersistentStoreIncompatibleVersionHashError
                                            userInfo:@{ NSLocalizedDescriptionKey: @"The notes were made by a version of SimpleNotes this one does not know." }];
        return NO;
    }

    NSMappingModel *mapping = [NSMappingModel inferredMappingModelForSourceModel:source destinationModel:current error:error];
    if (!mapping) return NO;
    NSURL *migrated = [storeURL URLByAppendingPathExtension:@"migrating"];
    for (NSString *p in SNStoreFiles(migrated)) [[NSFileManager defaultManager] removeItemAtPath:p error:NULL];
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
    return YES;
}
