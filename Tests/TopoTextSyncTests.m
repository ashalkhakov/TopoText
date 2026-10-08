#import <XCTest/XCTest.h>
#import <ODataSync/ODataSync.h>
#import <ODataService/ODataService.h>
#import <TopoTextSync/TopoTextSync.h>

/* A note's body edited on two devices while each was offline, synced through
   an ODataService in the process, and between the devices as peers: both
   edits in the end, on every side. */

@interface ODataSyncConflict (TopoTextTests)
- (instancetype)initWithEntity:(NSEntityDescription *)entity key:(NSDictionary *)key base:(NSDictionary *)base
                         local:(NSDictionary *)local remote:(NSDictionary *)remote
                  localChanges:(NSSet *)localChanges remoteChanges:(NSSet *)remoteChanges withPeer:(BOOL)withPeer;
@end

static NSAttributeDescription *TTAttribute(NSString *name, NSAttributeType type, NSDictionary *info) {
    NSAttributeDescription *a = [[NSAttributeDescription alloc] init];
    a.name = name;
    a.attributeType = type;
    a.optional = YES;
    a.preservesValueInHistoryOnDeletion = YES;
    a.userInfo = info ?: @{};
    return a;
}

static NSManagedObjectModel *TTNotesModel(void) {
    NSEntityDescription *note = [[NSEntityDescription alloc] init];
    note.name = @"Note";
    note.managedObjectClassName = @"NSManagedObject";
    note.userInfo = @{ @"OData.entitySet": @"Notes", ODataSyncDirectionKey: @"both",
                       ODataSyncModifiedKey: @"modified", ODataSyncVersionsKey: @"versions" };
    note.properties = @[ TTAttribute(@"id", NSStringAttributeType, @{ @"OData.key": @"YES" }),
                         TTAttribute(@"title", NSStringAttributeType, nil),
                         TTAttribute(@"body", NSStringAttributeType, nil),
                         TTAttribute(@"bodyText", NSBinaryDataAttributeType, @{ TTSyncTextKey: @"YES", TTSyncStringKey: @"body" }),
                         TTAttribute(@"modified", NSStringAttributeType, nil),
                         TTAttribute(@"versions", NSStringAttributeType, nil) ];
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
    model.entities = @[ note ];
    return model;
}

@interface TopoTextSyncTests : XCTestCase
@end

@implementation TopoTextSyncTests {
    NSMutableArray<NSURL *> *_files;
    NSMutableArray *_keep;
    NSPersistentStoreCoordinator *_server;
    ODataService *_service;
}

- (NSPersistentStoreCoordinator *)coordinatorWithModel:(NSManagedObjectModel *)model {
    NSPersistentStoreCoordinator *c = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]]];
    [_files addObject:url];
    NSError *error = nil;
    XCTAssertNotNil([c addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:url
                                          options:@{ NSPersistentHistoryTrackingKey: @YES } error:&error], @"%@", error);
    return c;
}

- (void)setUp {
    _files = [NSMutableArray array];
    _keep = [NSMutableArray array];
    _server = [self coordinatorWithModel:TTNotesModel()];
    _service = [[ODataService alloc] initWithPersistentStoreCoordinator:_server serviceRoot:[NSURL URLWithString:@"http://example.test/odata/"]];
}

- (void)tearDown {
    for (NSURL *url in _files)
        for (NSString *suffix in @[ @"", @"-wal", @"-shm" ])
            [[NSFileManager defaultManager] removeItemAtPath:[url.path stringByAppendingString:suffix] error:NULL];
}

- (ODataSyncEngine *)deviceWithService:(BOOL)service {
    NSManagedObjectModel *model = TTNotesModel();
    [ODataSyncEngine addBookkeepingToModel:model configuration:nil];
    ODataSyncEngine *engine = [[ODataSyncEngine alloc] initWithCoordinator:[self coordinatorWithModel:model]];
    engine.resolver = [[TTSyncResolver alloc] init];
    if (service) {
        ODataSyncRemote *remote = [ODataSyncRemote remoteWithServiceRoot:[NSURL URLWithString:@"http://example.test/odata/"]];
        remote.transport = _service;
        [engine addRemote:remote];
    }
    return engine;
}

- (ODataSyncRemote *)peerOf:(ODataSyncEngine *)engine {
    ODataSyncPeerServer *server = [[ODataSyncPeerServer alloc] initWithEngine:engine host:@"peer.test" port:8642];
    [_keep addObject:server];
    ODataSyncRemote *peer = [ODataSyncRemote peerWithServiceRoot:server.serviceRoot];
    peer.transport = server.service;
    return peer;
}

- (void)in:(NSPersistentStoreCoordinator *)coordinator do:(void (^)(NSManagedObjectContext *context))work {
    NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    context.persistentStoreCoordinator = coordinator;
    [context performBlockAndWait:^{
        work(context);
        NSError *error = nil;
        if (context.hasChanges) XCTAssertTrue([context save:&error], @"%@", error);
    }];
}

- (NSManagedObject *)note:(NSManagedObjectContext *)context {
    NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Note"];
    fetch.predicate = [NSPredicate predicateWithFormat:@"id == 'n1'"];
    return [[context executeFetchRequest:fetch error:NULL] firstObject];
}

/* The note's text where coordinator keeps it, and its plain string, and its title. */
- (NSArray *)noteIn:(NSPersistentStoreCoordinator *)coordinator {
    __block NSArray *out = nil;
    [self in:coordinator do:^(NSManagedObjectContext *context) {
        NSManagedObject *n = [self note:context];
        TopoText *t = [n tt_textForKey:@"bodyText"];
        out = @[ t.attributedString, [n valueForKey:@"body"] ?: [NSNull null], [n valueForKey:@"title"] ?: [NSNull null],
                 [n valueForKey:@"bodyText"] ?: [NSNull null] ];
    }];
    return out;
}

- (void)edit:(ODataSyncEngine *)device with:(void (^)(TopoText *text, NSManagedObject *note))work {
    [self in:device.coordinator do:^(NSManagedObjectContext *context) {
        NSManagedObject *n = [self note:context];
        TopoText *t = [n tt_textForKey:@"bodyText"];
        work(t, n);
        [n tt_setText:t forKey:@"bodyText"];
    }];
}

- (void)sync:(ODataSyncEngine *)device {
    NSError *error = nil;
    XCTAssertTrue([device syncWithError:&error], @"%@", error);
}

- (void)syncDevice:(ODataSyncEngine *)device withRemote:(ODataSyncRemote *)remote {
    NSError *error = nil;
    XCTAssertTrue([device syncWithRemote:remote error:&error], @"%@", error);
}

- (void)createNoteOn:(ODataSyncEngine *)device {
    [self in:device.coordinator do:^(NSManagedObjectContext *context) {
        NSManagedObject *n = [NSEntityDescription insertNewObjectForEntityForName:@"Note" inManagedObjectContext:context];
        [n setValue:@"n1" forKey:@"id"];
        [n setValue:@"Groceries" forKey:@"title"];
        TopoText *t = [TopoText text];
        [t insertString:@"Hello world" atIndex:0 attributes:nil];
        [n tt_setText:t forKey:@"bodyText"];
    }];
}

- (void)testEditsMadeApartAreMergedThroughTheService {
    ODataSyncEngine *a = [self deviceWithService:YES], *b = [self deviceWithService:YES];
    [self createNoteOn:a];
    [self sync:a];
    [self sync:b];
    XCTAssertEqualObjects([self noteIn:b.coordinator][1], @"Hello world");

    /* Both offline: a types into the middle and retitles; b makes "Hello" bold and adds a line. */
    [self edit:a with:^(TopoText *t, NSManagedObject *n) {
        [t insertString:@"big " atIndex:6 attributes:nil];
        [n setValue:@"Shopping" forKey:@"title"];
    }];
    [self edit:b with:^(TopoText *t, NSManagedObject *n) {
        [t addAttributes:@{ @"bold": @YES } range:NSMakeRange(0, 5)];
        [t insertString:@"\n- milk" atIndex:t.length attributes:nil];
    }];
    [self sync:a];  /* the service has a's */
    [self sync:b];  /* b meets a's: a conflict, merged, sent */
    [self sync:a];  /* a takes the merge: it includes its own */

    NSArray *atA = [self noteIn:a.coordinator], *atB = [self noteIn:b.coordinator], *atService = [self noteIn:_server];
    XCTAssertEqualObjects([atA[0] string], @"Hello big world\n- milk");
    XCTAssertEqualObjects(atA[0], atB[0]);
    XCTAssertEqualObjects(atA[0], atService[0]);
    XCTAssertEqualObjects(atA[3], atB[3], @"the same state, byte for byte");
    XCTAssertEqualObjects(atService[1], @"Hello big world\n- milk", @"the service's plain text, for $filter and $search");
    XCTAssertEqualObjects([atA[0] attributesAtIndex:0 effectiveRange:NULL], @{ @"bold": @YES });
    XCTAssertEqualObjects(atB[2], @"Shopping", @"what only one side changed, from it");
    XCTAssertEqual(b.issues.count, 0u);

    /* And again: nothing left to settle. */
    [self sync:b];
    [self sync:a];
    XCTAssertEqualObjects([self noteIn:a.coordinator][3], [self noteIn:b.coordinator][3]);
}

- (void)testEditsMadeApartAreMergedBetweenPeers {
    ODataSyncEngine *a = [self deviceWithService:YES], *b = [self deviceWithService:YES];
    [self createNoteOn:a];
    [self sync:a];
    [self sync:b];
    /* The service out of reach: the devices meet each other. */
    [self edit:a with:^(TopoText *t, NSManagedObject *n) { [t insertString:@"Oh, " atIndex:0 attributes:nil]; }];
    [self edit:b with:^(TopoText *t, NSManagedObject *n) { [t deleteCharactersInRange:NSMakeRange(5, 6)]; }];
    ODataSyncRemote *bAsSeenByA = [self peerOf:b], *aAsSeenByB = [self peerOf:a];
    [self syncDevice:a withRemote:bAsSeenByA];
    [self syncDevice:b withRemote:aAsSeenByB];
    [self syncDevice:a withRemote:bAsSeenByA];
    NSArray *atA = [self noteIn:a.coordinator], *atB = [self noteIn:b.coordinator];
    XCTAssertEqualObjects([atA[0] string], @"Oh, Hello");
    XCTAssertEqualObjects(atA[3], atB[3]);
    /* Back in reach: one goes up, the other comes down to the same. */
    [self sync:a];
    [self sync:b];
    XCTAssertEqualObjects([self noteIn:_server][3], atA[3]);
    XCTAssertEqualObjects([self noteIn:b.coordinator][3], atA[3]);
}

/* With a peer, the resolution must be the same whichever side asks. */
- (void)testTheMergeIsTheSameFromEitherSide {
    NSEntityDescription *note = TTNotesModel().entitiesByName[@"Note"];
    TopoText *base = [TopoText textWithReplica:1];
    [base insertString:@"shared" atIndex:0 attributes:nil];
    TopoText *x = [base copyWithReplica:2], *y = [base copyWithReplica:3];
    [x insertString:@"x" atIndex:0 attributes:nil];
    [y insertString:@"y" atIndex:6 attributes:@{ @"bold": @YES }];
    NSDictionary *bx = @{ @"id": @"n1", @"bodyText": x.data, @"body": x.string, @"title": @"T" };
    NSDictionary *by = @{ @"id": @"n1", @"bodyText": y.data, @"body": y.string, @"title": @"T" };
    NSDictionary *bb = @{ @"id": @"n1", @"bodyText": base.data, @"body": base.string, @"title": @"T" };
    NSSet *changed = [NSSet setWithObjects:@"bodyText", @"body", nil];
    TTSyncResolver *resolver = [[TTSyncResolver alloc] init];
    ODataSyncConflict *one = [[ODataSyncConflict alloc] initWithEntity:note key:@{ @"id": @"n1" } base:bb local:bx remote:by
                                                          localChanges:changed remoteChanges:changed withPeer:YES];
    ODataSyncConflict *two = [[ODataSyncConflict alloc] initWithEntity:note key:@{ @"id": @"n1" } base:bb local:by remote:bx
                                                          localChanges:changed remoteChanges:changed withPeer:YES];
    ODataSyncResolution *r1 = [resolver resolveConflict:one], *r2 = [resolver resolveConflict:two];
    XCTAssertEqual(r1.kind, ODataSyncMerge);
    XCTAssertEqualObjects(r1.values[@"bodyText"], r2.values[@"bodyText"]);
    XCTAssertEqualObjects(r1.values[@"body"], @"xsharedy");
    XCTAssertEqualObjects(r2.values[@"body"], @"xsharedy");
}

/* The merger ODataSync moves deltas with: what a copy lacks and nothing
   more, both ways; and what both copies have seen deleted collected. */
- (void)testTheMergerMovesDeltasAndCollects {
    TTSyncMerger *merger = [[TTSyncMerger alloc] init];
    TopoText *a = [TopoText textWithReplica:1];
    [a insertString:@"hello world" atIndex:0 attributes:nil];
    NSData *atA = a.data;
    /* A copy with nothing gets it whole. */
    NSData *atB = [merger stateByMerging:[merger deltaOfState:atA sinceVersion:nil] intoState:nil error:NULL];
    XCTAssertEqualObjects([TopoText textWithData:atB replica:2 error:NULL].string, @"hello world");
    XCTAssertEqual([merger deltaOfState:atA sinceVersion:[merger versionOfState:atB]].length, 0u, @"nothing it lacks: an empty delta");

    /* Apart: a deletes " world" (at the end: nothing is placed by it), b
       adds "Oh, " before it all. */
    TopoText *ta = [TopoText textWithData:atA replica:1 error:NULL], *tb = [TopoText textWithData:atB replica:2 error:NULL];
    [ta deleteCharactersInRange:NSMakeRange(5, 6)];
    [tb insertString:@"Oh, " atIndex:0 attributes:nil];
    atA = ta.data;
    atB = tb.data;
    NSData *toB = [merger deltaOfState:atA sinceVersion:[merger versionOfState:atB]];
    NSData *toA = [merger deltaOfState:atB sinceVersion:[merger versionOfState:atA]];
    XCTAssertLessThan(toB.length, atA.length, @"a delta, not the state");
    atA = [merger stateByMerging:toA intoState:atA error:NULL];
    atB = [merger stateByMerging:toB intoState:atB error:NULL];
    XCTAssertEqualObjects([TopoText textWithData:atA replica:1 error:NULL].string, @"Oh, hello");
    XCTAssertEqualObjects([TopoText textWithData:atB replica:2 error:NULL].string, @"Oh, hello");

    /* Both have seen " world" deleted: it goes, and the text stays. */
    NSData *seen = [merger versionMeeting:[merger versionOfState:atA] andVersion:[merger versionOfState:atB]];
    NSData *collected = [merger stateByCollecting:atA seenBy:seen];
    TopoText *after = [TopoText textWithData:collected replica:1 error:NULL];
    XCTAssertEqualObjects(after.string, @"Oh, hello");
    XCTAssertLessThan(after.tombstoneCount, [TopoText textWithData:atA replica:1 error:NULL].tombstoneCount);
    XCTAssertEqualObjects([merger stateByCollecting:collected seenBy:seen], collected, @"nothing more to collect: the same state");
    NSError *error = nil;
    XCTAssertNil([merger stateByMerging:[@"not text" dataUsingEncoding:NSUTF8StringEncoding] intoState:atA error:&error]);
    XCTAssertNotNil(error);
}

@end
