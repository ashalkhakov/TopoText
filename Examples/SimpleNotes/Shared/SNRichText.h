// A note's rich text: what TopoText keeps (plain values, the same on every
// system) and what a text view shows (fonts, indents, list markers), each
// made from the other. AppKit's (macOS, GNUstep) and UIKit's.
//
//   Of a character:  bold, italic, underline, strike: YES
//                    link: a URL's text (simplenotes://note/<id>: a note)
//                    attachment: an attachment's id, on U+FFFC (an image:
//                    SNAttachment; the view shows it, NSTextAttachment)
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
typedef CGSize SNSize;
#else
#import <AppKit/AppKit.h>
typedef NSFont SNFont;
typedef NSPoint SNPoint;
typedef NSSize SNSize;
#endif
#import <TopoText/TopoText.h>
#import "SNTextSource.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const SNBoldKey;        // @"bold"
FOUNDATION_EXPORT NSString * const SNItalicKey;      // @"italic"
FOUNDATION_EXPORT NSString * const SNUnderlineKey;   // @"underline"
FOUNDATION_EXPORT NSString * const SNStrikeKey;      // @"strike"
FOUNDATION_EXPORT NSString * const SNLinkKey;        // @"link"
FOUNDATION_EXPORT NSString * const SNAttachmentKey;  // @"attachment"
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
// A link given (SNLinkKey), beside NSLinkAttributeName: one only detected
// (an address typed, linked as Apple Notes does) has NSLinkAttributeName
// alone, and is the view's, not the text's.
FOUNDATION_EXPORT NSString * const SNLinkAttributeName;     // @"SNLink"
// An attachment's id (SNAttachmentKey), beside the NSTextAttachment that
// shows it: one pasted or dropped has none, until it is made one of the
// note's.
FOUNDATION_EXPORT NSString * const SNAttachmentAttributeName;   // @"SNAttachment"

// Images are kept no larger than this across (pixels), re-encoded (a JPEG,
// or a PNG for one with transparency) when larger or of another kind.
FOUNDATION_EXPORT const double SNAttachmentMaxPixels;   // 1600
// An image's data as an attachment keeps it, its type and size; nil: not an
// image.
FOUNDATION_EXPORT NSData *_Nullable SNImageDataForAttachment(NSData *data, NSString *_Nullable *_Nonnull type,
                                                             double *width, double *height);

// The text view's attributes for TopoText's (a character's and its
// paragraph's together), and TopoText's for the view's.
FOUNDATION_EXPORT NSDictionary<NSString *, id> *SNViewAttributes(NSDictionary<NSString *, id> *attributes);
FOUNDATION_EXPORT NSDictionary<NSString *, id> *SNTextAttributes(NSDictionary<NSString *, id> *viewAttributes);
FOUNDATION_EXPORT SNFont *SNFontFor(NSString *_Nullable style, BOOL bold, BOOL italic);
// A TopoText's whole text, as the view shows it: each paragraph as its
// newline says.
FOUNDATION_EXPORT NSAttributedString *SNViewString(TopoText *text);

// What a binding needs of its text view. AppKit's NSTextView and UIKit's
// UITextView have all of it (they are declared so below).
@protocol SNTextViewing <NSObject>
- (NSTextStorage *)textStorage;
- (NSRange)selectedRange;
- (void)setSelectedRange:(NSRange)range;
// What is typed next is formatted so. An empty last paragraph has no
// character to keep its paragraph's formatting: the binding keeps it here
// (a checklist item begun on the last line, say).
- (NSDictionary<NSString *, id> *)typingAttributes;
- (void)setTypingAttributes:(NSDictionary<NSString *, id> *)attributes;
// Cleared when remote edits come in: what it remembers no longer fits.
- (nullable NSUndoManager *)undoManager;
@end

#if TARGET_OS_IPHONE
@interface UITextView (SNTextViewing) <SNTextViewing>
@end
#else
@interface NSTextView (SNTextViewing) <SNTextViewing>
@end
#endif

@interface SNTextBinding : NSObject
// The view's storage set to the editor's text, and kept so: a note's
// (SNNoteEditor), whose delegate hands its merges to -applyEdits:, or a
// table cell's. A cell has no attachments: none is put in it.
- (instancetype)initWithTextView:(id<SNTextViewing>)view editor:(id<SNTextSource>)editor NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@property (nonatomic, readonly, weak) id<SNTextViewing> view;
@property (nonatomic, readonly) NSTextStorage *storage;
@property (nonatomic, readonly) id<SNTextSource> editor;
// What a sync merged into the editor's text (SNNoteEditorDelegate's
// -noteEditor:didMergeEdits:), done to the storage; the selection moved
// along.
- (void)applyEdits:(NSArray<TTEdit *> *)edits;

#pragma mark Formatting
// On the range's characters; with none selected, on what is typed next.
- (BOOL)range:(NSRange)range has:(NSString *)key;
- (void)toggle:(NSString *)key inRange:(NSRange)range;
// A link on the range's characters (nil: taken off), and the one at a place.
- (void)setLink:(nullable NSString *)link inRange:(NSRange)range;
- (nullable NSString *)linkAt:(NSUInteger)index;
// An image in place of the range, made one of the note's attachments
// (re-encoded, saved, synced); NO: not an image.
- (BOOL)insertImageData:(NSData *)data inRange:(NSRange)range;
// A table in place of the range (rows x columns, empty), made one of the
// note's attachments; its id.
- (nullable NSString *)insertTableWithRows:(NSUInteger)rows columns:(NSUInteger)columns inRange:(NSRange)range;
// The id of the attachment at a place (nil: none).
- (nullable NSString *)attachmentIDAt:(NSUInteger)index;
// A table's room in the text: the size its character keeps, empty, for its
// grid laid over it (SNTableGrid). Until it is said, the table is drawn
// there as a picture.
- (void)setRoomSize:(SNSize)size forAttachmentID:(NSString *)attachmentID;
// Attachments shown again: those a sync has brought since (a text can come
// before its attachment).
- (void)refreshAttachments;
// Images sized to the text's width again, when it changed (AppKit's text
// view says so itself; UIKit's controller calls this once laid out).
- (void)textWidthMayHaveChanged;
// The rest on every paragraph the range touches.
// A style (nil: body), the paragraphs' list taken off.
- (void)setStyle:(nullable NSString *)style forParagraphsInRange:(NSRange)range;
// A list: these paragraphs made items of it, their style taken off; when
// they all are already, made body again.
- (void)toggleList:(NSString *)list forParagraphsInRange:(NSRange)range;
// Checklist items ticked, or unticked when the first is ticked.
- (void)toggleCheckedForParagraphsInRange:(NSRange)range;
// The checklist a place is in (its items one after another), its ticked
// items moved after the others, as Apple Notes' Move Checked to Bottom;
// NO when nothing moved. Only the ticked ones out of place move, each a
// deletion and an insertion: typing another device does in one at the same
// time stays where the item was.
- (BOOL)moveCheckedToBottomOfChecklistAt:(NSUInteger)index;
// The checklist's range a place is in (NSNotFound: none), for an undo.
- (NSRange)checklistRangeAt:(NSUInteger)index;
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
