// An import or export as it goes (SNTransfer): what it is doing, how far,
// Stop; then what happened, and Close. Not modal: the notes can be read
// and edited meanwhile, and what is imported shows as it comes.

#pragma once
#import <AppKit/AppKit.h>
#import "SNTransfer.h"

NS_ASSUME_NONNULL_BEGIN

@class SNTransferPanel;

@protocol SNTransferPanelDelegate <NSObject>
// Closed, the transfer done: the views read again.
- (void)transferPanelDidClose:(SNTransferPanel *)panel;
@end

@interface SNTransferPanel : NSWindowController <SNTransferDelegate>
// Shows it, and starts it.
- (instancetype)initWithTransfer:(SNTransfer *)transfer;
@property (nonatomic, readonly) SNTransfer *transfer;
@property (nonatomic, weak, nullable) id<SNTransferPanelDelegate> delegate;
@property (nonatomic, strong) IBOutlet NSTextField *statusField;
@property (nonatomic, strong) IBOutlet NSProgressIndicator *progressBar;
@property (nonatomic, strong) IBOutlet NSTextField *detailField;
@property (nonatomic, strong) IBOutlet NSButton *button;
// Stop while it runs; Close when it is done.
- (IBAction)stopOrClose:(nullable id)sender;
@end

NS_ASSUME_NONNULL_END
