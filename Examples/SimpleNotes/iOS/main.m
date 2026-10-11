// SimpleNotes on iOS: the app's delegate, its window, a sync on opening.

#import <UIKit/UIKit.h>
#import "SNiOSControllers.h"
#import "SNiOSSelfTest.h"

@interface SNiOSAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) SNNotes *notes;
@property (nonatomic, strong) ODataSignIn *signIn;
@end

/* Shown while a store of an older version is brought up to this one. */
@interface SNUpdatingViewController : UIViewController
@end

@implementation SNUpdatingViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    [spinner startAnimating];
    UILabel *label = [[UILabel alloc] init];
    label.text = @"Updating your notes for this version of SimpleNotes…\nThis is done once, and can take a minute.";
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = [UIColor secondaryLabelColor];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[ spinner, label ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 16;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[ [stack.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
                                               [stack.leadingAnchor constraintEqualToAnchor:self.view.layoutMarginsGuide.leadingAnchor],
                                               [stack.trailingAnchor constraintEqualToAnchor:self.view.layoutMarginsGuide.trailingAnchor] ]];
}
@end

@implementation SNiOSAppDelegate {
    NSURL *_store;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    NSArray *args = [NSProcessInfo processInfo].arguments;
    NSUInteger i = [args indexOfObject:@"--self-test"];
    if (i != NSNotFound && i + 1 < args.count) SNSelfTestRoot = [NSURL URLWithString:args[i + 1]];
    /* A self-test runs on a store of its own. */
    NSURL *store = SNSelfTestRoot ? [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
                                                                [NSString stringWithFormat:@"sn-selftest-app-%@.sqlite", [NSProcessInfo processInfo].globallyUniqueString]]]
                                  : [SNNotes defaultStoreURLNamed:@"SimpleNotes"];
    _store = store;
    _window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    /* Made by an older version: brought up to this one off the main thread
       (a minute, with many files), the user told meanwhile; then opened. */
    if ([SNNotes storeNeedsUpdateAt:store]) {
        _window.rootViewController = [[SNUpdatingViewController alloc] init];
        [_window makeKeyAndVisible];
        [self performSelectorInBackground:@selector(updateStore:) withObject:store];
        return YES;
    }
    [self openNotes:nil];
    return YES;
}

/* On a thread of its own. */
- (void)updateStore:(NSURL *)store {
    @autoreleasepool {
        NSError *error = nil;
        BOOL updated = [SNNotes updateStoreAt:store error:&error];
        if (!updated) NSLog(@"SimpleNotes: the notes were not updated: %@", error);
        [self performSelectorOnMainThread:@selector(openNotes:) withObject:nil waitUntilDone:NO];
    }
}

/* The store opened, and the folders shown. */
- (void)openNotes:(id)sender {
    NSError *error = nil;
    NSURL *store = _store;
    _notes = [[SNNotes alloc] initWithStoreURL:store error:&error];
    if (!_notes) NSLog(@"SimpleNotes: the notes do not open: %@", error);
    NSString *server = [[NSUserDefaults standardUserDefaults] stringForKey:SNServerDefaultsKey];
    if (server.length) {
        /* Signed in as it was last time: the tokens kept for it. */
        NSURL *root = [NSURL URLWithString:server];
        _signIn = SNSignInTo(root, [[SNSecretStore alloc] init]);
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
    _window.rootViewController = nav;
    [_window makeKeyAndVisible];
    if (SNSelfTestRoot) {
        [_notes sync];
        SNStartSelfTest(_notes, nav);
    }
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
