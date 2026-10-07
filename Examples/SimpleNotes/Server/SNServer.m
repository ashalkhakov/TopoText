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
//   ServiceRoot  the public URL the service is reached at, its links
//                begin with (default http://<host>:<Port>/odata/)
//   Port, Localhost, AccessLog, and every other HTTPServerKit setting
//                (HSApplication.h); sign-in too: TrustedUserHeader for a
//                proxy that signs users in, or JWTIssuer and JWTAudience
//   AllowAnonymous  NO: a request that names no one is refused, once a
//                sign-in is set (default YES, for trying it out)
//
// Every device syncs all of Folders and Notes: one shared notebook. A
// notebook per user is a handler's work (an ODataSyncSetHandler subclass
// that filters by the principal), left for later.

#import <ODataService/ODataServer.h>
#include <dlfcn.h>
#import <ODataSync/ODataSyncService.h>
#import "SNModel.h"
#import "SNMigration.h"

@interface SNServerConfiguration : HSConfiguration
@end

@implementation SNServerConfiguration
+ (NSString *)environmentPrefix { return @"SN_"; }
+ (NSArray<NSString *> *)knownSettings {
    return [[super knownSettings] arrayByAddingObjectsFromArray:@[ @"Model", @"StoreType", @"StoreURL", @"ServiceRoot", @"AllowAnonymous" ]];
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
    /* Devices not yet updated write in their model's version: each version
       only adds to the one before, so what they send is taken as it is. */
    _service.upgradeBody = ^NSDictionary *(NSDictionary *body, NSString *version, NSEntityDescription *entity, ODataRequest *request, NSError **e) {
        return body;
    };
    _histories = [[ODataSyncService alloc] initWithService:_service];
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
