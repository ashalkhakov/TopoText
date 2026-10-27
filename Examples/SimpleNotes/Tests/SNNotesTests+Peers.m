// SimpleNotes' devices nearby, as SNPeers finds and syncs with them, and the
// server's part in it (peer tokens): SNNotesTests', in a file of its own,
// which a build without devices nearby (Windows, for now) leaves out.

#import <XCTest/XCTest.h>
#import <ODataSync/ODataSync.h>
#import "SNNotesTests.h"
#import "SNNotebooks.h"
#import "SNPeers.h"

/* A device nearby as the browser would say it is, made here. */
@interface SNTestAnnouncement : ODataSyncPeerAnnouncement
@property (nonatomic, copy) NSString *givenName;
@end

@implementation SNTestAnnouncement
- (NSString *)name { return _givenName; }
- (NSString *)thumbprint { return [@"thumbprint-" stringByAppendingString:_givenName]; }
- (NSString *)replica { return _givenName; }
- (NSString *)host { return @"127.0.0.1"; }
- (NSUInteger)port { return 1; }
- (NSURL *)serviceRoot { return [NSURL URLWithString:[NSString stringWithFormat:@"https://127.0.0.1:1/sync/%@/", _givenName]]; }
@end

/* SNPeers with its devices found given, a token or not, and its syncs
   with them run against the server instead (or one that cannot be
   reached, for a device that refuses): what it syncs with, and when. */
@interface SNTestPeers : SNPeers
@property (nonatomic, copy) NSArray<ODataSyncPeerAnnouncement *> *given;
@property (nonatomic) BOOL token;
@property (nonatomic, copy) NSSet<NSString *> *refusing;
@property (nonatomic, strong) NSMutableArray<NSString *> *syncedWith;
@end

@interface SNPeers (Browsing)
- (void)peerBrowser:(nullable ODataSyncPeerBrowser *)browser didFindPeer:(ODataSyncPeerAnnouncement *)peer;
@end

@implementation SNTestPeers
- (NSArray *)found { return _given ?: @[]; }
- (void)startBrowsing {}
- (BOOL)hasToken { return _token; }
- (BOOL)syncWithPeer:(ODataSyncPeerAnnouncement *)peer {
    [_syncedWith addObject:peer.name];
    ODataSyncRemote *remote = [_refusing containsObject:peer.name] ? [ODataSyncRemote peerWithServiceRoot:peer.serviceRoot] : self.notes.serverRemote;
    return [self.notes syncWithRemote:remote named:peer.name];
}
@end

@implementation SNNotesTests (Peers)

/* Devices nearby synced with by themselves (automatic): none without a
   token or a pairing; one as it is found; again a moment after a change
   here; one that refused, not again for a while; nothing once it is off. */
- (void)testDevicesNearbyAreSyncedWithByThemselves {
    SNNotes *a = [self device];
    [self sync:a];
    NSURL *directory = [[self temporaryStore] URLByAppendingPathExtension:@"peers"];
    [self removeAfterTest:directory];
    NSError *error = nil;
    SNTestPeers *peers = [[SNTestPeers alloc] initWithNotes:a directory:directory error:&error];
    XCTAssertNotNil(peers, @"%@", error);
    peers.syncedWith = [NSMutableArray array];
    peers.changeDelay = 0.2;
    peers.syncInterval = 1000;
    peers.refusalPause = 1000;
    SNTestAnnouncement *mine = [[SNTestAnnouncement alloc] init], *stranger = [[SNTestAnnouncement alloc] init];
    mine.givenName = @"Mine";
    stranger.givenName = @"Stranger";
    peers.given = @[ mine ];

    peers.automatic = YES;
    [self waitUntil:^BOOL { return NO; } for:0.5];
    XCTAssertEqualObjects(peers.syncedWith, @[], @"no token, no pairing: not synced with");

    peers.token = YES;
    [peers peerBrowser:nil didFindPeer:mine];
    [self waitUntil:^BOOL { return peers.syncedWith.count == 1 && !a.syncing; }];
    XCTAssertEqualObjects(peers.syncedWith, @[ @"Mine" ], @"synced with as it is found");

    [a addNoteInFolder:nil];
    [self waitUntil:^BOOL { return peers.syncedWith.count == 2 && !a.syncing; }];
    XCTAssertEqualObjects(peers.syncedWith, (@[ @"Mine", @"Mine" ]), @"again, a moment after a change here");

    peers.refusing = [NSSet setWithObject:@"Stranger"];
    peers.given = @[ mine, stranger ];
    [peers peerBrowser:nil didFindPeer:stranger];
    [self waitUntil:^BOOL { return [peers.syncedWith containsObject:@"Stranger"] && !a.syncing; }];
    XCTAssertTrue([peers.syncedWith containsObject:@"Stranger"]);
    [self waitUntil:^BOOL { return NO; } for:0.5];
    NSUInteger before = peers.syncedWith.count;
    [a addNoteInFolder:nil];
    [self waitUntil:^BOOL { return peers.syncedWith.count > before && !a.syncing; }];
    NSUInteger strangers = 0;
    for (NSString *name in peers.syncedWith) strangers += [name isEqual:@"Stranger"];
    XCTAssertEqual(strangers, 1u, @"one that refused is not tried again soon: %@", peers.syncedWith);
    XCTAssertEqualObjects(peers.syncedWith.lastObject, @"Mine");

    peers.automatic = NO;
    before = peers.syncedWith.count;
    [a addNoteInFolder:nil];
    [self waitUntil:^BOOL { return NO; } for:0.5];
    XCTAssertEqual(peers.syncedWith.count, before, @"off: not synced with");
    [peers stop];
    [peers.trust.identity removeWithError:NULL];
}

/* The server signs peer tokens with a key it keeps; a signed-in device
   asks for one, and keeps it. */
- (void)testAServerIssuesPeerTokens {
    NSURL *file = [self temporaryStore];
    NSError *error = nil;
    NSDictionary *signing = SNPeerSigningKeyAt(file, &error);
    XCTAssertNotNil(signing, @"%@", error);
    XCTAssertEqualObjects(SNPeerSigningKeyAt(file, NULL), signing, @"made once, then kept");
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:file.path error:NULL];
    XCTAssertEqual([attributes[NSFilePosixPermissions] integerValue], 0600);
    /* Where none can be made (a mount point the server's user cannot
       write): the error names the file, and why. */
    NSURL *nowhere = [[self temporaryStore] URLByAppendingPathComponent:@"SimpleNotes-peer-key.json"];
    XCTAssertNil(SNPeerSigningKeyAt(nowhere, &error));
    XCTAssertTrue([error.localizedDescription containsString:nowhere.path], @"%@", error.localizedDescription);
    XCTAssertTrue([error.localizedDescription containsString:@(strerror(ENOENT))], @"%@", error.localizedDescription);
    error = nil;

    NSDictionary *key = [self serveNotebooksPerUser];
    SNIssuePeerTokens(self.histories, signing);
    SNNotes *alice = [self deviceOf:@"alice" key:key];
    NSURL *directory = [[self temporaryStore] URLByAppendingPathExtension:@"peers"];
    [self removeAfterTest:directory];
    SNPeers *peers = [[SNPeers alloc] initWithNotes:alice directory:directory error:&error];
    XCTAssertNotNil(peers, @"%@", error);
    XCTAssertFalse(peers.hasToken);
    [peers fetchToken];
    [self waitUntil:^BOOL { return !peers.fetchingToken; }];
    XCTAssertTrue(peers.hasToken, @"%@", peers.status);
    XCTAssertGreaterThan(peers.tokenExpires.timeIntervalSinceNow, 3600);
    [peers stop];
    /* Kept: the next launch has it. */
    SNPeers *again = [[SNPeers alloc] initWithNotes:alice directory:directory error:&error];
    XCTAssertTrue(again.hasToken);
    [again.trust.identity removeWithError:NULL];
    [[NSFileManager defaultManager] removeItemAtURL:directory error:NULL];
}

@end
