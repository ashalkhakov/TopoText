// Fugue's ordering (typing backwards does not interleave), and tombstones
// collected once every copy has seen them deleted.

#import <XCTest/XCTest.h>
#import <TopoText/TopoText.h>

@interface TTCoreTests : XCTestCase
@end

@implementation TTCoreTests

/* Each character typed before the one typed last, as typing backwards
   (or a caret that stays put) does. */
static void TTTypeBackwards(TopoText *t, NSString *s, NSUInteger at) {
    for (NSUInteger i = 0; i < s.length; i++) [t insertString:[s substringWithRange:NSMakeRange(i, 1)] atIndex:at attributes:nil];
}

- (void)testTypingBackwardsApartDoesNotInterleave {
    TopoText *a = [TopoText textWithReplica:1];
    [a insertString:@"[]" atIndex:0 attributes:nil];
    TopoText *b = [a copyWithReplica:2];
    TTTypeBackwards(a, @"abc", 1);
    TTTypeBackwards(b, @"xyz", 1);
    XCTAssertEqualObjects(a.string, @"[cba]");
    [a mergeText:b];
    [b mergeText:a];
    XCTAssertEqualObjects(a.string, b.string);
    XCTAssertTrue([a.string isEqual:@"[cbazyx]"] || [a.string isEqual:@"[zyxcba]"], @"each typing whole: %@", a.string);
}

- (void)testTypingBackwardsAtTheStartDoesNotInterleave {
    TopoText *a = [TopoText textWithReplica:1], *b = [TopoText textWithReplica:2];
    TTTypeBackwards(a, @"abc", 0);
    TTTypeBackwards(b, @"xyz", 0);
    [a mergeText:b];
    [b mergeText:a];
    XCTAssertEqualObjects(a.string, b.string);
    XCTAssertTrue([a.string isEqual:@"cbazyx"] || [a.string isEqual:@"zyxcba"], @"%@", a.string);
}

- (void)testTypingForwardApartDoesNotInterleave {
    TopoText *a = [TopoText textWithReplica:1];
    [a insertString:@"[]" atIndex:0 attributes:nil];
    TopoText *b = [a copyWithReplica:2];
    for (NSString *c in @[ @"a", @"b", @"c" ]) [a insertString:c atIndex:a.length - 1 attributes:nil];
    for (NSString *c in @[ @"x", @"y", @"z" ]) [b insertString:c atIndex:b.length - 1 attributes:nil];
    [a mergeText:b];
    [b mergeText:a];
    XCTAssertEqualObjects(a.string, b.string);
    XCTAssertTrue([a.string isEqual:@"[abcxyz]"] || [a.string isEqual:@"[xyzabc]"], @"%@", a.string);
}

/* Typed in the middle of a backwards typing, apart: still one text. */
- (void)testInsertingBetweenLeftChildrenConverges {
    TopoText *a = [TopoText textWithReplica:1];
    TTTypeBackwards(a, @"abc", 0);   /* "cba" */
    TopoText *b = [a copyWithReplica:2], *c = [a copyWithReplica:3];
    [b insertString:@"1" atIndex:1 attributes:nil];
    [c insertString:@"2" atIndex:2 attributes:nil];
    [a insertString:@"3" atIndex:1 attributes:nil];
    for (TopoText *x in @[ a, b, c ])
        for (TopoText *y in @[ a, b, c ]) [x mergeText:y];
    XCTAssertEqualObjects(a.string, b.string);
    XCTAssertEqualObjects(a.string, c.string);
    XCTAssertEqualObjects(a.data, b.data);
}

#pragma mark tombstones

- (void)testTombstonesSeenEverywhereAreCollected {
    TopoText *a = [TopoText textWithReplica:1];
    [a insertString:@"Hello cruel world" atIndex:0 attributes:nil];
    TopoText *b = [a copyWithReplica:2];
    [a deleteCharactersInRange:NSMakeRange(11, 6)];   /* " world", at the end */
    XCTAssertEqual(a.tombstoneCount, 6u);
    XCTAssertEqual([a collectTombstonesSeenBy:b.version], 0u, @"b has not seen the deletion");
    [b mergeText:a];
    NSUInteger before = a.data.length;
    XCTAssertEqual([a collectTombstonesSeenBy:b.version], 6u, @"now both have");
    XCTAssertEqual(a.tombstoneCount, 0u);
    XCTAssertLessThan(a.data.length, before);
    XCTAssertEqualObjects(a.string, @"Hello cruel");
    /* b, which kept its tombstone, and a merge on as before. */
    [b insertString:@"!" atIndex:b.length attributes:nil];
    [a insertString:@"Oh, " atIndex:0 attributes:nil];
    [a mergeText:b];
    [b mergeText:a];
    XCTAssertEqualObjects(a.string, @"Oh, Hello cruel!");
    XCTAssertEqualObjects(b.string, a.string);
}

/* Deleted in the middle, a character at a time: what follows is placed by
   them, so they stay; but as one record. */
- (void)testTombstonesInTheMiddleBecomeOneRecord {
    TopoText *a = [TopoText textWithReplica:1];
    [a insertString:@"Hello cruel world" atIndex:0 attributes:nil];
    for (int i = 0; i < 6; i++) [a deleteCharactersInRange:NSMakeRange(6, 1)];
    NSUInteger before = a.data.length;
    XCTAssertEqual([a collectTombstonesSeenBy:a.version], 0u);
    XCTAssertEqual(a.tombstoneCount, 6u, @"still there: \"world\" is placed by them");
    XCTAssertLessThan(a.data.length, before, @"six records, one now");
    XCTAssertEqualObjects(a.string, @"Hello world");
}

/* Collected too soon (a copy had not seen it deleted, and had placed text
   by it): nothing lost, the whole state brings it back. */
- (void)testATombstoneCollectedTooSoonComesBack {
    TopoText *a = [TopoText textWithReplica:1];
    [a insertString:@"abc" atIndex:0 attributes:nil];
    TopoText *b = [a copyWithReplica:2];
    [a deleteCharactersInRange:NSMakeRange(2, 1)];   /* c, at the end */
    [b insertString:@"X" atIndex:3 attributes:nil];  /* after c, apart */
    XCTAssertEqual([a collectTombstonesSeenBy:a.version], 1u, @"wrongly: b has not seen it");
    [a mergeText:b];
    [b mergeText:a];
    XCTAssertEqualObjects(a.string, @"abX");
    XCTAssertEqualObjects(b.string, a.string);
}

/* Three copies editing at random, collecting what all have seen now and
   then: still one text. */
- (void)testCollectingAmongRandomEditsConverges {
    for (uint32_t seed = 1; seed <= 300; seed++) {
        srand(seed);
        NSArray<TopoText *> *copies = @[ [TopoText textWithReplica:1], [TopoText textWithReplica:2], [TopoText textWithReplica:3] ];
        for (int i = 0; i < 60; i++) {
            TopoText *t = copies[(NSUInteger)rand() % 3];
            NSUInteger n = t.length;
            int what = rand() % 5;
            if (what < 3 || !n) {
                NSString *ch = [NSString stringWithFormat:@"%c", 'a' + rand() % 26];
                /* Typing backwards, now and then. */
                NSUInteger at = (NSUInteger)rand() % (n + 1);
                [t insertString:ch atIndex:at attributes:nil];
            } else {
                NSUInteger at = (NSUInteger)rand() % n, most = (NSUInteger)(1 + rand() % 3);   /* not in MIN: GNUstep's evaluates twice */
                [t deleteCharactersInRange:NSMakeRange(at, MIN(n - at, most))];
            }
            if (rand() % 5 == 0) {
                TopoText *x = copies[(NSUInteger)rand() % 3], *y = copies[(NSUInteger)rand() % 3];
                [x mergeText:y];
            }
            if (rand() % 15 == 0) {
                /* Everyone synced: what all have seen, collected on one. */
                for (TopoText *x in copies)
                    for (TopoText *y in copies) [x mergeText:y];
                [copies[(NSUInteger)rand() % 3] collectTombstonesSeenBy:copies[0].version];
            }
        }
        for (TopoText *x in copies)
            for (TopoText *y in copies) [x mergeText:y];
        XCTAssertEqualObjects(copies[0].string, copies[1].string, @"seed %u", seed);
        XCTAssertEqualObjects(copies[0].string, copies[2].string, @"seed %u", seed);
    }
}

/* The same, collecting too soon (by what the one copy has seen): still one
   text, and what was deleted stays deleted. */
- (void)testCollectingTooSoonAmongRandomEditsConverges {
    for (uint32_t seed = 1; seed <= 300; seed++) {
        srand(seed);
        NSArray<TopoText *> *copies = @[ [TopoText textWithReplica:1], [TopoText textWithReplica:2], [TopoText textWithReplica:3] ];
        NSMutableSet<NSString *> *deleted = [NSMutableSet set];
        for (int i = 0; i < 60; i++) {
            TopoText *t = copies[(NSUInteger)rand() % 3];
            NSUInteger n = t.length;
            if (rand() % 5 < 3 || !n) {
                /* Each character typed once: deletions can be told apart. */
                [t insertString:[NSString stringWithFormat:@"%C", (unichar)(0x4e00 + i)] atIndex:(NSUInteger)rand() % (n + 1) attributes:nil];
            } else {
                NSUInteger at = (NSUInteger)rand() % n;
                [deleted addObject:[t.string substringWithRange:NSMakeRange(at, 1)]];
                [t deleteCharactersInRange:NSMakeRange(at, 1)];
            }
            if (rand() % 4 == 0) [copies[(NSUInteger)rand() % 3] mergeText:copies[(NSUInteger)rand() % 3]];
            if (rand() % 6 == 0) [t collectTombstonesSeenBy:t.version];
        }
        for (int round = 0; round < 2; round++)
            for (TopoText *x in copies)
                for (TopoText *y in copies) [x mergeText:y];
        XCTAssertEqualObjects(copies[0].string, copies[1].string, @"seed %u", seed);
        XCTAssertEqualObjects(copies[0].string, copies[2].string, @"seed %u", seed);
        for (NSString *gone in deleted) XCTAssertFalse([copies[0].string containsString:gone], @"seed %u: %@ came back", seed, gone);
    }
}

@end
