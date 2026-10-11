// A menu's item as target-action (SNMenuAction.h).

#import "SNMenuAction.h"

UIAction *SNMenuAction(NSString *title, UIImage *image, SEL action, id target) {
    __weak id weakTarget = target;
    BOOL toFirstResponder = target == nil;
    return [UIAction actionWithTitle:title image:image identifier:nil handler:^(UIAction *sent) {
        id to = weakTarget;
        if (!to && !toFirstResponder) return;
        [[UIApplication sharedApplication] sendAction:action to:to from:sent forEvent:nil];
    }];
}
