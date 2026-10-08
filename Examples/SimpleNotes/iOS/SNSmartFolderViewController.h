// A smart folder's name and rules, asked for on iOS: a form (the folder
// list's New Smart Folder, and Edit on a smart folder), as Apple Notes'.

#pragma once
#import <UIKit/UIKit.h>
#import "SNSmartFilter.h"

@class SNSmartFolderViewController;

NS_ASSUME_NONNULL_BEGIN

@protocol SNSmartFolderViewControllerDelegate <NSObject>
// Done: its name and filter what was chosen. The delegate dismisses it.
- (void)smartFolderViewControllerDidFinish:(SNSmartFolderViewController *)controller;
- (void)smartFolderViewControllerDidCancel:(SNSmartFolderViewController *)controller;
@end

@interface SNSmartFolderViewController : UITableViewController <UITextFieldDelegate>
- (instancetype)initWithName:(NSString *)name filter:(SNSmartFilter *)filter;
@property (nonatomic, weak, nullable) id<SNSmartFolderViewControllerDelegate> delegate;
// What is chosen now (read as the form says it).
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) SNSmartFilter *filter;
// What it is being made for (a folder being edited; nil: a new one).
@property (nonatomic, strong, nullable) id folder;
- (IBAction)done:(nullable id)sender;
- (IBAction)cancel:(nullable id)sender;
@end

NS_ASSUME_NONNULL_END
