// SimpleNotes on iOS: the app's delegate, its window, a sync on opening.

#import <UIKit/UIKit.h>
#import "SNiOSControllers.h"
#import "SNiOSSelfTest.h"

@interface SNiOSAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) SNNotes *notes;
@property (nonatomic, strong) SNSignIn *signIn;
@end

@implementation SNiOSAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    NSError *error = nil;
    NSArray *args = [NSProcessInfo processInfo].arguments;
    NSUInteger i = [args indexOfObject:@"--self-test"];
    if (i != NSNotFound && i + 1 < args.count) SNSelfTestRoot = [NSURL URLWithString:args[i + 1]];
    /* A self-test runs on a store of its own. */
    NSURL *store = SNSelfTestRoot ? [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
                                                                [NSString stringWithFormat:@"sn-selftest-app-%@.sqlite", [NSProcessInfo processInfo].globallyUniqueString]]]
                                  : [SNNotes defaultStoreURLNamed:@"SimpleNotes"];
    _notes = [[SNNotes alloc] initWithStoreURL:store error:&error];
    if (!_notes) NSLog(@"SimpleNotes: the notes do not open: %@", error);
    NSString *server = [[NSUserDefaults standardUserDefaults] stringForKey:SNServerDefaultsKey];
    if (server.length) {
        /* Signed in as it was last time: the tokens kept for it. */
        NSURL *root = [NSURL URLWithString:server];
        _signIn = [[SNSignIn alloc] initWithServiceRoot:root secrets:[[SNSecretStore alloc] init]];
        _notes.configuration = _signIn.configuration;
        _notes.serviceRoot = root;
    }
    if (SNSelfTestRoot) _notes.serviceRoot = SNSelfTestRoot;
    else _notes.syncInterval = 30;
    SNFoldersViewController *folders = [[SNFoldersViewController alloc] initWithNotes:_notes];
    folders.peersDirectory = [store.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"Peers" isDirectory:YES];
    /* Synced with devices nearby again if it was (served, and syncing by
       itself, while the app is open). */
    if (!SNSelfTestRoot && [[NSUserDefaults standardUserDefaults] boolForKey:SNServePeersDefaultsKey]) {
        [[folders peers] startServing:NULL];
        [folders peers].automatic = YES;
    }
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:folders];
    nav.navigationBar.prefersLargeTitles = YES;
    _window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    _window.rootViewController = nav;
    [_window makeKeyAndVisible];
    if (SNSelfTestRoot) {
        [_notes sync];
        SNStartSelfTest(_notes, nav);
    }
    return YES;
}

/* Opened, or back: the server's changes met, what waits sent. */
- (void)applicationDidBecomeActive:(UIApplication *)application {
    if (_notes.serviceRoot && !_notes.syncing) [_notes sync];
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    [_notes saveAll];
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([SNiOSAppDelegate class]));
    }
}
