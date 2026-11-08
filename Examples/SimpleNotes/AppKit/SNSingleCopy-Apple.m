// macOS's half: Launch Services keeps one copy of the app already, and
// shows its window when it is opened again; a second runs only when asked
// for (open -n), and finding the store held, brings the first to the front.

#import <AppKit/AppKit.h>
#import "SNSingleCopy.h"

BOOL SNHoldStore(NSURL *store, id target, SEL action) {
    if (SNLockFileForLife([store.path stringByAppendingString:@".lock"])) return YES;
    NSRunningApplication *me = [NSRunningApplication currentApplication];
    for (NSRunningApplication *app in [NSRunningApplication runningApplicationsWithBundleIdentifier:me.bundleIdentifier ?: @""])
        if (app.processIdentifier != me.processIdentifier) [app activateWithOptions:NSApplicationActivateAllWindows];
    return NO;
}
