#import "SNTextView.h"
#import "SNRichText.h"

/* SN_TYPING_TIMES set: how long each key takes, told every 40 keys on
   stderr (a machine where typing feels slow tells where the time goes):
   the key taken (the text system, and the note's binding), the text drawn
   after it, and the run loop round again (everything else it did). */
static BOOL SNTimesTyping(void) {
    static int times = -1;
    if (times < 0) times = getenv("SN_TYPING_TIMES") != NULL;
    return times;
}

static NSString *SNTypingSummary(NSMutableArray<NSNumber *> *ms) {
    [ms sortUsingSelector:@selector(compare:)];
    return ms.count ? [NSString stringWithFormat:@"median %.1f, worst %.1f", [ms[ms.count / 2] doubleValue], [ms.lastObject doubleValue]] : @"-";
}

@implementation SNTextView {
    NSDate *_keyAt;      /* the key being timed: when it came */
    BOOL _drawnSince;
    NSMutableArray<NSNumber *> *_taken, *_drawn, *_round;
}

- (void)keyDown:(NSEvent *)event {
    if (!SNTimesTyping()) {
        [super keyDown:event];
        return;
    }
    if (!_taken) {
        _taken = [NSMutableArray array];
        _drawn = [NSMutableArray array];
        _round = [NSMutableArray array];
    }
    NSDate *at = [NSDate date];
    _keyAt = at;
    _drawnSince = NO;
    [super keyDown:event];
    [_taken addObject:@(-at.timeIntervalSinceNow * 1000)];
    [self performSelector:@selector(keyCameRound:) withObject:at afterDelay:0];
}

- (void)drawRect:(NSRect)rect {
    [super drawRect:rect];
    if (_keyAt && !_drawnSince) {
        _drawnSince = YES;
        [_drawn addObject:@(-_keyAt.timeIntervalSinceNow * 1000)];
    }
}

- (void)keyCameRound:(NSDate *)at {
    [_round addObject:@(-at.timeIntervalSinceNow * 1000)];
    if (_round.count < 40) return;
    fprintf(stderr, "SimpleNotes typing, ms a key over %lu keys: taken %s; drawn %s; round %s\n", (unsigned long)_round.count,
            SNTypingSummary(_taken).UTF8String, SNTypingSummary(_drawn).UTF8String, SNTypingSummary(_round).UTF8String);
    [_taken removeAllObjects];
    [_drawn removeAllObjects];
    [_round removeAllObjects];
}

- (void)useListLayoutManager {
    if ([self.layoutManager isKindOfClass:[SNListLayoutManager class]]) return;
    [self.textContainer replaceLayoutManager:[[SNListLayoutManager alloc] init]];
}

- (NSString *)printJobTitle {
    return _printTitle ?: [super printJobTitle];
}

- (void)useFindInterface {
#ifdef GNUSTEP
    self.usesFindPanel = YES;
#else
    self.usesFindBar = YES;
    self.incrementalSearchingEnabled = YES;
#endif
}

- (IBAction)findAndReplace:(id)sender {
    NSMenuItem *action = [[NSMenuItem alloc] init];
#ifdef GNUSTEP
    action.tag = NSFindPanelActionShowFindPanel;
    [self performFindPanelAction:action];
#else
    action.tag = NSTextFinderActionShowReplaceInterface;
    [self performTextFinderAction:action];
#endif
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if (item.action == @selector(findAndReplace:)) return self.isEditable;
    return [super validateMenuItem:item];
}

/* The heading whose chevron is at a point of the view (NSNotFound: none). */
- (NSUInteger)sectionToggleAt:(NSPoint)p {
    SNListLayoutManager *lm = (SNListLayoutManager *)self.layoutManager;
    if (![lm isKindOfClass:[SNListLayoutManager class]]) return NSNotFound;
    NSPoint origin = self.textContainerOrigin;
    return [lm sectionToggleAtPoint:NSMakePoint(p.x - origin.x, p.y - origin.y)];
}

/* macOS's text view leaves a click in its inset to the clip view behind it;
   the chevrons drawn there are the text view's. */
- (NSView *)hitTest:(NSPoint)point {
    NSView *hit = [super hitTest:point];
    if (hit || !self.isEditable) return hit;
    NSPoint p = [self convertPoint:point fromView:self.superview];
    return NSPointInRect(p, self.bounds) && [self sectionToggleAt:p] != NSNotFound ? self : nil;
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
        at = [self sectionToggleAt:p];
        if (at != NSNotFound && [delegate respondsToSelector:@selector(textView:clickedSectionToggleAtIndex:)]) {
            [delegate textView:self clickedSectionToggleAtIndex:at];
            return;
        }
    }
    [super mouseDown:event];
}

@end
