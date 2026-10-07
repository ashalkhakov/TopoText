#import "SNNotebooks.h"

static NSString * const SNOwner = @"owner";

@implementation SNNotebookHandler

/* The signed-in user (nil: no one, an anonymous request). */
static NSString *SNOwnerOf(ODataRequest *request) {
    return request.principal.subject;
}

- (NSPredicate *)predicateForVisibleObjectsInRequest:(ODataRequest *)request {
    /* Made by hand: GNUstep's -predicateWithFormat: raises for a nil
       argument (it gathers them in an array), as no one signed in is. */
    NSPredicate *mine = [NSComparisonPredicate predicateWithLeftExpression:[NSExpression expressionForKeyPath:SNOwner]
                                                           rightExpression:[NSExpression expressionForConstantValue:SNOwnerOf(request)]
                                                                  modifier:NSDirectPredicateModifier type:NSEqualToPredicateOperatorType options:0];
    NSPredicate *theirs = [super predicateForVisibleObjectsInRequest:request];
    return theirs ? [NSCompoundPredicate andPredicateWithSubpredicates:@[ theirs, mine ]] : mine;
}

- (NSManagedObject *)insertObjectWithValues:(NSDictionary<NSString *, id> *)values request:(ODataRequest *)request reply:(ODataReply *)reply {
    NSManagedObject *made = [super insertObjectWithValues:values request:request reply:reply];
    [made setValue:SNOwnerOf(request) forKey:SNOwner];
    return made;
}

@end

void SNServeNotebookPerUser(ODataService *service) {
    for (NSEntityDescription *entity in service.model.entities) {
        if (![entity.attributesByName objectForKey:SNOwner] || entity.superentity) continue;
        NSString *set = entity.userInfo[@"OData.entitySet"];
        if (!set.length) continue;
        [service setHandler:[[SNNotebookHandler alloc] initWithEntity:entity] forEntitySet:set];
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
    /* The server's user's alone, from the first byte. */
    if (!data || ![[NSFileManager defaultManager] createFileAtPath:file.path contents:nil attributes:@{ NSFilePosixPermissions: @0600 }] ||
        ![data writeToURL:file options:0 error:error])
        return nil;
    return made;
}

void SNIssuePeerTokens(ODataSyncService *histories, NSDictionary *signingKey) {
    histories.peerTokens = [[ODataSyncPeerTokenIssuer alloc] initWithIssuer:histories.service.serviceRoot.absoluteString signingKey:signingKey];
}
