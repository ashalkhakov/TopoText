// A text view's storage and an editor's TopoText, kept the same: what is
// typed into the storage goes into the text; what a merge brings into the
// text comes into the storage, the selection moved along.

#import <XCTest/XCTest.h>
/* AppKit before Core Data: gnustep-gui's NSPredicateEditorRowTemplate.h
   declares NSAttributeType again when Core Data's came first. */
#import "SNRichText.h"
#import "SNModel.h"
#import "SNNotes.h"

@interface SNTextBindingTests : XCTestCase
@end

@implementation SNTextBindingTests {
    NSURL *_store;
    SNNotes *_notes;
    SNNoteEditor *_editor;
    NSTextStorage *_storage;
    SNTextBinding *_binding;
    NSRange _selection;
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
    _binding = [[SNTextBinding alloc] initWithStorage:_storage editor:_editor];
    __weak SNTextBindingTests *weak = self;
    _binding.getSelection = ^NSRange {
        SNTextBindingTests *me = weak;
        return me ? me->_selection : NSMakeRange(0, 0);
    };
    _binding.setSelection = ^(NSRange r) {
        SNTextBindingTests *me = weak;
        if (me) me->_selection = r;
    };
}

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
    _editor.didMerge(edits);
    XCTAssertEqualObjects(_storage.string, @">> Helloworld");
    XCTAssertEqualObjects(_editor.text.string, _storage.string);
    XCTAssertEqual([[_storage attribute:NSUnderlineStyleAttributeName atIndex:3 effectiveRange:NULL] integerValue], NSUnderlineStyleSingle);
    XCTAssertEqual(_selection.location, 8u, @"the selection moved along: %@", NSStringFromRange(_selection));
    XCTAssertEqual(_selection.length, 5u);
    /* And typing goes on as before. */
    [self type:@" " at:8];
    XCTAssertEqualObjects(_editor.text.string, @">> Hello world");
}

@end
