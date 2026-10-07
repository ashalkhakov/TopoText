#import "SNSmartFilter.h"
#import "SNModel.h"
#import "SNNote.h"

/* A paragraph's list and its ticks, as SNRichText keeps them (its keys,
   here without the view system SNRichText.h brings). */
static NSString * const SNFilterListKey = @"list";
static NSString * const SNFilterCheck = @"check";
static NSString * const SNFilterCheckedKey = @"checked";

@implementation SNSmartFilter

- (instancetype)init {
    if ((self = [super init])) _tags = @[];
    return self;
}

+ (instancetype)filterWithString:(NSString *)string {
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *d = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    if (![d isKindOfClass:[NSDictionary class]]) return nil;
    SNSmartFilter *f = [[self alloc] init];
    f.matchesAny = [d[@"match"] isEqual:@"any"];
    NSMutableArray *tags = [NSMutableArray array];
    for (id t in [d[@"tags"] isKindOfClass:[NSArray class]] ? d[@"tags"] : @[])
        if ([t isKindOfClass:[NSString class]] && [t length]) [tags addObject:[t lowercaseString]];
    f.tags = tags;
    f.anyTag = [d[@"tagsMatch"] isEqual:@"any"];
    f.editedWithinDays = [d[@"editedWithin"] isKindOfClass:[NSNumber class]] ? [d[@"editedWithin"] integerValue] : 0;
    f.createdWithinDays = [d[@"createdWithin"] isKindOfClass:[NSNumber class]] ? [d[@"createdWithin"] integerValue] : 0;
    NSString *c = d[@"checklists"];
    f.checklists = [c isEqual:@"any"] ? SNChecklistRuleAny : [c isEqual:@"ticked"] ? SNChecklistRuleTicked
                 : [c isEqual:@"unticked"] ? SNChecklistRuleUnticked : SNChecklistRuleNone;
    f.withAttachments = [d[@"attachments"] isKindOfClass:[NSNumber class]] && [d[@"attachments"] boolValue];
    f.pinnedOnly = [d[@"pinned"] isKindOfClass:[NSNumber class]] && [d[@"pinned"] boolValue];
    return f;
}

- (NSString *)string {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"match"] = _matchesAny ? @"any" : @"all";
    if (_tags.count) {
        d[@"tags"] = _tags;
        d[@"tagsMatch"] = _anyTag ? @"any" : @"all";
    }
    if (_editedWithinDays > 0) d[@"editedWithin"] = @(_editedWithinDays);
    if (_createdWithinDays > 0) d[@"createdWithin"] = @(_createdWithinDays);
    if (_checklists == SNChecklistRuleAny) d[@"checklists"] = @"any";
    if (_checklists == SNChecklistRuleTicked) d[@"checklists"] = @"ticked";
    if (_checklists == SNChecklistRuleUnticked) d[@"checklists"] = @"unticked";
    if (_withAttachments) d[@"attachments"] = @YES;
    if (_pinnedOnly) d[@"pinned"] = @YES;
    /* Sorted keys: the same rules, the same text (no change to sync). */
    NSData *data = [NSJSONSerialization dataWithJSONObject:d options:NSJSONWritingSortedKeys error:NULL];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

- (id)copyWithZone:(NSZone *)zone {
    return [SNSmartFilter filterWithString:[self string]];
}

- (BOOL)isEqual:(id)other {
    return [other isKindOfClass:[SNSmartFilter class]] && [[other string] isEqualToString:[self string]];
}

- (NSUInteger)hash {
    return [self string].hash;
}

- (BOOL)isEmpty {
    return !_tags.count && _editedWithinDays <= 0 && _createdWithinDays <= 0 && _checklists == SNChecklistRuleNone &&
           !_withAttachments && !_pinnedOnly;
}

static BOOL SNWithin(NSDate *date, NSInteger days, NSDate *now) {
    return date && [now timeIntervalSinceDate:date] <= days * 86400.0;
}

/* Whether the note has a checklist so (its text read only when asked). */
static BOOL SNHasChecklist(SNNote *note, SNChecklistRule rule) {
    TopoText *text = note.text;
    NSSet *keys = [NSSet setWithObjects:SNFilterListKey, SNFilterCheckedKey, nil];
    for (NSValue *v in text.paragraphRanges) {
        NSRange r = v.rangeValue;
        if (!r.length) continue;
        NSDictionary *p = [text paragraphAttributesAtIndex:r.location keys:keys];
        if (![p[SNFilterListKey] isEqual:SNFilterCheck]) continue;
        BOOL ticked = [p[SNFilterCheckedKey] boolValue];
        if (rule == SNChecklistRuleAny || (rule == SNChecklistRuleTicked) == ticked) return YES;
    }
    return NO;
}

- (BOOL)matchesNote:(SNNote *)note now:(NSDate *)now {
    NSMutableArray<NSNumber *> *rules = [NSMutableArray array];
    if (_tags.count) {
        NSArray *has = SNTagsInText(note.body ?: @"");
        NSUInteger found = 0;
        for (NSString *t in _tags)
            if ([has containsObject:t]) found++;
        [rules addObject:@(_anyTag ? found > 0 : found == _tags.count)];
    }
    if (_editedWithinDays > 0) [rules addObject:@(SNWithin(note.lastEdited, _editedWithinDays, now))];
    if (_createdWithinDays > 0) [rules addObject:@(SNWithin(note.created, _createdWithinDays, now))];
    if (_withAttachments) {
        BOOL attaches = [note.entity.relationshipsByName objectForKey:@"attachments"] != nil;
        [rules addObject:@(attaches && [[note valueForKey:@"attachments"] count] > 0)];
    }
    if (_pinnedOnly) [rules addObject:@(note.isPinned)];
    if (_checklists != SNChecklistRuleNone) [rules addObject:@(SNHasChecklist(note, _checklists))];
    if (!rules.count) return YES;
    for (NSNumber *r in rules)
        if (r.boolValue == _matchesAny) return _matchesAny;
    return !_matchesAny;
}

@end
