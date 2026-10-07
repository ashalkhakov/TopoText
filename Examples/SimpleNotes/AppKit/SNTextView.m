#import "SNTextView.h"
#import "SNRichText.h"

@implementation SNTextView

- (void)useListLayoutManager {
    if ([self.layoutManager isKindOfClass:[SNListLayoutManager class]]) return;
    [self.textContainer replaceLayoutManager:[[SNListLayoutManager alloc] init]];
}

- (void)mouseDown:(NSEvent *)event {
    SNListLayoutManager *lm = (SNListLayoutManager *)self.layoutManager;
    id<SNTextViewDelegate> delegate = (id<SNTextViewDelegate>)self.delegate;
    if (self.isEditable && [lm isKindOfClass:[SNListLayoutManager class]] &&
        [delegate respondsToSelector:@selector(textView:clickedCheckboxAtIndex:)]) {
        NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
        NSPoint origin = self.textContainerOrigin;
        NSUInteger at = [lm checkboxAtPoint:NSMakePoint(p.x - origin.x, p.y - origin.y)];
        if (at != NSNotFound) {
            [delegate textView:self clickedCheckboxAtIndex:at];
            return;
        }
    }
    [super mouseDown:event];
}

@end
