#import "SNModel.h"

NSString * const SNFolderEntity = @"Folder";
NSString * const SNNoteEntity = @"Note";
NSString * const SNAttachmentEntity = @"Attachment";

/* What a line says, read: an attachment's character (U+FFFC) is not
   words. */
static NSString *SNReadable(NSString *line) {
    NSString *t = [line stringByReplacingOccurrencesOfString:@"\uFFFC" withString:@""];
    return [t stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

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
    for (NSString *line in [body componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSString *t = SNReadable(line);
        if (t.length) return t.length > 120 ? [t substringToIndex:120] : t;
    }
    return @"New Note";
}

NSString *SNSnippetOfBody(NSString *body) {
    NSMutableArray *lines = [NSMutableArray array];
    BOOL title = NO;
    for (NSString *line in [body componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSString *t = SNReadable(line);
        if (!t.length) continue;
        if (!title) { title = YES; continue; }
        [lines addObject:t];
        if (lines.count == 3) break;
    }
    NSString *s = [lines componentsJoinedByString:@" "];
    return s.length > 160 ? [s substringToIndex:160] : s;
}

static BOOL SNIsTagCharacter(unichar c) {
    return [[NSCharacterSet alphanumericCharacterSet] characterIsMember:c] || c == '-' || c == '_';
}

NSArray<NSValue *> *SNTagRangesInText(NSString *text) {
    NSMutableArray *ranges = [NSMutableArray array];
    NSCharacterSet *space = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSCharacterSet *letters = [NSCharacterSet letterCharacterSet];
    NSUInteger n = text.length;
    for (NSUInteger i = 0; i < n; i++) {
        if ([text characterAtIndex:i] != '#' || (i && ![space characterIsMember:[text characterAtIndex:i - 1]])) continue;
        NSUInteger end = i + 1;
        BOOL letter = NO;
        while (end < n && SNIsTagCharacter([text characterAtIndex:end])) {
            letter = letter || [letters characterIsMember:[text characterAtIndex:end]];
            end++;
        }
        if (letter) [ranges addObject:[NSValue valueWithRange:NSMakeRange(i, end - i)]];
        i = end - 1;
    }
    return ranges;
}

NSArray<NSString *> *SNTagsInText(NSString *text) {
    NSMutableOrderedSet *tags = [NSMutableOrderedSet orderedSet];
    for (NSValue *v in SNTagRangesInText(text ?: @"")) {
        NSRange r = v.rangeValue;
        [tags addObject:[text substringWithRange:NSMakeRange(r.location + 1, r.length - 1)].lowercaseString];
    }
    return tags.array;
}

NSDictionary *SNUpgradeBody(NSDictionary *body, NSEntityDescription *entity) {
    if (![entity.name isEqualToString:SNNoteEntity] || !body[@"Updated"] || body[@"Edited"]) return body;
    NSMutableDictionary *b = [body mutableCopy];
    b[@"Edited"] = b[@"Updated"];
    [b removeObjectForKey:@"Updated"];
    return b;
}

NSArray<NSValue *> *SNLinkRangesInText(NSString *text) {
    static NSRegularExpression *web;
    if (!web)
        web = [NSRegularExpression regularExpressionWithPattern:@"(?:https?://|www\\.)[^\\s<>\"]+" options:NSRegularExpressionCaseInsensitive error:NULL];
    NSMutableArray *ranges = [NSMutableArray array];
    NSCharacterSet *trailing = [NSCharacterSet characterSetWithCharactersInString:@".,;:!?)]}'"];
    for (NSTextCheckingResult *m in [web matchesInString:text options:0 range:NSMakeRange(0, text.length)]) {
        NSRange r = m.range;
        if (r.location && ![[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:[text characterAtIndex:r.location - 1]] &&
            [text characterAtIndex:r.location - 1] != '(')
            continue;
        while (r.length && [trailing characterIsMember:[text characterAtIndex:NSMaxRange(r) - 1]]) r.length--;
        if (r.length > 4) [ranges addObject:[NSValue valueWithRange:r]];
    }
    return ranges;
}

static NSString * const SNNoteLinkPrefix = @"simplenotes://note/";

NSURL *SNLinkToNote(NSString *noteID) {
    return [NSURL URLWithString:[SNNoteLinkPrefix stringByAppendingString:noteID]];
}

NSString *SNNoteIDInLink(NSURL *link) {
    NSString *s = link.absoluteString;
    return [s hasPrefix:SNNoteLinkPrefix] && s.length > SNNoteLinkPrefix.length ? [s substringFromIndex:SNNoteLinkPrefix.length] : nil;
}

NSURL *SNURLOfLink(NSString *text) {
    NSString *t = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!t.length) return nil;
    if ([t rangeOfString:@"://"].location == NSNotFound && ![t hasPrefix:@"mailto:"]) t = [@"https://" stringByAppendingString:t];
    return [NSURL URLWithString:t];
}

@implementation SNNoteMerger
- (void)mergedAttribute:(NSAttributeDescription *)attribute ofObject:(NSManagedObject *)object {
    [super mergedAttribute:attribute ofObject:object];
    id body = [object valueForKey:@"body"];
    if (![object.entity.attributesByName objectForKey:@"title"] || ![body isKindOfClass:[NSString class]]) return;
    NSString *title = SNTitleOfBody(body);
    if (![[object valueForKey:@"title"] isEqual:title]) [object setValue:title forKey:@"title"];
}
@end

void SNRegisterMergers(ODataSyncEngine *engine) {
    [engine setMerger:[[SNNoteMerger alloc] init] forName:TTSyncMergerName];
}
