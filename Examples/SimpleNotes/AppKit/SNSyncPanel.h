// Where the notes are kept (SyncPanel.xib, Sync… in the menu): on this
// computer only, with a warning that nothing syncs or is backed up; or
// synced with a server, signed in as it asks (SNSignIn: nothing, a user and
// password, or OpenID Connect by a code entered in a browser).

#import <AppKit/AppKit.h>
#import "SNSignIn.h"

@class SNSyncPanel;

NS_ASSUME_NONNULL_BEGIN

@protocol SNSyncPanelDelegate <NSObject>
// OK: the server chosen (nil: this computer only), and its sign-in.
- (void)syncPanel:(SNSyncPanel *)panel didChooseServer:(nullable NSURL *)serviceRoot signIn:(nullable SNSignIn *)signIn;
@end

@interface SNSyncPanel : NSWindowController <SNSignInDelegate, NSTextFieldDelegate>
@property (nonatomic, strong) IBOutlet NSButton *localButton;
@property (nonatomic, strong) IBOutlet NSButton *serverButton;
@property (nonatomic, strong) IBOutlet NSTextField *warningLabel;
@property (nonatomic, strong) IBOutlet NSTextField *serverField;
@property (nonatomic, strong) IBOutlet NSTextField *statusLabel;
@property (nonatomic, strong) IBOutlet NSButton *signInButton;
@property (nonatomic, strong) IBOutlet NSButton *signOutButton;
@property (nonatomic, strong) IBOutlet NSTextField *codeHintLabel;
@property (nonatomic, strong) IBOutlet NSTextField *pageLabel;
@property (nonatomic, strong) IBOutlet NSTextField *codeLabel;
@property (nonatomic, strong) IBOutlet NSButton *openPageButton;
@property (nonatomic, strong) IBOutlet NSTextField *waitingLabel;

// Shown as it is now: the server synced with (nil: none).
- (instancetype)initWithServer:(nullable NSURL *)serviceRoot;
@property (nonatomic, weak, nullable) id<SNSyncPanelDelegate> delegate;
// Where the sign-in's tokens are kept (default: SNSecretStore).
@property (nonatomic, strong) id<SNSecretStoring> secrets;
@property (nonatomic, readonly, nullable) SNSignIn *signIn;

- (IBAction)keepLocal:(nullable id)sender;
- (IBAction)syncWithServer:(nullable id)sender;
- (IBAction)signIn:(nullable id)sender;
- (IBAction)signOut:(nullable id)sender;
- (IBAction)openPage:(nullable id)sender;
- (IBAction)ok:(nullable id)sender;
- (IBAction)cancel:(nullable id)sender;
@end

// The address typed, made a service root (a trailing /); nil: not an
// http(s) address.
FOUNDATION_EXPORT NSURL *_Nullable SNServiceRootOf(NSString *typed);

NS_ASSUME_NONNULL_END
