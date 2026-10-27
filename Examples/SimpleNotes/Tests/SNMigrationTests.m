// A device on an older version of the model, its store migrated: what it
// had sent is there, and what it had not sent yet goes when it next syncs.
// The server already on the newer version, taking the older one's writes.

#import <XCTest/XCTest.h>
#import <ODataService/ODataService.h>
#import <ODataSync/ODataSyncService.h>
#import "SNModel.h"
#import "SNNotes.h"
#import "SNMigration.h"

@interface SNMigrationTests : XCTestCase
@end

@implementation SNMigrationTests {
    NSMutableArray<NSURL *> *_files;
    NSURL *_momd;
    ODataService *_service;
    ODataSyncService *_histories;
    NSURL *_root;
}

- (NSURL *)temporaryStore {
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
                                            [NSString stringWithFormat:@"sn-migrate-%@.sqlite", [NSProcessInfo processInfo].globallyUniqueString]]];
    [_files addObject:url];
    return url;
}

- (void)setUp {
    _files = [NSMutableArray array];
    _momd = SNModelURLInBundle([NSBundle bundleForClass:[self class]]);
    _root = [NSURL URLWithString:@"http://notes.test/odata/"];
    NSManagedObjectModel *model = SNModelAt(_momd);
    [ODataSyncService addBookkeepingToModel:model configuration:nil];
    NSPersistentStoreCoordinator *server = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    NSError *error = nil;
    XCTAssertNotNil([server addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:[self temporaryStore]
                                               options:@{ NSPersistentHistoryTrackingKey: @YES } error:&error], @"%@", error);
    _service = [[ODataService alloc] initWithPersistentStoreCoordinator:server serviceRoot:_root];
    /* Older devices' writes, as the server takes them. */
    _service.upgradeBody = ^NSDictionary *(NSDictionary *body, NSString *version, NSEntityDescription *entity, ODataRequest *request, NSError **e) {
        return SNUpgradeBody(body, entity);
    };
    _histories = [[ODataSyncService alloc] initWithService:_service];
    SNRegisterMergers(_histories.engine);
}

- (void)tearDown {
    for (NSURL *url in _files) {
        for (NSString *suffix in @[ @"", @"-wal", @"-shm", @".old", @"-wal.old", @"-shm.old" ])
            [[NSFileManager defaultManager] removeItemAtPath:[url.path stringByAppendingString:suffix] error:NULL];
        [[NSFileManager defaultManager] removeItemAtPath:[self filesBeside:url] error:NULL];
        [[NSFileManager defaultManager] removeItemAtPath:[[self filesBeside:url] stringByAppendingString:@".old"] error:NULL];
    }
}

/* Where a store keeps the Binary values it keeps outside it (Apple's
   layout, which FreeCoreData's follows). */
- (NSString *)filesBeside:(NSURL *)store {
    NSString *name = [NSString stringWithFormat:@".%@_SUPPORT", store.lastPathComponent.stringByDeletingPathExtension];
    return [store.path.stringByDeletingLastPathComponent stringByAppendingPathComponent:name];
}

- (SNNotes *)deviceAt:(NSURL *)store model:(NSURL *)model {
    NSError *error = nil;
    SNNotes *d = [[SNNotes alloc] initWithStoreURL:store modelURL:model error:&error];
    XCTAssertNotNil(d, @"%@", error);
    d.transport = _service;
    d.serviceRoot = _root;
    return d;
}

- (void)sync:(SNNotes *)d {
    NSError *error = nil;
    XCTAssertTrue([d syncAndWait:&error], @"%@", error);
    XCTAssertEqual(d.engine.issues.count, 0u, @"%@", d.engine.issues);
}

- (void)type:(NSString *)text into:(SNNote *)note on:(SNNotes *)d {
    SNNoteEditor *e = [d editorForNote:note];
    [e.text insertString:text atIndex:e.text.length attributes:nil];
    [e textDidChange];
    [e close];
}

/* A device on the version in mom, updated to the current one. */
- (void)migrateFrom:(NSString *)mom {
    NSURL *store = [self temporaryStore];
    NSURL *older = [_momd URLByAppendingPathComponent:mom];
    XCTAssertEqual(SNModelVersions(_momd).count, 7u);
    NSString *replica = nil;
    @autoreleasepool {
        SNNotes *old = [self deviceAt:store model:older];
        replica = old.engine.replicaID;
        SNNote *note = [old addNoteInFolder:[old addFolderNamed:@"Home"]];
        [self type:@"Before the update" into:note on:old];
        [self sync:old];
        /* Typed, saved, not sent: in the store's history only. */
        [self type:@", and after" into:note on:old];
        XCTAssertNotNil([note.entity.attributesByName objectForKey:@"title"]);
        if (![mom isEqual:@"SimpleNotes 6.mom"])
            XCTAssertNil([note.entity.attributesByName objectForKey:@"owner"], @"before version 6, no owners");
        XCTAssertNil(note.managedObjectContext.persistentStoreCoordinator.managedObjectModel.entitiesByName[SNNoteVersionEntity],
                     @"before version 7, no versions");
        /* The app quit: its store let go before the update replaces it. */
        [old close];
    }

    /* The app updated: the device opened with the current model migrates
       its store, history and all. */
    SNNotes *updated = [self deviceAt:store model:_momd];
    XCTAssertEqualObjects(updated.engine.replicaID, replica, @"the same device, to the server and its peers");
    SNNote *note = [updated notesInFolder:nil matching:nil].firstObject;
    XCTAssertEqualObjects(note.body, @"Before the update, and after");
    XCTAssertEqualObjects(note.folder.name, @"Home");
    /* updated, renamed edited, kept: a new note's is when it was made. */
    XCTAssertEqualWithAccuracy(note.edited.timeIntervalSinceReferenceDate, note.created.timeIntervalSinceReferenceDate, 1,
                               @"updated, renamed edited, kept: %@", note.edited);
    XCTAssertNil(note.deletedAt);
    XCTAssertEqual(updated.pendingCount, 1u, @"still waiting, after the migration (in its history): %@", updated.engine.pendingChanges);
    [self sync:updated];
    XCTAssertEqual(updated.pendingCount, 0u);

    SNNotes *other = [self deviceAt:[self temporaryStore] model:_momd];
    [self sync:other];
    XCTAssertEqualObjects([other notesInFolder:nil matching:nil].firstObject.body, @"Before the update, and after",
                          @"what waited reached the server");
    /* And the migrated device goes on as any other. */
    [self type:@"!" into:note on:updated];
    [self sync:updated];
    [self sync:other];
    XCTAssertEqualObjects([other notesInFolder:nil matching:nil].firstObject.body, @"Before the update, and after!");
    /* Folders in folders, now. */
    SNFolder *home = note.folder;
    [updated addFolderNamed:@"Kitchen" inFolder:home];
    [self sync:updated];
    [self sync:other];
    XCTAssertEqualObjects([[other foldersInFolder:[other foldersInFolder:nil].firstObject] valueForKey:@"name"], @[ @"Kitchen" ]);
}

- (void)testAVersion1StoreIsMigratedAndWhatWaitedIsSent {
    [self migrateFrom:@"SimpleNotes.mom"];
}

- (void)testAVersion2StoreIsMigratedAndWhatWaitedIsSent {
    [self migrateFrom:@"SimpleNotes 2.mom"];
}

- (void)testAVersion3StoreIsMigratedAndWhatWaitedIsSent {
    [self migrateFrom:@"SimpleNotes 3.mom"];
}

- (void)testAVersion4StoreIsMigratedAndWhatWaitedIsSent {
    [self migrateFrom:@"SimpleNotes 4.mom"];
}

- (void)testAVersion5StoreIsMigratedAndWhatWaitedIsSent {
    [self migrateFrom:@"SimpleNotes 5.mom"];
}

- (void)testAVersion6StoreIsMigratedAndWhatWaitedIsSent {
    [self migrateFrom:@"SimpleNotes 6.mom"];
}

- (void)testAStoreOfTheCurrentVersionIsLeftAlone {
    NSURL *store = [self temporaryStore];
    @autoreleasepool { [[self deviceAt:store model:_momd] addNoteInFolder:nil]; }
    NSDate *before = [[NSFileManager defaultManager] attributesOfItemAtPath:store.path error:NULL].fileModificationDate;
    NSError *error = nil;
    XCTAssertTrue(SNMigrateStore(store, _momd, [ODataSyncEngine class], &error));
    XCTAssertEqualObjects([[NSFileManager defaultManager] attributesOfItemAtPath:store.path error:NULL].fileModificationDate, before);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:[store.path stringByAppendingString:@".old"]]);
}

/* A device's store made before ODataSync let synced files be kept beside
   the store (a flag in the entities' version hashes): migrated, its files
   moved out of it, read back whole. */
- (void)testAStoreFromBeforeFilesWereKeptBesideItIsMigrated {
    NSURL *store = [self temporaryStore];
    NSMutableData *file = [NSMutableData dataWithLength:300 * 1024];
    for (NSUInteger i = 0; i < file.length; i++) ((uint8_t *)file.mutableBytes)[i] = (uint8_t)(i * 31);
    @autoreleasepool {
        NSManagedObjectModel *before = SNModelAt(_momd);
        [ODataSyncEngine addBookkeepingToModel:before configuration:nil];
        for (NSEntityDescription *entity in before.entities)
            for (NSPropertyDescription *property in entity.properties)
                if ([property isKindOfClass:[NSAttributeDescription class]])
                    ((NSAttributeDescription *)property).allowsExternalBinaryDataStorage = NO;
        NSPersistentStoreCoordinator *c = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:before];
        NSError *error = nil;
        XCTAssertNotNil([c addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:store
                                              options:@{ NSPersistentHistoryTrackingKey: @YES } error:&error], @"%@", error);
        NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        context.persistentStoreCoordinator = c;
        [context performBlockAndWait:^{
            NSManagedObject *note = [NSEntityDescription insertNewObjectForEntityForName:SNNoteEntity inManagedObjectContext:context];
            [note setValue:@"N1" forKey:@"id"];
            [note setValue:@"With a file" forKey:@"body"];
            [note setValue:@"With a file" forKey:@"title"];
            NSManagedObject *a = [NSEntityDescription insertNewObjectForEntityForName:SNAttachmentEntity inManagedObjectContext:context];
            [a setValue:@"A1" forKey:@"id"];
            [a setValue:SNAttachmentKindFile forKey:@"kind"];
            [a setValue:@"application/octet-stream" forKey:@"type"];
            [a setValue:file forKey:@"data"];
            [a setValue:note forKey:@"note"];
            NSError *e = nil;
            XCTAssertTrue([context save:&e], @"%@", e);
        }];
    }
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:[self filesBeside:store]], @"in the store, before");

    NSError *error = nil;
    XCTAssertTrue(SNMigrateStore(store, _momd, [ODataSyncEngine class], &error), @"%@", error);
    SNNotes *updated = [self deviceAt:store model:_momd];
    NSEntityDescription *attachment = updated.context.persistentStoreCoordinator.managedObjectModel.entitiesByName[SNAttachmentEntity];
    NSAttributeDescription *data = attachment.attributesByName[@"data"];
    XCTAssertTrue(data.allowsExternalBinaryDataStorage, @"the current model keeps files beside the store");
    XCTAssertEqualObjects([updated attachmentWithID:@"A1"].data, file, @"read back whole");
    XCTAssertEqualObjects([updated noteWithID:@"N1"].body, @"With a file");
    NSArray *kept = [[NSFileManager defaultManager] subpathsAtPath:[self filesBeside:store]];
    XCTAssertGreaterThan(kept.count, 0u, @"moved beside the store");
}

/* A server's store made before its bookkeeping gained an entity (ODataSync's
   ODSMergeSeen, for merged attributes): brought up to it, its notes kept. */
- (void)testAServerStoreFromBeforeItsBookkeepingGrewIsMigrated {
    NSURL *store = [self temporaryStore];
    @autoreleasepool {
        NSManagedObjectModel *before = SNModelAt(_momd);
        [ODataSyncService addBookkeepingToModel:before configuration:nil];
        NSMutableArray *entities = [before.entities mutableCopy];
        for (NSEntityDescription *e in before.entities)
            if ([e.name isEqualToString:@"ODSMergeSeen"]) [entities removeObject:e];
        XCTAssertLessThan(entities.count, before.entities.count, @"the bookkeeping has the new entity");
        before.entities = entities;
        NSPersistentStoreCoordinator *old = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:before];
        NSError *error = nil;
        XCTAssertNotNil([old addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:store
                                                options:@{ NSPersistentHistoryTrackingKey: @YES } error:&error], @"%@", error);
        NSManagedObjectContext *c = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        c.persistentStoreCoordinator = old;
        [c performBlockAndWait:^{
            NSManagedObject *note = [NSEntityDescription insertNewObjectForEntityForName:SNNoteEntity inManagedObjectContext:c];
            [note setValue:@"n1" forKey:@"id"];
            [note setValue:@"Kept" forKey:@"title"];
            [c save:NULL];
        }];
        for (NSPersistentStore *s in [old.persistentStores copy]) [old removePersistentStore:s error:NULL];
    }
    NSError *error = nil;
    XCTAssertTrue(SNMigrateStore(store, _momd, [ODataSyncService class], &error), @"%@", error);
    NSManagedObjectModel *now = SNModelAt(_momd);
    [ODataSyncService addBookkeepingToModel:now configuration:nil];
    NSPersistentStoreCoordinator *opened = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:now];
    XCTAssertNotNil([opened addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:store
                                               options:@{ NSPersistentHistoryTrackingKey: @YES } error:&error], @"%@", error);
    NSManagedObjectContext *c = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    c.persistentStoreCoordinator = opened;
    __block NSArray *titles = nil;
    [c performBlockAndWait:^{
        titles = [[c executeFetchRequest:[NSFetchRequest fetchRequestWithEntityName:SNNoteEntity] error:NULL] valueForKey:@"title"];
    }];
    XCTAssertEqualObjects(titles, @[ @"Kept" ]);
}

/* What a store has: each entity's rows' ids, by entity. */
- (NSDictionary *)rowsOf:(NSURL *)url model:(NSManagedObjectModel *)model {
    NSPersistentStoreCoordinator *c = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    NSError *error = nil;
    XCTAssertNotNil([c addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:url
                                          options:@{ NSPersistentHistoryTrackingKey: @YES } error:&error], @"%@", error);
    NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    context.persistentStoreCoordinator = c;
    NSMutableDictionary *rows = [NSMutableDictionary dictionary];
    [context performBlockAndWait:^{
        for (NSString *entity in @[ SNNoteEntity, SNFolderEntity ]) {
            NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:entity];
            fetch.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:@"id" ascending:YES] ];
            rows[entity] = [[context executeFetchRequest:fetch error:NULL] valueForKey:@"id"];
        }
        NSFetchRequest *notes = [NSFetchRequest fetchRequestWithEntityName:SNNoteEntity];
        notes.predicate = [NSPredicate predicateWithFormat:@"folder.id == %@", @"f1"];
        notes.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:@"id" ascending:YES] ];
        rows[@"in f1"] = [[context executeFetchRequest:notes error:NULL] valueForKey:@"id"];
    }];
    for (NSPersistentStore *s in [c.persistentStores copy]) [c removePersistentStore:s error:NULL];
    return rows;
}

- (void)testAServerStoreIsMovedToAnotherWhenThatOneIsEmpty {
    NSManagedObjectModel *model = SNModelAt(_momd);
    [ODataSyncService addBookkeepingToModel:model configuration:nil];
    NSURL *from = [self temporaryStore], *to = [self temporaryStore];
    NSDictionary *options = @{ NSPersistentHistoryTrackingKey: @YES };
    @autoreleasepool {
        NSPersistentStoreCoordinator *c = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
        NSError *error = nil;
        XCTAssertNotNil([c addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:from options:options error:&error], @"%@", error);
        NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        context.persistentStoreCoordinator = c;
        [context performBlockAndWait:^{
            NSManagedObject *folder = [NSEntityDescription insertNewObjectForEntityForName:SNFolderEntity inManagedObjectContext:context];
            [folder setValue:@"f1" forKey:@"id"];
            [folder setValue:@"Work" forKey:@"name"];
            for (NSString *noteID in @[ @"n1", @"n2", @"n3" ]) {
                NSManagedObject *note = [NSEntityDescription insertNewObjectForEntityForName:SNNoteEntity inManagedObjectContext:context];
                [note setValue:noteID forKey:@"id"];
                [note setValue:noteID forKey:@"title"];
                if (![noteID isEqual:@"n3"]) [note setValue:folder forKey:@"folder"];
            }
            [context save:NULL];
        }];
        for (NSPersistentStore *s in [c.persistentStores copy]) [c removePersistentStore:s error:NULL];
    }
    NSDictionary *before = [self rowsOf:from model:model];
    XCTAssertEqualObjects(before[SNNoteEntity], (@[ @"n1", @"n2", @"n3" ]));

    BOOL moved = NO;
    NSError *error = nil;
    XCTAssertTrue(SNMoveStore(model, NSSQLiteStoreType, from, options, NSSQLiteStoreType, to, options, &moved, &error), @"%@", error);
    XCTAssertTrue(moved);
    XCTAssertEqualObjects([self rowsOf:to model:model], before);
    XCTAssertEqualObjects(before[@"in f1"], (@[ @"n1", @"n2" ]));
    XCTAssertEqualObjects([self rowsOf:from model:model], before, @"the store moved from is left as it was");

    /* Again (the setting left in place): the store has rows now, and is left alone. */
    XCTAssertTrue(SNMoveStore(model, NSSQLiteStoreType, from, options, NSSQLiteStoreType, to, options, &moved, &error), @"%@", error);
    XCTAssertFalse(moved);
    XCTAssertEqualObjects([self rowsOf:to model:model], before);
}

@end
