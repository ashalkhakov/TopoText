// SNTextSystem on UIKit (iOS).

#import "SNTextSystem.h"

@implementation SNTextAttachment
@end

#pragma mark fonts and colors

CGFloat SNSystemFontSize(NSString *style) {
    return [style isEqual:SNStyleTitle] ? 28 : [style isEqual:SNStyleHeading] ? 22 : [style isEqual:SNStyleSubheading] ? 18 : 17;
}

SNFont *SNSystemFont(CGFloat size, BOOL bold) {
    return bold ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
}

SNFont *SNSystemMonoFont(CGFloat size, BOOL bold) {
    return [UIFont monospacedSystemFontOfSize:size weight:bold ? UIFontWeightBold : UIFontWeightRegular];
}

SNFont *SNSystemFontWithTraits(SNFont *font, BOOL bold, BOOL italic) {
    UIFontDescriptorSymbolicTraits t = font.fontDescriptor.symbolicTraits;
    if (bold) t |= UIFontDescriptorTraitBold;
    if (italic) t |= UIFontDescriptorTraitItalic;
    UIFontDescriptor *d = [font.fontDescriptor fontDescriptorWithSymbolicTraits:t];
    return d ? [UIFont fontWithDescriptor:d size:font.pointSize] : font;
}

void SNSystemTraitsOf(SNFont *font, BOOL *bold, BOOL *italic) {
    UIFontDescriptorSymbolicTraits t = font.fontDescriptor.symbolicTraits;
    *bold = (t & UIFontDescriptorTraitBold) != 0;
    *italic = (t & UIFontDescriptorTraitItalic) != 0;
}

SNColor *SNSystemTextColor(void) {
    return [UIColor labelColor];
}

SNColor *SNSystemMarkerColor(void) {
    return [UIColor tertiaryLabelColor];
}

SNColor *SNSystemAccentColor(void) {
    return [UIColor systemOrangeColor];
}

SNColor *SNSystemGridColor(void) {
    return [UIColor systemGray3Color];
}

CGFloat SNSystemIndentStep(void) {
    return 28;
}

CGFloat SNSystemCheckboxSize(SNFont *font) {
    return round(font.pointSize * 1.25);
}

#pragma mark drawing

void SNSystemAddLine(SNPath *path, SNPoint from, SNPoint to) {
    [path moveToPoint:from];
    [path addLineToPoint:to];
}

#pragma mark images

BOOL SNSystemImagePixels(NSData *data, double *width, double *height) {
    UIImage *image = data.length ? [[UIImage alloc] initWithData:data] : nil;
    if (!image) return NO;
    *width = image.size.width * image.scale;
    *height = image.size.height * image.scale;
    return YES;
}

NSData *SNSystemScaledImage(NSData *data, NSUInteger width, NSUInteger height, BOOL png) {
    UIImage *image = [[UIImage alloc] initWithData:data];
    if (!image) return nil;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(width, height) format:format];
    UIImage *drawn = [r imageWithActions:^(UIGraphicsImageRendererContext *c) {
        [image drawInRect:CGRectMake(0, 0, width, height)];
    }];
    return png ? UIImagePNGRepresentation(drawn) : UIImageJPEGRepresentation(drawn, 0.85);
}

CGFloat SNSystemPointsPerPixel(void) {
    return 1.0 / [UIScreen mainScreen].scale;
}

#pragma mark attachments

/* A box to show while an attachment has not come yet. */
static UIImage *SNPlaceholderImage(SNSize size) {
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *c) {
        [[UIColor systemGray5Color] setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, size.width, size.height) cornerRadius:8] fill];
    }];
}

SNTextAttachment *SNSystemImageAttachment(NSData *data, NSString *type, SNSize size) {
    UIImage *image = data ? [[UIImage alloc] initWithData:data] : nil;
    SNTextAttachment *a = [[SNTextAttachment alloc] initWithData:image ? data : nil ofType:nil];
    a.image = image ?: SNPlaceholderImage(size);
    a.bounds = CGRectMake(0, 0, size.width, size.height);
    return a;
}

/* A file's card, Apple Notes' kind: a rounded box, an icon, the file's
   name, and under it what it is. */
SNTextAttachment *SNSystemFileAttachment(NSData *data, NSString *name, NSString *detail, CGFloat width) {
    CGSize size = CGSizeMake(MAX(160, width), 60);
    UIImage *card = [[[UIGraphicsImageRenderer alloc] initWithSize:size] imageWithActions:^(UIGraphicsImageRendererContext *c) {
        UIBezierPath *round = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(CGRectMake(0, 0, size.width, size.height), 0.5, 0.5)
                                                         cornerRadius:10];
        [[UIColor secondarySystemFillColor] setFill];
        [round fill];
        [[UIColor separatorColor] setStroke];
        [round stroke];
        UIImage *icon = [[UIImage systemImageNamed:@"doc.fill"] imageWithTintColor:[UIColor systemBlueColor]
                                                                     renderingMode:UIImageRenderingModeAlwaysOriginal];
        [icon drawInRect:CGRectMake(14, 14, 26, 32)];
        NSMutableParagraphStyle *clip = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
        clip.lineBreakMode = NSLineBreakByTruncatingTail;
        [name drawInRect:CGRectMake(52, 10, size.width - 62, 22)
          withAttributes:@{ NSFontAttributeName: [UIFont boldSystemFontOfSize:16], NSForegroundColorAttributeName: [UIColor labelColor],
                            NSParagraphStyleAttributeName: clip }];
        [detail drawInRect:CGRectMake(52, 33, size.width - 62, 18)
            withAttributes:@{ NSFontAttributeName: [UIFont systemFontOfSize:13], NSForegroundColorAttributeName: [UIColor secondaryLabelColor],
                              NSParagraphStyleAttributeName: clip }];
    }];
    SNTextAttachment *a = [[SNTextAttachment alloc] initWithData:nil ofType:nil];
    a.image = card;
    a.bounds = CGRectMake(0, 0, size.width, size.height);
    return a;
}

SNTextAttachment *SNSystemRoomAttachment(SNSize size) {
    SNTextAttachment *a = [[SNTextAttachment alloc] initWithData:nil ofType:nil];
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.opaque = NO;
    a.image = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(1, 1) format:format] imageWithActions:^(UIGraphicsImageRendererContext *c) {}];
    a.bounds = CGRectMake(0, 0, size.width, size.height);
    a.room = size;
    return a;
}

NSData *SNSystemDataOfAttachment(NSTextAttachment *a) {
    if (a.contents.length) return a.contents;
    if (a.fileWrapper.regularFile) return a.fileWrapper.regularFileContents;
    return a.image ? UIImagePNGRepresentation(a.image) : nil;
}

#pragma mark text views

CGFloat SNSystemContainerWidth(NSTextContainer *container) {
    return container.size.width;
}

SNPoint SNSystemTextOrigin(id<SNTextViewing> view) {
    UIEdgeInsets inset = [(UITextView *)view textContainerInset];
    return CGPointMake(inset.left, inset.top);
}

void SNSystemRedisplay(NSLayoutManager *layoutManager, NSRange range) {
    NSUInteger len = layoutManager.textStorage.length;
    range = NSIntersectionRange(range, NSMakeRange(0, len));
    if (range.length) [layoutManager invalidateDisplayForCharacterRange:range];
}

void SNSystemObserveResizing(id view, id observer, SEL selector) {
}

@implementation SNListLayoutManager (SNTextSystemEditing)

- (void)processEditingForTextStorage:(NSTextStorage *)storage edited:(NSTextStorageEditActions)mask range:(NSRange)range
                      changeInLength:(NSInteger)delta invalidatedRange:(NSRange)invalidated {
    [super processEditingForTextStorage:storage edited:mask range:range changeInLength:delta invalidatedRange:invalidated];
    [self textEdited];
}

@end
