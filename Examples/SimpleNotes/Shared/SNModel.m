#import "SNModel.h"

NSString * const SNFolderEntity = @"Folder";
NSString * const SNNoteEntity = @"Note";

NSURL *SNModelURLInBundle(NSBundle *bundle) {
    return [bundle URLForResource:@"SimpleNotes" withExtension:@"momd"] ?: [bundle URLForResource:@"SimpleNotes" withExtension:@"mom"];
}

NSManagedObjectModel *SNModelAt(NSURL *url) {
    NSManagedObjectModel *model = url ? [[NSManagedObjectModel alloc] initWithContentsOfURL:url] : nil;
    /* A copy: Apple's Core Data hands the same model to every load of a
       URL, and one a coordinator has used takes no more entities. */
    return model.entities.count ? [model copy] : nil;
}

NSManagedObjectModel *SNModel(void) {
    return SNModelAt(SNModelURLInBundle([NSBundle mainBundle]));
}

NSString *SNTitleOfBody(NSString *body) {
    NSCharacterSet *space = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    for (NSString *line in [body componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSString *t = [line stringByTrimmingCharactersInSet:space];
        if (t.length) return t.length > 120 ? [t substringToIndex:120] : t;
    }
    return @"New Note";
}

NSString *SNSnippetOfBody(NSString *body) {
    NSCharacterSet *space = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSMutableArray *lines = [NSMutableArray array];
    BOOL title = NO;
    for (NSString *line in [body componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSString *t = [line stringByTrimmingCharactersInSet:space];
        if (!t.length) continue;
        if (!title) { title = YES; continue; }
        [lines addObject:t];
        if (lines.count == 3) break;
    }
    NSString *s = [lines componentsJoinedByString:@" "];
    return s.length > 160 ? [s substringToIndex:160] : s;
}
