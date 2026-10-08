// Devices Nearby on iOS (the folder list's antenna button), as the desktop's
// window: the notes served to devices on the same network while the app is
// open, the peer token the server gave, the devices found and a sync with
// one, pairing with a device that shares no server (a code shown on one,
// pasted on the other). SNPeers does it.

#pragma once
#import <UIKit/UIKit.h>
#import "SNPeers.h"

NS_ASSUME_NONNULL_BEGIN

@interface SNPeersViewController : UITableViewController <SNPeersDelegate>
- (instancetype)initWithPeers:(SNPeers *)peers;
@property (nonatomic, readonly) SNPeers *peers;

- (IBAction)toggleServing:(nullable id)sender;
- (IBAction)getToken:(nullable id)sender;
- (IBAction)showPairingCode:(nullable id)sender;
- (IBAction)pairWithCode:(nullable id)sender;
- (IBAction)done:(nullable id)sender;
@end

NS_ASSUME_NONNULL_END
