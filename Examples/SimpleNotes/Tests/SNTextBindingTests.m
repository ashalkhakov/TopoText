// A text view's storage and an editor's TopoText, kept the same: what is
// typed into the storage goes into the text; what a merge brings into the
// text comes into the storage, the selection moved along.

#import <XCTest/XCTest.h>
/* AppKit before Core Data: gnustep-gui's NSPredicateEditorRowTemplate.h
   declares NSAttributeType again when Core Data's came first. */
#import "SNRichText.h"
#import "SNModel.h"
#import "SNNotes.h"
#import "SNTableGrid.h"

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

#pragma mark links

- (void)testALinkGivenIsTheTextsAndOneTypedIsTheViews {
    [self start:@"see notes and www.example.com"];
    [_binding setLink:@"https://apple.com/notes" inRange:NSMakeRange(4, 5)];
    XCTAssertEqualObjects([_editor.text attributesAtIndex:5 effectiveRange:NULL][SNLinkKey], @"https://apple.com/notes");
    XCTAssertEqualObjects([_storage attribute:NSLinkAttributeName atIndex:5 effectiveRange:NULL], [NSURL URLWithString:@"https://apple.com/notes"]);
    XCTAssertEqualObjects([_binding linkAt:5], @"https://apple.com/notes");
    /* The address typed: a link in the view only. */
    XCTAssertEqualObjects([_storage attribute:NSLinkAttributeName atIndex:20 effectiveRange:NULL], [NSURL URLWithString:@"https://www.example.com"]);
    XCTAssertNil([_editor.text attributesAtIndex:20 effectiveRange:NULL][SNLinkKey]);
    /* Typing on after a link is not in it. */
    _selection = NSMakeRange(9, 0);
    [_binding selectionDidChange];
    [self key:@"!"];
    XCTAssertNil([_editor.text attributesAtIndex:9 effectiveRange:NULL][SNLinkKey]);
    [_binding setLink:nil inRange:NSMakeRange(4, 5)];
    XCTAssertNil([_storage attribute:NSLinkAttributeName atIndex:5 effectiveRange:NULL]);
}

- (void)testLinksFoundInText {
    NSString *t = @"go to https://example.com/a?b=1, or (www.x.org). not:www.y.org";
    NSMutableArray *found = [NSMutableArray array];
    for (NSValue *v in SNLinkRangesInText(t)) [found addObject:[t substringWithRange:v.rangeValue]];
    XCTAssertEqualObjects(found, (@[ @"https://example.com/a?b=1", @"www.x.org" ]));
    NSURL *link = SNLinkToNote(@"ABC-123");
    XCTAssertEqualObjects(SNNoteIDInLink(link), @"ABC-123");
    XCTAssertNil(SNNoteIDInLink([NSURL URLWithString:@"https://example.com"]));
    XCTAssertEqualObjects(SNURLOfLink(@" example.com "), [NSURL URLWithString:@"https://example.com"]);
}

#pragma mark checked to the bottom

- (NSString *)checksOf:(NSString *)string {
    NSMutableString *marks = [NSMutableString string];
    for (NSValue *v in _editor.text.paragraphRanges) {
        NSDictionary *p = [self paragraphAt:v.rangeValue.location];
        [marks appendString:![p[SNListKey] isEqual:SNListCheck] ? @"-" : [p[SNCheckedKey] boolValue] ? @"x" : @"o"];
    }
    return marks;
}

- (void)testCheckedItemsMoveToTheBottom {
    [self start:@"Milk\nEggs\nBread"];
    [_binding toggleList:SNListCheck forParagraphsInRange:NSMakeRange(0, 14)];
    [_binding toggleCheckedForParagraphsInRange:NSMakeRange(0, 0)];
    XCTAssertEqualObjects([self checksOf:nil], @"xoo");
    XCTAssertTrue([_binding moveCheckedToBottomOfChecklistAt:6]);
    XCTAssertEqualObjects(_editor.text.string, @"Eggs\nBread\nMilk");
    XCTAssertEqualObjects(_storage.string, _editor.text.string);
    XCTAssertEqualObjects([self checksOf:nil], @"oox", @"Milk still ticked, at the bottom");
    XCTAssertFalse([_binding moveCheckedToBottomOfChecklistAt:0], @"nothing out of place");
}

- (void)testOnlyTheChecklistMoves {
    [self start:@"Title\nA\nB\nC\nafter"];
    [_binding toggleList:SNListCheck forParagraphsInRange:NSMakeRange(6, 5)];
    [_binding toggleCheckedForParagraphsInRange:NSMakeRange(6, 0)];
    [_binding toggleCheckedForParagraphsInRange:NSMakeRange(10, 0)];
    XCTAssertEqualObjects([self checksOf:nil], @"-xox-");
    XCTAssertTrue([_binding moveCheckedToBottomOfChecklistAt:8]);
    XCTAssertEqualObjects(_editor.text.string, @"Title\nB\nA\nC\nafter");
    XCTAssertEqualObjects([self checksOf:nil], @"-oxx-");
}

#pragma mark attachments

/* A small image, as a PNG. */
- (NSData *)png {
#if TARGET_OS_IPHONE
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(8, 6)];
    return UIImagePNGRepresentation([r imageWithActions:^(UIGraphicsImageRendererContext *c) { [[UIColor redColor] setFill]; UIRectFill(CGRectMake(0, 0, 8, 6)); }]);
#else
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:8 pixelsHigh:6 bitsPerSample:8 samplesPerPixel:4
                                                                      hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
#ifdef GNUSTEP
    return [rep representationUsingType:NSPNGFileType properties:@{}];
#else
    return [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
#endif
#endif
}

- (void)testAnImageInsertedIsAnAttachmentOfTheNote {
    XCTAssertTrue([_binding insertImageData:[self png] inRange:NSMakeRange(5, 0)]);
    XCTAssertEqualObjects(_editor.text.string, @"Hello\uFFFC world");
    NSString *attachmentID = [_editor.text attributesAtIndex:5 effectiveRange:NULL][SNAttachmentKey];
    XCTAssertNotNil(attachmentID);
    SNAttachment *a = [_editor attachmentWithID:attachmentID];
    XCTAssertEqualObjects(a.type, @"image/png");
    XCTAssertEqual(a.width.doubleValue, 8.0);
    XCTAssertNotNil([_storage attribute:NSAttachmentAttributeName atIndex:5 effectiveRange:NULL], @"shown");
    XCTAssertFalse([_binding insertImageData:[@"not an image" dataUsingEncoding:NSUTF8StringEncoding] inRange:NSMakeRange(0, 0)]);
}

/* A large image is kept smaller, and still an image: drawn, not blank
   (gnustep-back draws into a bitmap only when flushed). */
- (void)testALargeImageIsScaledDown {
#if !TARGET_OS_IPHONE
    NSBitmapImageRep *big = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:3200 pixelsHigh:100 bitsPerSample:8 samplesPerPixel:4
                                                                      hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    memset(big.bitmapData, 0xFF, (size_t)(big.bytesPerRow * 100));   /* white, opaque */
#ifdef GNUSTEP
    NSData *png = [big representationUsingType:NSPNGFileType properties:@{}];
#else
    NSData *png = [big representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
#endif
    NSString *type = nil;
    double w = 0, h = 0;
    NSData *kept = SNImageDataForAttachment(png, &type, &w, &h);
    XCTAssertEqual(w, 1600.0);
    XCTAssertEqual(h, 50.0);
    NSColor *pixel = [[NSBitmapImageRep imageRepWithData:kept] colorAtX:800 y:25];
    XCTAssertGreaterThan(pixel.alphaComponent, 0.9, @"drawn, not blank: %@", pixel);
#endif
}

- (void)testAnImagePastedIsMadeOneOfTheNotes {
    NSTextAttachment *pasted = [[NSTextAttachment alloc] init];
#if TARGET_OS_IPHONE
    pasted.image = [UIImage imageWithData:[self png]];
#else
    pasted.fileWrapper = [[NSFileWrapper alloc] initRegularFileWithContents:[self png]];
#endif
    unichar c = 0xFFFC;
    [_storage replaceCharactersInRange:NSMakeRange(0, 0) withAttributedString:
        [[NSAttributedString alloc] initWithString:[NSString stringWithCharacters:&c length:1] attributes:@{ NSAttachmentAttributeName: pasted }]];
    [_binding textDidChange];
    NSString *attachmentID = [_editor.text attributesAtIndex:0 effectiveRange:NULL][SNAttachmentKey];
    XCTAssertNotNil([_editor attachmentWithID:attachmentID], @"saved: %@", attachmentID);
    XCTAssertEqualObjects([_storage attribute:SNAttachmentAttributeName atIndex:0 effectiveRange:NULL], attachmentID, @"and its view knows it");
}

/* A note with an image opened, and an image merged in from elsewhere: the
   view keeps its character (gnustep-gui takes a U+FFFC with no attachment
   out of a text storage). */
- (void)testAnImageOpenedOrMergedIsKept {
    XCTAssertTrue([_binding insertImageData:[self png] inRange:NSMakeRange(11, 0)]);
    NSString *first = [_editor.text attributesAtIndex:11 effectiveRange:NULL][SNAttachmentKey];
    [_binding unbind];
    NSTextStorage *again = [[NSTextStorage alloc] init];
    _storage = again;
    _binding = [[SNTextBinding alloc] initWithTextView:self editor:_editor];
    XCTAssertEqualObjects(_storage.string, _editor.text.string, @"opened again, the image's character is there");
    XCTAssertNotNil([_storage attribute:NSAttachmentAttributeName atIndex:11 effectiveRange:NULL]);
    TopoText *elsewhere = [_editor.text copyWithReplica:0];
    [elsewhere insertString:@"\uFFFC" atIndex:0 attributes:@{ SNAttachmentKey: first }];
    [_binding applyEdits:[_editor.text mergeText:elsewhere]];
    XCTAssertEqualObjects(_storage.string, _editor.text.string, @"merged in, too");
    XCTAssertNotNil([_storage attribute:NSAttachmentAttributeName atIndex:0 effectiveRange:NULL]);
}

/* A table's character keeps its grid's room: empty, as large as said. */
- (void)testATableKeepsItsGridsRoom {
    NSString *tableID = [_binding insertTableWithRows:2 columns:3 inRange:NSMakeRange(11, 0)];
    XCTAssertNotNil(tableID);
    SNTableGrid *grid = [[SNTableGrid alloc] initWithNotes:_notes attachmentID:tableID];
    XCTAssertEqual(grid.table.columnCount, 3u);
    SNSize size = [grid layoutForWidth:300];
    XCTAssertEqualWithAccuracy(size.width, 300, 3, @"its columns sharing the width");
    [_binding setRoomSize:size forAttachmentID:tableID];
    NSTextAttachment *shown = [_storage attribute:NSAttachmentAttributeName atIndex:11 effectiveRange:NULL];
    SNSize room = [[shown valueForKey:@"room"] sizeValue];
    XCTAssertEqual(room.width, size.width);
    XCTAssertEqual(room.height, size.height);
    [_binding refreshAttachments];
    XCTAssertEqual([_storage attribute:NSAttachmentAttributeName atIndex:11 effectiveRange:NULL], shown, @"kept, not made again");
}

/* Typed into here while another device typed into the same table: what
   was stored meanwhile merged in, both kept, saved together. */
- (void)testATableTypedIntoHereAndElsewhereMerges {
    NSString *tableID = [_binding insertTableWithRows:2 columns:2 inRange:NSMakeRange(0, 0)];
    SNTableGrid *grid = [[SNTableGrid alloc] initWithNotes:_notes attachmentID:tableID];
    [grid layoutForWidth:300];
    [grid setString:@"Bike" atRow:0 column:0];
    SNAttachment *a = [_notes attachmentWithID:tableID];
    TTTable *elsewhere = [_notes tableOfAttachment:a];
    [[elsewhere textAtRow:1 column:1] setString:@"Sunday"];
    [[elsewhere textAtRow:1 column:1] addAttributes:@{ SNBoldKey: @YES } range:NSMakeRange(0, 3)];
    [elsewhere insertRowAtIndex:2];
    [[elsewhere textAtRow:2 column:0] setString:@"Grandma"];
    [_notes saveTable:elsewhere toAttachment:a];
    [grid reloadFromStore];
    NSArray *both = @[ @[ @"Bike", @"" ], @[ @"", @"Sunday" ], @[ @"Grandma", @"" ] ];
    XCTAssertEqualObjects(grid.table.strings, both);
    XCTAssertEqualObjects([grid textViewAtRow:2 column:0].string, @"Grandma", @"a row come is shown");
    NSFont *font = [[grid textViewAtRow:1 column:1].textStorage attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
    XCTAssertTrue([[NSFontManager sharedFontManager] traitsOfFont:font] & NSBoldFontMask, @"bold come, shown bold");
    [grid save];
    XCTAssertEqualObjects([_notes tableOfAttachment:a].strings, both);
}

/* Typed into elsewhere, the same cell: what came done to the cell's view
   as edits, the selection moved along with the text it was in. */
- (void)testACellTypedIntoElsewhereKeepsTheSelection {
    NSString *tableID = [_binding insertTableWithRows:1 columns:1 inRange:NSMakeRange(0, 0)];
    SNTableGrid *grid = [[SNTableGrid alloc] initWithNotes:_notes attachmentID:tableID];
    [grid layoutForWidth:300];
    [grid setString:@"tea" atRow:0 column:0];
    [grid save];
    NSTextView *cell = (NSTextView *)[grid textViewAtRow:0 column:0];
    cell.selectedRange = NSMakeRange(3, 0);
    SNAttachment *a = [_notes attachmentWithID:tableID];
    TTTable *elsewhere = [_notes tableOfAttachment:a];
    [[elsewhere textAtRow:0 column:0] insertString:@"green " atIndex:0 attributes:@{ SNItalicKey: @YES }];
    [_notes saveTable:elsewhere toAttachment:a];
    [grid reloadFromStore];
    XCTAssertEqualObjects(cell.string, @"green tea");
    XCTAssertEqual(cell.selectedRange.location, 9u, @"still after tea");
    NSFont *font = [cell.textStorage attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
    XCTAssertTrue([[NSFontManager sharedFontManager] traitsOfFont:font] & NSItalicFontMask);
}

/* An image as wide as the text, when the text is narrower: the text made
   wider (a window, a screen turned), the image is shown wider too. */
- (void)testAnImageFollowsTheTextsWidth {
    NSBitmapImageRep *wide = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:800 pixelsHigh:100 bitsPerSample:8 samplesPerPixel:4
                                                                       hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
#ifdef GNUSTEP
    NSData *png = [wide representationUsingType:NSPNGFileType properties:@{}];
#else
    NSData *png = [wide representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
#endif
    NSTextView *tv = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 300, 200)];
    [_binding unbind];
    SNTextBinding *binding = [[SNTextBinding alloc] initWithTextView:tv editor:_editor];
    XCTAssertTrue([binding insertImageData:png inRange:NSMakeRange(0, 0)]);
    NSTextAttachment *shown = [tv.textStorage attribute:NSAttachmentAttributeName atIndex:0 effectiveRange:NULL];
    CGFloat narrow = shown.attachmentCell.cellSize.width;
    XCTAssertLessThan(narrow, 300, @"as wide as the text");
    [tv setFrameSize:NSMakeSize(700, 200)];
    [binding textWidthMayHaveChanged];
    shown = [tv.textStorage attribute:NSAttachmentAttributeName atIndex:0 effectiveRange:NULL];
    XCTAssertGreaterThan(shown.attachmentCell.cellSize.width, narrow + 300, @"wider with it");
    [binding unbind];
}

@end
