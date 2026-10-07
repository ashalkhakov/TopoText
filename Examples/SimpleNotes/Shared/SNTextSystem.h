// What a note's rich text (SNRichText) and its tables (SNTableGrids) need
// of the system they run on, one implementation for each, which the build
// picks: AppKit/SNTextSystem.m (macOS, GNUstep), iOS/SNTextSystem.m
// (UIKit). Fonts and colors as each system has them, images made and
// read, attachments shown, a text view's geometry. The shared code does
// not ask which system it is on.

#pragma once
#import "SNRichText.h"

#if TARGET_OS_IPHONE
typedef UIColor SNColor;
typedef UIBezierPath SNPath;
typedef UIImage SNImage;
typedef CGRect SNRect;
#else
typedef NSColor SNColor;
typedef NSBezierPath SNPath;
typedef NSImage SNImage;
typedef NSRect SNRect;
#endif

NS_ASSUME_NONNULL_BEGIN

/* An attachment shown: the view's, made from the note's attachment of
   attachmentID; loaded NO while it has not come yet (a grey box shows). */
@interface SNTextAttachment : NSTextAttachment
@property (nonatomic, copy) NSString *attachmentID;
@property (nonatomic) BOOL loaded;
/* The data it was made from: made again when it changed. */
@property (nonatomic) NSUInteger dataHash;
/* A table's room, kept empty for its grid (zero: none). */
@property (nonatomic) SNSize room;
/* How wide the text was when an image was sized to it. */
@property (nonatomic) CGFloat textWidth;
@end

#pragma mark fonts and colors

// Body's size, and a style's (title, heading...).
FOUNDATION_EXPORT CGFloat SNSystemFontSize(NSString *_Nullable style);
FOUNDATION_EXPORT SNFont *SNSystemFont(CGFloat size, BOOL bold);
FOUNDATION_EXPORT SNFont *SNSystemMonoFont(CGFloat size, BOOL bold);
FOUNDATION_EXPORT SNFont *SNSystemFontWithTraits(SNFont *font, BOOL bold, BOOL italic);
FOUNDATION_EXPORT void SNSystemTraitsOf(SNFont *font, BOOL *bold, BOOL *italic);
FOUNDATION_EXPORT SNColor *SNSystemTextColor(void);
// A list marker's, an empty checkbox's.
FOUNDATION_EXPORT SNColor *SNSystemMarkerColor(void);
// A ticked checkbox's (Apple Notes' orange).
FOUNDATION_EXPORT SNColor *SNSystemAccentColor(void);
// A table's lines.
FOUNDATION_EXPORT SNColor *SNSystemGridColor(void);
// An indent's width (a list marker's column).
FOUNDATION_EXPORT CGFloat SNSystemIndentStep(void);
// A checkbox's width, for a font.
FOUNDATION_EXPORT CGFloat SNSystemCheckboxSize(SNFont *font);

#pragma mark drawing

FOUNDATION_EXPORT void SNSystemAddLine(SNPath *path, SNPoint from, SNPoint to);

#pragma mark images

// An image's size in pixels (not points); NO: not an image.
FOUNDATION_EXPORT BOOL SNSystemImagePixels(NSData *data, double *width, double *height);
// The image drawn width x height pixels, encoded (a PNG, or a JPEG); nil:
// it could not be.
FOUNDATION_EXPORT NSData *_Nullable SNSystemScaledImage(NSData *data, NSUInteger width, NSUInteger height, BOOL png);
// A screen's points a pixel (a Retina screen's half).
FOUNDATION_EXPORT CGFloat SNSystemPointsPerPixel(void);

#pragma mark attachments

// An image (nil: a grey box, while it has not come) size points large.
FOUNDATION_EXPORT SNTextAttachment *SNSystemImageAttachment(NSData *_Nullable data, NSString *_Nullable type, SNSize size);
// A file, as a card (the system's icon for it, its name, what it is) as
// wide as width; data kept in it (copied out, dragged out, as the file).
FOUNDATION_EXPORT SNTextAttachment *SNSystemFileAttachment(NSData *_Nullable data, NSString *name, NSString *detail, CGFloat width);
// A room: as large as size, nothing drawn in it.
FOUNDATION_EXPORT SNTextAttachment *SNSystemRoomAttachment(SNSize size);
// What a view's attachment holds, as data (one pasted or dropped).
FOUNDATION_EXPORT NSData *_Nullable SNSystemDataOfAttachment(NSTextAttachment *attachment);

#pragma mark text views

// How wide a text container lays text.
FOUNDATION_EXPORT CGFloat SNSystemContainerWidth(NSTextContainer *container);
// Where a text view's text container is, in the view.
FOUNDATION_EXPORT SNPoint SNSystemTextOrigin(id<SNTextViewing> view);
// A text view's drawing done again (the list markers: a range of its
// characters, or all).
FOUNDATION_EXPORT void SNSystemRedisplay(NSLayoutManager *layoutManager, NSRange range);
// observer sent selector (an NSNotification) when the view's width may
// have changed; nothing where its controller says so instead (UIKit's
// -viewDidLayoutSubviews).
FOUNDATION_EXPORT void SNSystemObserveResizing(id view, id observer, SEL selector);

// Each edit, as each system's layout manager hears of one, told to the
// list layout manager's -textEdited (shared); each system's file overrides
// its own method.
@interface SNListLayoutManager (SNTextSystem)
- (void)textEdited;
@end

NS_ASSUME_NONNULL_END
