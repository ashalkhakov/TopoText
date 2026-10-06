#import "TTInternal.h"

NSString * const TopoTextErrorDomain = @"TopoTextErrorDomain";

static inline BOOL TTIdGreater(uint64_t c1, TTReplica r1, uint64_t c2, TTReplica r2) {
    return c1 > c2 || (c1 == c2 && r1 > r2);
}

#pragma mark ids, versions, edits

@implementation TTId
+ (instancetype)idWithReplica:(TTReplica)replica clock:(uint64_t)clock {
    TTId *i = [self new];
    i->_replica = replica;
    i->_clock = clock;
    return i;
}
- (NSString *)key { return [NSString stringWithFormat:@"%llu:%llu", (unsigned long long)_replica, (unsigned long long)_clock]; }
- (NSString *)description { return [self key]; }
- (id)copyWithZone:(NSZone *)zone { return self; }
- (BOOL)isEqual:(id)o {
    return [o isKindOfClass:[TTId class]] && ((TTId *)o)->_replica == _replica && ((TTId *)o)->_clock == _clock;
}
- (NSUInteger)hash { return (NSUInteger)(_replica * 16777619u) ^ (NSUInteger)_clock; }
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)c {
    [c encodeInt64:(int64_t)_replica forKey:@"r"];
    [c encodeInt64:(int64_t)_clock forKey:@"c"];
}
- (instancetype)initWithCoder:(NSCoder *)c {
    if ((self = [super init])) {
        _replica = (TTReplica)[c decodeInt64ForKey:@"r"];
        _clock = (uint64_t)[c decodeInt64ForKey:@"c"];
    }
    return self;
}
@end

@implementation TTVersion {
    NSDictionary<NSNumber *, NSNumber *> *_clocks;
}
- (instancetype)initWithClocks:(NSDictionary *)clocks {
    if ((self = [super init])) _clocks = [clocks copy];
    return self;
}
+ (instancetype)version { return [[self alloc] initWithClocks:@{}]; }
+ (instancetype)versionWithData:(NSData *)data error:(NSError **)error {
    NSDictionary *clocks = TTDecodeVersion(data, error);
    return clocks ? [[self alloc] initWithClocks:clocks] : nil;
}
- (NSDictionary *)clocks { return _clocks; }
- (NSData *)data { return TTEncodeVersion(_clocks); }
- (NSArray<NSNumber *> *)replicas { return [_clocks.allKeys sortedArrayUsingSelector:@selector(compare:)]; }
- (uint64_t)clockForReplica:(TTReplica)replica { return [_clocks[@(replica)] unsignedLongLongValue]; }
- (BOOL)includesVersion:(TTVersion *)other {
    for (NSNumber *r in other->_clocks)
        if ([other->_clocks[r] unsignedLongLongValue] > [_clocks[r] unsignedLongLongValue]) return NO;
    return YES;
}
- (TTVersion *)versionByMergingVersion:(TTVersion *)other {
    NSMutableDictionary *m = [_clocks mutableCopy];
    for (NSNumber *r in other->_clocks)
        if ([other->_clocks[r] unsignedLongLongValue] > [m[r] unsignedLongLongValue]) m[r] = other->_clocks[r];
    return [[TTVersion alloc] initWithClocks:m];
}
- (BOOL)isEqual:(id)o { return [o isKindOfClass:[TTVersion class]] && [((TTVersion *)o)->_clocks isEqualToDictionary:_clocks]; }
- (NSUInteger)hash { return _clocks.count; }
- (id)copyWithZone:(NSZone *)zone { return self; }
- (NSString *)description { return [NSString stringWithFormat:@"<TTVersion %@>", _clocks]; }
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)c { [c encodeObject:[self data] forKey:@"v"]; }
- (instancetype)initWithCoder:(NSCoder *)c {
    NSDictionary *clocks = TTDecodeVersion([c decodeObjectOfClass:[NSData class] forKey:@"v"] ?: [NSData data], NULL);
    return clocks ? [self initWithClocks:clocks] : nil;
}
@end

@implementation TTEdit
+ (instancetype)editWithKind:(TTEditKind)kind range:(NSRange)range string:(NSString *)string attributes:(NSDictionary *)attributes {
    TTEdit *e = [self new];
    e->_kind = kind;
    e->_range = range;
    e->_string = [string copy];
    e->_attributes = [attributes copy] ?: @{};
    return e;
}
- (void)applyToAttributedString:(NSMutableAttributedString *)s {
    switch (_kind) {
    case TTEditInsert:
        [s replaceCharactersInRange:NSMakeRange(_range.location, 0)
               withAttributedString:[[NSAttributedString alloc] initWithString:_string attributes:_attributes]];
        break;
    case TTEditDelete:
        [s deleteCharactersInRange:_range];
        break;
    case TTEditAttributes:
        [s setAttributes:_attributes range:_range];
        break;
    }
}
- (NSString *)description {
    static NSString *names[] = { @"insert", @"delete", @"attributes" };
    return [NSString stringWithFormat:@"<%@ %@%@>", names[_kind], NSStringFromRange(_range),
            _kind == TTEditInsert ? [NSString stringWithFormat:@" \"%@\"", _string] : @""];
}
@end

#pragma mark registers

static NSDictionary *TTVisible(NSDictionary<NSString *, TTRegister *> *regs) {
    if (!regs.count) return @{};
    NSMutableDictionary *m = [NSMutableDictionary dictionaryWithCapacity:regs.count];
    for (NSString *k in regs) {
        id v = regs[k]->_value;
        if (![v isKindOfClass:[NSNull class]]) m[k] = v;
    }
    return m;
}

static NSDictionary *TTBirth(NSDictionary *attrs) {
    if (!attrs.count) return @{};
    NSMutableDictionary *m = [NSMutableDictionary dictionaryWithCapacity:attrs.count];
    for (NSString *k in attrs)
        if (![attrs[k] isKindOfClass:[NSNull class]]) m[k] = [TTRegister registerWithValue:[attrs[k] copy] clock:0 replica:0];
    return m;
}

/* Theirs merged into mine, key by key: the later writer stands. */
static NSDictionary *TTMergeRegisters(NSDictionary<NSString *, TTRegister *> *mine, NSDictionary<NSString *, TTRegister *> *theirs) {
    NSMutableDictionary *m = nil;
    for (NSString *k in theirs) {
        TTRegister *t = theirs[k], *o = mine[k];
        if (!o || TTRegisterWins(t, o)) {
            if (!m) m = [mine mutableCopy] ?: [NSMutableDictionary dictionary];
            m[k] = t;
        }
    }
    return m ? [m copy] : mine;
}

static void TTCheckAttributes(NSDictionary *attrs) {
    for (id k in attrs)
        if (![k isKindOfClass:[NSString class]] || !TTValueIsCodable(attrs[k]))
            [NSException raise:NSInvalidArgumentException
                        format:@"TopoText: attribute %@ = %@ is not a property-list value", k, attrs[k]];
}

static TTReplica TTSeedReplica(NSString *string) {
    /* FNV-1a over the UTF-16 units, under a tag of its own. */
    uint64_t h = 0xcbf29ce484222325ull;
    for (const char *t = "TopoText.seed"; *t; t++) h = (h ^ (uint8_t)*t) * 0x100000001b3ull;
    NSUInteger n = string.length;
    for (NSUInteger i = 0; i < n; i++) {
        unichar u = [string characterAtIndex:i];
        h = (h ^ (u & 0xff)) * 0x100000001b3ull;
        h = (h ^ (u >> 8)) * 0x100000001b3ull;
    }
    return h ?: 1;
}

#pragma mark the text

@implementation TopoText {
    TTReplica _replica;
    uint64_t _clock;
    NSMutableArray<TTRun *> *_runs;                                    /* document order, tombstones too */
    NSMutableDictionary<NSNumber *, NSMutableArray<TTRun *> *> *_byReplica; /* each replica's runs by clock */
    NSMutableDictionary<NSNumber *, NSNumber *> *_seen;                /* the version */
    NSMutableString *_string;                                          /* the live characters */
}

+ (TTReplica)randomReplica {
    uuid_t bytes;
    [[NSUUID UUID] getUUIDBytes:bytes];
    TTReplica r;
    memcpy(&r, bytes, sizeof r);
    return r ?: 1;
}

+ (instancetype)text { return [self textWithReplica:0]; }

+ (instancetype)textWithReplica:(TTReplica)replica {
    TopoText *t = [self new];
    t->_replica = replica ?: [self randomReplica];
    t->_runs = [NSMutableArray array];
    t->_byReplica = [NSMutableDictionary dictionary];
    t->_seen = [NSMutableDictionary dictionary];
    t->_string = [NSMutableString string];
    return t;
}

+ (instancetype)textWithData:(NSData *)data replica:(TTReplica)replica error:(NSError **)error {
    TopoText *t = [self textWithReplica:replica];
    return [t applyData:data error:error] ? t : nil;
}

+ (instancetype)textSeededWithString:(NSString *)string replica:(TTReplica)replica {
    TopoText *t = [self textWithReplica:replica];
    if (!string.length) return t;
    TTRun *run = [TTRun new];
    run->_r = TTSeedReplica(string);
    run->_c = 1;
    run->_len = string.length;
    run->_text = [string copy];
    run->_attrs = @{};
    [t adopt:run at:0];
    [t->_string setString:string];
    return t;
}

- (id)copyWithZone:(NSZone *)zone { return [self copyWithReplica:_replica]; }

- (TopoText *)copyWithReplica:(TTReplica)replica {
    TopoText *t = [TopoText textWithData:[self data] replica:replica error:NULL];
    if (_clock > t->_clock) t->_clock = _clock;
    return t;
}

- (TTReplica)replica { return _replica; }
- (uint64_t)clock { return _clock; }

- (NSString *)description {
    return [NSString stringWithFormat:@"<TopoText %llu \"%@\" %@>", (unsigned long long)_replica, _string, _runs];
}

#pragma mark bookkeeping

- (void)see:(TTReplica)r clock:(uint64_t)c {
    if (!r) return;
    if (c > _clock) _clock = c;
    NSNumber *k = @(r);
    if ([_seen[k] unsignedLongLongValue] < c) _seen[k] = @(c);
}

- (void)seeRegisters:(NSDictionary<NSString *, TTRegister *> *)regs {
    for (TTRegister *g in regs.allValues) [self see:g->_replica clock:g->_clock];
}

/* run, put at pos in document order and indexed. */
- (void)adopt:(TTRun *)run at:(NSUInteger)pos {
    [_runs insertObject:run atIndex:pos];
    NSNumber *k = @(run->_r);
    NSMutableArray *a = _byReplica[k] ?: (_byReplica[k] = [NSMutableArray array]);
    NSUInteger lo = 0, hi = a.count;
    if (hi && ((TTRun *)a.lastObject)->_c < run->_c) {
        lo = hi;
    } else {
        while (lo < hi) {
            NSUInteger mid = (lo + hi) / 2;
            if (((TTRun *)a[mid])->_c < run->_c) lo = mid + 1; else hi = mid;
        }
    }
    [a insertObject:run atIndex:lo];
    [self see:run->_r clock:run->_c + run->_len - 1];
    [self seeRegisters:run->_attrs];
}

/* The run holding character (r, c), and c's offset in it. */
- (TTRun *)runWithReplica:(TTReplica)r clock:(uint64_t)c offset:(NSUInteger *)off {
    NSArray<TTRun *> *a = _byReplica[@(r)];
    NSUInteger lo = 0, hi = a.count;
    while (lo < hi) {
        NSUInteger mid = (lo + hi) / 2;
        if (a[mid]->_c <= c) lo = mid + 1; else hi = mid;
    }
    if (!lo) return nil;
    TTRun *run = a[lo - 1];
    if (c >= run->_c + run->_len) return nil;
    if (off) *off = (NSUInteger)(c - run->_c);
    return run;
}

/* The first of r's runs after clock c. */
- (TTRun *)runOfReplica:(TTReplica)r after:(uint64_t)c {
    NSArray<TTRun *> *a = _byReplica[@(r)];
    NSUInteger lo = 0, hi = a.count;
    while (lo < hi) {
        NSUInteger mid = (lo + hi) / 2;
        if (a[mid]->_c <= c) lo = mid + 1; else hi = mid;
    }
    return lo < a.count ? a[lo] : nil;
}

- (BOOL)knowsReplica:(TTReplica)r clock:(uint64_t)c { return [self runWithReplica:r clock:c offset:NULL] != nil; }

/* run cut after off characters; the right part, which follows it. pos: run's
   place in document order, or NSNotFound to look it up. */
- (TTRun *)split:(TTRun *)run at:(NSUInteger)off position:(NSUInteger)pos {
    if (off == 0 || off >= run->_len) return nil;
    TTRun *right = [TTRun new];
    right->_r = run->_r;
    right->_c = run->_c + off;
    right->_len = run->_len - off;
    right->_or = run->_r;
    right->_oc = run->_c + off - 1;
    right->_deleted = run->_deleted;
    right->_attrs = run->_attrs;
    if (run->_text) {
        right->_text = [run->_text substringFromIndex:off];
        run->_text = [run->_text substringToIndex:off];
    }
    run->_len = off;
    if (pos == NSNotFound) pos = [_runs indexOfObjectIdenticalTo:run];
    [_runs insertObject:right atIndex:pos + 1];
    NSMutableArray *a = _byReplica[@(run->_r)];
    NSUInteger lo = 0, hi = a.count;
    while (lo < hi) {
        NSUInteger mid = (lo + hi) / 2;
        if (((TTRun *)a[mid])->_c < right->_c) lo = mid + 1; else hi = mid;
    }
    [a insertObject:right atIndex:lo];
    return right;
}

/* The live run holding visible character index: its place in document order,
   and index's offset in it. */
- (TTRun *)liveRunAt:(NSUInteger)index position:(NSUInteger *)pos offset:(NSUInteger *)off {
    NSUInteger before = 0, i = 0;
    for (TTRun *run in _runs) {
        if (!run->_deleted) {
            if (index < before + run->_len) {
                *pos = i;
                *off = index - before;
                return run;
            }
            before += run->_len;
        }
        i++;
    }
    return nil;
}

/* How many live characters come before the run at pos. */
- (NSUInteger)visibleIndexOfPosition:(NSUInteger)pos {
    NSUInteger n = 0;
    for (NSUInteger i = 0; i < pos; i++) {
        TTRun *run = _runs[i];
        if (!run->_deleted) n += run->_len;
    }
    return n;
}

#pragma mark reading

- (NSString *)string { return [_string copy]; }
- (NSUInteger)length { return _string.length; }

- (NSAttributedString *)attributedString {
    NSMutableAttributedString *s = [[NSMutableAttributedString alloc] init];
    for (NSDictionary *run in [self attributeRuns]) {
        NSRange range = NSMakeRange([run[@"location"] unsignedIntegerValue], [run[@"length"] unsignedIntegerValue]);
        [s appendAttributedString:[[NSAttributedString alloc] initWithString:[_string substringWithRange:range]
                                                                  attributes:run[@"attributes"]]];
    }
    return s;
}

- (NSArray<NSDictionary *> *)attributeRuns {
    NSMutableArray *out = [NSMutableArray array];
    NSUInteger at = 0, start = 0;
    NSDictionary *current = nil;
    for (TTRun *run in _runs) {
        if (run->_deleted) continue;
        NSDictionary *attrs = TTVisible(run->_attrs);
        if (current && ![current isEqualToDictionary:attrs]) {
            [out addObject:@{ @"location": @(start), @"length": @(at - start), @"attributes": current }];
            start = at;
        }
        current = attrs;
        at += run->_len;
    }
    if (current) [out addObject:@{ @"location": @(start), @"length": @(at - start), @"attributes": current }];
    return out;
}

- (NSDictionary *)attributesAtIndex:(NSUInteger)index effectiveRange:(NSRangePointer)range {
    if (index >= _string.length) [NSException raise:NSRangeException format:@"TopoText: index %lu beyond %lu", (unsigned long)index, (unsigned long)_string.length];
    for (NSDictionary *run in [self attributeRuns]) {
        NSUInteger loc = [run[@"location"] unsignedIntegerValue], len = [run[@"length"] unsignedIntegerValue];
        if (index < loc + len) {
            if (range) *range = NSMakeRange(loc, len);
            return run[@"attributes"];
        }
    }
    return @{};
}

#pragma mark editing

- (void)checkRange:(NSRange)range {
    if (range.location > _string.length || range.length > _string.length - range.location)
        [NSException raise:NSRangeException format:@"TopoText: range %@ beyond %lu", NSStringFromRange(range), (unsigned long)_string.length];
}

- (void)insertString:(NSString *)string atIndex:(NSUInteger)index attributes:(NSDictionary *)attrs {
    [self checkRange:NSMakeRange(index, 0)];
    TTCheckAttributes(attrs);
    NSUInteger n = string.length;
    if (!n) return;
    NSDictionary *birth = TTBirth(attrs);
    TTReplica or = 0;
    uint64_t oc = 0;
    NSUInteger pos = 0;
    if (index > 0) {
        NSUInteger p, off;
        TTRun *left = [self liveRunAt:index - 1 position:&p offset:&off];
        /* Typing on at the end of our own latest run: the same run, longer. */
        if (left->_r == _replica && off + 1 == left->_len && left->_c + left->_len == _clock + 1 &&
            [left->_attrs isEqualToDictionary:birth]) {
            left->_text = [left->_text stringByAppendingString:string];
            left->_len += n;
            [self see:_replica clock:left->_c + left->_len - 1];
            [_string insertString:string atIndex:index];
            return;
        }
        [self split:left at:off + 1 position:p];
        or = left->_r;
        oc = left->_c + off;
        pos = p + 1;
    }
    /* Newer than anything here, so it goes right after its origin. */
    TTRun *run = [TTRun new];
    run->_r = _replica;
    run->_c = _clock + 1;
    run->_len = n;
    run->_or = or;
    run->_oc = oc;
    run->_text = [string copy];
    run->_attrs = birth;
    [self adopt:run at:pos];
    [_string insertString:string atIndex:index];
}

/* Live runs cut at range's ends, then each one in it visited. */
- (void)visitLiveRange:(NSRange)range with:(void (^)(TTRun *run))block {
    if (!range.length) return;
    NSUInteger pos, off;
    TTRun *run = [self liveRunAt:range.location position:&pos offset:&off];
    if (off) {
        [self split:run at:off position:pos];
        pos++;
    }
    NSUInteger left = range.length;
    while (left) {
        run = _runs[pos++];
        if (run->_deleted) continue;
        if (run->_len > left) [self split:run at:left position:pos - 1];
        left -= run->_len;
        block(run);
    }
}

- (void)deleteCharactersInRange:(NSRange)range {
    [self checkRange:range];
    [self visitLiveRange:range with:^(TTRun *run) {
        run->_deleted = YES;
        run->_text = nil;
        run->_attrs = @{};
    }];
    [_string deleteCharactersInRange:range];
}

- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)string attributes:(NSDictionary *)attrs {
    [self checkRange:range];
    TTCheckAttributes(attrs);
    [self deleteCharactersInRange:range];
    [self insertString:string atIndex:range.location attributes:attrs];
}

/* One edit: one clock, the same registers on every character it touches. */
- (void)changeAttributesInRange:(NSRange)range with:(NSDictionary *)attrs exclusive:(BOOL)exclusive {
    [self checkRange:range];
    TTCheckAttributes(attrs);
    if (!range.length) return;
    uint64_t c = _clock + 1;
    [self see:_replica clock:c];
    NSMutableDictionary *regs = [NSMutableDictionary dictionary];
    for (NSString *k in attrs) regs[k] = [TTRegister registerWithValue:[attrs[k] copy] clock:c replica:_replica];
    TTRegister *removed = [TTRegister registerWithValue:[NSNull null] clock:c replica:_replica];
    [self visitLiveRange:range with:^(TTRun *run) {
        NSMutableDictionary *m = [run->_attrs mutableCopy];
        [m addEntriesFromDictionary:regs];
        if (exclusive)
            for (NSString *k in run->_attrs)
                if (!regs[k] && ![run->_attrs[k]->_value isKindOfClass:[NSNull class]]) m[k] = removed;
        run->_attrs = m;
    }];
}

- (void)addAttributes:(NSDictionary *)attrs range:(NSRange)range {
    [self changeAttributesInRange:range with:attrs exclusive:NO];
}

- (void)setAttributes:(NSDictionary *)attrs range:(NSRange)range {
    [self changeAttributesInRange:range with:attrs ?: @{} exclusive:YES];
}

- (void)removeAttribute:(NSString *)name range:(NSRange)range {
    [self changeAttributesInRange:range with:@{ name: [NSNull null] } exclusive:NO];
}

/* The range of _string that differs from string, and string's part for it;
   never between the halves of a surrogate pair. */
static void TTDiff(NSString *a, NSString *b, NSRange *mine, NSRange *theirs) {
    NSUInteger na = a.length, nb = b.length, pre = 0, suf = 0;
    unichar *x = malloc((na + 1) * sizeof(unichar)), *y = malloc((nb + 1) * sizeof(unichar));
    [a getCharacters:x range:NSMakeRange(0, na)];
    [b getCharacters:y range:NSMakeRange(0, nb)];
    while (pre < na && pre < nb && x[pre] == y[pre]) pre++;
    if (pre && pre < na && x[pre - 1] >= 0xd800 && x[pre - 1] < 0xdc00) pre--;
    while (suf < na - pre && suf < nb - pre && x[na - 1 - suf] == y[nb - 1 - suf]) suf++;
    if (suf && suf < na - pre && x[na - suf] >= 0xdc00 && x[na - suf] < 0xe000) suf--;
    free(x);
    free(y);
    *mine = NSMakeRange(pre, na - pre - suf);
    *theirs = NSMakeRange(pre, nb - pre - suf);
}

- (void)setString:(NSString *)string {
    NSRange mine, theirs;
    TTDiff(_string, string, &mine, &theirs);
    if (!mine.length && !theirs.length) return;
    NSDictionary *attrs = mine.location ? [self attributesAtIndex:mine.location - 1 effectiveRange:NULL] : nil;
    [self replaceCharactersInRange:mine withString:[string substringWithRange:theirs] attributes:attrs];
}

/* gnustep-base has no -enumerateAttributesInRange:options:usingBlock:. */
static void TTEachAttributeRun(NSAttributedString *s, NSRange range, void (^block)(NSDictionary *attrs, NSRange range)) {
    NSUInteger i = range.location;
    while (i < NSMaxRange(range)) {
        NSRange run;
        NSDictionary *attrs = [s attributesAtIndex:i longestEffectiveRange:&run inRange:range];
        run = NSIntersectionRange(run, NSMakeRange(i, NSMaxRange(range) - i));
        block(attrs ?: @{}, run);
        i = NSMaxRange(run);
    }
}

- (void)setAttributedString:(NSAttributedString *)target {
    NSString *string = target.string;
    NSRange mine, theirs;
    TTDiff(_string, string, &mine, &theirs);
    [self deleteCharactersInRange:mine];
    __block NSUInteger at = mine.location;
    TTEachAttributeRun(target, theirs, ^(NSDictionary *attrs, NSRange range) {
        [self insertString:[string substringWithRange:range] atIndex:at attributes:attrs];
        at += range.length;
    });
    TTEachAttributeRun(target, NSMakeRange(0, string.length), ^(NSDictionary *attrs, NSRange range) {
        NSUInteger i = range.location;
        while (i < NSMaxRange(range)) {
            NSRange ours;
            NSDictionary *have = [self attributesAtIndex:i effectiveRange:&ours];
            NSRange part = NSMakeRange(i, MIN(NSMaxRange(ours), NSMaxRange(range)) - i);
            if (![have isEqualToDictionary:attrs]) [self setAttributes:attrs range:part];
            i = NSMaxRange(part);
        }
    });
}

#pragma mark positions

- (TTId *)anchorAtIndex:(NSUInteger)index {
    index = MIN(index, _string.length);
    if (!index) return nil;
    NSUInteger pos, off;
    TTRun *run = [self liveRunAt:index - 1 position:&pos offset:&off];
    return [TTId idWithReplica:run->_r clock:run->_c + off];
}

- (NSUInteger)indexForAnchor:(TTId *)anchor {
    if (!anchor) return 0;
    NSUInteger off;
    TTRun *run = [self runWithReplica:anchor.replica clock:anchor.clock offset:&off];
    if (!run) return NSNotFound;
    NSUInteger at = [self visibleIndexOfPosition:[_runs indexOfObjectIdenticalTo:run]];
    return run->_deleted ? at : at + off + 1;
}

#pragma mark merging

- (TTVersion *)version { return [[TTVersion alloc] initWithClocks:_seen]; }

- (NSData *)data { return [self deltaSinceVersion:[TTVersion version]]; }

- (NSData *)deltaSinceVersion:(TTVersion *)version {
    TTPayload *p = [TTPayload new];
    [p.version addEntriesFromDictionary:_seen];
    for (TTRun *run in _runs) {
        uint64_t seen = [version clockForReplica:run->_r];
        uint64_t end = run->_c + run->_len;
        uint64_t cut = seen < run->_c ? run->_c : (seen + 1 < end ? seen + 1 : end);
        if (cut > run->_c) {
            /* Characters it has: whether they are gone, and the registers it has not seen. */
            NSMutableDictionary *regs = [NSMutableDictionary dictionary];
            if (!run->_deleted)
                for (NSString *k in run->_attrs) {
                    TTRegister *g = run->_attrs[k];
                    if (g->_replica && g->_clock > [version clockForReplica:g->_replica]) regs[k] = g;
                }
            if (run->_deleted || regs.count) {
                TTRun *u = [TTRun new];
                u->_r = run->_r;
                u->_c = run->_c;
                u->_len = (NSUInteger)(cut - run->_c);
                u->_deleted = run->_deleted;
                u->_attrs = regs;
                [p addUpdate:u];
            }
        }
        if (cut < end) {
            TTRun *n = run;
            if (cut > run->_c) {
                NSUInteger off = (NSUInteger)(cut - run->_c);
                n = [TTRun new];
                n->_r = run->_r;
                n->_c = cut;
                n->_len = run->_len - off;
                n->_or = run->_r;
                n->_oc = cut - 1;
                n->_deleted = run->_deleted;
                n->_text = [run->_text substringFromIndex:off];
                n->_attrs = run->_attrs;
            }
            [p addInsert:n];
        }
    }
    return TTEncodePayload(p);
}

/* Before anything changes: every origin known here or earlier in the delta,
   every character an update names known, no id twice. */
- (BOOL)checkPayload:(TTPayload *)p error:(NSError **)error {
    NSMutableDictionary<NSNumber *, NSMutableArray<TTRun *> *> *pending = [NSMutableDictionary dictionary];
    TTRun *(^inPending)(TTReplica, uint64_t) = ^TTRun *(TTReplica r, uint64_t c) {
        NSArray<TTRun *> *a = pending[@(r)];
        NSUInteger lo = 0, hi = a.count;
        while (lo < hi) {
            NSUInteger mid = (lo + hi) / 2;
            if (a[mid]->_c <= c) lo = mid + 1; else hi = mid;
        }
        return lo && c < a[lo - 1]->_c + a[lo - 1]->_len ? a[lo - 1] : nil;
    };
    for (TTRun *rec in p.inserts) {
        if (rec->_or && ![self knowsReplica:rec->_or clock:rec->_oc] && !inPending(rec->_or, rec->_oc)) {
            if (error) *error = TTMakeError(TopoTextErrorMissingHistory, @"A delta for a copy that has seen more than this one");
            return NO;
        }
        NSNumber *k = @(rec->_r);
        NSMutableArray *a = pending[k] ?: (pending[k] = [NSMutableArray array]);
        NSUInteger lo = 0, hi = a.count;
        while (lo < hi) {
            NSUInteger mid = (lo + hi) / 2;
            if (((TTRun *)a[mid])->_c < rec->_c) lo = mid + 1; else hi = mid;
        }
        TTRun *before = lo ? a[lo - 1] : nil, *after = lo < a.count ? a[lo] : nil;
        if ((before && before->_c + before->_len > rec->_c) || (after && rec->_c + rec->_len > after->_c)) {
            if (error) *error = TTMakeError(TopoTextErrorCorrupt, @"Damaged TopoText data: an id twice");
            return NO;
        }
        [a insertObject:rec atIndex:lo];
    }
    for (TTRun *rec in p.updates) {
        uint64_t c = rec->_c, end = rec->_c + rec->_len;
        while (c < end) {
            NSUInteger off;
            TTRun *run = [self runWithReplica:rec->_r clock:c offset:&off] ?: inPending(rec->_r, c);
            if (!run) {
                if (error) *error = TTMakeError(TopoTextErrorMissingHistory, @"A delta for a copy that has seen more than this one");
                return NO;
            }
            c = run->_c + run->_len;
        }
    }
    return YES;
}

- (NSArray<TTEdit *> *)applyData:(NSData *)data error:(NSError **)error {
    TTPayload *p = TTDecodePayload(data, error);
    if (!p || ![self checkPayload:p error:error]) return nil;
    NSMutableArray *edits = [NSMutableArray array];
    if (!_runs.count && !p.updates.count) {
        /* Into an empty text: as it comes, already in document order. */
        for (TTRun *rec in p.inserts) {
            if (!rec->_deleted) {
                rec->_text = [rec->_text copy];
                NSDictionary *attrs = TTVisible(rec->_attrs);
                [edits addObject:[TTEdit editWithKind:TTEditInsert range:NSMakeRange(_string.length, rec->_len) string:rec->_text attributes:attrs]];
                [_string appendString:rec->_text];
            }
            [self adopt:rec at:_runs.count];
        }
    } else {
        for (TTRun *rec in p.inserts) [self integrate:rec edits:edits];
        for (TTRun *rec in p.updates)
            [self mergeReplica:rec->_r clock:rec->_c length:rec->_len deleted:rec->_deleted registers:rec->_attrs edits:edits];
    }
    for (NSNumber *r in p.version) [self see:r.unsignedLongLongValue clock:p.version[r].unsignedLongLongValue];
    return edits;
}

/* A run from elsewhere: the characters new here placed, the others' deletions
   and registers merged. */
- (void)integrate:(TTRun *)rec edits:(NSMutableArray *)edits {
    NSUInteger done = 0;
    while (done < rec->_len) {
        uint64_t c = rec->_c + done;
        NSUInteger off, span = rec->_len - done;
        TTRun *known = [self runWithReplica:rec->_r clock:c offset:&off];
        if (known) {
            span = MIN(span, known->_len - off);
            [self mergeReplica:rec->_r clock:c length:span deleted:rec->_deleted registers:rec->_attrs edits:edits];
        } else {
            TTRun *next = [self runOfReplica:rec->_r after:c];
            if (next && next->_c - c < span) span = (NSUInteger)(next->_c - c);
            TTRun *piece = [TTRun new];
            piece->_r = rec->_r;
            piece->_c = c;
            piece->_len = span;
            piece->_or = done ? rec->_r : rec->_or;
            piece->_oc = done ? c - 1 : rec->_oc;
            piece->_deleted = rec->_deleted;
            piece->_text = rec->_deleted ? nil : [rec->_text substringWithRange:NSMakeRange(done, span)];
            piece->_attrs = rec->_deleted ? @{} : rec->_attrs;
            [self place:piece edits:edits];
        }
        done += span;
    }
}

/* RGA: after the origin, past every run newer than this one (those, and what
   was inserted after them, come first), before the first older one. */
- (void)place:(TTRun *)run edits:(NSMutableArray *)edits {
    NSUInteger pos = 0;
    if (run->_or) {
        NSUInteger off;
        TTRun *origin = [self runWithReplica:run->_or clock:run->_oc offset:&off];
        pos = [_runs indexOfObjectIdenticalTo:origin];
        [self split:origin at:off + 1 position:pos];
        pos++;
    }
    NSUInteger count = _runs.count;
    while (pos < count) {
        TTRun *next = _runs[pos];
        if (!TTIdGreater(next->_c, next->_r, run->_c, run->_r)) break;
        pos++;
    }
    [self adopt:run at:pos];
    if (!run->_deleted) {
        NSUInteger at = [self visibleIndexOfPosition:pos];
        [_string insertString:run->_text atIndex:at];
        [edits addObject:[TTEdit editWithKind:TTEditInsert range:NSMakeRange(at, run->_len) string:run->_text attributes:TTVisible(run->_attrs)]];
    }
}

/* Characters (r, c) to (r, c + len - 1), all known: deleted if they are gone
   there, and theirs registers merged in. Only what changes is cut. */
- (void)mergeReplica:(TTReplica)r clock:(uint64_t)c length:(NSUInteger)len deleted:(BOOL)deleted
           registers:(NSDictionary *)regs edits:(NSMutableArray *)edits {
    [self seeRegisters:regs];
    while (len) {
        NSUInteger off;
        TTRun *run = [self runWithReplica:r clock:c offset:&off];
        NSUInteger span = MIN(len, run->_len - off);
        NSDictionary *merged = run->_deleted || deleted ? nil : TTMergeRegisters(run->_attrs, regs);
        BOOL kill = deleted && !run->_deleted;
        BOOL change = merged && merged != run->_attrs;
        if (kill || change) {
            NSUInteger pos = [_runs indexOfObjectIdenticalTo:run];
            if (off) {
                run = [self split:run at:off position:pos];
                pos++;
            }
            if (run->_len > span) [self split:run at:span position:pos];
            NSUInteger at = [self visibleIndexOfPosition:pos];
            if (kill) {
                [_string deleteCharactersInRange:NSMakeRange(at, run->_len)];
                [edits addObject:[TTEdit editWithKind:TTEditDelete range:NSMakeRange(at, run->_len) string:nil attributes:nil]];
                run->_deleted = YES;
                run->_text = nil;
                run->_attrs = @{};
            } else {
                NSDictionary *before = TTVisible(run->_attrs), *after = TTVisible(merged);
                run->_attrs = merged;
                if (![before isEqualToDictionary:after])
                    [edits addObject:[TTEdit editWithKind:TTEditAttributes range:NSMakeRange(at, run->_len) string:nil attributes:after]];
            }
        }
        c += span;
        len -= span;
    }
}

- (NSArray<TTEdit *> *)mergeText:(TopoText *)other {
    /* The whole state, when this copy's version claims more than other can tell. */
    NSArray *edits = [self applyData:[other deltaSinceVersion:[self version]] error:NULL];
    return edits ?: [self applyData:[other data] error:NULL] ?: @[];
}

- (TopoText *)mergedWith:(TopoText *)other {
    TopoText *t = [self copy];
    [t mergeText:other];
    return t;
}

@end
