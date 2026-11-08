// GNUstep's half (Linux and Windows): nothing else keeps a second copy
// from starting, so the copy holding the store answers a message port
// named for it. macOS: SNSingleCopy-Apple.m.

#import <AppKit/AppKit.h>
#import "SNSingleCopy.h"

/* What a copy asks of the one holding the store, through a message port
   named for the store. */
@protocol SNHolding
- (oneway void)showYourself;
@end

@interface SNHolder : NSObject <SNHolding>
@property (nonatomic, weak) id target;
@property (nonatomic) SEL action;
@end

@implementation SNHolder
- (oneway void)showYourself {
    [NSApp activateIgnoringOtherApps:YES];
    void (*send)(id, SEL, id) = (void (*)(id, SEL, id))[_target methodForSelector:_action];
    if (send) send(_target, _action, self);
}
@end

/* The port's name: the store's path, hashed (FNV-1a), short enough for a
   name server that makes a file of each name. */
static NSString *SNPortNameOf(NSURL *store) {
    uint64_t hash = 14695981039346656037ULL;
    for (const unsigned char *c = (const unsigned char *)store.path.UTF8String; *c; c++) hash = (hash ^ *c) * 1099511628211ULL;
    return [NSString stringWithFormat:@"SimpleNotes-%016llx", (unsigned long long)hash];
}

/* Kept: it answers while the app runs. */
static NSConnection *SNHolding;

BOOL SNHoldStore(NSURL *store, id target, SEL action) {
    NSString *name = SNPortNameOf(store);
    NSPortNameServer *names = [NSMessagePortNameServer sharedInstance];
    if (!SNLockFileForLife([store.path stringByAppendingString:@".lock"])) {
        NSConnection *connection = [NSConnection connectionWithRegisteredName:name host:nil usingNameServer:names];
        if (!connection) {
            NSLog(@"SimpleNotes is open on %@ already, and cannot be asked to show itself", store.path);
            return NO;
        }
        connection.requestTimeout = 5;
        connection.replyTimeout = 5;
        @try {
            NSDistantObject *holder = connection.rootProxy;
            [holder setProtocolForProxy:@protocol(SNHolding)];
            [(id<SNHolding>)holder showYourself];
        } @catch (NSException *exception) {
            NSLog(@"SimpleNotes is open on %@ already, and did not answer: %@", store.path, exception.reason);
        }
        return NO;
    }
    SNHolder *holder = [[SNHolder alloc] init];
    holder.target = target;
    holder.action = action;
    SNHolding = [[NSConnection alloc] initWithReceivePort:[NSMessagePort port] sendPort:nil];
    SNHolding.rootObject = holder;
    /* Asked while a menu is open or an alert is up, too; and while this
       thread waits for a reply of its own. */
    [SNHolding addRequestMode:NSModalPanelRunLoopMode];
    [SNHolding addRequestMode:NSEventTrackingRunLoopMode];
    [SNHolding addRequestMode:NSConnectionReplyMode];
    if (![SNHolding registerName:name withNameServer:names])
        NSLog(@"SimpleNotes holds %@, but another copy cannot ask it to show itself (%@ not registered)", store.path, name);
    return YES;
}
