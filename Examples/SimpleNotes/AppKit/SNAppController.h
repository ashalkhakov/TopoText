// SimpleNotes on AppKit (macOS and GNUstep): the application's delegate,
// made by MainMenu.xib. The device (SNNotes), its server, the window.

#pragma once
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

// The server's root, as the user set it (Server…).
FOUNDATION_EXPORT NSString * const SNServerDefaultsKey;   // @"SNServer"

@interface SNAppController : NSObject <NSApplicationDelegate>
- (IBAction)chooseServer:(nullable id)sender;
- (IBAction)showNotes:(nullable id)sender;
@end

NS_ASSUME_NONNULL_END
