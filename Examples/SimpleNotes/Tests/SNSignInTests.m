// Signing in as a device does: what the server asks for, from its
// $metadata; the device flow with an identity provider (answered here as
// Keycloak would); tokens kept, refreshed, and a sync signed in with them.

#import <XCTest/XCTest.h>
#import <ODataService/ODataService.h>
#import <ODataSync/ODataSyncService.h>
#import "SNModel.h"
#import "SNNotes.h"
#import "SNNotebooks.h"
#import "SNSignIn.h"

/* Kept in memory, as the Keychain would keep them. */
@interface SNMemorySecrets : NSObject <SNSecretStoring>
@property (nonatomic, strong) NSMutableDictionary *all;
@end

@implementation SNMemorySecrets
- (instancetype)init {
    if ((self = [super init])) _all = [NSMutableDictionary dictionary];
    return self;
}
- (NSDictionary *)secretsForAccount:(NSString *)account { return _all[account]; }
- (BOOL)setSecrets:(NSDictionary *)secrets forAccount:(NSString *)account {
    _all[account] = secrets;
    return YES;
}
@end

/* The server and the identity provider, answering as they would. */
@interface SNFakeSignIn : SNSignIn
@property (nonatomic, strong) ODataService *service;
@property (nonatomic, copy) NSDictionary *key;
@property (nonatomic) NSInteger polls, refreshes;
@property (nonatomic, copy) NSString *challenge;
@end

@implementation SNFakeSignIn

/* A form's value (application/x-www-form-urlencoded). */
static NSString *SNFormValue(NSString *form, NSString *name) {
    for (NSString *pair in [form componentsSeparatedByString:@"&"]) {
        NSArray *kv = [pair componentsSeparatedByString:@"="];
        if (kv.count == 2 && [kv[0] isEqual:name]) return [kv[1] stringByRemovingPercentEncoding];
    }
    return nil;
}

- (NSString *)tokenFor:(NSString *)user {
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    return HSSignJWT(@{ @"iss": @"https://id.test", @"sub": user, @"preferred_username": user, @"iat": @((long)now), @"exp": @((long)now + 3600) },
                     _key, NULL);
}

- (void)send:(NSURLRequest *)request done:(void (^)(NSData *, NSHTTPURLResponse *, NSError *))done {
    NSString *url = request.URL.absoluteString;
    NSString *form = request.HTTPBody ? [[NSString alloc] initWithData:request.HTTPBody encoding:NSUTF8StringEncoding] : @"";
    NSInteger status = 200;
    NSData *body = nil;
    if ([url hasSuffix:@"$metadata"]) {
        body = [[_service metadataXMLForVersion:@"4.01"] dataUsingEncoding:NSUTF8StringEncoding];
    } else if ([url hasSuffix:@"/.well-known/openid-configuration"]) {
        body = [NSJSONSerialization dataWithJSONObject:@{ @"issuer": @"https://id.test", @"device_authorization_endpoint": @"https://id.test/device",
                                                          @"token_endpoint": @"https://id.test/token" } options:0 error:NULL];
    } else if ([url hasSuffix:@"/device"] && ![SNFormValue(form, @"code_challenge_method") isEqual:@"S256"]) {
        /* As Keycloak answers with PKCE set on the client. */
        status = 400;
        body = [NSJSONSerialization dataWithJSONObject:@{ @"error": @"invalid_request", @"error_description": @"Missing parameter: code_challenge_method" }
                                               options:0 error:NULL];
    } else if ([url hasSuffix:@"/device"]) {
        _challenge = SNFormValue(form, @"code_challenge");
        body = [NSJSONSerialization dataWithJSONObject:@{ @"device_code": @"dc-1", @"user_code": @"WDJB-MJHT",
                                                          @"verification_uri": @"https://id.test/activate",
                                                          @"verification_uri_complete": @"https://id.test/activate?user_code=WDJB-MJHT",
                                                          @"interval": @0.05, @"expires_in": @60 } options:0 error:NULL];
    } else if ([url hasSuffix:@"/token"] && [form containsString:@"device_code"]) {
        /* Pending once (the user still signing in), then the tokens; for
           the verifier of the challenge only. */
        NSString *verifier = SNFormValue(form, @"code_verifier");
        if (!verifier || ![SNChallengeOfVerifier(verifier) isEqual:_challenge]) {
            status = 400;
            body = [NSJSONSerialization dataWithJSONObject:@{ @"error": @"invalid_grant", @"error_description": @"PKCE verification failed" }
                                                   options:0 error:NULL];
        } else if (_polls++ == 0) {
            status = 400;
            body = [NSJSONSerialization dataWithJSONObject:@{ @"error": @"authorization_pending" } options:0 error:NULL];
        } else {
            body = [NSJSONSerialization dataWithJSONObject:@{ @"access_token": [self tokenFor:@"alice"], @"refresh_token": @"refresh-1",
                                                              @"id_token": [self tokenFor:@"alice"], @"expires_in": @300 } options:0 error:NULL];
        }
    } else if ([url hasSuffix:@"/token"] && [form containsString:@"refresh_token"]) {
        _refreshes++;
        body = [NSJSONSerialization dataWithJSONObject:@{ @"access_token": [self tokenFor:@"alice"], @"refresh_token": @"refresh-2", @"expires_in": @300 }
                                               options:0 error:NULL];
    } else {
        status = 404;
    }
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:request.URL statusCode:status HTTPVersion:@"HTTP/1.1" headerFields:@{}];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        done(body, response, nil);
    });
}

@end

@interface SNSignInTests : XCTestCase <SNSignInDelegate>
@end

@implementation SNSignInTests {
    NSMutableArray<NSURL *> *_files;
    ODataService *_service;
    ODataSyncService *_histories;
    NSPersistentStoreCoordinator *_server;
    NSDictionary *_key;
    NSString *_code;
    BOOL _learnt, _finished;
    NSError *_failed;
}

- (NSURL *)temporaryStore {
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
                                            [NSString stringWithFormat:@"sn-signin-%@.sqlite", [NSProcessInfo processInfo].globallyUniqueString]]];
    [_files addObject:url];
    return url;
}

- (void)setUp {
    _files = [NSMutableArray array];
    NSManagedObjectModel *model = SNModelAt(SNModelURLInBundle([NSBundle bundleForClass:[self class]]));
    [ODataSyncService addBookkeepingToModel:model configuration:nil];
    _server = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    [_server addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:[self temporaryStore]
                                options:@{ NSPersistentHistoryTrackingKey: @YES } error:NULL];
    _service = [[ODataService alloc] initWithPersistentStoreCoordinator:_server serviceRoot:[NSURL URLWithString:@"http://notes.test/odata/"]];
    _key = HSGenerateSigningKey(NULL);
    HSJWTAuthenticator *jwt = [[HSJWTAuthenticator alloc] initWithIssuer:@"https://id.test" audience:nil];
    jwt.keySet = @{ @"keys": @[ HSPublicKey(_key) ] };
    _service.authenticator = jwt;
    _service.allowsAnonymousMetadata = YES;
    SNServeNotebookPerUser(_service);
    _histories = [[ODataSyncService alloc] initWithService:_service];
}

- (void)tearDown {
    for (NSURL *url in _files)
        for (NSString *suffix in @[ @"", @"-wal", @"-shm" ])
            [[NSFileManager defaultManager] removeItemAtPath:[url.path stringByAppendingString:suffix] error:NULL];
}

- (void)waitFor:(BOOL *)flag {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:10];
    while (!*flag && !_failed && [until timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
}

- (void)signInDidLearn:(SNSignIn *)signIn { _learnt = YES; }
- (void)signIn:(SNSignIn *)signIn showCode:(NSString *)code page:(NSURL *)page completePage:(NSURL *)completePage { _code = code; }
- (void)signInDidFinish:(SNSignIn *)signIn { _finished = YES; }
- (void)signIn:(SNSignIn *)signIn didFail:(NSError *)error { _failed = error; }

- (SNFakeSignIn *)signInWith:(id<SNSecretStoring>)secrets {
    SNFakeSignIn *s = [[SNFakeSignIn alloc] initWithServiceRoot:[NSURL URLWithString:@"http://notes.test/odata/"] secrets:secrets];
    s.service = _service;
    s.key = _key;
    s.delegate = self;
    return s;
}

/* RFC 7636's own example: the challenge of its verifier. */
- (void)testPKCEChallenge {
    XCTAssertEqualObjects(SNChallengeOfVerifier(@"dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"), @"E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM");
}

- (void)testTheServerSaysHowToSignIn {
    SNSignIn *s = [self signInWith:[[SNMemorySecrets alloc] init]];
    [s learn];
    [self waitFor:&_learnt];
    XCTAssertNil(_failed);
    XCTAssertEqual(s.kind, SNSignInOpenID);
    XCTAssertEqualObjects(s.issuer.absoluteString, @"https://id.test");
    XCTAssertFalse(s.signedIn);
}

/* The device flow: a code shown, signed in elsewhere, tokens kept; a sync
   signed in with them is alice's. */
- (void)testSigningInWithACodeAndSyncing {
    SNMemorySecrets *secrets = [[SNMemorySecrets alloc] init];
    SNFakeSignIn *s = [self signInWith:secrets];
    [s begin];
    [self waitFor:&_finished];
    XCTAssertNil(_failed, @"%@", _failed);
    XCTAssertEqualObjects(_code, @"WDJB-MJHT", @"the code shown");
    XCTAssertEqual(s.polls, 2, @"pending once, then signed in");
    XCTAssertTrue(s.signedIn);
    XCTAssertEqualObjects(s.userName, @"alice");
    /* Kept: another sign-in for the same server is signed in already. */
    SNSignIn *again = [self signInWith:secrets];
    XCTAssertTrue(again.signedIn);
    XCTAssertEqualObjects(again.userName, @"alice");

    SNNotes *device = [[SNNotes alloc] initWithStoreURL:[self temporaryStore] modelURL:SNModelURLInBundle([NSBundle bundleForClass:[self class]]) error:NULL];
    device.transport = _service;
    device.configuration = s.configuration;
    device.serviceRoot = [NSURL URLWithString:@"http://notes.test/odata/"];
    [device addNoteInFolder:nil];
    NSError *error = nil;
    XCTAssertTrue([device syncAndWait:&error], @"%@", error);
    NSManagedObjectContext *c = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    c.persistentStoreCoordinator = _server;
    XCTAssertEqualObjects([[c executeFetchRequest:[NSFetchRequest fetchRequestWithEntityName:SNNoteEntity] error:NULL] valueForKey:@"owner"], @[ @"alice" ]);

    /* Run out: refreshed. Signed out: no token. */
    NSMutableDictionary *kept = [secrets.all[@"http://notes.test/odata/"] mutableCopy];
    kept[@"expires"] = @0;
    secrets.all[@"http://notes.test/odata/"] = kept;
    XCTAssertNotNil([s accessTokenForAuthorization:nil refresh:NO]);
    XCTAssertEqual(s.refreshes, 1);
    [s signOut];
    XCTAssertFalse(s.signedIn);
    XCTAssertNil([s accessTokenForAuthorization:nil refresh:NO]);
}

@end
