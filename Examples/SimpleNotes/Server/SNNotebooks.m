#import "SNNotebooks.h"

static NSString * const SNOwner = @"owner";

@implementation SNNotebookHandler

/* The signed-in user (nil: no one, an anonymous request). */
static NSString *SNOwnerOf(ODataRequest *request) {
    return request.principal.subject;
}

- (NSPredicate *)predicateForVisibleObjectsInRequest:(ODataRequest *)request {
    /* Made by hand: GNUstep's format parser gives nothing for a nil %@. */
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
