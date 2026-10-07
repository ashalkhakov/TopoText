#import "SNPeersWindow.h"
#import "SNWindowController.h"

NSString * const SNServePeersDefaultsKey = @"SNServePeers";

@implementation SNPeersWindow

- (instancetype)initWithPeers:(SNPeers *)peers {
    if ((self = [super initWithWindowNibName:@"DevicesNearby"])) {
        _peers = peers;
        peers.delegate = self;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(peersChanged:)
                                                     name:SNPeersDidChangeNotification object:peers];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)windowDidLoad {
    [super windowDidLoad];
    _codeLabel.stringValue = @"";
    _statusLabel.stringValue = _peers.status;
    /* Looked for while it is open (and after: found stays known). */
    [_peers startBrowsing];
    [self refresh];
}

- (void)peersChanged:(NSNotification *)n {
    if (!self.isWindowLoaded) return;
    _statusLabel.stringValue = _peers.status;
    [self refresh];
}

- (ODataSyncPeerAnnouncement *)selectedDevice {
    NSInteger row = _devicesTable.selectedRow;
    NSArray *found = _peers.found;
    return row >= 0 && row < (NSInteger)found.count ? found[row] : nil;
}

- (void)refresh {
    _serveButton.state = _peers.serving ? NSControlStateValueOn : NSControlStateValueOff;
    _servingLabel.stringValue = _peers.serving ? [NSString stringWithFormat:@"Served at %@", _peers.serviceRoot.host] : @"Not served.";
    if (_peers.fetchingToken) _tokenLabel.stringValue = @"Asking the server for a peer token…";
    else if (_peers.hasToken)
        _tokenLabel.stringValue = [NSString stringWithFormat:@"Peer token until %@.",
                                   [NSDateFormatter localizedStringFromDate:_peers.tokenExpires ?: [NSDate distantFuture]
                                                                  dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle]];
    else _tokenLabel.stringValue = _peers.notes.serverRemote ? @"No peer token." : @"No peer token: this computer syncs with no server.";
    _tokenButton.enabled = _peers.notes.serverRemote != nil && !_peers.fetchingToken;
    _showCodeButton.enabled = _peers.serving;
    if (!_peers.serving) _codeLabel.stringValue = @"";
    _codeCopyButton.enabled = _codeLabel.stringValue.length > 0;
    [_devicesTable reloadData];
    [self selectionChanged];
}

- (void)selectionChanged {
    ODataSyncPeerAnnouncement *device = [self selectedDevice];
    _syncButton.enabled = device && !_peers.notes.syncing && (_peers.hasToken || [_peers pairingOfPeer:device]);
    _forgetButton.enabled = device && [_peers pairingOfPeer:device];
}

#pragma mark serving

- (IBAction)toggleServing:(id)sender {
    BOOL serve = _serveButton.state == NSControlStateValueOn;
    [[NSUserDefaults standardUserDefaults] setBool:serve forKey:SNServePeersDefaultsKey];
    if (!serve) {
        [_peers stopServing];
        return;
    }
    NSError *error = nil;
    if (![_peers startServing:&error]) {
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:SNServePeersDefaultsKey];
        [self refresh];
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Your notes cannot be served to devices nearby.";
        alert.informativeText = error.localizedDescription ?: @"";
        [alert beginSheetModalForWindow:self.window completionHandler:nil];
    }
}

- (IBAction)getToken:(id)sender {
    [_peers fetchToken];
}

#pragma mark the devices

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)_peers.found.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    NSArray *found = _peers.found;
    if (row < 0 || row >= (NSInteger)found.count) return nil;
    ODataSyncPeerAnnouncement *device = found[row];
    if (![column.identifier isEqual:@"trust"]) return device.name;
    if ([_peers pairingOfPeer:device]) return @"Pairing";
    return _peers.hasToken ? @"Peer token" : @"—";
}

- (void)tableViewSelectionDidChange:(NSNotification *)n {
    [self selectionChanged];
}

- (IBAction)syncWithDevice:(id)sender {
    ODataSyncPeerAnnouncement *device = [self selectedDevice];
    if (device) [_peers syncWithPeer:device];
}

- (IBAction)forgetPairing:(id)sender {
    ODataSyncPeerPairing *pairing = [self selectedDevice] ? [_peers pairingOfPeer:[self selectedDevice]] : nil;
    if (pairing) [_peers forgetPairing:pairing error:NULL];
}

#pragma mark pairing

- (IBAction)showPairingCode:(id)sender {
    _codeLabel.stringValue = [_peers newPairingOffer] ?: @"";
    _statusLabel.stringValue = _codeLabel.stringValue.length ? @"On the other device, Pair With Code… and paste this (good for two minutes, once)." : @"";
    [self refresh];
}

- (IBAction)copyPairingCode:(id)sender {
    if (!_codeLabel.stringValue.length) return;
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:_codeLabel.stringValue forType:NSPasteboardTypeString];
}

- (IBAction)pairWithCode:(id)sender {
    NSString *pasted = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString];
    BOOL looksLikeOne = [pasted containsString:@"\"thumbprint\""] || [pasted containsString:@"\"code\""];
    NSString *code = SNAskForText(@"Pair With Code", @"The other device's pairing code (Show Pairing Code there):", looksLikeOne ? pasted : @"");
    if (code.length) [_peers pairWithOffer:code];
}

- (void)peers:(SNPeers *)peers didPairWithError:(NSError *)error {
    if (!error || !self.isWindowLoaded) return;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Not paired.";
    alert.informativeText = error.localizedDescription ?: @"";
    [alert beginSheetModalForWindow:self.window completionHandler:nil];
}

@end
