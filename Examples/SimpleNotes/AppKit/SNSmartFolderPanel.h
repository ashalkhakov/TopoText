// A smart folder's name and rules, asked for (SmartFolderPanel.xib): File >
// New Smart Folder…, and Edit Smart Folder… on one.

#import <AppKit/AppKit.h>
#import "SNSmartFilter.h"

NS_ASSUME_NONNULL_BEGIN

@interface SNSmartFolderPanel : NSWindowController
@property (nonatomic, strong) IBOutlet NSTextField *nameField;
@property (nonatomic, strong) IBOutlet NSPopUpButton *matchPopUp;
@property (nonatomic, strong) IBOutlet NSTextField *tagsField;
@property (nonatomic, strong) IBOutlet NSPopUpButton *tagsMatchPopUp;
@property (nonatomic, strong) IBOutlet NSPopUpButton *editedPopUp;
@property (nonatomic, strong) IBOutlet NSPopUpButton *createdPopUp;
@property (nonatomic, strong) IBOutlet NSPopUpButton *checklistsPopUp;
@property (nonatomic, strong) IBOutlet NSButton *attachmentsBox;
@property (nonatomic, strong) IBOutlet NSButton *pinnedBox;

// Shown with these, to begin with.
- (instancetype)initWithName:(NSString *)name filter:(SNSmartFilter *)filter;
// Modally: YES, OK (name and filter now what was chosen); NO, cancelled.
- (BOOL)runModal;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) SNSmartFilter *filter;

- (IBAction)ok:(nullable id)sender;
- (IBAction)cancel:(nullable id)sender;
@end

NS_ASSUME_NONNULL_END
