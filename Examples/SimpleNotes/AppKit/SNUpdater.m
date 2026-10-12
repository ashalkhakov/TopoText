#import "SNUpdater.h"

/* GNUstep: the AppImage is updated from outside it (SNUpdater.h). */
@implementation SNUpdater

- (instancetype)initStarting:(BOOL)start {
    return [super init];
}

- (BOOL)available {
    return NO;
}

- (BOOL)canCheckForUpdates {
    return NO;
}

- (IBAction)checkForUpdates:(id)sender {
}

@end
