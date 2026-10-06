#import "SNAppController.h"
#import "SNNotes.h"
#import "SNWindowController.h"
#import "SNSelfTest.h"

NSString * const SNServerDefaultsKey = @"SNServer";

@implementation SNAppController {
    SNNotes *_notes;
    SNWindowController *_window;
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
    if (server.length) _notes.serviceRoot = [NSURL URLWithString:server];
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
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app {
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)n {
    [_window closeEditor];
    [_notes saveAll];
}

- (void)applicationDidBecomeActive:(NSNotification *)n {
    if (_notes.serviceRoot && !_notes.syncing) [_notes sync];
}

- (IBAction)showNotes:(id)sender {
    [_window showWindow:nil];
}

- (IBAction)chooseServer:(id)sender {
    NSString *now = _notes.serviceRoot.absoluteString ?: @"http://127.0.0.1:8080/odata/";
    NSString *typed = SNAskForText(@"Server", @"The SimpleNotes server's address (empty: this device only):", now);
    if (!typed) return;
    typed = [typed stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (typed.length && ![typed hasSuffix:@"/"]) typed = [typed stringByAppendingString:@"/"];
    NSURL *root = typed.length ? [NSURL URLWithString:typed] : nil;
    if (typed.length && (!root.host.length || !([root.scheme isEqual:@"http"] || [root.scheme isEqual:@"https"]))) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"That is not a server's address.";
        alert.informativeText = @"For example: http://192.168.1.10:8080/odata/";
        [alert runModal];
        return;
    }
    if (root) [[NSUserDefaults standardUserDefaults] setObject:root.absoluteString forKey:SNServerDefaultsKey];
    else [[NSUserDefaults standardUserDefaults] removeObjectForKey:SNServerDefaultsKey];
    _notes.serviceRoot = root;
    [_notes sync];
}

@end
