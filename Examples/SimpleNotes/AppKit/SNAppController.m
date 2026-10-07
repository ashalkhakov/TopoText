#import "SNAppController.h"
#import "SNNotes.h"
#import "SNWindowController.h"
#import "SNSelfTest.h"
#import "SNSyncPanel.h"
#import "SNPeersWindow.h"

NSString * const SNServerDefaultsKey = @"SNServer";
/* Whether where to keep the notes was chosen once (else Sync… opens). */
static NSString * const SNSyncChosenDefaultsKey = @"SNSyncChosen";

@interface SNAppController () <SNSyncPanelDelegate>
@end

@implementation SNAppController {
    SNNotes *_notes;
    SNWindowController *_window;
    /* The server's sign-in (its credentials, for each sync). */
    SNSignIn *_signIn;
    SNSyncPanel *_panel;
    /* Devices nearby (nil: this computer has no identity for them). */
    SNPeers *_peers;
    NSError *_peersError;
    NSURL *_store;
    SNPeersWindow *_peersWindow;
}

- (void)applicationDidFinishLaunching:(NSNotification *)n {
    NSError *error = nil;
    /* -SNStore path: another device on this machine, for trying sync out. */
    NSString *path = [[NSUserDefaults standardUserDefaults] stringForKey:@"SNStore"];
    if (SNSelfTestRoot && !path.length)
        path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                   [NSString stringWithFormat:@"sn-selftest-app-%@.sqlite", [NSProcessInfo processInfo].globallyUniqueString]];
    NSURL *store = path.length ? [NSURL fileURLWithPath:path] : [SNNotes defaultStoreURLNamed:@"SimpleNotes"];
    _notes = [[SNNotes alloc] initWithStoreURL:store error:&error];
    if (!_notes) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"The notes cannot be opened.";
        alert.informativeText = error.localizedDescription ?: @"";
        [alert runModal];
        [NSApp terminate:nil];
        return;
    }
    NSString *server = [[NSUserDefaults standardUserDefaults] stringForKey:SNServerDefaultsKey];
    NSURL *root = server.length ? [NSURL URLWithString:server] : nil;
    if (root) {
        /* Signed in as it was last time: the tokens kept for it. */
        _signIn = [[SNSignIn alloc] initWithServiceRoot:root secrets:[[SNSecretStore alloc] init]];
        _notes.configuration = _signIn.configuration;
        _notes.serviceRoot = root;
    }
    _notes.syncInterval = 30;
    _window = [[SNWindowController alloc] initWithNotes:_notes];
    [_window showWindow:nil];
    /* --self-test <root>: driven from within (SNSelfTest.h), on a store
       of its own. */
    if (SNSelfTestRoot) {
        _notes.serviceRoot = SNSelfTestRoot;
        _notes.syncInterval = 0;
        [_notes sync];
        SNStartSelfTest(_notes, _window, _notes.serviceRoot);
        return;
    }
    [_notes sync];
    _store = store;
    /* Served again if it was; else made when Devices Nearby opens (its
       identity is a key in the keychain: none made for nothing). */
    if ([[NSUserDefaults standardUserDefaults] boolForKey:SNServePeersDefaultsKey] && [self makePeers]) [_peers startServing:NULL];
    /* The first time: where to keep the notes, chosen. */
    if (![[NSUserDefaults standardUserDefaults] boolForKey:SNSyncChosenDefaultsKey] && !root) [self chooseServer:nil];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app {
    return YES;
}

/* Its files beside the store's; a token asked for once there is a server
   to ask. */
- (SNPeers *)makePeers {
    if (_peers) return _peers;
    NSError *error = nil;
    _peers = [[SNPeers alloc] initWithNotes:_notes directory:[_store.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"Peers" isDirectory:YES]
                                      error:&error];
    _peersError = error;
    [self fetchPeerTokenIfNeeded];
    return _peers;
}

- (void)fetchPeerTokenIfNeeded {
    if (_peers && _notes.serverRemote && !_peers.hasToken) [_peers fetchToken];
}

- (IBAction)showDevicesNearby:(id)sender {
    if (![self makePeers]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Devices nearby cannot be synced with.";
        alert.informativeText = _peersError.localizedDescription ?: @"";
        [alert runModal];
        return;
    }
    if (!_peersWindow) _peersWindow = [[SNPeersWindow alloc] initWithPeers:_peers];
    [_peersWindow showWindow:nil];
}

- (void)applicationWillTerminate:(NSNotification *)n {
    [_peers stop];
    [_window closeEditor];
    [_notes saveAll];
}

- (void)applicationDidBecomeActive:(NSNotification *)n {
    if (_notes.serviceRoot && !_notes.syncing) [_notes sync];
}

- (IBAction)showNotes:(id)sender {
    [_window showWindow:nil];
}

/* Sync…: this computer only, or a server and its sign-in (SNSyncPanel). */
- (IBAction)chooseServer:(id)sender {
    _panel = [[SNSyncPanel alloc] initWithServer:_notes.serviceRoot];
    _panel.delegate = self;
    [_panel.window center];
    [_panel showWindow:nil];
}

- (void)syncPanel:(SNSyncPanel *)panel didChooseServer:(NSURL *)root signIn:(SNSignIn *)signIn {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:YES forKey:SNSyncChosenDefaultsKey];
    if (root) [defaults setObject:root.absoluteString forKey:SNServerDefaultsKey];
    else [defaults removeObjectForKey:SNServerDefaultsKey];
    _signIn = signIn;
    signIn.delegate = nil;
    _notes.configuration = signIn ? signIn.configuration : nil;
    _notes.serviceRoot = root;
    [_notes sync];
    [self fetchPeerTokenIfNeeded];
}

@end
