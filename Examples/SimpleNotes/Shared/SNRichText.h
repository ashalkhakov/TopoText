// A note's rich text: what TopoText keeps (plain values, the same on every
// system) and what a text view shows (fonts, indents, list markers), each
// made from the other. AppKit's (macOS, GNUstep) and UIKit's.
//
//   Of a character:  bold, italic, underline, strike: YES
//   Of a paragraph:  style: title, heading, subheading or mono (else body)
//                    list: bullet, dash, number or check
//                    checked: YES (a checklist item ticked)
//                    indent: 1, 2... (else none)
//
// A paragraph's are on every character of it and its newline, as TopoText
// keeps paragraphs (TopoText (Paragraphs)): where they disagree, after a
// merge, its newline's stand, and the view shows the whole paragraph so.
// A paragraph has a style or a list, not both, as in Apple Notes.
//
// SNTextBinding keeps a text view's storage and an editor's TopoText the
// same, both ways; SNListLayoutManager draws the list markers and
// checkboxes in a paragraph's indent, which are not text.

#pragma once
#import <Foundation/Foundation.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
typedef UIFont SNFont;
typedef CGPoint SNPoint;
#else
#import <AppKit/AppKit.h>
typedef NSFont SNFont;
typedef NSPoint SNPoint;
#endif
#import <TopoText/TopoText.h>

@class SNNoteEditor;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const SNBoldKey;        // @"bold"
FOUNDATION_EXPORT NSString * const SNItalicKey;      // @"italic"
FOUNDATION_EXPORT NSString * const SNUnderlineKey;   // @"underline"
FOUNDATION_EXPORT NSString * const SNStrikeKey;      // @"strike"
FOUNDATION_EXPORT NSString * const SNStyleKey;       // @"style"
FOUNDATION_EXPORT NSString * const SNStyleTitle;     // @"title"
FOUNDATION_EXPORT NSString * const SNStyleHeading;   // @"heading"
FOUNDATION_EXPORT NSString * const SNStyleSubheading;// @"subheading"
FOUNDATION_EXPORT NSString * const SNStyleMono;      // @"mono"
FOUNDATION_EXPORT NSString * const SNListKey;        // @"list"
FOUNDATION_EXPORT NSString * const SNListBullet;     // @"bullet"
FOUNDATION_EXPORT NSString * const SNListDash;       // @"dash"
FOUNDATION_EXPORT NSString * const SNListNumber;     // @"number"
FOUNDATION_EXPORT NSString * const SNListCheck;      // @"check"
FOUNDATION_EXPORT NSString * const SNCheckedKey;     // @"checked"
FOUNDATION_EXPORT NSString * const SNIndentKey;      // @"indent"
// The paragraph's keys.
FOUNDATION_EXPORT NSSet<NSString *> *SNParagraphKeys(void);
// The storage's attributes that say a paragraph's (their values TopoText's).
FOUNDATION_EXPORT NSString * const SNStyleAttributeName;    // @"SNStyle"
FOUNDATION_EXPORT NSString * const SNListAttributeName;     // @"SNList"
FOUNDATION_EXPORT NSString * const SNCheckedAttributeName;  // @"SNChecked"
FOUNDATION_EXPORT NSString * const SNIndentAttributeName;   // @"SNIndent"

// The text view's attributes for TopoText's (a character's and its
// paragraph's together), and TopoText's for the view's.
FOUNDATION_EXPORT NSDictionary<NSString *, id> *SNViewAttributes(NSDictionary<NSString *, id> *attributes);
FOUNDATION_EXPORT NSDictionary<NSString *, id> *SNTextAttributes(NSDictionary<NSString *, id> *viewAttributes);
FOUNDATION_EXPORT SNFont *SNFontFor(NSString *_Nullable style, BOOL bold, BOOL italic);
// A TopoText's whole text, as the view shows it: each paragraph as its
// newline says.
FOUNDATION_EXPORT NSAttributedString *SNViewString(TopoText *text);

@interface SNTextBinding : NSObject
// The storage set to the editor's text, and kept so.
- (instancetype)initWithStorage:(NSTextStorage *)storage editor:(SNNoteEditor *)editor NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@property (nonatomic, readonly) NSTextStorage *storage;
@property (nonatomic, readonly) SNNoteEditor *editor;
// The view's selection, for remote edits to move it along.
@property (nonatomic, copy, nullable) NSRange (^getSelection)(void);
@property (nonatomic, copy, nullable) void (^setSelection)(NSRange range);
// After remote edits came in (an undo stack no longer matches).
@property (nonatomic, copy, nullable) void (^didApplyRemoteEdits)(void);
// The view's typing attributes: what is typed next is formatted so. An empty
// last paragraph has no character to keep its paragraph's formatting, and
// keeps it there (a checklist item begun on the last line, say).
@property (nonatomic, copy, nullable) NSDictionary<NSString *, id> *(^getTypingAttributes)(void);
@property (nonatomic, copy, nullable) void (^setTypingAttributes)(NSDictionary<NSString *, id> *attributes);

#pragma mark Formatting
// On the range's characters; with none selected, on what is typed next.
- (BOOL)range:(NSRange)range has:(NSString *)key;
- (void)toggle:(NSString *)key inRange:(NSRange)range;
// The rest on every paragraph the range touches.
// A style (nil: body), the paragraphs' list taken off.
- (void)setStyle:(nullable NSString *)style forParagraphsInRange:(NSRange)range;
// A list: these paragraphs made items of it, their style taken off; when
// they all are already, made body again.
- (void)toggleList:(NSString *)list forParagraphsInRange:(NSRange)range;
// Checklist items ticked, or unticked when the first is ticked.
- (void)toggleCheckedForParagraphsInRange:(NSRange)range;
// Indented one more (by > 0) or one less, from none to 8.
- (void)indentParagraphsInRange:(NSRange)range by:(NSInteger)by;
// The paragraph at index's formatting (TopoText's keys), as the view shows it.
- (NSDictionary<NSString *, id> *)paragraphAttributesAt:(NSUInteger)index;
// The range of the paragraphs a range touches, their newlines included.
- (NSRange)paragraphsRangeForRange:(NSRange)range;
// The attributes typing goes on with at a place.
- (NSDictionary<NSString *, id> *)typingAttributesAt:(NSUInteger)index;

#pragma mark Typing in lists
// What the view is about to do to its text, asked first (its delegate's
// shouldChangeText): NO when the binding did something else instead, as
// Apple Notes does - Return on an empty item ends the list (or outdents it),
// Delete at an item's start takes its marker off, Tab indents an item.
- (BOOL)shouldChangeTextInRange:(NSRange)range replacementString:(nullable NSString *)string;
// After the view changed its text (its delegate's textDidChange): a new
// checklist item unticked, the line after a title body, each paragraph
// touched made one formatting, its first character's.
- (void)textDidChange;
// After the view's selection moved: typing goes on as the text there.
- (void)selectionDidChange;

// No longer listening.
- (void)unbind;
@end

// Draws the list markers - •, –, 1., a checkbox - in the indent before each
// list paragraph's first line, from the storage's SN attributes; numbers
// count the items before at the same indent. Set as the text view's layout
// manager.
@interface SNListLayoutManager : NSLayoutManager
// The view's typing attributes, for the marker of an empty last paragraph,
// which has no character to say it.
@property (nonatomic, copy, nullable) NSDictionary<NSString *, id> *extraLineAttributes;
// The paragraph whose checkbox is at point (in the text container's
// coordinates), its first character's index; NSNotFound for none.
- (NSUInteger)checkboxAtPoint:(SNPoint)point;
@end

NS_ASSUME_NONNULL_END
