#import "TTInternal.h"
#import <objc/runtime.h>

/* The wire format, little-endian, every count and clock a LEB128 varint:

     'T' 'T' 1
     replicas   n, then n u64s, ascending; records name them by index
     version    n, then n (replica index ascending, clock)
     inserts    n, then n records, in the sender's document order:
                  replica, clock, length, flags
                  (1 deleted, 2 has origin, 4 origin is the previous record's
                   last character, 8 has attributes)
                  origin replica and clock, unless 4 or none
                  text, unless deleted: byte count, then WTF-8
                  attributes: n, then n (key, value, clock, replica index + 1
                  or 0 for a birth register), keys in byte order
     updates    n, then n records: replica, clock, length, flags (1, 8),
                attributes

   Text is WTF-8, UTF-8 that also carries a lone surrogate: a run split by a
   remote insert between the halves of a pair must still encode. Everything is
   written in one order, so the same state is the same bytes on every system. */

static const uint8_t TTMagic[3] = { 'T', 'T', 1 };
static const uint8_t TTVersionMagic[3] = { 'T', 'V', 1 };
enum { TTMaxDepth = 32 };

NSError *TTMakeError(TopoTextError code, NSString *reason) {
    return [NSError errorWithDomain:TopoTextErrorDomain code:code userInfo:@{ NSLocalizedDescriptionKey: reason }];
}

#pragma mark writing

static void TTPutByte(NSMutableData *d, uint8_t b) { [d appendBytes:&b length:1]; }

static void TTPutVarint(NSMutableData *d, uint64_t v) {
    uint8_t b[10];
    int n = 0;
    do {
        uint8_t x = v & 0x7f;
        v >>= 7;
        if (v) x |= 0x80;
        b[n++] = x;
    } while (v);
    [d appendBytes:b length:n];
}

static void TTPutU64(NSMutableData *d, uint64_t v) {
    uint8_t b[8];
    for (int i = 0; i < 8; i++) b[i] = (uint8_t)(v >> (8 * i));
    [d appendBytes:b length:8];
}

static NSData *TTWTF8(NSString *s) {
    NSUInteger n = s.length;
    unichar stack[256];
    unichar *u = n <= 256 ? stack : malloc(n * sizeof(unichar));
    [s getCharacters:u range:NSMakeRange(0, n)];
    NSMutableData *out = [NSMutableData dataWithCapacity:n];
    for (NSUInteger i = 0; i < n; i++) {
        uint32_t c = u[i];
        uint8_t b[4];
        if (c < 0x80) {
            b[0] = (uint8_t)c;
            [out appendBytes:b length:1];
        } else if (c < 0x800) {
            b[0] = 0xc0 | (c >> 6); b[1] = 0x80 | (c & 0x3f);
            [out appendBytes:b length:2];
        } else if (c >= 0xd800 && c < 0xdc00 && i + 1 < n && u[i + 1] >= 0xdc00 && u[i + 1] < 0xe000) {
            uint32_t p = 0x10000 + ((c - 0xd800) << 10) + (u[++i] - 0xdc00);
            b[0] = 0xf0 | (p >> 18); b[1] = 0x80 | ((p >> 12) & 0x3f);
            b[2] = 0x80 | ((p >> 6) & 0x3f); b[3] = 0x80 | (p & 0x3f);
            [out appendBytes:b length:4];
        } else {
            b[0] = 0xe0 | (c >> 12); b[1] = 0x80 | ((c >> 6) & 0x3f); b[2] = 0x80 | (c & 0x3f);
            [out appendBytes:b length:3];
        }
    }
    if (u != stack) free(u);
    return out;
}

static void TTPutBytes(NSMutableData *d, NSData *bytes) {
    TTPutVarint(d, bytes.length);
    [d appendData:bytes];
}

static BOOL TTIsBool(NSNumber *n) {
    static Class boolClass, intClass;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ boolClass = object_getClass(@YES); intClass = object_getClass(@1); });
    if (n == (id)@YES || n == (id)@NO) return YES;
    return boolClass != intClass && object_getClass(n) == boolClass;
}

static BOOL TTIsReal(NSNumber *n) {
    const char *t = n.objCType;
    return t && (t[0] == 'f' || t[0] == 'd');
}

static NSArray<NSString *> *TTSortedKeys(NSDictionary *d) {
    /* By their bytes: -compare: is not the same ordering everywhere. */
    return [d.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSData *x = TTWTF8(a), *y = TTWTF8(b);
        int c = memcmp(x.bytes, y.bytes, MIN(x.length, y.length));
        if (c) return c < 0 ? NSOrderedAscending : NSOrderedDescending;
        return x.length == y.length ? NSOrderedSame : (x.length < y.length ? NSOrderedAscending : NSOrderedDescending);
    }];
}

static BOOL TTValueIsCodableAt(id v, int depth) {
    if (depth > TTMaxDepth) return NO;
    if ([v isKindOfClass:[NSNull class]] || [v isKindOfClass:[NSString class]] || [v isKindOfClass:[NSNumber class]] ||
        [v isKindOfClass:[NSData class]] || [v isKindOfClass:[NSDate class]])
        return YES;
    if ([v isKindOfClass:[NSArray class]]) {
        for (id e in v) if (!TTValueIsCodableAt(e, depth + 1)) return NO;
        return YES;
    }
    if ([v isKindOfClass:[NSDictionary class]]) {
        for (id k in v) if (![k isKindOfClass:[NSString class]] || !TTValueIsCodableAt(v[k], depth + 1)) return NO;
        return YES;
    }
    return NO;
}

BOOL TTValueIsCodable(id value) { return TTValueIsCodableAt(value, 0); }

enum { TTNull, TTFalse, TTTrue, TTInt, TTReal, TTString, TTBytes, TTArray, TTDict, TTDate };

static void TTPutValue(NSMutableData *d, id v) {
    if ([v isKindOfClass:[NSNull class]]) {
        TTPutByte(d, TTNull);
    } else if ([v isKindOfClass:[NSString class]]) {
        TTPutByte(d, TTString);
        TTPutBytes(d, TTWTF8(v));
    } else if ([v isKindOfClass:[NSNumber class]]) {
        if (TTIsBool(v)) {
            TTPutByte(d, [v boolValue] ? TTTrue : TTFalse);
        } else if (TTIsReal(v)) {
            double x = [v doubleValue];
            uint64_t bits;
            memcpy(&bits, &x, 8);
            TTPutByte(d, TTReal);
            TTPutU64(d, bits);
        } else {
            int64_t x = [v longLongValue];
            TTPutByte(d, TTInt);
            TTPutVarint(d, ((uint64_t)x << 1) ^ (uint64_t)(x >> 63));
        }
    } else if ([v isKindOfClass:[NSData class]]) {
        TTPutByte(d, TTBytes);
        TTPutBytes(d, v);
    } else if ([v isKindOfClass:[NSDate class]]) {
        double x = [v timeIntervalSince1970];
        uint64_t bits;
        memcpy(&bits, &x, 8);
        TTPutByte(d, TTDate);
        TTPutU64(d, bits);
    } else if ([v isKindOfClass:[NSArray class]]) {
        TTPutByte(d, TTArray);
        TTPutVarint(d, [v count]);
        for (id e in v) TTPutValue(d, e);
    } else {
        TTPutByte(d, TTDict);
        TTPutVarint(d, [v count]);
        for (NSString *k in TTSortedKeys(v)) {
            TTPutBytes(d, TTWTF8(k));
            TTPutValue(d, v[k]);
        }
    }
}

#pragma mark reading

typedef struct {
    const uint8_t *p, *end;
    BOOL bad;
} TTReader;

static uint8_t TTGetByte(TTReader *r) {
    if (r->p >= r->end) { r->bad = YES; return 0; }
    return *r->p++;
}

static uint64_t TTGetVarint(TTReader *r) {
    uint64_t v = 0;
    for (int shift = 0;; shift += 7) {
        if (r->p >= r->end || shift > 63) { r->bad = YES; return 0; }
        uint8_t b = *r->p++;
        v |= (uint64_t)(b & 0x7f) << shift;
        if (!(b & 0x80)) return v;
    }
}

static uint64_t TTGetU64(TTReader *r) {
    if (r->end - r->p < 8) { r->bad = YES; r->p = r->end; return 0; }
    uint64_t v = 0;
    for (int i = 0; i < 8; i++) v |= (uint64_t)r->p[i] << (8 * i);
    r->p += 8;
    return v;
}

static const uint8_t *TTGetSpan(TTReader *r, uint64_t *n) {
    *n = TTGetVarint(r);
    if (r->bad || *n > (uint64_t)(r->end - r->p)) { r->bad = YES; return NULL; }
    const uint8_t *s = r->p;
    r->p += *n;
    return s;
}

/* WTF-8 to UTF-16; nil when malformed. */
static NSString *TTGetText(TTReader *r) {
    uint64_t n;
    const uint8_t *s = TTGetSpan(r, &n);
    if (!s) return nil;
    unichar *u = malloc((n ? n : 1) * sizeof(unichar));
    NSUInteger k = 0;
    NSString *str = nil;
    for (uint64_t i = 0; i < n;) {
        uint8_t b = s[i];
        uint32_t c;
        int more;
        if (b < 0x80) { c = b; more = 0; }
        else if ((b & 0xe0) == 0xc0) { c = b & 0x1f; more = 1; }
        else if ((b & 0xf0) == 0xe0) { c = b & 0x0f; more = 2; }
        else if ((b & 0xf8) == 0xf0) { c = b & 0x07; more = 3; }
        else goto bad;
        if (i + more >= n && more) goto bad;
        for (int j = 1; j <= more; j++) {
            if ((s[i + j] & 0xc0) != 0x80) goto bad;
            c = (c << 6) | (s[i + j] & 0x3f);
        }
        if ((more == 1 && c < 0x80) || (more == 2 && c < 0x800) || (more == 3 && (c < 0x10000 || c > 0x10ffff))) goto bad;
        i += more + 1;
        if (c >= 0x10000) {
            c -= 0x10000;
            u[k++] = 0xd800 + (c >> 10);
            u[k++] = 0xdc00 + (c & 0x3ff);
        } else {
            u[k++] = (unichar)c;
        }
    }
    str = [[NSString alloc] initWithCharacters:u length:k];
    free(u);
    return str;
bad:
    free(u);
    r->bad = YES;
    return nil;
}

static id TTGetValue(TTReader *r, int depth) {
    if (depth > TTMaxDepth) { r->bad = YES; return nil; }
    uint8_t tag = TTGetByte(r);
    switch (tag) {
    case TTNull: return [NSNull null];
    case TTFalse: return @NO;
    case TTTrue: return @YES;
    case TTInt: {
        uint64_t z = TTGetVarint(r);
        return @((int64_t)(z >> 1) ^ -(int64_t)(z & 1));
    }
    case TTReal:
    case TTDate: {
        uint64_t bits = TTGetU64(r);
        double x;
        memcpy(&x, &bits, 8);
        return tag == TTReal ? (id)@(x) : (id)[NSDate dateWithTimeIntervalSince1970:x];
    }
    case TTString: return TTGetText(r);
    case TTBytes: {
        uint64_t n;
        const uint8_t *s = TTGetSpan(r, &n);
        return s ? [NSData dataWithBytes:s length:n] : nil;
    }
    case TTArray: {
        uint64_t n = TTGetVarint(r);
        if (n > (uint64_t)(r->end - r->p)) { r->bad = YES; return nil; }
        NSMutableArray *a = [NSMutableArray arrayWithCapacity:n];
        for (uint64_t i = 0; i < n && !r->bad; i++) {
            id e = TTGetValue(r, depth + 1);
            if (e) [a addObject:e];
        }
        return r->bad ? nil : a;
    }
    case TTDict: {
        uint64_t n = TTGetVarint(r);
        if (n > (uint64_t)(r->end - r->p)) { r->bad = YES; return nil; }
        NSMutableDictionary *m = [NSMutableDictionary dictionaryWithCapacity:n];
        for (uint64_t i = 0; i < n && !r->bad; i++) {
            NSString *k = TTGetText(r);
            id e = TTGetValue(r, depth + 1);
            if (k && e) m[k] = e;
        }
        return r->bad ? nil : m;
    }
    default:
        r->bad = YES;
        return nil;
    }
}

#pragma mark registers

@implementation TTRegister
+ (instancetype)registerWithValue:(id)value clock:(uint64_t)clock replica:(TTReplica)replica {
    TTRegister *g = [self new];
    g->_value = value;
    g->_clock = clock;
    g->_replica = replica;
    return g;
}
- (BOOL)isEqual:(id)o {
    if (o == self) return YES;
    if (![o isKindOfClass:[TTRegister class]]) return NO;
    TTRegister *g = o;
    return g->_clock == _clock && g->_replica == _replica && [g->_value isEqual:_value];
}
- (NSUInteger)hash { return (NSUInteger)(_clock * 31 + _replica) ^ [_value hash]; }
- (NSString *)description { return [NSString stringWithFormat:@"%@@%llu:%llu", _value, (unsigned long long)_replica, (unsigned long long)_clock]; }
@end

@implementation TTRun
- (NSString *)description {
    return [NSString stringWithFormat:@"<%llu:%llu+%lu after %llu:%llu%@ %@ %@>", (unsigned long long)_r,
            (unsigned long long)_c, (unsigned long)_len, (unsigned long long)_or, (unsigned long long)_oc,
            _deleted ? @" deleted" : @"", _text ? [NSString stringWithFormat:@"\"%@\"", _text] : @"", _attrs];
}
@end

#pragma mark payloads

static TTRun *TTCopyRun(TTRun *run) {
    TTRun *c = [TTRun new];
    c->_r = run->_r; c->_c = run->_c; c->_len = run->_len;
    c->_or = run->_or; c->_oc = run->_oc;
    c->_deleted = run->_deleted;
    c->_text = run->_text ? [run->_text mutableCopy] : nil;
    c->_attrs = run->_attrs ?: @{};
    return c;
}

@implementation TTPayload
- (instancetype)init {
    if ((self = [super init])) {
        _inserts = [NSMutableArray array];
        _updates = [NSMutableArray array];
        _version = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)addInsert:(TTRun *)run {
    TTRun *last = _inserts.lastObject;
    if (last && last->_r == run->_r && last->_c + last->_len == run->_c && last->_deleted == run->_deleted &&
        run->_or == run->_r && run->_oc == run->_c - 1 && [last->_attrs isEqualToDictionary:run->_attrs]) {
        last->_len += run->_len;
        if (run->_text) [(NSMutableString *)last->_text appendString:run->_text];
        return;
    }
    [_inserts addObject:TTCopyRun(run)];
}

- (void)addUpdate:(TTRun *)run {
    TTRun *last = _updates.lastObject;
    if (last && last->_r == run->_r && last->_c + last->_len == run->_c && last->_deleted == run->_deleted &&
        [last->_attrs isEqualToDictionary:run->_attrs]) {
        last->_len += run->_len;
        return;
    }
    TTRun *c = TTCopyRun(run);
    c->_text = nil;
    [_updates addObject:c];
}
@end

static void TTNote(NSMutableSet *s, TTReplica r) { if (r) [s addObject:@(r)]; }

static void TTPutAttrs(NSMutableData *d, NSDictionary<NSString *, TTRegister *> *attrs, NSDictionary *index) {
    TTPutVarint(d, attrs.count);
    for (NSString *k in TTSortedKeys(attrs)) {
        TTRegister *g = attrs[k];
        TTPutBytes(d, TTWTF8(k));
        TTPutValue(d, g->_value);
        TTPutVarint(d, g->_clock);
        TTPutVarint(d, g->_replica ? [index[@(g->_replica)] unsignedLongLongValue] + 1 : 0);
    }
}

NSData *TTEncodePayload(TTPayload *p) {
    NSMutableSet *seen = [NSMutableSet set];
    for (NSNumber *r in p.version) TTNote(seen, r.unsignedLongLongValue);
    for (NSArray *list in @[ p.inserts, p.updates ])
        for (TTRun *run in list) {
            TTNote(seen, run->_r);
            TTNote(seen, run->_or);
            for (TTRegister *g in run->_attrs.allValues) TTNote(seen, g->_replica);
        }
    NSArray<NSNumber *> *replicas = [seen.allObjects sortedArrayUsingSelector:@selector(compare:)];
    NSMutableDictionary *index = [NSMutableDictionary dictionary];
    [replicas enumerateObjectsUsingBlock:^(NSNumber *r, NSUInteger i, BOOL *stop) { index[r] = @(i); }];

    NSMutableData *d = [NSMutableData dataWithBytes:TTMagic length:3];
    TTPutVarint(d, replicas.count);
    for (NSNumber *r in replicas) TTPutU64(d, r.unsignedLongLongValue);

    NSArray *versioned = [p.version.allKeys sortedArrayUsingSelector:@selector(compare:)];
    TTPutVarint(d, versioned.count);
    for (NSNumber *r in versioned) {
        TTPutVarint(d, [index[r] unsignedLongLongValue]);
        TTPutVarint(d, [p.version[r] unsignedLongLongValue]);
    }

    TTPutVarint(d, p.inserts.count);
    TTRun *prev = nil;
    for (TTRun *run in p.inserts) {
        BOOL implicit = run->_or && prev && run->_or == prev->_r && run->_oc == prev->_c + prev->_len - 1;
        BOOL attrs = !run->_deleted && run->_attrs.count;
        TTPutVarint(d, [index[@(run->_r)] unsignedLongLongValue]);
        TTPutVarint(d, run->_c);
        TTPutVarint(d, run->_len);
        TTPutByte(d, (run->_deleted ? 1 : 0) | (run->_or ? 2 : 0) | (implicit ? 4 : 0) | (attrs ? 8 : 0));
        if (run->_or && !implicit) {
            TTPutVarint(d, [index[@(run->_or)] unsignedLongLongValue]);
            TTPutVarint(d, run->_oc);
        }
        if (!run->_deleted) TTPutBytes(d, TTWTF8(run->_text ?: @""));
        if (attrs) TTPutAttrs(d, run->_attrs, index);
        prev = run;
    }

    TTPutVarint(d, p.updates.count);
    for (TTRun *run in p.updates) {
        BOOL attrs = !run->_deleted && run->_attrs.count;
        TTPutVarint(d, [index[@(run->_r)] unsignedLongLongValue]);
        TTPutVarint(d, run->_c);
        TTPutVarint(d, run->_len);
        TTPutByte(d, (run->_deleted ? 1 : 0) | (attrs ? 8 : 0));
        if (attrs) TTPutAttrs(d, run->_attrs, index);
    }
    return d;
}

static TTReplica TTGetReplica(TTReader *r, NSArray<NSNumber *> *replicas) {
    uint64_t i = TTGetVarint(r);
    if (i >= replicas.count) { r->bad = YES; return 0; }
    return replicas[(NSUInteger)i].unsignedLongLongValue;
}

static NSDictionary *TTGetAttrs(TTReader *r, NSArray<NSNumber *> *replicas) {
    uint64_t n = TTGetVarint(r);
    if (n > (uint64_t)(r->end - r->p)) { r->bad = YES; return nil; }
    NSMutableDictionary *m = [NSMutableDictionary dictionaryWithCapacity:n];
    for (uint64_t i = 0; i < n && !r->bad; i++) {
        NSString *k = TTGetText(r);
        id v = TTGetValue(r, 0);
        uint64_t clock = TTGetVarint(r);
        uint64_t ri = TTGetVarint(r);
        if (r->bad) break;
        if (ri > replicas.count || (ri == 0) != (clock == 0)) { r->bad = YES; break; }
        TTReplica rep = ri ? replicas[(NSUInteger)ri - 1].unsignedLongLongValue : 0;
        if (k && v) m[k] = [TTRegister registerWithValue:v clock:clock replica:rep];
    }
    return m;
}

static BOOL TTGetSpanOf(TTReader *r, TTRun *run, NSArray *replicas) {
    run->_r = TTGetReplica(r, replicas);
    run->_c = TTGetVarint(r);
    uint64_t len = TTGetVarint(r);
    if (r->bad || run->_c == 0 || len == 0 || len > NSUIntegerMax || run->_c + len < run->_c) return NO;
    run->_len = (NSUInteger)len;
    return YES;
}

TTPayload *TTDecodePayload(NSData *data, NSError **error) {
    TTReader r = { data.bytes, (const uint8_t *)data.bytes + data.length, NO };
    if (data.length < 3 || memcmp(data.bytes, TTMagic, 2) != 0) {
        if (error) *error = TTMakeError(TopoTextErrorCorrupt, @"Not TopoText data");
        return nil;
    }
    if (((const uint8_t *)data.bytes)[2] != TTMagic[2]) {
        if (error) *error = TTMakeError(TopoTextErrorFormat, @"Written by a newer TopoText");
        return nil;
    }
    r.p += 3;
    TTPayload *p = [TTPayload new];

    uint64_t n = TTGetVarint(&r);
    if (n > (uint64_t)(r.end - r.p) / 8) r.bad = YES;
    NSMutableArray<NSNumber *> *replicas = [NSMutableArray array];
    for (uint64_t i = 0; i < n && !r.bad; i++) {
        uint64_t v = TTGetU64(&r);
        if (v == 0 || (replicas.count && v <= replicas.lastObject.unsignedLongLongValue)) r.bad = YES;
        [replicas addObject:@(v)];
    }

    n = TTGetVarint(&r);
    if (n > replicas.count) r.bad = YES;
    for (uint64_t i = 0; i < n && !r.bad; i++) {
        TTReplica rep = TTGetReplica(&r, replicas);
        uint64_t clock = TTGetVarint(&r);
        if (!r.bad) p.version[@(rep)] = @(clock);
    }

    n = TTGetVarint(&r);
    if (n > (uint64_t)(r.end - r.p)) r.bad = YES;
    TTRun *prev = nil;
    for (uint64_t i = 0; i < n && !r.bad; i++) {
        TTRun *run = [TTRun new];
        if (!TTGetSpanOf(&r, run, replicas)) { r.bad = YES; break; }
        uint8_t flags = TTGetByte(&r);
        if (flags & ~15) { r.bad = YES; break; }
        run->_deleted = flags & 1;
        if (flags & 4) {
            if (!(flags & 2) || !prev) { r.bad = YES; break; }
            run->_or = prev->_r;
            run->_oc = prev->_c + prev->_len - 1;
        } else if (flags & 2) {
            run->_or = TTGetReplica(&r, replicas);
            run->_oc = TTGetVarint(&r);
            if (run->_oc == 0) r.bad = YES;
        }
        if (!run->_deleted) {
            run->_text = TTGetText(&r);
            if (run->_text.length != run->_len) r.bad = YES;
        }
        run->_attrs = (flags & 8) ? TTGetAttrs(&r, replicas) : @{};
        if (run->_deleted) run->_attrs = @{};
        [p.inserts addObject:run];
        prev = run;
    }

    n = TTGetVarint(&r);
    if (n > (uint64_t)(r.end - r.p)) r.bad = YES;
    for (uint64_t i = 0; i < n && !r.bad; i++) {
        TTRun *run = [TTRun new];
        if (!TTGetSpanOf(&r, run, replicas)) { r.bad = YES; break; }
        uint8_t flags = TTGetByte(&r);
        if (flags & ~9) { r.bad = YES; break; }
        run->_deleted = flags & 1;
        run->_attrs = (flags & 8) ? TTGetAttrs(&r, replicas) : @{};
        [p.updates addObject:run];
    }

    if (r.bad || r.p != r.end) {
        if (error) *error = TTMakeError(TopoTextErrorCorrupt, @"Damaged TopoText data");
        return nil;
    }
    return p;
}

NSData *TTEncodeVersion(NSDictionary<NSNumber *, NSNumber *> *clocks) {
    NSMutableData *d = [NSMutableData dataWithBytes:TTVersionMagic length:3];
    NSArray *keys = [clocks.allKeys sortedArrayUsingSelector:@selector(compare:)];
    TTPutVarint(d, keys.count);
    for (NSNumber *k in keys) {
        TTPutU64(d, k.unsignedLongLongValue);
        TTPutVarint(d, clocks[k].unsignedLongLongValue);
    }
    return d;
}

NSDictionary<NSNumber *, NSNumber *> *TTDecodeVersion(NSData *data, NSError **error) {
    TTReader r = { data.bytes, (const uint8_t *)data.bytes + data.length, NO };
    if (data.length < 3 || memcmp(data.bytes, TTVersionMagic, 3) != 0) r.bad = YES;
    else r.p += 3;
    uint64_t n = r.bad ? 0 : TTGetVarint(&r);
    if (n > (uint64_t)(r.end - r.p) / 9) r.bad = YES;
    NSMutableDictionary *m = [NSMutableDictionary dictionary];
    for (uint64_t i = 0; i < n && !r.bad; i++) {
        uint64_t rep = TTGetU64(&r), clock = TTGetVarint(&r);
        if (rep == 0) r.bad = YES;
        m[@(rep)] = @(clock);
    }
    if (r.bad || r.p != r.end) {
        if (error) *error = TTMakeError(TopoTextErrorCorrupt, @"Not a TopoText version");
        return nil;
    }
    return m;
}
