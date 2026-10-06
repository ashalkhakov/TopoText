#import <XCTest/XCTest.h>
#import <TopoText/TopoText.h>

/* Copies edited at random and synced at random, in every way there is to
   sync, until they agree. Each copy has an editor's text beside it, which
   sees only what the user typed there and the edits merges report: it must
   be the copy's text all along. TOPOTEXT_SEEDS=1000 for a long run. */

@interface TopoTextFuzzTests : XCTestCase
@end

typedef struct { uint64_t s; } TTRandom;

static uint32_t TTNext(TTRandom *r) {
    r->s ^= r->s << 13;
    r->s ^= r->s >> 7;
    r->s ^= r->s << 17;
    return (uint32_t)(r->s >> 11);
}

static NSUInteger TTBelow(TTRandom *r, NSUInteger n) { return n ? TTNext(r) % n : 0; }

static NSString *TTRandomString(TTRandom *r) {
    static NSString *pieces[] = { @"a", @"b", @"c", @" ", @"xyz", @"\n", @"😀", @"é", @"́", @"Hello" };
    NSMutableString *s = [NSMutableString string];
    NSUInteger n = 1 + TTBelow(r, 3);
    for (NSUInteger i = 0; i < n; i++) [s appendString:pieces[TTBelow(r, 10)]];
    return s;
}

static NSDictionary *TTRandomAttributes(TTRandom *r) {
    switch (TTBelow(r, 5)) {
    case 0: return @{ @"bold": @YES };
    case 1: return @{ @"italic": @YES, @"size": @(12 + TTBelow(r, 3)) };
    case 2: return @{ @"color": @[ @"red", @"green", @"blue" ][TTBelow(r, 3)] };
    case 3: return @{ @"bold": [NSNull null] };
    default: return @{};
    }
}

static NSRange TTRandomRange(TTRandom *r, NSUInteger length) {
    NSUInteger at = TTBelow(r, length + 1);
    return NSMakeRange(at, TTBelow(r, MIN(length - at, 8) + 1));
}

@implementation TopoTextFuzzTests {
    NSMutableArray<TopoText *> *_texts;
    NSMutableArray<NSMutableAttributedString *> *_editors;
}

- (void)apply:(NSArray<TTEdit *> *)edits to:(NSUInteger)i {
    for (TTEdit *e in edits) [e applyToAttributedString:_editors[i]];
}

- (void)editAt:(NSUInteger)i random:(TTRandom *)r {
    TopoText *t = _texts[i];
    NSMutableAttributedString *e = _editors[i];
    NSUInteger len = t.length;
    switch (TTBelow(r, 7)) {
    case 0: case 1: case 2: {
        NSUInteger at = TTBelow(r, len + 1);
        NSString *s = TTRandomString(r);
        NSDictionary *attrs = TTBelow(r, 2) ? @{} : @{ @"font": @"Body" };
        [t insertString:s atIndex:at attributes:attrs];
        [e replaceCharactersInRange:NSMakeRange(at, 0) withAttributedString:[[NSAttributedString alloc] initWithString:s attributes:attrs]];
        break;
    }
    case 3: case 4: {
        NSRange range = TTRandomRange(r, len);
        [t deleteCharactersInRange:range];
        [e deleteCharactersInRange:range];
        break;
    }
    case 5: {
        NSRange range = TTRandomRange(r, len);
        NSDictionary *attrs = TTRandomAttributes(r);
        [t addAttributes:attrs range:range];
        if (!range.length) break;
        for (NSString *k in attrs) {
            if (attrs[k] == [NSNull null]) [e removeAttribute:k range:range];
            else [e addAttribute:k value:attrs[k] range:range];
        }
        break;
    }
    default: {
        NSRange range = TTRandomRange(r, len);
        NSMutableDictionary *attrs = [TTRandomAttributes(r) mutableCopy];
        [attrs removeObjectForKey:@"bold"];
        [t setAttributes:attrs range:range];
        if (range.length) [e setAttributes:attrs range:range];
        break;
    }
    }
}

/* b takes what a has: by delta, by the whole state, or by merging. */
- (void)syncFrom:(NSUInteger)a to:(NSUInteger)b random:(TTRandom *)r {
    TopoText *from = _texts[a], *to = _texts[b];
    NSArray *edits;
    switch (TTBelow(r, 4)) {
    case 0: edits = [to applyData:[from deltaSinceVersion:to.version] error:NULL]; break;
    case 1: edits = [to applyData:from.data error:NULL]; break;
    case 2: {
        /* By way of the bytes of a version, as a peer would send it. */
        TTVersion *v = [TTVersion versionWithData:to.version.data error:NULL];
        edits = [to applyData:[from deltaSinceVersion:v] error:NULL];
        break;
    }
    default: edits = [to mergeText:from]; break;
    }
    XCTAssertNotNil(edits);
    [self apply:edits to:b];
}

- (void)checkEditor:(NSUInteger)i seed:(uint64_t)seed step:(NSUInteger)step {
    NSAttributedString *mine = _texts[i].attributedString;
    if (![mine isEqualToAttributedString:_editors[i]])
        XCTFail(@"seed %llu step %lu copy %lu: the editor has %@, the text %@", (unsigned long long)seed, (unsigned long)step,
                (unsigned long)i, _editors[i], mine);
}

- (BOOL)runSeed:(uint64_t)seed {
    TTRandom r = { seed * 0x9e3779b97f4a7c15ull + 1 };
    NSUInteger copies = 2 + TTBelow(&r, 3);
    _texts = [NSMutableArray array];
    _editors = [NSMutableArray array];
    for (NSUInteger i = 0; i < copies; i++) {
        [_texts addObject:[TopoText textWithReplica:i + 1]];
        [_editors addObject:[[NSMutableAttributedString alloc] init]];
    }
    NSUInteger steps = 60 + TTBelow(&r, 60);
    for (NSUInteger step = 0; step < steps; step++) {
        NSUInteger i = TTBelow(&r, copies);
        if (TTBelow(&r, 4)) {
            [self editAt:i random:&r];
        } else {
            NSUInteger j = TTBelow(&r, copies);
            if (j != i) [self syncFrom:j to:i random:&r];
        }
        [self checkEditor:i seed:seed step:step];
        /* A copy reloaded from its data, now and then: a new session, a new replica. */
        if (!TTBelow(&r, 25)) {
            TopoText *again = [TopoText textWithData:_texts[i].data replica:100 + step error:NULL];
            XCTAssertEqualObjects(again.data, _texts[i].data, @"seed %llu: reloaded, the same bytes", (unsigned long long)seed);
            _texts[i] = again;
        }
    }
    /* Everyone hears from everyone, in turn, twice. */
    for (int round = 0; round < 2; round++)
        for (NSUInteger i = 0; i < copies; i++)
            for (NSUInteger j = 0; j < copies; j++)
                if (i != j) [self syncFrom:j to:i random:&r];
    NSData *data = _texts[0].data;
    BOOL same = YES;
    for (NSUInteger i = 0; i < copies; i++) {
        [self checkEditor:i seed:seed step:steps];
        if (![_texts[i].data isEqualToData:data] || ![_texts[i].attributedString isEqualToAttributedString:_texts[0].attributedString]) {
            XCTFail(@"seed %llu: copy %lu has %@, copy 0 %@", (unsigned long long)seed, (unsigned long)i, _texts[i], _texts[0]);
            same = NO;
        }
    }
    return same;
}

- (void)testCopiesConverge {
    NSUInteger seeds = (NSUInteger)[[[NSProcessInfo processInfo] environment][@"TOPOTEXT_SEEDS"] integerValue] ?: 200;
    for (uint64_t seed = 1; seed <= seeds; seed++)
        if (![self runSeed:seed]) break;
}

/* Two writers at one place, merged in every order: one order of runs. */
- (void)testMergeOrderDoesNotMatter {
    for (uint64_t seed = 1; seed <= 50; seed++) {
        TTRandom r = { seed };
        TopoText *base = [TopoText textWithReplica:1];
        [base insertString:@"0123456789" atIndex:0 attributes:nil];
        NSMutableArray<TopoText *> *copies = [NSMutableArray array];
        for (TTReplica k = 2; k < 6; k++) {
            TopoText *c = [base copyWithReplica:k];
            for (int n = 0; n < 6; n++) {
                NSUInteger at = TTBelow(&r, c.length + 1);
                if (TTBelow(&r, 3)) [c insertString:TTRandomString(&r) atIndex:at attributes:nil];
                else [c deleteCharactersInRange:TTRandomRange(&r, c.length)];
            }
            [copies addObject:c];
        }
        NSData *first = nil;
        for (int order = 0; order < 6; order++) {
            TopoText *m = [base copyWithReplica:9];
            NSMutableArray *left = [copies mutableCopy];
            while (left.count) {
                NSUInteger k = TTBelow(&r, left.count);
                [m mergeText:left[k]];
                [left removeObjectAtIndex:k];
            }
            if (!first) first = m.data;
            XCTAssertEqualObjects(m.data, first, @"seed %llu order %d", (unsigned long long)seed, order);
        }
    }
}

@end
