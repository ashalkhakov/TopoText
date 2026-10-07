// Undo of a copy's own edits, after others' were merged in: what was meant
// is undone, and nothing of the others'.

#import <XCTest/XCTest.h>
#import <TopoText/TopoText.h>

@interface TTUndoTests : XCTestCase
@end

@implementation TTUndoTests

/* The edits an undo says it did, done to the text as it was shown, give
   the text as it is now. */
- (NSArray<TTEdit *> *)undo:(TTUndoStep *)step in:(TopoText *)text redo:(TTUndoStep **)redo {
    NSMutableAttributedString *shown = [text.attributedString mutableCopy];
    NSArray<TTEdit *> *edits = [text undoStep:step redoStep:redo];
    for (TTEdit *e in edits) [e applyToAttributedString:shown];
    XCTAssertEqualObjects(shown, text.attributedString, @"the edits a view is told of");
    return edits;
}

- (void)testTypingUndoneAndRedone {
    TopoText *t = [TopoText textWithReplica:1];
    [t insertString:@"Hello" atIndex:0 attributes:nil];
    [t beginUndoStep];
    [t insertString:@" wor" atIndex:5 attributes:nil];
    [t insertString:@"ld" atIndex:9 attributes:nil];
    TTUndoStep *typing = [t endUndoStep];
    XCTAssertFalse(typing.isEmpty);
    TTUndoStep *redo = nil;
    [self undo:typing in:t redo:&redo];
    XCTAssertEqualObjects(t.string, @"Hello");
    [self undo:redo in:t redo:NULL];
    XCTAssertEqualObjects(t.string, @"Hello world", @"redone");
    XCTAssertTrue([[t endUndoStep] isEmpty], @"nothing left recording");
}

- (void)testTypedTextIsTakenOutWhereverItIsNow {
    TopoText *a = [TopoText textWithReplica:1];
    [a insertString:@"abc" atIndex:0 attributes:nil];
    TopoText *b = [a copyWithReplica:2];
    [a beginUndoStep];
    [a insertString:@"XY" atIndex:1 attributes:nil];
    TTUndoStep *step = [a endUndoStep];
    /* Elsewhere, meanwhile: text before it, and text typed in it. */
    [b insertString:@">> " atIndex:0 attributes:nil];
    [b mergeText:a];
    [b insertString:@"!" atIndex:5 attributes:nil];   /* between X and Y */
    [a mergeText:b];
    XCTAssertEqualObjects(a.string, @">> aX!Ybc");
    [self undo:step in:a redo:NULL];
    XCTAssertEqualObjects(a.string, @">> a!bc", @"XY out; the others' stays");
    [b mergeText:a];
    XCTAssertEqualObjects(b.string, a.string, @"an edit like any, merged");
}

- (void)testDeletedTextComesBackWhereItWas {
    TopoText *a = [TopoText textWithReplica:1];
    [a insertString:@"hello world" atIndex:0 attributes:nil];
    [a addAttributes:@{ @"bold": @YES } range:NSMakeRange(6, 5)];
    TopoText *b = [a copyWithReplica:2];
    [a beginUndoStep];
    [a deleteCharactersInRange:NSMakeRange(5, 6)];   /* " world" */
    TTUndoStep *step = [a endUndoStep];
    [b insertString:@"Oh, " atIndex:0 attributes:nil];
    [b insertString:@"!" atIndex:b.length attributes:nil];
    [a mergeText:b];
    XCTAssertEqualObjects(a.string, @"Oh, hello!");
    TTUndoStep *redo = nil;
    [self undo:step in:a redo:&redo];
    XCTAssertEqualObjects(a.string, @"Oh, hello world!");
    XCTAssertEqualObjects([a attributesAtIndex:11 effectiveRange:NULL][@"bold"], @YES, @"with its attributes");
    [self undo:redo in:a redo:NULL];
    XCTAssertEqualObjects(a.string, @"Oh, hello!", @"redone: deleted again");
}

- (void)testFormattingSetBackOnlyForItsKeys {
    TopoText *a = [TopoText textWithReplica:1];
    [a insertString:@"note" atIndex:0 attributes:nil];
    TopoText *b = [a copyWithReplica:2];
    [a beginUndoStep];
    [a addAttributes:@{ @"bold": @YES } range:NSMakeRange(0, 4)];
    TTUndoStep *bold = [a endUndoStep];
    [b addAttributes:@{ @"italic": @YES } range:NSMakeRange(0, 4)];
    [b insertString:@"s" atIndex:4 attributes:nil];
    [a mergeText:b];
    [self undo:bold in:a redo:NULL];
    NSDictionary *at = [a attributesAtIndex:0 effectiveRange:NULL];
    XCTAssertNil(at[@"bold"], @"its bold undone");
    XCTAssertEqualObjects(at[@"italic"], @YES, @"the other's italic stays");
    XCTAssertEqualObjects(a.string, @"notes");
}

- (void)testAReplacementUndoneWhole {
    TopoText *a = [TopoText textWithReplica:1];
    [a insertString:@"cat" atIndex:0 attributes:nil];
    [a beginUndoStep];
    [a replaceCharactersInRange:NSMakeRange(0, 3) withString:@"dog" attributes:nil];
    TTUndoStep *step = [a endUndoStep];
    [self undo:step in:a redo:NULL];
    XCTAssertEqualObjects(a.string, @"cat");
}

/* Two copies editing at random, one undoing its own steps now and then:
   they still converge. */
- (void)testUndoingAmongOthersEditsConverges {
    for (uint32_t seed = 1; seed <= 200; seed++) {
        srand(seed);
        TopoText *a = [TopoText textWithReplica:1], *b = [TopoText textWithReplica:2];
        NSMutableArray<TTUndoStep *> *steps = [NSMutableArray array];
        for (int i = 0; i < 40; i++) {
            TopoText *t = rand() % 2 ? a : b;
            int what = rand() % 6;
            if (t == a && what == 5 && steps.count) {
                TTUndoStep *s = steps.lastObject;
                [steps removeLastObject];
                [self undo:s in:a redo:NULL];
                continue;
            }
            if (t == a) [a beginUndoStep];
            NSUInteger n = t.length;
            if (what < 3 || !n) [t insertString:[NSString stringWithFormat:@"%c", 'a' + rand() % 26] atIndex:(NSUInteger)rand() % (n + 1) attributes:nil];
            else if (what == 3) [t deleteCharactersInRange:NSMakeRange((NSUInteger)rand() % n, 1)];
            else [t addAttributes:@{ @"bold": @(rand() % 2) } range:NSMakeRange((NSUInteger)rand() % n, 1)];
            if (t == a) [steps addObject:[a endUndoStep]];
            if (rand() % 4 == 0) {
                [a mergeText:b];
                [b mergeText:a];
            }
        }
        [a mergeText:b];
        [b mergeText:a];
        XCTAssertEqualObjects(a.attributedString, b.attributedString, @"seed %u", seed);
        XCTAssertEqualObjects(a.data, b.data, @"seed %u", seed);
    }
}

@end
