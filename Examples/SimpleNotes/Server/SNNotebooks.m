#import "SNNotebooks.h"
#import "SNVersions.h"
#import <ODataKit/ODataError.h>
#import "SNModel.h"

static NSString * const SNOwner = @"owner";

@implementation SNNotebookHandler

/* The signed-in user (nil: no one, an anonymous request). */
static NSString *SNOwnerOf(ODataRequest *request) {
    return request.principal.subject;
}

- (NSPredicate *)predicateForVisibleObjectsInRequest:(ODataRequest *)request {
    NSPredicate *theirs = [super predicateForVisibleObjectsInRequest:request];
    if (!_perUser) return theirs;
    NSPredicate *mine = [NSPredicate predicateWithFormat:@"%K == %@", SNOwner, SNOwnerOf(request)];
    return theirs ? [NSCompoundPredicate andPredicateWithSubpredicates:@[ theirs, mine ]] : mine;
}

/* A note's versions are the server's to make and let go of. */
- (BOOL)refusesWrites:(ODataReply *)reply {
    if (![self.entity.name isEqualToString:SNNoteVersionEntity]) return NO;
    [reply failWithError:ODataServiceError(403, @"A note's versions are the server's: read them, do not write them")];
    return YES;
}

- (NSManagedObject *)insertObjectWithValues:(NSDictionary<NSString *, id> *)values request:(ODataRequest *)request reply:(ODataReply *)reply {
    if ([self refusesWrites:reply]) return nil;
    NSManagedObject *made = [super insertObjectWithValues:values request:request reply:reply];
    if (_perUser) [made setValue:SNOwnerOf(request) forKey:SNOwner];
    return made;
}

- (NSManagedObject *)updateObject:(NSManagedObject *)object values:(NSDictionary<NSString *, id> *)values request:(ODataRequest *)request
                            reply:(ODataReply *)reply {
    if ([self refusesWrites:reply]) return nil;
    /* The text it had, kept before it changes: its plain text (a device's
       write of the row) or its rich text (merged), whichever comes first. */
    if ([self.entity.name isEqualToString:SNNoteEntity] && (values[@"bodyText"] || values[@"body"])) SNKeepVersionOfNote(object, [NSDate date]);
    return [super updateObject:object values:values request:request reply:reply];
}

- (void)deleteObject:(NSManagedObject *)object request:(ODataRequest *)request reply:(ODataReply *)reply {
    if ([self refusesWrites:reply]) return;
    /* A note deleted for good: its versions with it. */
    if ([self.entity.name isEqualToString:SNNoteEntity]) SNForgetVersionsOfNote(object);
    [super deleteObject:object request:request reply:reply];
}

@end

void SNServeNotebooks(ODataService *service, BOOL perUser) {
    for (NSEntityDescription *entity in service.model.entities) {
        if (![entity.attributesByName objectForKey:SNOwner] || entity.superentity) continue;
        NSString *set = entity.userInfo[@"OData.entitySet"];
        if (!set.length) continue;
        SNNotebookHandler *handler = [[SNNotebookHandler alloc] initWithEntity:entity];
        handler.perUser = perUser;
        [service setHandler:handler forEntitySet:set];
    }
}

NSUInteger SNGiveUnownedRows(NSPersistentStoreCoordinator *coordinator, NSString *owner, NSError **error) {
    NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    context.persistentStoreCoordinator = coordinator;
    __block NSUInteger given = 0;
    __block BOOL ok = YES;
    __block NSError *failure = nil;
    [context performBlockAndWait:^{
        for (NSEntityDescription *entity in coordinator.managedObjectModel.entities) {
            if (![entity.attributesByName objectForKey:SNOwner] || entity.superentity) continue;
            NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:entity.name];
            f.predicate = [NSPredicate predicateWithFormat:@"%K == nil", SNOwner];
            for (NSManagedObject *o in [context executeFetchRequest:f error:NULL] ?: @[]) {
                [o setValue:owner forKey:SNOwner];
                given++;
            }
        }
        NSError *e = nil;
        if (context.hasChanges) ok = [context save:&e];
        failure = e;
    }];
    if (!ok && error) *error = failure;
    return ok ? given : 0;
}

NSDictionary *SNPeerSigningKeyAt(NSURL *file, NSError **error) {
    NSData *data = [NSData dataWithContentsOfURL:file];
    if (data) {
        NSDictionary *kept = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        if ([kept isKindOfClass:[NSDictionary class]] && [kept[@"kty"] isEqual:@"EC"] && [kept[@"d"] isKindOfClass:[NSString class]]) return kept;
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError
                                            userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%@ is not a signing key (a P-256 JWK)", file.path] }];
        return nil;
    }
    NSDictionary *made = HSGenerateSigningKey(error);
    if (!made) return nil;
    data = [NSJSONSerialization dataWithJSONObject:made options:0 error:error];
    if (!data) return nil;
    /* The server's user's alone, from the first byte. Not made: said with
       the file and why, as the file manager says neither (a directory the
       server's user cannot write, as a new mount point is). */
    NSError *failure = nil;
    errno = 0;
    if (![[NSFileManager defaultManager] createFileAtPath:file.path contents:nil attributes:@{ NSFilePosixPermissions: @0600 }]) {
        failure = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
    } else if (![data writeToURL:file options:0 error:&failure]) {
        failure = failure ?: [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
    }
    if (failure) {
        NSString *why = failure.domain == NSPOSIXErrorDomain && failure.code ? @(strerror((int)failure.code)) : failure.localizedDescription;
        if (error) *error = [NSError errorWithDomain:failure.domain code:failure.code
                                            userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"the peer signing key cannot be written at %@: %@ (does the server's user own %@?)",
                                                                                    file.path, why.length ? why : @"no reason given", file.path.stringByDeletingLastPathComponent],
                                                        NSUnderlyingErrorKey: failure }];
        return nil;
    }
    return made;
}

void SNIssuePeerTokens(ODataSyncService *histories, NSDictionary *signingKey) {
    histories.peerTokens = [[ODataSyncPeerTokenIssuer alloc] initWithIssuer:histories.service.serviceRoot.absoluteString signingKey:signingKey];
}
