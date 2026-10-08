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

#pragma mark undo steps

/* Characters (_r, _c) to (_r, _c + _len - 1): ids, not positions. */
@interface TTSpan : NSObject {
@public
    TTReplica _r;
    uint64_t _c;
    NSUInteger _len;
}
@end
@implementation TTSpan
@end

static TTSpan *TTMakeSpan(TTReplica r, uint64_t c, NSUInteger len) {
    TTSpan *s = [TTSpan new];
    s->_r = r;
    s->_c = c;
    s->_len = len;
    return s;
}

typedef NS_ENUM(NSInteger, TTUndoKind) { TTUndoInserted, TTUndoDeleted, TTUndoAttributes };

/* One edit kept: characters typed (their span); characters deleted (their
   spans, text, and attributes in runs: location, length, attributes); or
   attributes set (each span's earlier values of the keys set, NSNull for
   none). */
@interface TTUndoRecord : NSObject {
@public
    TTUndoKind _kind;
    NSMutableArray<TTSpan *> *_spans;
    NSString *_text;
    NSArray<NSDictionary *> *_runs;
    NSMutableArray<NSDictionary *> *_old;
}
@end
@implementation TTUndoRecord
@end

@implementation TTUndoStep {
@public
    NSMutableArray<TTUndoRecord *> *_records;
}
- (instancetype)init {
    if ((self = [super init])) _records = [NSMutableArray array];
    return self;
}
- (BOOL)isEmpty { return _records.count == 0; }
- (NSString *)description { return [NSString stringWithFormat:@"<TTUndoStep %lu edits>", (unsigned long)_records.count]; }
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

/* Kept for undo as this copy edits (TopoText (Undo), below). */
@interface TopoText (UndoRecording)
- (void)recordInsertOf:(NSUInteger)n;
- (void)recordDeleteOf:(NSRange)range;
- (void)recordAttributes:(NSDictionary *)attrs exclusive:(BOOL)exclusive range:(NSRange)range;
@end

@implementation TopoText {
    TTReplica _replica;
    uint64_t _clock;
    NSMutableArray<TTRun *> *_runs;                                    /* document order, tombstones too */
    NSMutableDictionary<NSNumber *, NSMutableArray<TTRun *> *> *_byReplica; /* each replica's runs by clock */
    NSMutableDictionary<NSNumber *, NSNumber *> *_seen;                /* the version */
    NSMutableString *_string;                                          /* the live characters */
    TTUndoStep *_recording;                                            /* this copy's edits kept, for undo */
    NSMutableDictionary<NSNumber *, NSMutableIndexSet *> *_collected;  /* ids deleted and gone: by replica, clocks */
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
    t->_collected = [NSMutableDictionary dictionary];
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
    right->_dr = run->_dr;
    right->_dc = run->_dc;
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
    /* Its characters' ids: this copy's next clocks, either way below. */
    if (_recording) [self recordInsertOf:n];
    NSDictionary *birth = TTBirth(attrs);
    /* Fugue: the right child of the character before, unless that one has a
       right child already (typing backwards, or between two characters
       typed apart); then the left child of the node right after it, the
       first of that right subtree, deleted or not. */
    TTReplica pr = 0;
    uint64_t pc = 0;
    BOOL left = NO, hasRight;
    NSUInteger p = 0, off = 0;
    TTRun *before = nil;
    if (index > 0) {
        before = [self liveRunAt:index - 1 position:&p offset:&off];
        pr = before->_r;
        pc = before->_c + off;
        hasRight = off + 1 < before->_len || [self hasRightChildReplica:pr clock:pc];
        /* Typing on at the end of our own latest run: the same run, longer. */
        if (!hasRight && before->_r == _replica && before->_c + before->_len == _clock + 1 &&
            [before->_attrs isEqualToDictionary:birth]) {
            before->_text = [before->_text stringByAppendingString:string];
            before->_len += n;
            [self see:_replica clock:before->_c + before->_len - 1];
            [_string insertString:string atIndex:index];
            return;
        }
    } else {
        hasRight = [self hasRightChildReplica:0 clock:0];
    }
    if (hasRight) {
        TTRun *next = !before ? _runs.firstObject : off + 1 < before->_len ? before : _runs[p + 1];
        pr = next->_r;
        pc = next == before ? before->_c + off + 1 : next->_c;
        left = YES;
    }
    TTRun *run = [TTRun new];
    run->_r = _replica;
    run->_c = _clock + 1;
    run->_len = n;
    run->_or = pr;
    run->_oc = pc;
    run->_left = left;
    run->_text = [string copy];
    run->_attrs = birth;
    [self adopt:run at:[self positionForRun:run]];
    [_string insertString:string atIndex:index];
}

/* Whether a character (0: the root) has a right child: a run placed after
   it, on its right (the next character of its own run is checked apart). */
- (BOOL)hasRightChildReplica:(TTReplica)r clock:(uint64_t)c {
    for (TTRun *run in _runs)
        if (!run->_left && run->_or == r && (!r || run->_oc == c)) return YES;
    return NO;
}

/* The live runs in range, in order, cut at its ends first. */
- (NSArray<TTRun *> *)liveRunsInRange:(NSRange)range {
    NSMutableArray<TTRun *> *runs = [NSMutableArray array];
    if (!range.length) return runs;
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
        [runs addObject:run];
    }
    return runs;
}

- (void)deleteCharactersInRange:(NSRange)range {
    [self checkRange:range];
    if (_recording && range.length) [self recordDeleteOf:range];
    if (!range.length) return;
    /* Who deleted it, and when: one clock, for collecting it once every
       copy has seen it. */
    uint64_t c = _clock + 1;
    [self see:_replica clock:c];
    for (TTRun *run in [self liveRunsInRange:range]) {
        run->_deleted = YES;
        run->_dr = _replica;
        run->_dc = c;
        run->_text = nil;
        run->_attrs = @{};
    }
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
    if (_recording) [self recordAttributes:attrs exclusive:exclusive range:range];
    for (TTRun *run in [self liveRunsInRange:range]) {
        NSMutableDictionary *m = [run->_attrs mutableCopy];
        [m addEntriesFromDictionary:regs];
        if (exclusive)
            for (NSString *k in run->_attrs)
                if (!regs[k] && ![run->_attrs[k]->_value isKindOfClass:[NSNull class]]) m[k] = removed;
        run->_attrs = m;
    }
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

/* The ranges of s's runs of the same attributes in range, in order
   (gnustep-base has no -enumerateAttributesInRange:options:usingBlock:). */
static NSArray<NSValue *> *TTAttributeRuns(NSAttributedString *s, NSRange range) {
    NSMutableArray *runs = [NSMutableArray array];
    NSUInteger i = range.location;
    while (i < NSMaxRange(range)) {
        NSRange run;
        [s attributesAtIndex:i longestEffectiveRange:&run inRange:range];
        run = NSIntersectionRange(run, NSMakeRange(i, NSMaxRange(range) - i));
        [runs addObject:[NSValue valueWithRange:run]];
        i = NSMaxRange(run);
    }
    return runs;
}

- (void)setAttributedString:(NSAttributedString *)target {
    NSString *string = target.string;
    NSRange mine, theirs;
    TTDiff(_string, string, &mine, &theirs);
    [self deleteCharactersInRange:mine];
    NSUInteger at = mine.location;
    for (NSValue *v in TTAttributeRuns(target, theirs)) {
        NSRange range = v.rangeValue;
        [self insertString:[string substringWithRange:range] atIndex:at
                attributes:[target attributesAtIndex:range.location effectiveRange:NULL]];
        at += range.length;
    }
    for (NSValue *v in TTAttributeRuns(target, NSMakeRange(0, string.length))) {
        NSRange range = v.rangeValue;
        NSDictionary *attrs = [target attributesAtIndex:range.location effectiveRange:NULL] ?: @{};
        NSUInteger i = range.location;
        while (i < NSMaxRange(range)) {
            NSRange ours;
            NSDictionary *have = [self attributesAtIndex:i effectiveRange:&ours];
            NSRange part = NSMakeRange(i, MIN(NSMaxRange(ours), NSMaxRange(range)) - i);
            if (![have isEqualToDictionary:attrs]) [self setAttributes:attrs range:part];
            i = NSMaxRange(part);
        }
    }
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
    for (NSNumber *r in _collected) p.collected[r] = [_collected[r] mutableCopy];
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
                u->_dr = run->_dr;
                u->_dc = run->_dc;
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
                n->_dr = run->_dr;
                n->_dc = run->_dc;
                n->_text = [run->_text substringFromIndex:off];
                n->_attrs = run->_attrs;
            }
            [p addInsert:n];
        }
    }
    return TTEncodePayload(p);
}

/* The run of a delta's inserts so far holding (r, c): pending holds each
   replica's, by clock. */
static TTRun *TTPendingRun(NSDictionary<NSNumber *, NSArray<TTRun *> *> *pending, TTReplica r, uint64_t c) {
    NSArray<TTRun *> *a = pending[@(r)];
    NSUInteger lo = 0, hi = a.count;
    while (lo < hi) {
        NSUInteger mid = (lo + hi) / 2;
        if (a[mid]->_c <= c) lo = mid + 1; else hi = mid;
    }
    return lo && c < a[lo - 1]->_c + a[lo - 1]->_len ? a[lo - 1] : nil;
}

/* Before anything changes: every origin known here or in the delta (a left
   child comes before its parent in document order), every character an
   update names known, no id twice. */
- (BOOL)checkPayload:(TTPayload *)p error:(NSError **)error {
    NSMutableDictionary<NSNumber *, NSMutableArray<TTRun *> *> *pending = [NSMutableDictionary dictionary];
    for (TTRun *rec in p.inserts) {
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
    for (TTRun *rec in p.inserts)
        if (rec->_or && ![self knowsReplica:rec->_or clock:rec->_oc] && !TTPendingRun(pending, rec->_or, rec->_oc)) {
            if (error) *error = TTMakeError(TopoTextErrorMissingHistory, @"A delta for a copy that has seen more than this one");
            return NO;
        }
    /* And each one placeable in turn: origins in a circle are no tree. */
    NSHashTable *placed = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
    NSMutableArray<TTRun *> *waiting = [p.inserts mutableCopy];
    while (waiting.count) {
        NSMutableArray<TTRun *> *still = [NSMutableArray array];
        for (TTRun *rec in waiting) {
            TTRun *origin = rec->_or && ![self knowsReplica:rec->_or clock:rec->_oc] ? TTPendingRun(pending, rec->_or, rec->_oc) : nil;
            if (origin && ![placed containsObject:origin]) [still addObject:rec];
            else [placed addObject:rec];
        }
        if (still.count == waiting.count) {
            if (error) *error = TTMakeError(TopoTextErrorCorrupt, @"Damaged TopoText data: origins in a circle");
            return NO;
        }
        waiting = still;
    }
    for (TTRun *rec in p.updates) {
        uint64_t c = rec->_c, end = rec->_c + rec->_len;
        while (c < end) {
            NSUInteger off;
            TTRun *run = [self runWithReplica:rec->_r clock:c offset:&off] ?: TTPendingRun(pending, rec->_r, c);
            if (!run && [self isCollectedReplica:rec->_r clock:c]) {
                /* Gone here: nothing to merge into it. */
                c++;
                continue;
            }
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
        /* Each run once its origin is here: a parent before its children. */
        NSMutableArray<TTRun *> *waiting = [p.inserts mutableCopy];
        while (waiting.count) {
            NSMutableArray<TTRun *> *still = [NSMutableArray array];
            for (TTRun *rec in waiting) {
                if (rec->_or && ![self knowsReplica:rec->_or clock:rec->_oc]) [still addObject:rec];
                else [self integrate:rec edits:edits];
            }
            if (still.count == waiting.count) break;   /* not after -checkPayload: */
            waiting = still;
        }
        for (TTRun *rec in p.updates)
            [self mergeReplica:rec->_r clock:rec->_c length:rec->_len deleted:rec->_deleted by:rec->_dr at:rec->_dc registers:rec->_attrs edits:edits];
    }
    [self applyCollected:p.collected edits:edits];
    for (NSNumber *r in p.version) [self see:r.unsignedLongLongValue clock:p.version[r].unsignedLongLongValue];
    return edits;
}

- (BOOL)isCollectedReplica:(TTReplica)r clock:(uint64_t)c {
    return c < NSNotFound && [_collected[@(r)] containsIndex:(NSUInteger)c];
}

/* What another copy collected: deleted here too where it is still shown
   (that copy had seen it deleted; this one had not yet), and remembered
   where it is not here at all. */
- (void)applyCollected:(NSDictionary<NSNumber *, NSIndexSet *> *)collected edits:(NSMutableArray *)edits {
    for (NSNumber *k in collected) {
        TTReplica r = k.unsignedLongLongValue;
        [collected[k] enumerateRangesUsingBlock:^(NSRange range, BOOL *stop) {
            NSUInteger c = range.location, end = NSMaxRange(range);
            while (c < end) {
                NSUInteger off;
                TTRun *run = [self runWithReplica:r clock:c offset:&off];
                if (!run) {
                    [self->_collected[k] ?: (self->_collected[k] = [NSMutableIndexSet indexSet]) addIndex:c];
                    c++;
                    continue;
                }
                NSUInteger span = MIN(end - c, run->_len - off);
                if (!run->_deleted)
                    [self mergeReplica:r clock:c length:span deleted:YES by:0 at:0 registers:@{} edits:edits];
                c += span;
            }
        }];
    }
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
            [self mergeReplica:rec->_r clock:c length:span deleted:rec->_deleted by:rec->_dr at:rec->_dc registers:rec->_attrs edits:edits];
        } else {
            TTRun *next = [self runOfReplica:rec->_r after:c];
            if (next && next->_c - c < span) span = (NSUInteger)(next->_c - c);
            /* Ids collected here come back deleted (they were), and are no
               longer counted gone: they are here again, to place by. */
            NSMutableIndexSet *gone = _collected[@(rec->_r)];
            BOOL dead = [gone containsIndex:(NSUInteger)c];
            if (gone) {
                NSUInteger i = (NSUInteger)c;
                while (i < c + span && [gone containsIndex:i] == dead) i++;
                span = i - (NSUInteger)c;
                if (dead) [gone removeIndexesInRange:NSMakeRange((NSUInteger)c, span)];
            }
            TTRun *piece = [TTRun new];
            piece->_r = rec->_r;
            piece->_c = c;
            piece->_len = span;
            piece->_or = done ? rec->_r : rec->_or;
            piece->_oc = done ? c - 1 : rec->_oc;
            piece->_left = done ? NO : rec->_left;
            piece->_deleted = rec->_deleted || dead;
            piece->_dr = rec->_deleted ? rec->_dr : 0;
            piece->_dc = rec->_deleted ? rec->_dc : 0;
            piece->_text = piece->_deleted ? nil : [rec->_text substringWithRange:NSMakeRange(done, span)];
            piece->_attrs = piece->_deleted ? @{} : rec->_attrs;
            [self place:piece edits:edits];
        }
        done += span;
    }
}

/* The child of (pr, pc) (0: the root) whose subtree holds the run x: its
   id and side; NO when x is not under it. Up x's parents: within a run, a
   character's is the one before it; a run's first character's, its origin. */
- (BOOL)childOfReplica:(TTReplica)pr clock:(uint64_t)pc holding:(TTRun *)x
                replica:(TTReplica *)cr clock:(uint64_t *)cc left:(BOOL *)cl {
    TTReplica r = x->_r, par = x->_or;
    uint64_t c = x->_c, parc = x->_oc;
    BOOL left = x->_left;
    for (;;) {
        if (!par) {
            if (pr) return NO;
            break;
        }
        if (par == pr && parc == pc) break;
        NSUInteger off;
        TTRun *run = [self runWithReplica:par clock:parc offset:&off];
        if (!run) return NO;
        /* The parent sought before it in its run: its right child there. */
        if (run->_r == pr && pc >= run->_c && pc < parc) {
            r = pr;
            c = pc + 1;
            left = NO;
            break;
        }
        r = run->_r;
        c = run->_c;
        left = run->_left;
        par = run->_or;
        parc = run->_oc;
    }
    *cr = r;
    *cc = c;
    *cl = left;
    return YES;
}

/* Fugue: a run's place, from its parent and side. A node's left subtree
   comes before it, its right subtree after; children on one side, the
   newest first (as RGA's, which is Fugue with right children only). So a
   right child goes after its parent, past the subtrees of newer right
   children; a left child before its parent, before the subtrees of older
   left children. */
- (NSUInteger)positionForRun:(TTRun *)run {
    TTReplica pr = run->_or, cr;
    uint64_t pc = run->_oc, cc;
    BOOL cl;
    NSUInteger count = _runs.count, pos;
    if (!pr) {
        pos = 0;
        while (pos < count && [self childOfReplica:0 clock:0 holding:_runs[pos] replica:&cr clock:&cc left:&cl] &&
               TTIdGreater(cc, cr, run->_c, run->_r))
            pos++;
        return pos;
    }
    NSUInteger off;
    TTRun *parent = [self runWithReplica:pr clock:pc offset:&off];
    pos = [_runs indexOfObjectIdenticalTo:parent];
    if (!run->_left) {
        [self split:parent at:off + 1 position:pos];
        pos++;
        count = _runs.count;
        while (pos < count && [self childOfReplica:pr clock:pc holding:_runs[pos] replica:&cr clock:&cc left:&cl] &&
               TTIdGreater(cc, cr, run->_c, run->_r))
            pos++;
        return pos;
    }
    if (off) {
        [self split:parent at:off position:pos];
        pos++;
    }
    while (pos > 0 && [self childOfReplica:pr clock:pc holding:_runs[pos - 1] replica:&cr clock:&cc left:&cl] &&
           TTIdGreater(run->_c, run->_r, cc, cr))
        pos--;
    return pos;
}

- (void)place:(TTRun *)run edits:(NSMutableArray *)edits {
    NSUInteger pos = [self positionForRun:run];
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
                  by:(TTReplica)dr at:(uint64_t)dc registers:(NSDictionary *)regs edits:(NSMutableArray *)edits {
    [self seeRegisters:regs];
    [self see:dr clock:dc];
    while (len) {
        NSUInteger off;
        TTRun *run = [self runWithReplica:r clock:c offset:&off];
        if (!run) {
            /* Collected here: on to what is here. */
            c++;
            len--;
            continue;
        }
        NSUInteger span = MIN(len, run->_len - off);
        NSDictionary *merged = run->_deleted || deleted ? nil : TTMergeRegisters(run->_attrs, regs);
        BOOL kill = deleted && !run->_deleted;
        BOOL change = merged && merged != run->_attrs;
        /* Deleted on both sides: the later deletion's stamp, the same on
           every copy (and one not known gives way to one known). */
        BOOL restamp = deleted && run->_deleted && dr && (!run->_dr || TTIdGreater(dc, dr, run->_dc, run->_dr));
        if (kill || change || restamp) {
            NSUInteger pos = [_runs indexOfObjectIdenticalTo:run];
            if (off) {
                run = [self split:run at:off position:pos];
                pos++;
            }
            if (run->_len > span) [self split:run at:span position:pos];
            NSUInteger at = [self visibleIndexOfPosition:pos];
            if (kill || restamp) {
                if (kill) {
                    [_string deleteCharactersInRange:NSMakeRange(at, run->_len)];
                    [edits addObject:[TTEdit editWithKind:TTEditDelete range:NSMakeRange(at, run->_len) string:nil attributes:nil]];
                }
                if (kill || !run->_dr || (dr && TTIdGreater(dc, dr, run->_dc, run->_dr))) {
                    run->_dr = dr;
                    run->_dc = dc;
                }
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

#pragma mark tombstones

- (NSUInteger)tombstoneCount {
    NSUInteger n = 0;
    for (TTRun *run in _runs)
        if (run->_deleted) n += run->_len;
    return n;
}

- (NSUInteger)collectTombstonesSeenBy:(TTVersion *)version {
    NSUInteger collected = 0;
    for (BOOL again = YES; again;) {
        again = NO;
        /* What places others: each origin, by replica. */
        NSMutableDictionary<NSNumber *, NSMutableIndexSet *> *origins = [NSMutableDictionary dictionary];
        NSMutableDictionary<NSNumber *, NSMutableArray<NSNumber *> *> *bigOrigins = [NSMutableDictionary dictionary];
        for (TTRun *run in _runs) {
            if (!run->_or) continue;
            NSNumber *k = @(run->_or);
            if (run->_oc < NSNotFound) [origins[k] ?: (origins[k] = [NSMutableIndexSet indexSet]) addIndex:(NSUInteger)run->_oc];
            else [bigOrigins[k] ?: (bigOrigins[k] = [NSMutableArray array]) addObject:@(run->_oc)];
        }
        for (NSInteger i = (NSInteger)_runs.count - 1; i >= 0; i--) {
            TTRun *run = _runs[(NSUInteger)i];
            if (!run->_deleted || !run->_dr) continue;
            if ([version clockForReplica:run->_dr] < run->_dc || [version clockForReplica:run->_r] < run->_c + run->_len - 1) continue;
            NSNumber *k = @(run->_r);
            if (run->_c + run->_len <= NSNotFound &&
                [origins[k] intersectsIndexesInRange:NSMakeRange((NSUInteger)run->_c, run->_len)])
                continue;
            BOOL big = NO;
            for (NSNumber *o in bigOrigins[k])
                if (o.unsignedLongLongValue >= run->_c && o.unsignedLongLongValue < run->_c + run->_len) big = YES;
            if (big) continue;
            [_runs removeObjectAtIndex:(NSUInteger)i];
            [_byReplica[k] removeObjectIdenticalTo:run];
            [_collected[k] ?: (_collected[k] = [NSMutableIndexSet indexSet]) addIndexesInRange:NSMakeRange((NSUInteger)run->_c, run->_len)];
            collected += run->_len;
            /* Its own origin may be free now: once more. */
            again = YES;
        }
    }
    /* Those that stay: one record where they follow one another in a run,
       the later deletion's stamp kept. */
    for (NSUInteger i = 0; i + 1 < _runs.count;) {
        TTRun *a = _runs[i], *b = _runs[i + 1];
        BOOL seen = a->_deleted && b->_deleted && a->_dr && b->_dr && [version clockForReplica:a->_dr] >= a->_dc &&
                    [version clockForReplica:b->_dr] >= b->_dc;
        if (seen && b->_r == a->_r && b->_c == a->_c + a->_len && !b->_left && b->_or == a->_r && b->_oc == a->_c + a->_len - 1) {
            a->_len += b->_len;
            if (TTIdGreater(b->_dc, b->_dr, a->_dc, a->_dr)) {
                a->_dr = b->_dr;
                a->_dc = b->_dc;
            }
            [_runs removeObjectAtIndex:i + 1];
            [_byReplica[@(b->_r)] removeObjectIdenticalTo:b];
            continue;
        }
        i++;
    }
    return collected;
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

#pragma mark undo

@implementation TopoText (Undo)

- (TTUndoStep *)recordingUndoStep { return _recording; }

- (void)beginUndoStep { _recording = [TTUndoStep new]; }

- (void)continueUndoStep:(TTUndoStep *)step { _recording = step; }

- (TTUndoStep *)endUndoStep {
    TTUndoStep *step = _recording ?: [TTUndoStep new];
    _recording = nil;
    return step;
}

/* n characters about to be typed: this copy's next n clocks; typing on
   right after the last ones kept, the same record, longer. */
- (void)recordInsertOf:(NSUInteger)n {
    uint64_t c = _clock + 1;
    TTUndoRecord *last = _recording->_records.lastObject;
    TTSpan *span = last && last->_kind == TTUndoInserted ? last->_spans.lastObject : nil;
    if (span && span->_r == _replica && span->_c + span->_len == c) {
        span->_len += n;
        return;
    }
    TTUndoRecord *r = [TTUndoRecord new];
    r->_kind = TTUndoInserted;
    r->_spans = [NSMutableArray arrayWithObject:TTMakeSpan(_replica, c, n)];
    [_recording->_records addObject:r];
}

/* range about to be deleted: its characters' ids, its text and its
   attributes, to put back. */
- (void)recordDeleteOf:(NSRange)range {
    TTUndoRecord *r = [TTUndoRecord new];
    r->_kind = TTUndoDeleted;
    r->_spans = [NSMutableArray array];
    for (TTRun *run in [self liveRunsInRange:range]) [r->_spans addObject:TTMakeSpan(run->_r, run->_c, run->_len)];
    r->_text = [_string substringWithRange:range];
    NSMutableArray *runs = [NSMutableArray array];
    for (NSDictionary *a in [self attributeRuns]) {
        NSRange ar = NSMakeRange([a[@"location"] unsignedIntegerValue], [a[@"length"] unsignedIntegerValue]);
        NSRange in = NSIntersectionRange(ar, range);
        if (in.length) [runs addObject:@{ @"location": @(in.location - range.location), @"length": @(in.length), @"attributes": a[@"attributes"] }];
    }
    r->_runs = runs;
    [_recording->_records addObject:r];
}

/* Attributes about to be set on range: each run's earlier values of the
   keys that change (all of its keys, when the set is exclusive). */
- (void)recordAttributes:(NSDictionary *)attrs exclusive:(BOOL)exclusive range:(NSRange)range {
    if (!range.length) return;
    TTUndoRecord *r = [TTUndoRecord new];
    r->_kind = TTUndoAttributes;
    r->_spans = [NSMutableArray array];
    r->_old = [NSMutableArray array];
    for (TTRun *run in [self liveRunsInRange:range]) {
        NSDictionary *now = TTVisible(run->_attrs);
        NSMutableSet *keys = [NSMutableSet setWithArray:attrs.allKeys];
        if (exclusive) [keys addObjectsFromArray:now.allKeys];
        NSMutableDictionary *old = [NSMutableDictionary dictionary];
        for (NSString *k in keys) old[k] = now[k] ?: [NSNull null];
        [r->_spans addObject:TTMakeSpan(run->_r, run->_c, run->_len)];
        [r->_old addObject:old];
    }
    [_recording->_records addObject:r];
}

/* Where a span's live characters are now: visible ranges, in order. */
- (NSArray<NSValue *> *)liveRangesOfSpan:(TTSpan *)span {
    NSMutableArray *ranges = [NSMutableArray array];
    uint64_t c = span->_c, end = span->_c + span->_len;
    while (c < end) {
        NSUInteger off;
        TTRun *run = [self runWithReplica:span->_r clock:c offset:&off];
        if (!run) {
            /* Collected (deleted, and seen so everywhere): on past it. */
            TTRun *next = [self runOfReplica:span->_r after:c];
            if (!next || next->_c >= end) break;
            c = next->_c;
            continue;
        }
        NSUInteger n = (NSUInteger)MIN((uint64_t)(run->_len - off), end - c);
        if (!run->_deleted) {
            NSUInteger at = [self visibleIndexOfPosition:[_runs indexOfObjectIdenticalTo:run]] + off;
            NSValue *last = ranges.lastObject;
            if (last && NSMaxRange(last.rangeValue) == at)
                ranges[ranges.count - 1] = [NSValue valueWithRange:NSMakeRange(last.rangeValue.location, last.rangeValue.length + n)];
            else
                [ranges addObject:[NSValue valueWithRange:NSMakeRange(at, n)]];
        }
        c += n;
    }
    return ranges;
}

/* Where a deleted character stands now: how many live characters come
   before it. */
- (NSUInteger)indexOfDeletedReplica:(TTReplica)r clock:(uint64_t)c {
    NSUInteger off;
    TTRun *run = [self runWithReplica:r clock:c offset:&off];
    if (!run) return NSNotFound;
    NSUInteger at = [self visibleIndexOfPosition:[_runs indexOfObjectIdenticalTo:run]];
    return run->_deleted ? at : at + off;
}

/* The attribute edits a view needs for range, as it now is. */
- (void)addAttributeEditsIn:(NSRange)range to:(NSMutableArray<TTEdit *> *)edits {
    for (NSDictionary *a in [self attributeRuns]) {
        NSRange ar = NSMakeRange([a[@"location"] unsignedIntegerValue], [a[@"length"] unsignedIntegerValue]);
        NSRange in = NSIntersectionRange(ar, range);
        if (in.length) [edits addObject:[TTEdit editWithKind:TTEditAttributes range:in string:nil attributes:a[@"attributes"]]];
    }
}

- (NSArray<TTEdit *> *)undoStep:(TTUndoStep *)step redoStep:(TTUndoStep **)redo {
    TTUndoStep *outer = _recording;
    _recording = [TTUndoStep new];
    NSMutableArray<TTEdit *> *edits = [NSMutableArray array];
    for (TTUndoRecord *r in step->_records.reverseObjectEnumerator) {
        switch (r->_kind) {
        case TTUndoInserted: {
            /* What was typed taken out, wherever it is; last first, so the
               ranges before stay where they are. */
            NSMutableArray<NSValue *> *ranges = [NSMutableArray array];
            for (TTSpan *s in r->_spans) [ranges addObjectsFromArray:[self liveRangesOfSpan:s]];
            [ranges sortUsingComparator:^NSComparisonResult(NSValue *a, NSValue *b) {
                return a.rangeValue.location > b.rangeValue.location ? NSOrderedAscending
                     : a.rangeValue.location < b.rangeValue.location ? NSOrderedDescending : NSOrderedSame;
            }];
            for (NSValue *v in ranges) {
                [self deleteCharactersInRange:v.rangeValue];
                [edits addObject:[TTEdit editWithKind:TTEditDelete range:v.rangeValue string:nil attributes:nil]];
            }
            break;
        }
        case TTUndoDeleted: {
            /* What was deleted, back where its first character was. */
            TTSpan *first = r->_spans.firstObject;
            NSUInteger at = first ? [self indexOfDeletedReplica:first->_r clock:first->_c] : NSNotFound;
            if (at == NSNotFound) break;
            for (NSDictionary *run in r->_runs) {
                NSRange in = NSMakeRange([run[@"location"] unsignedIntegerValue], [run[@"length"] unsignedIntegerValue]);
                NSString *part = [r->_text substringWithRange:in];
                [self insertString:part atIndex:at + in.location attributes:run[@"attributes"]];
                [edits addObject:[TTEdit editWithKind:TTEditInsert range:NSMakeRange(at + in.location, in.length) string:part
                                           attributes:run[@"attributes"]]];
            }
            break;
        }
        case TTUndoAttributes: {
            /* The keys set back, on the characters still there. */
            for (NSUInteger i = 0; i < r->_spans.count; i++)
                for (NSValue *v in [self liveRangesOfSpan:r->_spans[i]]) {
                    [self addAttributes:r->_old[i] range:v.rangeValue];
                    [self addAttributeEditsIn:v.rangeValue to:edits];
                }
            break;
        }
        }
    }
    TTUndoStep *done = _recording;
    _recording = outer;
    if (redo) *redo = done;
    return edits;
}

@end

#pragma mark paragraphs

@implementation TopoText (Paragraphs)

- (NSRange)paragraphRangeForIndex:(NSUInteger)index {
    NSString *s = _string;
    NSUInteger n = s.length;
    index = MIN(index, n);
    NSUInteger start = index;
    while (start > 0 && [s characterAtIndex:start - 1] != '\n') start--;
    NSUInteger end = index;
    while (end < n && [s characterAtIndex:end] != '\n') end++;
    if (end < n) end++;   /* its newline */
    return NSMakeRange(start, end - start);
}

- (NSArray<NSValue *> *)paragraphRanges {
    NSMutableArray *ranges = [NSMutableArray array];
    NSString *s = _string;
    NSUInteger n = s.length, start = 0;
    for (NSUInteger i = 0; i < n; i++)
        if ([s characterAtIndex:i] == '\n') {
            [ranges addObject:[NSValue valueWithRange:NSMakeRange(start, i + 1 - start)]];
            start = i + 1;
        }
    [ranges addObject:[NSValue valueWithRange:NSMakeRange(start, n - start)]];
    return ranges;
}

- (NSDictionary *)paragraphAttributesAtIndex:(NSUInteger)index keys:(NSSet<NSString *> *)keys {
    NSRange p = [self paragraphRangeForIndex:index];
    if (!p.length) return @{};
    NSUInteger end = NSMaxRange(p) - 1;
    /* Its newline, or the last paragraph's first character. */
    NSUInteger at = [_string characterAtIndex:end] == '\n' ? end : p.location;
    NSDictionary *all = [self attributesAtIndex:at effectiveRange:NULL];
    NSMutableDictionary *mine = [NSMutableDictionary dictionary];
    for (NSString *k in keys)
        if (all[k]) mine[k] = all[k];
    return mine;
}

- (void)addParagraphAttributes:(NSDictionary *)attrs range:(NSRange)range {
    [self checkRange:range];
    NSRange first = [self paragraphRangeForIndex:range.location];
    NSRange last = [self paragraphRangeForIndex:range.length ? NSMaxRange(range) - 1 : range.location];
    NSRange whole = NSUnionRange(first, last);
    if (whole.length) [self addAttributes:attrs range:whole];
}

@end
