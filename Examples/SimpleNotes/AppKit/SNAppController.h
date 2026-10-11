// SimpleNotes on AppKit (macOS and GNUstep): the application's delegate,
// made by MainMenu.xib. The device (SNNotes), its server, the window.

#pragma once
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

// The server's root, as the user set it (Sync…); none: this computer only.
FOUNDATION_EXPORT NSString * const SNServerDefaultsKey;   // @"SNServer"

@interface SNAppController : NSObject <NSApplicationDelegate>
// Shown while a store of an older version is brought up to this one
// (UpdatePanel.xib).
@property (nonatomic, strong, nullable) IBOutlet NSPanel *updatePanel;
@property (nonatomic, weak, nullable) IBOutlet NSProgressIndicator *updateBar;
- (IBAction)chooseServer:(nullable id)sender;
- (IBAction)showNotes:(nullable id)sender;
// Devices Nearby… (SNPeersWindow).
- (IBAction)showDevicesNearby:(nullable id)sender;
@end

NS_ASSUME_NONNULL_END
