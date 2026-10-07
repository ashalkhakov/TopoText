#import "SNUndoTextView.h"
#import "SNRichText.h"

@implementation SNUndoManager

- (void)registerUndoWithTarget:(id)target selector:(SEL)selector object:(id)object {
    if ([target isKindOfClass:[SNTextBinding class]]) [super registerUndoWithTarget:target selector:selector object:object];
}

- (void)registerUndoWithTarget:(id)target handler:(void (^)(id))handler {
    if ([target isKindOfClass:[SNTextBinding class]]) [super registerUndoWithTarget:target handler:handler];
}

- (id)prepareWithInvocationTarget:(id)target {
    return [target isKindOfClass:[SNTextBinding class]] ? [super prepareWithInvocationTarget:target] : nil;
}

@end

@implementation SNUndoTextView {
    SNUndoManager *_undo;
}

- (NSUndoManager *)undoManager {
    if (_followsSuperview && self.superview) return self.superview.undoManager;
    if (!_undo) _undo = [[SNUndoManager alloc] init];
    return _undo;
}

@end
