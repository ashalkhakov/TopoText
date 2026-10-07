// A text view's storage and an editor's TopoText, kept the same: what is
// typed into the storage goes into the text; what a merge brings into the
// text comes into the storage, the selection moved along.

#import <XCTest/XCTest.h>
/* AppKit before Core Data: gnustep-gui's NSPredicateEditorRowTemplate.h
   declares NSAttributeType again when Core Data's came first. */
#import "SNRichText.h"
#import "SNModel.h"
#import "SNNotes.h"

/* The test is the text view: its storage, selection and typing. */
@interface SNTextBindingTests : XCTestCase <SNTextViewing>
@end

@implementation SNTextBindingTests {
    NSURL *_store;
    SNNotes *_notes;
    SNNoteEditor *_editor;
    NSTextStorage *_storage;
    SNTextBinding *_binding;
    NSRange _selection;
    NSDictionary *_typing;
}

- (void)setUp {
#if !TARGET_OS_IPHONE
    [NSApplication sharedApplication]; /* GNUstep: fonts come from the backend */
#endif
    _store = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
                                         [NSString stringWithFormat:@"sn-binding-%@.sqlite", [NSProcessInfo processInfo].globallyUniqueString]]];
    _notes = [[SNNotes alloc] initWithStoreURL:_store modelURL:SNModelURLInBundle([NSBundle bundleForClass:[self class]]) error:NULL];
    SNNote *note = [_notes addNoteInFolder:nil];
    _editor = [_notes editorForNote:note];
    [_editor.text insertString:@"Hello world" atIndex:0 attributes:nil];
    _storage = [[NSTextStorage alloc] init];
    _binding = [[SNTextBinding alloc] initWithTextView:self editor:_editor];
    _typing = [_binding typingAttributesAt:_storage.length];
}

- (NSTextStorage *)textStorage { return _storage; }
- (NSRange)selectedRange { return _selection; }
- (void)setSelectedRange:(NSRange)range { _selection = range; }
- (NSDictionary *)typingAttributes { return _typing ?: @{}; }
- (void)setTypingAttributes:(NSDictionary *)attributes { _typing = attributes; }
- (NSUndoManager *)undoManager { return nil; }

- (void)tearDown {
    [_binding unbind];
    [_editor close];
    for (NSString *suffix in @[ @"", @"-wal", @"-shm" ])
        [[NSFileManager defaultManager] removeItemAtPath:[_store.path stringByAppendingString:suffix] error:NULL];
}

- (void)type:(NSString *)s at:(NSUInteger)i {
    NSDictionary *attrs = [_binding typingAttributesAt:i];
    [_storage replaceCharactersInRange:NSMakeRange(i, 0) withAttributedString:[[NSAttributedString alloc] initWithString:s attributes:attrs]];
}

- (void)testTheStorageStartsAsTheText {
    XCTAssertEqualObjects(_storage.string, @"Hello world");
    XCTAssertNotNil([_storage attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL]);
}

- (void)testTypingGoesIntoTheText {
    [self type:@"," at:5];
    [self type:@"!" at:12];
    [_storage deleteCharactersInRange:NSMakeRange(0, 1)];
    [self type:@"J" at:0];
    XCTAssertEqualObjects(_editor.text.string, @"Jello, world!");
    [_storage replaceCharactersInRange:NSMakeRange(7, 5) withString:@"there"];
    XCTAssertEqualObjects(_editor.text.string, @"Jello, there!");
}

- (void)testFormattingGoesIntoTheText {
    [_binding toggle:SNBoldKey inRange:NSMakeRange(0, 5)];
    XCTAssertEqualObjects([_editor.text attributesAtIndex:0 effectiveRange:NULL], @{ SNBoldKey: @YES });
    XCTAssertEqualObjects([_editor.text attributesAtIndex:6 effectiveRange:NULL], @{});
    XCTAssertTrue([_binding range:NSMakeRange(0, 5) has:SNBoldKey]);
    [_binding toggle:SNBoldKey inRange:NSMakeRange(0, 5)];
    XCTAssertEqualObjects([_editor.text attributesAtIndex:0 effectiveRange:NULL], @{});
    [_binding toggle:SNStrikeKey inRange:NSMakeRange(6, 5)];
    [_binding toggle:SNItalicKey inRange:NSMakeRange(6, 5)];
    XCTAssertEqualObjects([_editor.text attributesAtIndex:8 effectiveRange:NULL], (@{ SNStrikeKey: @YES, SNItalicKey: @YES }));
    [_binding setStyle:SNStyleTitle forParagraphsInRange:NSMakeRange(2, 0)];
    XCTAssertEqualObjects([_editor.text attributesAtIndex:0 effectiveRange:NULL], @{ SNStyleKey: SNStyleTitle });
    /* Typing on in bold text is bold. */
    [_binding toggle:SNBoldKey inRange:NSMakeRange(0, 11)];
    [self type:@"!" at:11];
    XCTAssertEqualObjects([_editor.text attributesAtIndex:11 effectiveRange:NULL][SNStyleKey], SNStyleTitle);
}

- (void)testMergedEditsComeIntoTheStorage {
    _selection = NSMakeRange(6, 5); /* "world" */
    TopoText *elsewhere = [_editor.text copyWithReplica:0];
    [elsewhere insertString:@">> " atIndex:0 attributes:nil];
    [elsewhere addAttributes:@{ SNUnderlineKey: @YES } range:NSMakeRange(3, 5)];
    [elsewhere deleteCharactersInRange:NSMakeRange(8, 1)];  /* the space */
    NSArray *edits = [_editor.text mergeText:elsewhere];
    [_binding applyEdits:edits];
    XCTAssertEqualObjects(_storage.string, @">> Helloworld");
    XCTAssertEqualObjects(_editor.text.string, _storage.string);
    XCTAssertEqual([[_storage attribute:NSUnderlineStyleAttributeName atIndex:3 effectiveRange:NULL] integerValue], NSUnderlineStyleSingle);
    XCTAssertEqual(_selection.location, 8u, @"the selection moved along: %@", NSStringFromRange(_selection));
    XCTAssertEqual(_selection.length, 5u);
    /* And typing goes on as before. */
    [self type:@" " at:8];
    XCTAssertEqualObjects(_editor.text.string, @">> Hello world");
}

#pragma mark lists

/* What a text view does with a key typed at the insertion point: the
   binding asked first, then the text replaced with the typing attributes,
   then told. A backspace is "" over the character before. */
- (void)key:(NSString *)s {
    NSRange r = s.length ? NSMakeRange(_selection.location, 0) : NSMakeRange(_selection.location - 1, 1);
    if (![_binding shouldChangeTextInRange:r replacementString:s]) return;
    [_storage replaceCharactersInRange:r withAttributedString:[[NSAttributedString alloc] initWithString:s attributes:_typing]];
    _selection = NSMakeRange(r.location + s.length, 0);
    [_binding selectionDidChange];
    [_binding textDidChange];
}

- (void)start:(NSString *)s {
    _selection = NSMakeRange(0, 0);
    [_storage replaceCharactersInRange:NSMakeRange(0, _storage.length) withString:@""];
    [_binding textDidChange];
    for (NSUInteger i = 0; i < s.length; i++) [self key:[s substringWithRange:NSMakeRange(i, 1)]];
}

- (NSDictionary *)paragraphAt:(NSUInteger)i {
    return [_editor.text paragraphAttributesAtIndex:i keys:SNParagraphKeys()];
}

- (void)testAListIsOnWholeParagraphs {
    [self start:@"Milk\nEggs\nBread"];
    [_binding toggleList:SNListCheck forParagraphsInRange:NSMakeRange(2, 5)];
    XCTAssertEqualObjects([self paragraphAt:0], @{ SNListKey: SNListCheck });
    XCTAssertEqualObjects([self paragraphAt:5], @{ SNListKey: SNListCheck });
    XCTAssertEqualObjects([self paragraphAt:10], @{});
    XCTAssertEqualObjects([_editor.text attributesAtIndex:9 effectiveRange:NULL][SNListKey], SNListCheck, @"the newline too");
    XCTAssertEqualObjects([_storage attribute:SNListAttributeName atIndex:7 effectiveRange:NULL], SNListCheck);
    XCTAssertGreaterThan([[_storage attribute:NSParagraphStyleAttributeName atIndex:7 effectiveRange:NULL] headIndent], 0);
    /* A style and a list do not go together. */
    [_binding setStyle:SNStyleHeading forParagraphsInRange:NSMakeRange(0, 0)];
    XCTAssertEqualObjects([self paragraphAt:0], @{ SNStyleKey: SNStyleHeading });
    /* Toggled off where they all are one already. */
    [_binding toggleList:SNListCheck forParagraphsInRange:NSMakeRange(5, 0)];
    XCTAssertEqualObjects([self paragraphAt:5], @{});
    [_binding toggleCheckedForParagraphsInRange:NSMakeRange(5, 0)];
    XCTAssertEqualObjects([self paragraphAt:5], @{}, @"only a checklist item is ticked");
}

- (void)testReturnBeginsAnItemUnticked {
    [self start:@"Milk"];
    [_binding toggleList:SNListCheck forParagraphsInRange:NSMakeRange(0, 0)];
    [_binding toggleCheckedForParagraphsInRange:NSMakeRange(0, 0)];
    XCTAssertEqualObjects([self paragraphAt:0], (@{ SNListKey: SNListCheck, SNCheckedKey: @YES }));
    [self key:@"\n"];
    XCTAssertEqualObjects(_typing[SNListAttributeName], SNListCheck, @"the list goes on");
    XCTAssertNil(_typing[SNCheckedAttributeName], @"not ticked");
    for (NSString *c in @[ @"E", @"g", @"g", @"s" ]) [self key:c];
    XCTAssertEqualObjects(_editor.text.string, @"Milk\nEggs");
    XCTAssertEqualObjects([self paragraphAt:0], (@{ SNListKey: SNListCheck, SNCheckedKey: @YES }));
    XCTAssertEqualObjects([self paragraphAt:5], @{ SNListKey: SNListCheck });
    /* In the middle, too: Return after Milk. */
    _selection = NSMakeRange(4, 0);
    [self key:@"\n"];
    XCTAssertEqualObjects(_editor.text.string, @"Milk\n\nEggs");
    XCTAssertEqualObjects([self paragraphAt:5], @{ SNListKey: SNListCheck });
    XCTAssertEqualObjects([self paragraphAt:0], (@{ SNListKey: SNListCheck, SNCheckedKey: @YES }));
}

- (void)testReturnOnAnEmptyItemEndsTheList {
    [self start:@"One"];
    [_binding toggleList:SNListBullet forParagraphsInRange:NSMakeRange(0, 0)];
    [self key:@"\n"];
    [self key:@"\n"]; /* on the empty item */
    XCTAssertEqualObjects(_editor.text.string, @"One\n", @"no new line, the list ended");
    XCTAssertNil(_typing[SNListAttributeName]);
    [self key:@"x"];
    XCTAssertEqualObjects([self paragraphAt:4], @{});
    XCTAssertEqualObjects([self paragraphAt:0], @{ SNListKey: SNListBullet });
    /* An empty item between others: made body. */
    [self start:@"A\n\nB"];
    [_binding toggleList:SNListDash forParagraphsInRange:NSMakeRange(0, 4)];
    _selection = NSMakeRange(2, 0);
    [self key:@"\n"];
    XCTAssertEqualObjects(_editor.text.string, @"A\n\nB");
    XCTAssertEqualObjects([self paragraphAt:2], @{});
    XCTAssertEqualObjects([self paragraphAt:3], @{ SNListKey: SNListDash });
    /* Indented, it is outdented first. */
    _selection = NSMakeRange(3, 0);
    [self key:@"\t"];
    XCTAssertEqualObjects([self paragraphAt:3], (@{ SNListKey: SNListDash, SNIndentKey: @1 }), @"Tab indents an item");
    XCTAssertEqualObjects(_editor.text.string, @"A\n\nB");
}

- (void)testDeleteAtAnItemsStartTakesItsMarkerOff {
    [self start:@"Milk\nEggs"];
    [_binding toggleList:SNListNumber forParagraphsInRange:NSMakeRange(0, 9)];
    _selection = NSMakeRange(5, 0);
    [self key:@""];
    XCTAssertEqualObjects(_editor.text.string, @"Milk\nEggs");
    XCTAssertEqualObjects([self paragraphAt:5], @{});
    [self key:@""];
    XCTAssertEqualObjects(_editor.text.string, @"MilkEggs", @"then the lines are joined");
    XCTAssertEqualObjects([self paragraphAt:0], @{ SNListKey: SNListNumber }, @"the upper line's stands");
    XCTAssertEqualObjects([_editor.text attributesAtIndex:6 effectiveRange:NULL][SNListKey], SNListNumber);
}

- (void)testAfterATitleComesBody {
    [self start:@"Groceries"];
    [_binding setStyle:SNStyleTitle forParagraphsInRange:NSMakeRange(0, 0)];
    [self key:@"\n"];
    [self key:@"M"];
    XCTAssertEqualObjects([self paragraphAt:0], @{ SNStyleKey: SNStyleTitle });
    XCTAssertEqualObjects([self paragraphAt:10], @{});
    /* Split in its middle, both halves stay titles. */
    _selection = NSMakeRange(4, 0);
    [self key:@"\n"];
    XCTAssertEqualObjects([self paragraphAt:5], @{ SNStyleKey: SNStyleTitle });
}

- (void)testAParagraphChangedElsewhereIsShownWhole {
    [self start:@"Milk\nEggs"];
    TopoText *elsewhere = [_editor.text copyWithReplica:0];
    [elsewhere addParagraphAttributes:@{ SNListKey: SNListCheck } range:NSMakeRange(0, 0)];
    /* Meanwhile, typed here into the line. */
    _selection = NSMakeRange(2, 0);
    [self key:@"l"];
    [_binding applyEdits:[_editor.text mergeText:elsewhere]];
    XCTAssertEqualObjects(_storage.string, @"Millk\nEggs");
    for (NSUInteger i = 0; i < 6; i++)
        XCTAssertEqualObjects([_storage attribute:SNListAttributeName atIndex:i effectiveRange:NULL], SNListCheck, @"at %lu", (unsigned long)i);
    XCTAssertNil([_storage attribute:SNListAttributeName atIndex:6 effectiveRange:NULL]);
}

#pragma mark tags

- (void)testTagsAreShownInTheirColourOnly {
    [self start:@"buy #milk"];
    id plain = [_storage attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL];
    id tag = [_storage attribute:NSForegroundColorAttributeName atIndex:6 effectiveRange:NULL];
    XCTAssertNotNil(tag);
    XCTAssertNotEqualObjects(tag, plain, @"a tag stands out");
    XCTAssertEqualObjects([_editor.text attributesAtIndex:6 effectiveRange:NULL], @{}, @"the view's, not the text's");
    /* No longer a tag, no longer shown so. */
    _selection = NSMakeRange(5, 0);
    [self key:@""];
    XCTAssertEqualObjects(_storage.string, @"buy milk");
    XCTAssertEqualObjects([_storage attribute:NSForegroundColorAttributeName atIndex:5 effectiveRange:NULL], plain);
}

@end
