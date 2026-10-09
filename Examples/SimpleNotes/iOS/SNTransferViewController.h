// An import or export as it goes (SNTransfer), as a sheet: what it is
// doing, how far, Stop; then what happened, and Done. The notes behind it
// fill in as they come.

#pragma once
#import <UIKit/UIKit.h>
#import "SNTransfer.h"

NS_ASSUME_NONNULL_BEGIN

@class SNTransferViewController;

@protocol SNTransferViewControllerDelegate <NSObject>
// Done tapped, the transfer finished (its outcome on it).
- (void)transferViewControllerDidClose:(SNTransferViewController *)controller;
@end

@interface SNTransferViewController : UIViewController <SNTransferDelegate>
// Its delegate set to this; started by the one presenting it.
- (instancetype)initWithTransfer:(SNTransfer *)transfer;
@property (nonatomic, readonly) SNTransfer *transfer;
@property (nonatomic, weak, nullable) id<SNTransferViewControllerDelegate> delegate;
@end

NS_ASSUME_NONNULL_END
