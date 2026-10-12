// SNTextSystem on AppKit: macOS's, and GNUstep's (gnustep-gui), where it
// differs from macOS's (#ifdef GNUSTEP).

#import "SNTextSystem.h"

@implementation SNTextAttachment
@end

#pragma mark fonts and colors

CGFloat SNSystemFontSize(NSString *style) {
    return [style isEqual:SNStyleTitle] ? 24 : [style isEqual:SNStyleHeading] ? 18 : [style isEqual:SNStyleSubheading] ? 15 : 14;
}

SNFont *SNSystemFont(CGFloat size, BOOL bold) {
    return bold ? [NSFont boldSystemFontOfSize:size] : [NSFont systemFontOfSize:size];
}

SNFont *SNSystemMonoFont(CGFloat size, BOOL bold) {
    return SNSystemFontWithTraits([NSFont userFixedPitchFontOfSize:size] ?: [NSFont systemFontOfSize:size], bold, NO);
}

SNFont *SNSystemFontWithTraits(SNFont *font, BOOL bold, BOOL italic) {
    NSFontManager *fm = [NSFontManager sharedFontManager];
    if (bold) font = [fm convertFont:font toHaveTrait:NSBoldFontMask] ?: font;
    if (italic) font = [fm convertFont:font toHaveTrait:NSItalicFontMask] ?: font;
    return font;
}

void SNSystemTraitsOf(SNFont *font, BOOL *bold, BOOL *italic) {
    NSFontTraitMask t = [[NSFontManager sharedFontManager] traitsOfFont:font];
    *bold = (t & NSBoldFontMask) != 0;
    *italic = (t & NSItalicFontMask) != 0;
}

SNColor *SNSystemTextColor(void) {
    return [NSColor textColor];
}

SNColor *SNSystemMarkerColor(void) {
    return [NSColor grayColor];
}

SNColor *SNSystemAccentColor(void) {
    return [NSColor colorWithCalibratedRed:0.96 green:0.66 blue:0.0 alpha:1];
}

SNColor *SNSystemGridColor(void) {
    return [[NSColor grayColor] colorWithAlphaComponent:0.6];
}

SNColor *SNSystemNamedColor(NSString *name) {
#ifdef GNUSTEP
    /* Its colour lists have no system purple, pink, mint: macOS's light
       ones. */
    NSDictionary *rgb = @{ @"purple": @[ @0.69, @0.32, @0.87 ], @"pink": @[ @1.0, @0.18, @0.33 ], @"orange": @[ @1.0, @0.58, @0.0 ],
                           @"mint": @[ @0.0, @0.78, @0.75 ], @"blue": @[ @0.0, @0.48, @1.0 ] };
    NSArray *c = rgb[name];
    return c ? [NSColor colorWithCalibratedRed:[c[0] doubleValue] green:[c[1] doubleValue] blue:[c[2] doubleValue] alpha:1] : SNSystemTextColor();
#else
    if ([name isEqual:@"purple"]) return [NSColor systemPurpleColor];
    if ([name isEqual:@"pink"]) return [NSColor systemPinkColor];
    if ([name isEqual:@"orange"]) return [NSColor systemOrangeColor];
    if ([name isEqual:@"mint"]) return [NSColor systemMintColor];
    if ([name isEqual:@"blue"]) return [NSColor systemBlueColor];
    return SNSystemTextColor();
#endif
}

SNColor *SNSystemHighlightColor(NSString *name) {
    return [SNSystemNamedColor(name) colorWithAlphaComponent:0.3];
}

CGFloat SNSystemIndentStep(void) {
    return 24;
}

CGFloat SNSystemCheckboxSize(SNFont *font) {
    return round(font.pointSize * 1.15);
}

#pragma mark drawing

void SNSystemAddLine(SNPath *path, SNPoint from, SNPoint to) {
    [path moveToPoint:from];
    [path lineToPoint:to];
}

#pragma mark images

BOOL SNSystemImagePixels(NSData *data, double *width, double *height) {
    NSImage *image = data.length ? [[NSImage alloc] initWithData:data] : nil;
    if (!image) return NO;
    NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:data];
    *width = rep ? rep.pixelsWide : image.size.width;
    *height = rep ? rep.pixelsHigh : image.size.height;
    return YES;
}

NSData *SNSystemScaledImage(NSData *data, NSUInteger width, NSUInteger height, BOOL png) {
    NSImage *image = [[NSImage alloc] initWithData:data];
    if (!image) return nil;
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:(NSInteger)width pixelsHigh:(NSInteger)height
                                                                 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    [NSGraphicsContext setCurrentContext:context];
#ifdef GNUSTEP
    [image drawInRect:NSMakeRect(0, 0, width, height) fromRect:NSZeroRect operation:NSCompositeCopy fraction:1.0];
#else
    [image drawInRect:NSMakeRect(0, 0, width, height) fromRect:NSZeroRect operation:NSCompositingOperationCopy fraction:1.0];
#endif
    /* Into the bitmap: gnustep-back's cairo draws on a surface of its own,
       copied into the bitmap only when flushed. */
    [context flushGraphics];
    [NSGraphicsContext restoreGraphicsState];
#ifdef GNUSTEP
    return png ? [rep representationUsingType:NSPNGFileType properties:@{}]
               : [rep representationUsingType:NSJPEGFileType properties:@{ NSImageCompressionFactor: @0.85 }];
#else
    return png ? [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
               : [rep representationUsingType:NSBitmapImageFileTypeJPEG properties:@{ NSImageCompressionFactor: @0.85 }];
#endif
}

CGFloat SNSystemPointsPerPixel(void) {
    return 1;
}

#pragma mark attachments

/* A box to show while an attachment has not come yet. */
static NSImage *SNPlaceholderImage(SNSize size) {
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image lockFocus];
    [[NSColor colorWithCalibratedWhite:0.85 alpha:1] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0, 0, size.width, size.height) xRadius:8 yRadius:8] fill];
    [image unlockFocus];
    return image;
}

SNTextAttachment *SNSystemImageAttachment(NSData *data, NSString *type, SNSize size) {
    NSImage *image = data ? [[NSImage alloc] initWithData:data] : nil;
    SNTextAttachment *a;
    if (image) {
        NSFileWrapper *file = [[NSFileWrapper alloc] initRegularFileWithContents:data];
        file.preferredFilename = [type isEqual:@"image/png"] ? @"image.png" : @"image.jpg";
        a = [[SNTextAttachment alloc] initWithFileWrapper:file];
        image.size = size;
    } else {
        a = [[SNTextAttachment alloc] init];
        image = SNPlaceholderImage(size);
    }
    a.attachmentCell = [[NSTextAttachmentCell alloc] initImageCell:image];
    return a;
}

/* A file's card, Apple Notes' kind: a rounded box, the file's icon, its
   name, and under it what it is. */
SNTextAttachment *SNSystemFileAttachment(NSData *data, NSString *name, NSString *detail, CGFloat width) {
    NSSize size = NSMakeSize(MAX(160, width), 52);
    NSImage *card = [[NSImage alloc] initWithSize:size];
    [card lockFocus];
    NSRect box = NSInsetRect(NSMakeRect(0, 0, size.width, size.height), 0.5, 0.5);
    NSBezierPath *round = [NSBezierPath bezierPathWithRoundedRect:box xRadius:8 yRadius:8];
    [[NSColor colorWithCalibratedWhite:0.5 alpha:0.10] setFill];
    [round fill];
    [[NSColor colorWithCalibratedWhite:0.5 alpha:0.35] setStroke];
    [round stroke];
    NSImage *icon = [[NSWorkspace sharedWorkspace] iconForFileType:name.pathExtension.length ? name.pathExtension : @"txt"];
    [icon drawInRect:NSMakeRect(10, 10, 32, 32) fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
    NSMutableParagraphStyle *clip = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
    clip.lineBreakMode = NSLineBreakByTruncatingTail;
    [name drawInRect:NSMakeRect(52, 26, size.width - 62, 18)
      withAttributes:@{ NSFontAttributeName: [NSFont boldSystemFontOfSize:13], NSForegroundColorAttributeName: [NSColor textColor],
                        NSParagraphStyleAttributeName: clip }];
    [detail drawInRect:NSMakeRect(52, 9, size.width - 62, 16)
        withAttributes:@{ NSFontAttributeName: [NSFont systemFontOfSize:11], NSForegroundColorAttributeName: [NSColor grayColor],
                          NSParagraphStyleAttributeName: clip }];
    [card unlockFocus];
    SNTextAttachment *a;
    if (data) {
        NSFileWrapper *file = [[NSFileWrapper alloc] initRegularFileWithContents:data];
        file.preferredFilename = name;
        a = [[SNTextAttachment alloc] initWithFileWrapper:file];
    } else {
        a = [[SNTextAttachment alloc] init];
    }
    a.attachmentCell = [[NSTextAttachmentCell alloc] initImageCell:card];
    return a;
}

/* A room: as large as it is said to be, and nothing drawn in it. */
@interface SNRoomCell : NSTextAttachmentCell
@property (nonatomic) NSSize room;
@end

@implementation SNRoomCell
- (NSSize)cellSize { return _room; }
- (NSPoint)cellBaselineOffset { return NSZeroPoint; }
- (void)drawWithFrame:(NSRect)frame inView:(NSView *)view {}
- (void)drawWithFrame:(NSRect)frame inView:(NSView *)view characterIndex:(NSUInteger)index layoutManager:(NSLayoutManager *)lm {}
- (void)highlight:(BOOL)flag withFrame:(NSRect)frame inView:(NSView *)view {}
@end

SNTextAttachment *SNSystemRoomAttachment(SNSize size) {
    SNTextAttachment *a = [[SNTextAttachment alloc] init];
    SNRoomCell *cell = [[SNRoomCell alloc] init];
    cell.room = size;
    a.attachmentCell = cell;
    a.room = size;
    return a;
}

NSData *SNSystemDataOfAttachment(NSTextAttachment *a) {
    if (a.fileWrapper.isRegularFile) return a.fileWrapper.regularFileContents;
    id cell = a.attachmentCell;
    NSImage *image = [cell respondsToSelector:@selector(image)] ? [cell image] : nil;
    return image.TIFFRepresentation;
}

#pragma mark text views

CGFloat SNSystemContainerWidth(NSTextContainer *container) {
#ifdef GNUSTEP
    return container.containerSize.width;
#else
    return container.size.width;
#endif
}

SNPoint SNSystemTextOrigin(id<SNTextViewing> view) {
    return [(NSTextView *)view textContainerOrigin];
}

NSUndoManager *SNSystemUndoManager(id<SNTextViewing> view) {
    if ([(id)view isKindOfClass:[NSView class]]) return [(NSView *)view window].undoManager;
    return view.undoManager;
}

void SNSystemTextChanged(id<SNTextViewing> view) {
    if ([(id)view isKindOfClass:[NSTextView class]]) [(NSTextView *)view didChangeText];
}

/* The headings' chevrons, over a text view: AppKit's covers its margin
   (macOS's draws its background in a layer above what -drawRect: draws,
   and clips the layout manager's drawing to the text container). Clicks go
   through, to the text view. */
@interface SNChevronsView : NSView
@end

@implementation SNChevronsView

- (BOOL)isFlipped {
    return YES;
}

- (NSView *)hitTest:(NSPoint)point {
    return nil;
}

- (void)drawRect:(NSRect)rect {
    NSTextView *tv = (NSTextView *)self.superview;
    if (![tv isKindOfClass:[NSTextView class]] || ![tv.layoutManager isKindOfClass:[SNListLayoutManager class]]) return;
    [(SNListLayoutManager *)tv.layoutManager drawChevronsAtPoint:tv.textContainerOrigin];
}

@end

void SNSystemShowChevrons(id<SNTextViewing> view) {
    if (![(id)view isKindOfClass:[NSTextView class]]) return;
    NSTextView *tv = (NSTextView *)view;
    for (NSView *v in tv.subviews) if ([v isKindOfClass:[SNChevronsView class]]) return;
    SNChevronsView *chevrons = [[SNChevronsView alloc] initWithFrame:tv.bounds];
    chevrons.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [tv addSubview:chevrons];
}

void SNSystemRedisplay(NSLayoutManager *layoutManager, NSRange range) {
    NSTextView *tv = layoutManager.firstTextView;
    [tv setNeedsDisplay:YES];
    for (NSView *v in tv.subviews) if ([v isKindOfClass:[SNChevronsView class]]) [v setNeedsDisplay:YES];
}

void SNSystemObserveResizing(id view, id observer, SEL selector) {
    if (![view isKindOfClass:[NSView class]]) return;   /* a test's stand-in */
    [view setPostsFrameChangedNotifications:YES];
    [[NSNotificationCenter defaultCenter] addObserver:observer selector:selector name:NSViewFrameDidChangeNotification object:view];
}

@implementation SNListLayoutManager (SNTextSystemEditing)

#ifdef GNUSTEP
- (void)textStorage:(NSTextStorage *)storage edited:(unsigned int)mask range:(NSRange)range
     changeInLength:(int)delta invalidatedRange:(NSRange)invalidated {
    [super textStorage:storage edited:mask range:range changeInLength:delta invalidatedRange:invalidated];
    [self textEdited];
}
#else
- (void)processEditingForTextStorage:(NSTextStorage *)storage edited:(NSTextStorageEditActions)mask range:(NSRange)range
                      changeInLength:(NSInteger)delta invalidatedRange:(NSRange)invalidated {
    [super processEditingForTextStorage:storage edited:mask range:range changeInLength:delta invalidatedRange:invalidated];
    [self textEdited];
}
#endif

@end
