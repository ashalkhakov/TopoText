// A note's history, kept at the server (SNVersions.h).

#import "SNVersions.h"
#import "SNModel.h"
#import "SNNote.h"
#import <TopoText/TopoText.h>

NSTimeInterval SNVersionInterval = 600;

NSIndexSet *SNVersionsToForget(NSArray<NSDate *> *dates, NSDate *now) {
    static const NSTimeInterval hour = 3600, day = 86400;
    /* The newest first: the first one an hour's (a day's) bucket meets is
       the one it keeps. */
    NSMutableArray *order = [NSMutableArray array];
    for (NSUInteger i = 0; i < dates.count; i++) [order addObject:@{ @"date": dates[i], @"index": @(i) }];
    [order sortUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"date" ascending:NO] ]];
    NSMutableIndexSet *forget = [NSMutableIndexSet indexSet];
    NSMutableSet *buckets = [NSMutableSet set];
    for (NSDictionary *o in order) {
        NSUInteger i = [o[@"index"] unsignedIntegerValue];
        NSTimeInterval age = [now timeIntervalSinceDate:o[@"date"]];
        if (age < day) continue;
        if (age >= 30 * day) {
            [forget addIndex:i];
            continue;
        }
        NSString *bucket = age < 7 * day ? [NSString stringWithFormat:@"h%ld", (long)(age / hour)]
                                         : [NSString stringWithFormat:@"d%ld", (long)(age / day)];
        if ([buckets containsObject:bucket]) [forget addIndex:i];
        else [buckets addObject:bucket];
    }
    return forget;
}

void SNForgetVersionsOfNote(NSManagedObject *note) {
    NSManagedObjectContext *context = note.managedObjectContext;
    NSString *noteID = [note valueForKey:@"id"];
    if (!noteID.length || !context.persistentStoreCoordinator.managedObjectModel.entitiesByName[SNNoteVersionEntity]) return;
    NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:SNNoteVersionEntity];
    f.predicate = [NSPredicate predicateWithFormat:@"noteID == %@", noteID];
    for (NSManagedObject *v in [context executeFetchRequest:f error:NULL] ?: @[]) [context deleteObject:v];
}

BOOL SNKeepVersionOfNote(NSManagedObject *note, NSDate *now) {
    NSManagedObjectContext *context = note.managedObjectContext;
    NSEntityDescription *entity = context.persistentStoreCoordinator.managedObjectModel.entitiesByName[SNNoteVersionEntity];
    NSString *noteID = [note valueForKey:@"id"];
    NSData *state = [note valueForKey:@"bodyText"];
    NSString *body = [note valueForKey:@"body"];
    /* A note made with plain text alone (by OData, or an import), its rich
       text not written yet: that text is what it had. */
    BOOL plain = ![state isKindOfClass:[NSData class]] || !state.length;
    if (!entity || !noteID.length || (plain && ![body isKindOfClass:[NSString class]])) return NO;
    NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:SNNoteVersionEntity];
    f.predicate = [NSPredicate predicateWithFormat:@"noteID == %@", noteID];
    NSArray<NSManagedObject *> *versions = [context executeFetchRequest:f error:NULL] ?: @[];
    NSDate *last = [versions valueForKeyPath:@"@max.created"];
    if (last && [now timeIntervalSinceDate:last] < SNVersionInterval) return NO;
    /* As small as its text: a copy without its tombstones, nor its history. */
    TopoText *copy = [TopoText textWithReplica:1];
    if (plain) {
        [copy insertString:body atIndex:0 attributes:nil];
    } else {
        TopoText *text = [TopoText textWithData:state replica:0 error:NULL];
        if (!text) return NO;
        [copy setAttributedString:text.attributedString];
    }
    /* The same as the newest: nothing to keep (a device writes a note's
       plain text and its rich text apart; a copy's bytes are canonical). */
    NSManagedObject *newest = nil;
    for (NSManagedObject *v in versions)
        if (!newest || [[v valueForKey:@"created"] compare:[newest valueForKey:@"created"]] == NSOrderedDescending) newest = v;
    if ([[newest valueForKey:@"text"] isEqual:copy.data]) return NO;
    NSManagedObject *version = [[NSManagedObject alloc] initWithEntity:entity insertIntoManagedObjectContext:context];
    [version setValue:[NSUUID UUID].UUIDString forKey:@"id"];
    [version setValue:noteID forKey:@"noteID"];
    [version setValue:[note valueForKey:@"title"] forKey:@"title"];
    [version setValue:copy.data forKey:@"text"];
    [version setValue:now forKey:@"created"];
    if (entity.attributesByName[@"owner"] && note.entity.attributesByName[@"owner"]) [version setValue:[note valueForKey:@"owner"] forKey:@"owner"];
    /* Thinned, this one with them. */
    NSMutableArray *all = [versions mutableCopy];
    [all addObject:version];
    NSMutableArray *dates = [NSMutableArray array];
    for (NSManagedObject *v in all) [dates addObject:[v valueForKey:@"created"] ?: [NSDate distantPast]];
    NSIndexSet *forget = SNVersionsToForget(dates, now);
    for (NSUInteger i = forget.firstIndex; i != NSNotFound; i = [forget indexGreaterThanIndex:i]) [context deleteObject:all[i]];
    return YES;
}
