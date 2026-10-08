// simplenotes-server: SimpleNotes' OData service, the place every device's
// notes meet. ODataKit's server (HTTPServerKit, ODataService), with
// ODataSync's part of it: version vectors compared, deletions remembered.
//
//   simplenotes-server -StoreURL notes.sqlite -Port 8080 -Localhost NO
//   simplenotes-server -Config server.plist
//
// Settings (and SN_ variables: SN_PORT, SN_STORE_URL):
//
//   Model        the compiled model (default: SimpleNotes.momd beside the
//                server, or in its Resources)
//   StoreType    SQLite (the default); PostgreSQL or MySQL (MariaDB too):
//                FreeCoreData's SQL stores (CDPostgreSQLStore,
//                CDMySQLStore), loaded as lib<type> when not linked; or
//                any store type a loaded library registers. A store must
//                keep persistent history (delta links are read from it):
//                FreeCoreData's SQL stores do on GNUstep, not on Apple's
//                Core Data
//   StoreURL     where: a SQLite file (default SimpleNotes.sqlite here; a
//                plain path is a file; Temporary: one removed when the
//                server stops, for a demo or a test), or the database's
//                URL (postgresql://user:password@host/notes,
//                mysql://user:password@host:3306/notes)
//   MoveFrom     a store to move the notes from, as StoreURL names one (a
//                SQLite file, postgresql://…, mysql://…): its type from
//                its scheme, or MoveFromType. At start, when the store
//                (StoreType, StoreURL) has nothing in it yet, everything is
//                copied into it from there, which is left as it was;
//                devices read their notes again at their next sync. Once
//                moved, the setting does nothing, and can go
//   ServiceRoot  the public URL the service is reached at, its links
//                begin with (default http://<host>:<Port>/odata/)
//   Port, Localhost, AccessLog, and every other HTTPServerKit setting
//                (HSApplication.h); sign-in too: TrustedUserHeader for a
//                proxy that signs users in, or JWTIssuer and JWTAudience
//   AllowAnonymous  NO: a request that names no one is refused, once a
//                sign-in is set (default YES, for trying it out)
//   AllowAnonymousMetadata  NO: $metadata too is refused to one not
//                signed in (default YES: the apps read there how to sign
//                in)
//   Notebooks    PerUser: each signed-in user has their own folders and
//                notes (SNNotebooks.h); Shared: every device has all of
//                them. Default: PerUser once a sign-in is set
//                (TrustedUserHeader, JWTIssuer, IntrospectionEndpoint),
//                else Shared
//   GiveUnownedTo  a user's subject: the rows no one owns (made while the
//                notebook was shared) given to them, at start
//   PeerKey      the file of the key peer tokens are signed with (default
//                SimpleNotes-peer-key.json beside a SQLite store, else
//                here; made the first time); None: no peer tokens. Issued
//                once a sign-in is set: a user's devices nearby then sync
//                with each other while offline

#import <ODataService/ODataServer.h>
#include <dlfcn.h>
#import <ODataSync/ODataSyncService.h>
#import "SNModel.h"
#import "SNMigration.h"
#import "SNNotebooks.h"

@interface SNServerConfiguration : HSConfiguration
@end

@implementation SNServerConfiguration
+ (NSString *)environmentPrefix { return @"SN_"; }
+ (NSArray<NSString *> *)knownSettings {
    return [[super knownSettings] arrayByAddingObjectsFromArray:@[ @"Model", @"StoreType", @"StoreURL", @"MoveFrom", @"MoveFromType", @"ServiceRoot", @"AllowAnonymous", @"AllowAnonymousMetadata", @"Notebooks", @"GiveUnownedTo", @"PeerKey" ]];
}
@end

@interface SNServer : HSApplication
@property (nonatomic, strong) ODataService *service;
@property (nonatomic, strong) ODataSyncService *histories;
@end

@implementation SNServer

+ (Class)configurationClass { return [SNServerConfiguration class]; }

static NSString *SNTemporaryStore;

static void SNRemoveTemporaryStore(void) {
    for (NSString *suffix in @[ @"", @"-wal", @"-shm" ])
        [[NSFileManager defaultManager] removeItemAtPath:[SNTemporaryStore stringByAppendingString:suffix] error:NULL];
}

/* A URL as a log may show it: no password. */
static NSString *SNShown(NSURL *url) {
    if (url.isFileURL) return url.path;
    if (!url.password.length) return url.absoluteString;
    return [url.absoluteString stringByReplacingOccurrencesOfString:[@":" stringByAppendingString:url.password]
                                                         withString:@":***"];
}

/* A store type by its short name; one nothing registered, its library
   loaded by name (libCDPostgreSQLStore), which registers it as it loads. */
static NSString *SNStoreType(NSString *name) {
    NSDictionary *known = @{ @"SQLite": NSSQLiteStoreType, @"PostgreSQL": @"CDPostgreSQLStore", @"MySQL": @"CDMySQLStore",
                             @"MariaDB": @"CDMySQLStore" };
    NSString *type = known[name ?: @"SQLite"] ?: name;
    if (![NSPersistentStoreCoordinator registeredStoreTypes][type] &&
        [type rangeOfCharacterFromSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]].location == NSNotFound) {
#if defined(__APPLE__)
        NSString *library = [NSString stringWithFormat:@"lib%@.dylib", type];
#else
        NSString *library = [NSString stringWithFormat:@"lib%@.so", type];
#endif
        dlopen(library.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL);
    }
    return type;
}

static NSURL *SNURL(id value) {
    if (![value isKindOfClass:[NSString class]] || ![value length]) return nil;
    NSURL *url = [NSURL URLWithString:value];
    return url.scheme ? url : [NSURL fileURLWithPath:value];
}

- (BOOL)makeService:(NSError **)error {
    HSConfiguration *c = self.configuration;
    NSString *executable = [NSBundle mainBundle].executablePath.stringByDeletingLastPathComponent;
    NSURL *modelURL = SNURL([c setting:@"Model"]) ?: SNModelURLInBundle([NSBundle mainBundle])
        ?: [NSURL fileURLWithPath:[executable stringByAppendingPathComponent:@"SimpleNotes.momd"]];
    NSManagedObjectModel *model = SNModelAt(modelURL);
    if (!model) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadNoSuchFileError
                                            userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"no model at %@ (-Model)", modelURL.path] }];
        return NO;
    }
    /* The service's part of ODataSync: tombstones, before the store opens. */
    [ODataSyncService addBookkeepingToModel:model configuration:nil];
    NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    NSString *type = SNStoreType([c setting:@"StoreType"]);
    BOOL sqlite = [type isEqual:NSSQLiteStoreType];
    NSString *where = [c setting:@"StoreURL"];
    NSURL *url = SNURL(where) ?: (sqlite ? [NSURL fileURLWithPath:@"SimpleNotes.sqlite"] : nil);
    /* A store in memory keeps no history (Apple's): a temporary SQLite one
       instead, gone when the server stops. */
    if (sqlite && [where isEqual:@"Temporary"]) {
        SNTemporaryStore = [NSTemporaryDirectory() stringByAppendingPathComponent:
                               [NSString stringWithFormat:@"simplenotes-%@.sqlite", [NSProcessInfo processInfo].globallyUniqueString]];
        url = [NSURL fileURLWithPath:SNTemporaryStore];
        atexit(SNRemoveTemporaryStore);
    }
    /* An older version's store brought to this one: a SQLite file by the
       migrator (SNMigration.h), a database by FreeCoreData's SQL store
       itself, in place. */
    NSMutableDictionary *options = [@{ NSPersistentHistoryTrackingKey: @YES } mutableCopy];
    NSError *failure = nil;
    if (sqlite) {
        if ([modelURL.pathExtension isEqual:@"momd"] &&
            !SNMigrateStore(url, modelURL, [ODataSyncService class], &failure)) {
            if (error) *error = failure;
            return NO;
        }
    } else {
        options[@"CDSQLStoreMigrateSchema"] = @YES;
        options[NSIgnorePersistentStoreVersioningOption] = @YES;
    }
    /* The notes moved here from another store (MoveFrom), while this one
       has none: SNMoveStore (SNMigration.h). */
    BOOL moved = NO;
    NSURL *from = SNURL([c setting:@"MoveFrom"]);
    if (from) {
        NSString *scheme = from.scheme.lowercaseString;
        NSString *fromName = [c setting:@"MoveFromType"]
            ?: [scheme hasPrefix:@"postgres"] ? @"PostgreSQL" : [scheme isEqual:@"mysql"] || [scheme isEqual:@"mariadb"] ? @"MySQL" : @"SQLite";
        NSString *fromType = SNStoreType(fromName);
        NSMutableDictionary *fromOptions = [@{ NSPersistentHistoryTrackingKey: @YES } mutableCopy];
        if ([fromType isEqual:NSSQLiteStoreType]) {
            if (![[NSFileManager defaultManager] fileExistsAtPath:from.path]) {
                if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadNoSuchFileError
                                                    userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"no store to move from at %@ (-MoveFrom)", from.path] }];
                return NO;
            }
            if ([modelURL.pathExtension isEqual:@"momd"] && !SNMigrateStore(from, modelURL, [ODataSyncService class], &failure)) {
                if (error) *error = failure;
                return NO;
            }
        } else {
            fromOptions[@"CDSQLStoreMigrateSchema"] = @YES;
            fromOptions[NSIgnorePersistentStoreVersioningOption] = @YES;
        }
        if ([from isEqual:url]) {
            if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSPersistentStoreOperationError
                                                userInfo:@{ NSLocalizedDescriptionKey: @"MoveFrom names the store itself" }];
            return NO;
        }
        if (!SNMoveStore(model, fromType, from, fromOptions, type, url, options, &moved, &failure)) {
            if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSPersistentStoreOperationError
                                                userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"the notes were not moved from %@: %@",
                                                                                        SNShown(from), failure.localizedDescription] }];
            return NO;
        }
        if (moved) NSLog(@"the notes moved here from %@ (%@)", SNShown(from), fromName);
        else NSLog(@"MoveFrom: the store has notes already; nothing moved from %@", SNShown(from));
    }
    /* History: delta links are read from it. */
    if (![coordinator addPersistentStoreWithType:type configuration:nil URL:url options:options error:&failure]) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSPersistentStoreOpenError
                                            userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"the %@ store at %@ does not open: %@",
                                                                                    type, url ?: @"(none)", failure.localizedDescription] }];
        return NO;
    }
    NSURL *root = SNURL([c setting:@"ServiceRoot"])
        ?: [NSURL URLWithString:[NSString stringWithFormat:@"http://%@:%lu/odata/", c.bindToLocalhost ? @"127.0.0.1" : [NSProcessInfo processInfo].hostName,
                                                            (unsigned long)c.port]];
    _service = [[ODataService alloc] initWithPersistentStoreCoordinator:coordinator serviceRoot:root];
    _service.allowsAnonymousRequests = [c flag:@"AllowAnonymous" otherwise:YES];
    /* Moved: the history began again with the copy, so every delta link
       given before answers 410, and each device reads its notes again. */
    if (moved && ![_service pruneHistoryBeforeDate:[NSDate date] error:&failure]) {
        if (error) *error = failure;
        return NO;
    }
    /* How to sign in ($metadata's Authorization), to a device not signed
       in yet: SNSignIn reads it there. AllowAnonymousMetadata NO turns it
       off (ODataServiceModule reads it). */
    _service.allowsAnonymousMetadata = YES;
    /* Devices not yet updated write in their model's version: each version
       adds to the one before, and renames Updated Edited (SNUpgradeBody). */
    _service.upgradeBody = ^NSDictionary *(NSDictionary *body, NSString *version, NSEntityDescription *entity, ODataRequest *request, NSError **e) {
        return SNUpgradeBody(body, entity);
    };
    /* A notebook per user: its handlers before ODataSync's, which keeps
       them (they are ODataSync's kind). */
    NSString *notebooks = [c setting:@"Notebooks"];
    BOOL signIn = [c setting:@"TrustedUserHeader"] || [c setting:@"JWTIssuer"] || [c setting:@"IntrospectionEndpoint"];
    NSString *peerKey = [c setting:@"PeerKey"];
    BOOL peers = signIn && ![peerKey isEqual:@"None"];
    if (notebooks ? [notebooks caseInsensitiveCompare:@"PerUser"] == NSOrderedSame : signIn) SNServeNotebookPerUser(_service);
    NSString *heir = [c setting:@"GiveUnownedTo"];
    if (heir.length) {
        NSUInteger given = SNGiveUnownedRows(coordinator, heir, &failure);
        if (failure) {
            if (error) *error = failure;
            return NO;
        }
        NSLog(@"%lu rows no one owned given to %@", (unsigned long)given, heir);
    }
    _histories = [[ODataSyncService alloc] initWithService:_service];
    /* The notes' texts, merged as deltas come (and as older devices'
       whole states do). */
    SNRegisterMergers(_histories.engine);
    if (peers) {
        NSURL *file = peerKey.length ? [NSURL fileURLWithPath:peerKey]
            : [NSURL fileURLWithPath:@"SimpleNotes-peer-key.json"
                       relativeToURL:url.isFileURL && SNTemporaryStore == nil ? url.URLByDeletingLastPathComponent : nil];
        /* Moved from a SQLite file: its key comes along, so the peer
           tokens given before still hold. */
        NSURL *old = moved && from.isFileURL ? [from.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"SimpleNotes-peer-key.json"] : nil;
        NSFileManager *fm = [NSFileManager defaultManager];
        if (old && !peerKey.length && ![fm fileExistsAtPath:file.path] && [fm fileExistsAtPath:old.path])
            [fm copyItemAtPath:old.path toPath:file.path error:NULL];
        NSDictionary *key = SNPeerSigningKeyAt(file, &failure);
        if (!key) {
            if (error) *error = failure;
            return NO;
        }
        SNIssuePeerTokens(_histories, key);
    }
    return YES;
}

- (BOOL)prepare:(NSError **)error {
    if (!_service && ![self makeService:error]) return NO;
    return [super prepare:error];
}

- (void)configureModules:(NSMutableArray<id<HSModule>> *)modules {
    [super configureModules:modules];
    [modules addObject:[[ODataServiceModule alloc] initWithService:_service]];
}

@end

int main(int argc, const char *argv[]) {
    return HSMain(argc, argv, [SNServer class]);
}
