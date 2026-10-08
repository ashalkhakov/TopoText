#import "SNPeersViewController.h"

typedef NS_ENUM(NSInteger, SNPeersSection) {
    SNPeersSectionThisDevice,
    SNPeersSectionFound,
    SNPeersSectionPairing,
    SNPeersSectionCount
};

@implementation SNPeersViewController {
    UISwitch *_serveSwitch;
}

- (instancetype)initWithPeers:(SNPeers *)peers {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _peers = peers;
        peers.delegate = self;
        self.title = @"Devices Nearby";
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(peersChanged:)
                                                     name:SNPeersDidChangeNotification object:peers];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                                           target:self action:@selector(done:)];
    _serveSwitch = [[UISwitch alloc] init];
    [_serveSwitch addTarget:self action:@selector(toggleServing:) forControlEvents:UIControlEventValueChanged];
    /* Looked for while it is open (and after: found stays known). */
    [_peers startBrowsing];
}

- (void)peersChanged:(NSNotification *)n {
    if (self.isViewLoaded) [self.tableView reloadData];
}

- (IBAction)done:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark the table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return SNPeersSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case SNPeersSectionThisDevice: return 2;
        case SNPeersSectionFound: return MAX((NSInteger)_peers.found.count, 1);
        default: return 2;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case SNPeersSectionThisDevice: return @"This Device";
        case SNPeersSectionFound: return @"Devices Nearby";
        default: return @"Pairing";
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch (section) {
        case SNPeersSectionThisDevice:
            return _peers.status.length ? _peers.status
                                        : @"Your other devices signed in to the same server sync with this one by its peer token, even offline. "
                                          @"Served while SimpleNotes is open.";
        case SNPeersSectionFound: return @"Tap a device to sync with it.";
        default: return @"A device on no server of yours: pair with it once.";
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    if (indexPath.section == SNPeersSectionThisDevice && indexPath.row == 0) {
        cell.textLabel.text = @"Serve My Notes";
        _serveSwitch.on = _peers.serving;
        cell.accessoryView = _serveSwitch;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.detailTextLabel.text = nil;
    } else if (indexPath.section == SNPeersSectionThisDevice) {
        cell.textLabel.text = @"Peer Token";
        if (_peers.fetchingToken) cell.detailTextLabel.text = @"Asking…";
        else if (_peers.hasToken)
            cell.detailTextLabel.text = [NSString stringWithFormat:@"until %@",
                                         [NSDateFormatter localizedStringFromDate:_peers.tokenExpires ?: [NSDate distantFuture]
                                                                        dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle]];
        else cell.detailTextLabel.text = _peers.notes.serverRemote ? @"Get One" : @"No server";
        BOOL can = _peers.notes.serverRemote != nil && !_peers.fetchingToken;
        cell.textLabel.enabled = can;
        cell.selectionStyle = can ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    } else if (indexPath.section == SNPeersSectionFound) {
        NSArray *found = _peers.found;
        if (!found.count) {
            cell.textLabel.text = @"Looking…";
            cell.textLabel.textColor = [UIColor secondaryLabelColor];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            return cell;
        }
        ODataSyncPeerAnnouncement *device = found[indexPath.row];
        cell.textLabel.text = device.name;
        if ([_peers pairingOfPeer:device]) cell.detailTextLabel.text = @"Paired";
        else cell.detailTextLabel.text = _peers.hasToken ? @"Peer token" : @"—";
    } else {
        cell.textLabel.text = indexPath.row == 0 ? @"Show Pairing Code" : @"Pair With Code…";
        cell.textLabel.textColor = [UIColor tintColor];
        BOOL can = indexPath.row == 1 || _peers.serving;
        cell.textLabel.enabled = can;
        cell.selectionStyle = can ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == SNPeersSectionThisDevice && indexPath.row == 1) [self getToken:nil];
    else if (indexPath.section == SNPeersSectionFound && indexPath.row < (NSInteger)_peers.found.count)
        [_peers syncWithPeer:_peers.found[indexPath.row]];
    else if (indexPath.section == SNPeersSectionPairing) {
        if (indexPath.row == 0) [self showPairingCode:nil];
        else [self pairWithCode:nil];
    }
}

/* A paired device's row: Forget, as the desktop's Forget Pairing. */
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != SNPeersSectionFound || indexPath.row >= (NSInteger)_peers.found.count) return nil;
    ODataSyncPeerPairing *pairing = [_peers pairingOfPeer:_peers.found[indexPath.row]];
    if (!pairing) return nil;
    UIContextualAction *forget = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Forget"
                                                                       handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
        done([self.peers forgetPairing:pairing error:NULL]);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[ forget ]];
}

#pragma mark actions

- (IBAction)toggleServing:(id)sender {
    BOOL serve = _serveSwitch.on;
    [[NSUserDefaults standardUserDefaults] setBool:serve forKey:SNServePeersDefaultsKey];
    if (!serve) {
        [_peers stopServing];
        return;
    }
    NSError *error = nil;
    if (![_peers startServing:&error]) {
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:SNServePeersDefaultsKey];
        _serveSwitch.on = NO;
        [self tell:@"Your notes cannot be served to devices nearby." message:error.localizedDescription];
    }
}

- (IBAction)getToken:(id)sender {
    if (_peers.notes.serverRemote) [_peers fetchToken];
}

- (IBAction)showPairingCode:(id)sender {
    NSString *code = [_peers newPairingOffer];
    if (!code) return;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Pairing Code"
                                                               message:@"On the other device, Pair With Code… and paste this. Good for two minutes, once."
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Copy Code" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [UIPasteboard generalPasteboard].string = code;
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (IBAction)pairWithCode:(id)sender {
    NSString *pasted = [UIPasteboard generalPasteboard].hasStrings ? [UIPasteboard generalPasteboard].string : nil;
    BOOL looksLikeOne = [pasted containsString:@"\"thumbprint\""];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Pair With Code"
                                                               message:@"The other device's pairing code (Show Pairing Code there)."
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f) {
        f.text = looksLikeOne ? pasted : @"";
        f.placeholder = @"Paste the code";
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Pair" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *code = a.textFields.firstObject.text;
        if (code.length) [self.peers pairWithOffer:code];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)peers:(SNPeers *)peers didPairWithError:(NSError *)error {
    if (error && self.viewIfLoaded.window) [self tell:@"Not paired." message:error.localizedDescription];
}

- (void)tell:(NSString *)title message:(NSString *)message {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
