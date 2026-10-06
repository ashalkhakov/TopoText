// A note's rich text: what TopoText keeps (plain values, the same on every
// system) and what a text view shows (fonts), each made from the other.
// AppKit's (macOS, GNUstep) and UIKit's.
//
//   TopoText      bold, italic, underline, strike: YES
//                 style: "title" or "heading" (else body)
//   text view     the font for the style and traits; underline and
//                 strikethrough styles; SNStyle, the style's name
//
// And SNTextBinding: a text view's storage and an editor's TopoText kept
// the same, both ways. What the user does to the storage goes into the
// text as it happens; what a sync merged into the text comes into the
// storage as the edits it made, the selection moved along.

#pragma once
#import <Foundation/Foundation.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
typedef UIFont SNFont;
#else
#import <AppKit/AppKit.h>
typedef NSFont SNFont;
#endif
#import <TopoText/TopoText.h>

@class SNNoteEditor;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const SNBoldKey;       // @"bold"
FOUNDATION_EXPORT NSString * const SNItalicKey;     // @"italic"
FOUNDATION_EXPORT NSString * const SNUnderlineKey;  // @"underline"
FOUNDATION_EXPORT NSString * const SNStrikeKey;     // @"strike"
FOUNDATION_EXPORT NSString * const SNStyleKey;      // @"style"
FOUNDATION_EXPORT NSString * const SNStyleTitle;    // @"title"
FOUNDATION_EXPORT NSString * const SNStyleHeading;  // @"heading"
// The storage's attribute that says a style (its value: SNStyleTitle...).
FOUNDATION_EXPORT NSString * const SNStyleAttributeName;

// The text view's attributes for TopoText's, and TopoText's for the view's.
FOUNDATION_EXPORT NSDictionary<NSString *, id> *SNViewAttributes(NSDictionary<NSString *, id> *attributes);
FOUNDATION_EXPORT NSDictionary<NSString *, id> *SNTextAttributes(NSDictionary<NSString *, id> *viewAttributes);
FOUNDATION_EXPORT SNFont *SNFontFor(NSString *_Nullable style, BOOL bold, BOOL italic);
// A TopoText's whole text, as the view shows it.
FOUNDATION_EXPORT NSAttributedString *SNViewString(TopoText *text);

@interface SNTextBinding : NSObject
// The storage set to the editor's text, and kept so.
- (instancetype)initWithStorage:(NSTextStorage *)storage editor:(SNNoteEditor *)editor NS_DESIGNATED_INITIALIZER;
@property (nonatomic, readonly) NSTextStorage *storage;
@property (nonatomic, readonly) SNNoteEditor *editor;
// The view's selection, for remote edits to move it along.
@property (nonatomic, copy, nullable) NSRange (^getSelection)(void);
@property (nonatomic, copy, nullable) void (^setSelection)(NSRange range);
// After remote edits came in (an undo stack no longer matches).
@property (nonatomic, copy, nullable) void (^didApplyRemoteEdits)(void);

// Formatting, as a format bar or menu asks: on the range's characters;
// a style, on its whole paragraphs. On when the range's first character
// has it not.
- (BOOL)range:(NSRange)range has:(NSString *)key;
- (void)toggle:(NSString *)key inRange:(NSRange)range;
- (void)setStyle:(nullable NSString *)style forParagraphsInRange:(NSRange)range;
// The attributes typing goes on with at a place (the view's typingAttributes).
- (NSDictionary<NSString *, id> *)typingAttributesAt:(NSUInteger)index;
// No longer listening.
- (void)unbind;
@end

NS_ASSUME_NONNULL_END
