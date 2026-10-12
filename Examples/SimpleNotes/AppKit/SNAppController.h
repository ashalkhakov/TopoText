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
// Services > Add to SimpleNotes (another app's selection: its text, a link,
// a picture): a new note at the top, shown. As the Share extension does on
// iOS: through an inbox (SNShares.h), imported at once.
- (void)addToSimpleNotes:(NSPasteboard *)pasteboard userData:(nullable NSString *)userData error:(NSString *_Nullable *_Nullable)error;
@end

NS_ASSUME_NONNULL_END
