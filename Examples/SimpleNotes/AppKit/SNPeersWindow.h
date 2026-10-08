// Devices Nearby (DevicesNearby.xib, in the File menu): the notes served
// to devices on the same network, the peer token the server gave, the
// devices found and a sync with one, pairing with a device that shares no
// server (a code shown on one, pasted on the other). SNPeers does it.

#import <AppKit/AppKit.h>
#import "SNPeers.h"

NS_ASSUME_NONNULL_BEGIN

// Whether the notes are served to devices nearby (kept: served again at
// the next launch).
FOUNDATION_EXPORT NSString * const SNServePeersDefaultsKey;   // @"SNServePeers"

@interface SNPeersWindow : NSWindowController <SNPeersDelegate, NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) IBOutlet NSButton *serveButton;
@property (nonatomic, strong) IBOutlet NSTextField *servingLabel;
@property (nonatomic, strong) IBOutlet NSTextField *tokenLabel;
@property (nonatomic, strong) IBOutlet NSButton *tokenButton;
@property (nonatomic, strong) IBOutlet NSTableView *devicesTable;
@property (nonatomic, strong) IBOutlet NSButton *syncButton;
@property (nonatomic, strong) IBOutlet NSButton *forgetButton;
@property (nonatomic, strong) IBOutlet NSButton *showCodeButton;
@property (nonatomic, strong) IBOutlet NSButton *codeCopyButton;
@property (nonatomic, strong) IBOutlet NSTextField *codeLabel;
@property (nonatomic, strong) IBOutlet NSTextField *statusLabel;

- (instancetype)initWithPeers:(SNPeers *)peers;
@property (nonatomic, readonly) SNPeers *peers;

- (IBAction)toggleServing:(nullable id)sender;
- (IBAction)getToken:(nullable id)sender;
- (IBAction)syncWithDevice:(nullable id)sender;
- (IBAction)forgetPairing:(nullable id)sender;
- (IBAction)showPairingCode:(nullable id)sender;
- (IBAction)copyPairingCode:(nullable id)sender;
- (IBAction)pairWithCode:(nullable id)sender;
@end

NS_ASSUME_NONNULL_END
