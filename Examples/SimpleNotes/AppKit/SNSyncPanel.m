#import "SNSyncPanel.h"
#import "SNWindowController.h"

NSURL *SNServiceRootOf(NSString *typed) {
    typed = [typed stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!typed.length) return nil;
    if (![typed hasSuffix:@"/"]) typed = [typed stringByAppendingString:@"/"];
    NSURL *root = [NSURL URLWithString:typed];
    BOOL web = [root.scheme isEqual:@"http"] || [root.scheme isEqual:@"https"];
    return web && root.host.length ? root : nil;
}

@implementation SNSyncPanel {
    NSURL *_current;
    NSURL *_page;
    BOOL _showingCode;
    /* Why the last sign-in failed, until another begins. */
    NSString *_failure;
    /* What a sign-in learnt is waited for by: Sign In, OK. */
    BOOL _signInWhenLearnt, _okWhenLearnt;
}

- (instancetype)initWithServer:(NSURL *)serviceRoot {
    if ((self = [super initWithWindowNibName:@"SyncPanel"])) {
        _current = serviceRoot;
        _secrets = [[SNSecretStore alloc] init];
    }
    return self;
}

- (void)windowDidLoad {
    [super windowDidLoad];
    _serverField.stringValue = _current.absoluteString ?: @"";
    _serverField.delegate = self;
    [self choose:_current != nil];
}

#pragma mark the choice

- (BOOL)syncs {
    return _serverButton.state == NSControlStateValueOn;
}

- (void)choose:(BOOL)server {
    _serverButton.state = server ? NSControlStateValueOn : NSControlStateValueOff;
    _localButton.state = server ? NSControlStateValueOff : NSControlStateValueOn;
    [self refresh];
}

- (IBAction)keepLocal:(id)sender {
    [self choose:NO];
}

- (IBAction)syncWithServer:(id)sender {
    [self choose:YES];
    [self.window makeFirstResponder:_serverField];
}

/* The sign-in of the address typed: the one made already, or a new one
   (what it keeps, the Keychain's, comes with it). */
- (SNSignIn *)signInForTyped {
    NSURL *root = SNServiceRootOf(_serverField.stringValue);
    if (!root) return nil;
    if (![_signIn.serviceRoot isEqual:root]) {
        [_signIn cancel];
        _signIn = [[SNSignIn alloc] initWithServiceRoot:root secrets:_secrets];
        _signIn.delegate = self;
        _showingCode = NO;
    }
    return _signIn;
}

- (void)refresh {
    BOOL server = [self syncs];
    _warningLabel.hidden = server;
    _serverField.enabled = server;
    SNSignIn *s = server ? [self signInForTyped] : nil;
    NSString *status = @"";
    if (server && !s) status = @"Type the server's address.";
    else if (s.kind == SNSignInNone) status = @"This server asks for no sign-in.";
    else if (s.signedIn) status = s.userName.length ? [NSString stringWithFormat:@"Signed in as %@.", s.userName] : @"Signed in.";
    else if (s && _failure.length) status = [NSString stringWithFormat:@"Not signed in: %@", _failure];
    else if (s) status = @"Not signed in.";
    _statusLabel.stringValue = status;
    _statusLabel.toolTip = status;
    _signInButton.enabled = s && !s.signedIn && !_showingCode;
    _signOutButton.enabled = s.signedIn && s.kind != SNSignInNone;
    for (NSView *v in @[ _codeHintLabel, _pageLabel, _codeLabel, _openPageButton, _waitingLabel ]) v.hidden = !_showingCode;
}

- (void)controlTextDidChange:(NSNotification *)n {
    [self refresh];
}

#pragma mark signing in

- (IBAction)signIn:(id)sender {
    _failure = nil;
    SNSignIn *s = [self signInForTyped];
    if (!s) {
        NSBeep();
        return;
    }
    if (s.kind == SNSignInUnknown) {
        _signInWhenLearnt = YES;
        _statusLabel.stringValue = @"Asking the server how to sign in…";
        [s learn];
        return;
    }
    if (s.kind == SNSignInPassword) {
        NSString *user = SNAskForText(@"Sign In", @"User name:", @"");
        if (!user.length) return;
        NSString *password = SNAskForText(@"Sign In", [NSString stringWithFormat:@"Password for %@:", user], @"");
        if (!password) return;
        [s signInWithUser:user password:password];
        return;
    }
    [s begin];
}

- (IBAction)signOut:(id)sender {
    [_signIn signOut];
    _showingCode = NO;
    [self refresh];
}

- (IBAction)openPage:(id)sender {
    if (_page) [[NSWorkspace sharedWorkspace] openURL:_page];
}

- (void)signInDidLearn:(SNSignIn *)signIn {
    [self refresh];
    if (_signInWhenLearnt) {
        _signInWhenLearnt = NO;
        if (signIn.kind != SNSignInNone) [self signIn:nil];
    }
    if (_okWhenLearnt) {
        _okWhenLearnt = NO;
        [self ok:nil];
    }
}

- (void)signIn:(SNSignIn *)signIn showCode:(NSString *)code page:(NSURL *)page completePage:(NSURL *)completePage {
    _showingCode = YES;
    _page = completePage ?: page;
    _codeLabel.stringValue = code;
    _pageLabel.stringValue = page.absoluteString;
    [self refresh];
    /* The page opened at once, the code filled in where the provider can. */
    [self openPage:nil];
}

- (void)signInDidFinish:(SNSignIn *)signIn {
    _showingCode = NO;
    [self refresh];
}

- (void)signIn:(SNSignIn *)signIn didFail:(NSError *)error {
    _showingCode = NO;
    _failure = error.localizedDescription;
    _signInWhenLearnt = _okWhenLearnt = NO;
    [self refresh];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Not signed in.";
    alert.informativeText = error.localizedDescription ?: @"";
    [alert beginSheetModalForWindow:self.window completionHandler:nil];
}

#pragma mark done

- (IBAction)ok:(id)sender {
    id<SNSyncPanelDelegate> delegate = _delegate;
    if (![self syncs]) {
        /* From syncing to this computer only: said plainly first. */
        if (_current) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"Keep notes on this computer only?";
            alert.informativeText = @"They will no longer sync, and nothing backs them up. The notes here stay as they are.";
            [alert addButtonWithTitle:@"This Computer Only"];
            [alert addButtonWithTitle:@"Cancel"];
            if ([alert runModal] != NSAlertFirstButtonReturn) return;
        }
        [_signIn cancel];
        [delegate syncPanel:self didChooseServer:nil signIn:nil];
        [self close];
        return;
    }
    SNSignIn *s = [self signInForTyped];
    if (!s) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"That is not a server's address.";
        alert.informativeText = @"For example: https://notes.example.com/odata/";
        [alert beginSheetModalForWindow:self.window completionHandler:nil];
        return;
    }
    if (s.kind == SNSignInUnknown) {
        _okWhenLearnt = YES;
        _statusLabel.stringValue = @"Asking the server how to sign in…";
        [s learn];
        return;
    }
    if (!s.signedIn) {
        [self signIn:nil];
        return;
    }
    [delegate syncPanel:self didChooseServer:s.serviceRoot signIn:s];
    [self close];
}

- (IBAction)cancel:(id)sender {
    [_signIn cancel];
    [self close];
}

@end
