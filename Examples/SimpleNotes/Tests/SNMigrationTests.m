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
    /* Older devices' writes: the newer model only adds, so taken as they are. */
    _service.upgradeBody = ^NSDictionary *(NSDictionary *body, NSString *version, NSEntityDescription *entity, ODataRequest *request, NSError **e) {
        return body;
    };
    _histories = [[ODataSyncService alloc] initWithService:_service];
}

- (void)tearDown {
    for (NSURL *url in _files)
        for (NSString *suffix in @[ @"", @"-wal", @"-shm", @".old", @"-wal.old", @"-shm.old" ])
            [[NSFileManager defaultManager] removeItemAtPath:[url.path stringByAppendingString:suffix] error:NULL];
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

- (void)testAnOlderStoreIsMigratedAndWhatWaitedIsSent {
    NSURL *store = [self temporaryStore];
    NSURL *version1 = [_momd URLByAppendingPathComponent:@"SimpleNotes.mom"];
    XCTAssertEqual(SNModelVersions(_momd).count, 2u);
    NSString *replica = nil;
    @autoreleasepool {
        SNNotes *old = [self deviceAt:store model:version1];
        replica = old.engine.replicaID;
        SNNote *note = [old addNoteInFolder:[old addFolderNamed:@"Home"]];
        [self type:@"Before the update" into:note on:old];
        [self sync:old];
        /* Typed, saved, not sent: in the store's history only. */
        [self type:@", and after" into:note on:old];
        XCTAssertNotNil([note.entity.attributesByName objectForKey:@"title"]);
        XCTAssertNil([note.entity.attributesByName objectForKey:@"deletedAt"], @"version 1 has no deletedAt");
    }

    /* The app updated: the device opened with the current model migrates
       its store, history and all. */
    SNNotes *updated = [self deviceAt:store model:_momd];
    XCTAssertEqualObjects(updated.engine.replicaID, replica, @"the same device, to the server and its peers");
    SNNote *note = [updated notesInFolder:nil matching:nil].firstObject;
    XCTAssertEqualObjects(note.body, @"Before the update, and after");
    XCTAssertEqualObjects(note.folder.name, @"Home");
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

@end
