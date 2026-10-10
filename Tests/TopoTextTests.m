#import <XCTest/XCTest.h>
#import <TopoText/TopoText.h>

/* TTScripted()'s data, as written on macOS (format 2). */
static NSString * const TTGolden =
    @"545402020807060504030201f0ffffffffffffff0200100112080001010801480604626f6c64020f0104666f6e740504426f64790000046c69737407020501610801016b010f01026f6e020000057363616c6504000000000000f83f00000473697a65031800000002012700100003010e03eda0bd0604626f6c64020f0104666f6e740504426f64790000046c69737407020501610801016b010f01026f6e020000057363616c6504000000000000f83f00000473697a65031800000004020e04edb880200404666f6e740504426f64790000026f6e020000057363616c6504000000000000f83f00000473697a6503180000000b031a000603626967010473697a65001202000e010601200006050a000505776f726c640404666f6e740504426f64790000026f6e020000057363616c6504000000000000f83f00000473697a65031800000111010601210000";
/* The same, as format 1 wrote it (RGA; no deleters): still read. */
static NSString * const TTGoldenFormat1 =
    @"545401020807060504030201f0ffffffffffffff02000f0111080001010801480604626f6c64020f0104666f6e740504426f64790000046c69737407020501610801016b010f01026f6e020000057363616c6504000000000000f83f00000473697a6503180000000201070003010e03eda0bd0604626f6c64020f0104666f6e740504426f64790000046c69737407020501610801016b010f01026f6e020000057363616c6504000000000000f83f00000473697a65031800000004020e04edb880200404666f6e740504426f64790000026f6e020000057363616c6504000000000000f83f00000473697a6503180000000b030e03626967010473697a65001102000e010601200006050a000505776f726c640404666f6e740504426f64790000026f6e020000057363616c6504000000000000f83f00000473697a650318000001100106012100";

@interface TopoTextTests : XCTestCase
@end

static TopoText *TTText(TTReplica replica, NSString *string) {
    TopoText *t = [TopoText textWithReplica:replica];
    [t insertString:string atIndex:0 attributes:nil];
    return t;
}

/* b brought up to date with a, and a with b. */
static void TTSync(TopoText *a, TopoText *b) {
    [a mergeText:b];
    [b mergeText:a];
}

@implementation TopoTextTests

#pragma mark editing

- (void)testTypingAndDeleting {
    TopoText *t = [TopoText textWithReplica:1];
    [t insertString:@"Hello" atIndex:0 attributes:nil];
    [t insertString:@" world" atIndex:5 attributes:nil];
    XCTAssertEqualObjects(t.string, @"Hello world");
    [t deleteCharactersInRange:NSMakeRange(0, 6)];
    XCTAssertEqualObjects(t.string, @"world");
    [t replaceCharactersInRange:NSMakeRange(0, 1) withString:@"W" attributes:nil];
    XCTAssertEqualObjects(t.string, @"World");
}

/* The sketch put the new text after the rest of the run it was typed into. */
- (void)testTypingIntoTheMiddleOfARun {
    TopoText *t = TTText(1, @"abc");
    [t insertString:@"X" atIndex:1 attributes:nil];
    XCTAssertEqualObjects(t.string, @"aXbc");
    [t insertString:@"Y" atIndex:2 attributes:nil];
    XCTAssertEqualObjects(t.string, @"aXYbc");
    XCTAssertEqualObjects([TopoText textWithData:t.data replica:2 error:NULL].string, @"aXYbc");
}

- (void)testTypingAtOnePlaceAgainAndAgain {
    TopoText *t = [TopoText textWithReplica:1];
    for (NSString *s in @[ @"c", @"b", @"a" ]) [t insertString:s atIndex:0 attributes:nil];
    XCTAssertEqualObjects(t.string, @"abc");
    TopoText *u = TTText(2, @"[]");
    for (NSString *s in @[ @"1", @"2", @"3" ]) [u insertString:s atIndex:1 attributes:nil];
    XCTAssertEqualObjects(u.string, @"[321]");
}

- (void)testTypingOnIsOneRun {
    TopoText *t = [TopoText textWithReplica:1];
    for (NSUInteger i = 0; i < 5000; i++) [t insertString:@"x" atIndex:i attributes:@{ @"font": @"Body" }];
    XCTAssertLessThan(t.data.length, 5000u + 64u, @"one run: the text and a header");
    XCTAssertEqual(t.clock, 5000u);
}

#pragma mark merging

- (void)testConcurrentTypingAtOnePlaceDoesNotInterleave {
    TopoText *a = TTText(1, @"Hi ");
    TopoText *b = [a copyWithReplica:2];
    [a insertString:@"Alice" atIndex:3 attributes:nil];
    [b insertString:@"Bob" atIndex:3 attributes:nil];
    for (NSString *s in @[ @" here", @"!" ]) [a insertString:s atIndex:a.length attributes:nil];
    [b insertString:@" too" atIndex:b.length attributes:nil];
    TopoText *ab = [a mergedWith:b], *ba = [b mergedWith:a];
    XCTAssertEqualObjects(ab.string, ba.string);
    XCTAssertTrue(([@[ @"Hi Alice here!Bob too", @"Hi Bob tooAlice here!" ] containsObject:ab.string]), @"%@", ab.string);
    XCTAssertEqualObjects(ab.data, ba.data, @"the same state, the same bytes");
}

- (void)testDeleteWhileAnotherInsertsInside {
    TopoText *a = TTText(1, @"the quick brown fox");
    TopoText *b = [a copyWithReplica:2];
    [a deleteCharactersInRange:NSMakeRange(4, 6)]; /* "quick " */
    [b insertString:@"very " atIndex:4 attributes:nil];
    [b insertString:@"ly" atIndex:14 attributes:nil];  /* "quickly" */
    TTSync(a, b);
    XCTAssertEqualObjects(a.string, b.string);
    XCTAssertEqualObjects(a.string, @"the very lybrown fox", @"what b typed survives what a deleted around it");
}

- (void)testBothDeleteTheSame {
    TopoText *a = TTText(1, @"abcdef");
    TopoText *b = [a copyWithReplica:2];
    [a deleteCharactersInRange:NSMakeRange(1, 3)];
    [b deleteCharactersInRange:NSMakeRange(2, 3)];
    TTSync(a, b);
    XCTAssertEqualObjects(a.string, @"af");
    XCTAssertEqualObjects(a.data, b.data);
}

- (void)testMergingIsIdempotent {
    TopoText *a = TTText(1, @"one");
    TopoText *b = [a copyWithReplica:2];
    [b insertString:@" two" atIndex:3 attributes:nil];
    NSData *delta = [b deltaSinceVersion:a.version];
    XCTAssertEqual([a applyData:delta error:NULL].count, 1u);
    XCTAssertEqual([a applyData:delta error:NULL].count, 0u, @"heard twice, done once");
    XCTAssertEqual([a applyData:b.data error:NULL].count, 0u);
    XCTAssertEqualObjects(a.string, @"one two");
}

- (void)testADeltaIsWhatIsMissing {
    TopoText *a = [TopoText textWithReplica:1];
    for (int i = 0; i < 100; i++) [a insertString:@"Lorem ipsum dolor sit amet. " atIndex:0 attributes:nil];
    TopoText *b = [a copyWithReplica:2];
    TTVersion *v = b.version;
    XCTAssertTrue([v includesVersion:a.version]);
    [a insertString:@"New" atIndex:10 attributes:nil];
    XCTAssertFalse([v includesVersion:a.version]);
    NSData *delta = [a deltaSinceVersion:v];
    XCTAssertLessThan(delta.length, 64u, @"only the new run: %lu bytes", (unsigned long)delta.length);
    [b applyData:delta error:NULL];
    XCTAssertEqualObjects(b.string, a.string);
    XCTAssertEqualObjects(b.version, a.version);
}

- (void)testADeltaForAnotherCopyIsRefused {
    TopoText *a = TTText(1, @"base");
    TopoText *b = [a copyWithReplica:2];
    [a insertString:@" one" atIndex:4 attributes:nil];
    TTVersion *afterOne = a.version;
    [a insertString:@" two" atIndex:8 attributes:nil];
    NSError *error = nil;
    XCTAssertNil([b applyData:[a deltaSinceVersion:afterOne] error:&error]);
    XCTAssertEqual(error.code, TopoTextErrorMissingHistory);
    XCTAssertEqualObjects(b.string, @"base", @"nothing changed");
    [b mergeText:a];
    XCTAssertEqualObjects(b.string, @"base one two");
}

- (void)testThroughAThirdCopy {
    TopoText *a = TTText(1, @"x");
    TopoText *b = [a copyWithReplica:2], *c = [a copyWithReplica:3];
    [a insertString:@"a" atIndex:1 attributes:nil];
    [b insertString:@"b" atIndex:0 attributes:nil];
    [c mergeText:a];
    [c mergeText:b];
    [b applyData:[c deltaSinceVersion:b.version] error:NULL];
    XCTAssertEqualObjects(b.string, @"bxa");
    XCTAssertEqualObjects(b.data, c.data);
}

#pragma mark attributes

- (void)testBoldHereItalicThereBothStay {
    TopoText *a = TTText(1, @"hello world");
    TopoText *b = [a copyWithReplica:2];
    [a addAttributes:@{ @"bold": @YES } range:NSMakeRange(0, 5)];
    [b addAttributes:@{ @"italic": @YES } range:NSMakeRange(0, 11)];
    TTSync(a, b);
    XCTAssertEqualObjects([a attributesAtIndex:0 effectiveRange:NULL], (@{ @"bold": @YES, @"italic": @YES }));
    XCTAssertEqualObjects([a attributesAtIndex:6 effectiveRange:NULL], (@{ @"italic": @YES }));
    XCTAssertEqualObjects(a.attributedString, b.attributedString);
}

- (void)testTheLaterWriterOfAKeyStands {
    TopoText *a = TTText(1, @"text");
    TopoText *b = [a copyWithReplica:2];
    [a addAttributes:@{ @"color": @"red" } range:NSMakeRange(0, 4)];
    [b addAttributes:@{ @"color": @"blue" } range:NSMakeRange(0, 4)];
    [b addAttributes:@{ @"color": @"green" } range:NSMakeRange(0, 2)];
    TTSync(a, b);
    XCTAssertEqualObjects(a.attributeRuns, b.attributeRuns);
    /* Same clock for red and blue; replica 2 is the later. */
    XCTAssertEqualObjects([a attributesAtIndex:3 effectiveRange:NULL][@"color"], @"blue");
    XCTAssertEqualObjects([a attributesAtIndex:0 effectiveRange:NULL][@"color"], @"green");
}

- (void)testTheNotesRace {
    TopoText *a = TTText(1, @"hello world");
    TopoText *b = [a copyWithReplica:2];
    [a addAttributes:@{ @"bold": @YES } range:NSMakeRange(0, 11)];
    [b insertString:@"big " atIndex:6 attributes:nil];
    TTSync(a, b);
    XCTAssertEqualObjects(a.string, @"hello big world");
    NSRange r;
    XCTAssertEqualObjects([a attributesAtIndex:6 effectiveRange:&r], @{}, @"typed as plain, it stays plain");
    XCTAssertEqual(r.length, 4u);
    XCTAssertEqualObjects([a attributesAtIndex:10 effectiveRange:NULL], @{ @"bold": @YES });
}

- (void)testRemovingAndSetting {
    TopoText *t = [TopoText textWithReplica:1];
    [t insertString:@"abcdef" atIndex:0 attributes:@{ @"font": @"Body", @"bold": @YES }];
    [t removeAttribute:@"bold" range:NSMakeRange(0, 3)];
    XCTAssertEqualObjects([t attributesAtIndex:0 effectiveRange:NULL], @{ @"font": @"Body" });
    [t setAttributes:@{ @"link": @"https://example.com" } range:NSMakeRange(4, 2)];
    XCTAssertEqualObjects([t attributesAtIndex:5 effectiveRange:NULL], @{ @"link": @"https://example.com" });
    XCTAssertEqualObjects([t attributesAtIndex:3 effectiveRange:NULL], (@{ @"font": @"Body", @"bold": @YES }));
    TopoText *u = [TopoText textWithData:t.data replica:2 error:NULL];
    XCTAssertEqualObjects(u.attributedString, t.attributedString);
}

- (void)testValuesRoundTrip {
    NSDictionary *attrs = @{ @"s": @"ünïcødé 😀", @"i": @(-42), @"big": @(INT64_MAX), @"d": @(0.25), @"yes": @YES, @"no": @NO,
                             @"data": [@"bytes" dataUsingEncoding:NSUTF8StringEncoding], @"date": [NSDate dateWithTimeIntervalSince1970:1.5e9],
                             @"list": @[ @1, @"two", @[ @3 ] ], @"map": @{ @"k": @{ @"nested": @YES } } };
    TopoText *t = [TopoText textWithReplica:1];
    [t insertString:@"v" atIndex:0 attributes:attrs];
    NSDictionary *back = [[TopoText textWithData:t.data replica:2 error:NULL] attributesAtIndex:0 effectiveRange:NULL];
    XCTAssertEqualObjects(back, attrs);
    XCTAssertThrows([t addAttributes:@{ @"bad": [NSObject new] } range:NSMakeRange(0, 1)]);
}

#pragma mark text

- (void)testSurrogatePairsSplitByARemoteInsert {
    TopoText *a = TTText(1, @"a😀b");
    TopoText *b = [a copyWithReplica:2];
    [b insertString:@"|" atIndex:2 attributes:nil]; /* between the halves */
    [a mergeText:b];
    XCTAssertEqual(a.length, 5u);
    TopoText *c = [TopoText textWithData:a.data replica:3 error:NULL];
    XCTAssertEqualObjects(c.string, a.string, @"lone surrogates survive the encoding");
    [a deleteCharactersInRange:NSMakeRange(2, 1)];
    XCTAssertEqualObjects(a.string, @"a😀b");
}

- (void)testSetString {
    TopoText *t = TTText(1, @"The cat sat on the mat");
    [t addAttributes:@{ @"bold": @YES } range:NSMakeRange(4, 3)];
    TTId *mat = [t anchorAtIndex:22];
    [t setString:@"The cats sat on a mat"];
    XCTAssertEqualObjects(t.string, @"The cats sat on a mat");
    XCTAssertEqualObjects([t attributesAtIndex:7 effectiveRange:NULL], @{ @"bold": @YES }, @"typed after bold, bold");
    XCTAssertEqual([t indexForAnchor:mat], 21u, @"what did not change kept its ids");

    NSMutableAttributedString *s = [[NSMutableAttributedString alloc] initWithString:@"The dogs sat"];
    [s addAttribute:@"italic" value:@YES range:NSMakeRange(0, 3)];
    [t setAttributedString:s];
    XCTAssertEqualObjects(t.attributedString, s);
}

- (void)testAnchors {
    TopoText *a = TTText(1, @"hello world");
    TTId *cursor = [a anchorAtIndex:6]; /* after "hello " */
    TopoText *b = [a copyWithReplica:2];
    [b insertString:@">> " atIndex:0 attributes:nil];
    [b deleteCharactersInRange:NSMakeRange(3 + 4, 2)]; /* "o " */
    [a mergeText:b];
    XCTAssertEqualObjects(a.string, @">> hellworld");
    XCTAssertEqual([a indexForAnchor:cursor], 7u, @"deleted under the cursor: where it was");
    XCTAssertEqual([a indexForAnchor:nil], 0u);
    XCTAssertEqual([a indexForAnchor:[TTId idWithReplica:99 clock:1]], (NSUInteger)NSNotFound);
}

- (void)testSeededCopiesShareTheirText {
    TopoText *a = [TopoText textSeededWithString:@"stored before TopoText" replica:1];
    TopoText *b = [TopoText textSeededWithString:@"stored before TopoText" replica:2];
    [a insertString:@"Text " atIndex:0 attributes:nil];
    [b insertString:@"!" atIndex:b.length attributes:nil];
    TTSync(a, b);
    XCTAssertEqualObjects(a.string, @"Text stored before TopoText!");
    XCTAssertEqualObjects(a.data, b.data);
}

#pragma mark data

- (void)testDamagedDataIsAnError {
    TopoText *t = TTText(1, @"some text");
    [t addAttributes:@{ @"bold": @YES, @"list": @[ @1, @2 ] } range:NSMakeRange(2, 3)];
    [t deleteCharactersInRange:NSMakeRange(0, 1)];
    NSData *data = t.data;
    for (NSUInteger n = 0; n < data.length; n++) {
        NSError *error = nil;
        XCTAssertNil([TopoText textWithData:[data subdataWithRange:NSMakeRange(0, n)] replica:2 error:&error], @"cut at %lu", (unsigned long)n);
        XCTAssertNotNil(error);
    }
    uint32_t seed = 7;
    for (int i = 0; i < 2000; i++) {
        NSMutableData *bent = [data mutableCopy];
        seed = seed * 1103515245 + 12345;
        ((uint8_t *)bent.mutableBytes)[3 + (seed >> 8) % (data.length - 3)] ^= 1 << ((seed >> 4) % 8);
        [TopoText textWithData:bent replica:2 error:NULL]; /* no crash, whatever it says */
    }
    NSError *error = nil;
    XCTAssertNil([TopoText textWithData:[@"TT\x09" dataUsingEncoding:NSASCIIStringEncoding] replica:2 error:&error]);
    XCTAssertEqual(error.code, TopoTextErrorFormat);
}

/* The same state is the same bytes on every system: a device's merge and a
   peer's must agree, whichever Foundation each runs. */
static TopoText *TTScripted(void) {
    TopoText *t = [TopoText textWithReplica:0x0102030405060708ull];
    [t insertString:@"Hé😀 world" atIndex:0 attributes:@{ @"font": @"Body", @"size": @12, @"scale": @1.5, @"on": @YES }];
    [t insertString:@"big " atIndex:5 attributes:nil];
    [t addAttributes:@{ @"bold": @YES, @"list": @[ @"a", @{ @"k": @NO } ] } range:NSMakeRange(0, 3)];
    [t deleteCharactersInRange:NSMakeRange(1, 1)];
    TopoText *u = [t copyWithReplica:0xfffffffffffffff0ull];
    [u insertString:@"!" atIndex:u.length attributes:nil];
    [u removeAttribute:@"size" range:NSMakeRange(4, 3)];
    [t mergeText:u];
    return t;
}

static NSString *TTHex(NSData *d) {
    NSMutableString *s = [NSMutableString string];
    for (NSUInteger i = 0; i < d.length; i++) [s appendFormat:@"%02x", ((const uint8_t *)d.bytes)[i]];
    return s;
}

- (void)testFormat1IsStillRead {
    NSMutableData *d = [NSMutableData data];
    for (NSUInteger i = 0; i + 1 < TTGoldenFormat1.length; i += 2) {
        unsigned b;
        sscanf([TTGoldenFormat1 substringWithRange:NSMakeRange(i, 2)].UTF8String, "%x", &b);
        uint8_t byte = (uint8_t)b;
        [d appendBytes:&byte length:1];
    }
    NSError *error = nil;
    TopoText *old = [TopoText textWithData:d replica:0 error:&error];
    XCTAssertNotNil(old, @"%@", error);
    XCTAssertEqualObjects(old.attributedString, TTScripted().attributedString, @"the same text and attributes, in the same order");
    XCTAssertEqual(((const uint8_t *)old.data.bytes)[2], 2, @"written as format 2");
}

- (void)testTheBytesAreTheSameEverywhere {
    NSString *hex = TTHex(TTScripted().data);
    NSString *golden = TTGolden;
    XCTAssertEqualObjects(hex, golden, @"the format changed, or a system writes it differently");
}

- (void)testVersionData {
    TopoText *t = TTText(5, @"abc");
    TTVersion *v = [TTVersion versionWithData:t.version.data error:NULL];
    XCTAssertEqualObjects(v, t.version);
    XCTAssertEqual([v clockForReplica:5], 3u);
    XCTAssertNil([TTVersion versionWithData:[NSData data] error:NULL]);
}

/* What two copies have both seen: each replica's lower clock; one only one
   has seen, neither has. */
- (void)testVersionMeet {
    TopoText *a = TTText(5, @"abc"), *b = [a copyWithReplica:6];
    [b insertString:@"de" atIndex:3 attributes:nil];
    [a insertString:@"x" atIndex:0 attributes:nil];
    TTVersion *both = [a.version versionByMeetingVersion:b.version];
    XCTAssertEqual([both clockForReplica:5], 3u, @"b has seen a's first three");
    XCTAssertEqual([both clockForReplica:6], 0u, @"a has seen none of b's");
    XCTAssertEqualObjects(both, [b.version versionByMeetingVersion:a.version]);
    XCTAssertTrue([a.version includesVersion:both] && [b.version includesVersion:both]);
}

#pragma mark paragraphs

static NSSet *TTListKeys(void) { return [NSSet setWithObjects:@"list", @"checked", nil]; }

- (void)testParagraphRanges {
    TopoText *t = TTText(1, @"one\ntwo\n");
    XCTAssertEqualObjects(t.paragraphRanges, (@[ [NSValue valueWithRange:NSMakeRange(0, 4)], [NSValue valueWithRange:NSMakeRange(4, 4)],
                                                [NSValue valueWithRange:NSMakeRange(8, 0)] ]));
    XCTAssertEqual([t paragraphRangeForIndex:5].location, 4u);
    XCTAssertEqual([t paragraphRangeForIndex:3].length, 4u, @"a newline is its paragraph's");
    XCTAssertEqual([t paragraphRangeForIndex:8].length, 0u, @"the empty last one");
}

- (void)testParagraphAttributesAreOnEveryCharacterAndTheNewlineDecides {
    TopoText *t = TTText(1, @"milk\neggs");
    [t addParagraphAttributes:@{ @"list": @"check" } range:NSMakeRange(1, 0)];
    XCTAssertEqualObjects([t attributesAtIndex:0 effectiveRange:NULL], @{ @"list": @"check" });
    XCTAssertEqualObjects([t attributesAtIndex:4 effectiveRange:NULL], @{ @"list": @"check" }, @"its newline too");
    XCTAssertEqualObjects([t attributesAtIndex:5 effectiveRange:NULL], @{}, @"the next paragraph not");
    XCTAssertEqualObjects([t paragraphAttributesAtIndex:2 keys:TTListKeys()], @{ @"list": @"check" });
    /* The last paragraph: its first character. */
    [t addParagraphAttributes:@{ @"list": @"bullet" } range:NSMakeRange(6, 1)];
    XCTAssertEqualObjects([t paragraphAttributesAtIndex:9 keys:TTListKeys()], @{ @"list": @"bullet" });
    /* Only the keys asked for. */
    [t addAttributes:@{ @"bold": @YES } range:NSMakeRange(0, 5)];
    XCTAssertEqualObjects([t paragraphAttributesAtIndex:0 keys:TTListKeys()], @{ @"list": @"check" });
}

/* Typed into a line as it was made a checklist item elsewhere: in the item. */
- (void)testTextTypedIntoAParagraphChangedElsewhereIsInIt {
    TopoText *a = TTText(1, @"buy milk\nlater");
    TopoText *b = [a copyWithReplica:2];
    [a addParagraphAttributes:@{ @"list": @"check" } range:NSMakeRange(0, 0)];
    [b insertString:@" and eggs" atIndex:8 attributes:nil];
    TTSync(a, b);
    XCTAssertEqualObjects(a.string, @"buy milk and eggs\nlater");
    for (NSUInteger i = 0; i < 17; i++)
        XCTAssertEqualObjects([a paragraphAttributesAtIndex:i keys:TTListKeys()], @{ @"list": @"check" });
    XCTAssertEqualObjects([a attributesAtIndex:10 effectiveRange:NULL], @{}, @"the characters disagree; the paragraph does not");
    XCTAssertEqualObjects(a.data, b.data);
}

/* Checked on one device, unchecked on another: one register, the last
   writer's, the same on both. */
- (void)testCheckedIsOneRegister {
    TopoText *a = TTText(1, @"item\n");
    [a addParagraphAttributes:@{ @"list": @"check" } range:NSMakeRange(0, 0)];
    TopoText *b = [a copyWithReplica:2];
    [a addParagraphAttributes:@{ @"checked": @YES } range:NSMakeRange(0, 0)];
    [b addParagraphAttributes:@{ @"checked": [NSNull null] } range:NSMakeRange(0, 0)];
    TTSync(a, b);
    XCTAssertEqualObjects([a paragraphAttributesAtIndex:0 keys:TTListKeys()], [b paragraphAttributesAtIndex:0 keys:TTListKeys()]);
    XCTAssertEqualObjects([a paragraphAttributesAtIndex:0 keys:TTListKeys()], @{ @"list": @"check" }, @"replica 2 wrote last");
}

/* Two paragraphs joined: the surviving newline's style is the paragraph's. */
- (void)testJoiningParagraphsTakesTheSurvivingNewlines {
    TopoText *t = TTText(1, @"head\nitem\n");
    [t addParagraphAttributes:@{ @"list": @"bullet" } range:NSMakeRange(5, 0)];
    [t deleteCharactersInRange:NSMakeRange(4, 1)];  /* the first newline */
    XCTAssertEqualObjects(t.string, @"headitem\n");
    XCTAssertEqualObjects([t paragraphAttributesAtIndex:0 keys:TTListKeys()], @{ @"list": @"bullet" });
}

@end
