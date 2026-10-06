#import "TopoTextSync.h"

NSString * const TTSyncTextKey = @"TopoText.text";
NSString * const TTSyncStringKey = @"TopoText.string";

static BOOL TTYes(id v) {
    return [v respondsToSelector:@selector(boolValue)] && [v boolValue];
}

static TopoText *TTDecode(id state) {
    return [state isKindOfClass:[NSData class]] ? [TopoText textWithData:state replica:0 error:NULL] : nil;
}

@implementation TTSyncResolver

- (instancetype)initWithFallback:(id<ODataSyncResolving>)fallback {
    if ((self = [super init])) _fallback = fallback;
    return self;
}

- (instancetype)init { return [self initWithFallback:[[ODataSyncMergeFields alloc] init]]; }

+ (NSDictionary<NSString *, NSString *> *)textAttributesOfEntity:(NSEntityDescription *)entity {
    NSMutableDictionary *texts = [NSMutableDictionary dictionary];
    for (NSPropertyDescription *p in entity.properties) {
        if (![p isKindOfClass:[NSAttributeDescription class]] || !TTYes(p.userInfo[TTSyncTextKey])) continue;
        NSString *string = p.userInfo[TTSyncStringKey];
        texts[p.name] = [string isKindOfClass:[NSString class]] ? string : @"";
    }
    return texts;
}

+ (TopoText *)mergeState:(id)state withState:(id)other {
    TopoText *a = TTDecode(state), *b = TTDecode(other);
    if (!a || !b) return a ?: b;
    [a mergeText:b];
    return a;
}

- (ODataSyncResolution *)resolveConflict:(ODataSyncConflict *)conflict {
    ODataSyncResolution *rest = [_fallback resolveConflict:conflict];
    NSDictionary<NSString *, NSString *> *texts = [TTSyncResolver textAttributesOfEntity:conflict.entity];
    /* A deletion against a change is not a text's to settle. */
    if (!texts.count || !conflict.local || !conflict.remote) return rest;

    NSMutableSet *mine = [NSMutableSet setWithArray:texts.allKeys];
    [mine addObjectsFromArray:texts.allValues];
    NSDictionary *info = conflict.entity.userInfo;
    for (NSString *key in @[ ODataSyncModifiedKey, ODataSyncVersionsKey ])
        if ([info[key] isKindOfClass:[NSString class]]) [mine addObject:info[key]];

    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    switch (rest.kind) {
    case ODataSyncDefer: {
        NSMutableSet *others = [conflict.localChanges mutableCopy];
        [others unionSet:conflict.remoteChanges];
        [others minusSet:mine];
        if (others.count) return rest;
        break;
    }
    case ODataSyncTakeRemote:
        for (NSString *name in conflict.remote)
            if (![mine containsObject:name]) values[name] = conflict.remote[name];
        break;
    case ODataSyncKeepLocal:
        break;
    case ODataSyncMerge:
        for (NSString *name in rest.values)
            if (![texts objectForKey:name] && ![texts.allValues containsObject:name]) values[name] = rest.values[name];
        break;
    }
    for (NSString *name in texts) {
        TopoText *merged = [TTSyncResolver mergeState:conflict.local[name] withState:conflict.remote[name]];
        if (!merged) continue;
        values[name] = merged.data;
        if (texts[name].length) values[texts[name]] = merged.string;
    }
    return [ODataSyncResolution mergedValues:values];
}

@end

@implementation NSManagedObject (TopoText)

- (NSString *)tt_stringKeyFor:(NSString *)key {
    NSAttributeDescription *a = self.entity.attributesByName[key];
    NSString *string = a.userInfo[TTSyncStringKey];
    return [string isKindOfClass:[NSString class]] && string.length ? string : nil;
}

- (TopoText *)tt_textForKey:(NSString *)key { return [self tt_textForKey:key replica:0]; }

- (TopoText *)tt_textForKey:(NSString *)key replica:(TTReplica)replica {
    TopoText *t = nil;
    id state = [self valueForKey:key];
    if ([state isKindOfClass:[NSData class]]) t = [TopoText textWithData:state replica:replica error:NULL];
    if (t) return t;
    NSString *stringKey = [self tt_stringKeyFor:key];
    id plain = stringKey ? [self valueForKey:stringKey] : nil;
    return [plain isKindOfClass:[NSString class]] ? [TopoText textSeededWithString:plain replica:replica]
                                                   : [TopoText textWithReplica:replica];
}

- (void)tt_setText:(TopoText *)text forKey:(NSString *)key {
    NSData *data = text.data;
    if (![[self valueForKey:key] isEqual:data]) [self setValue:data forKey:key];
    NSString *stringKey = [self tt_stringKeyFor:key];
    NSString *string = text.string;
    if (stringKey && ![[self valueForKey:stringKey] isEqual:string]) [self setValue:string forKey:stringKey];
}

- (NSArray<TTEdit *> *)tt_mergeKey:(NSString *)key intoText:(TopoText *)text {
    id state = [self valueForKey:key];
    if (![state isKindOfClass:[NSData class]]) return @[];
    return [text applyData:state error:NULL] ?: @[];
}

@end
