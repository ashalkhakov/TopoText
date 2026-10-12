// File > Version History... (VersionsPanel.xib): a note's versions, which
// the server keeps (SNVersions.h) and every device downloads; the one
// chosen beside the note as it is now (what restoring it brings back, and
// what goes), and Restore This Version.

#import <AppKit/AppKit.h>
#import "SNNotes.h"

NS_ASSUME_NONNULL_BEGIN

@class SNVersionsPanel;

@protocol SNVersionsPanelDelegate <NSObject>
// Restore This Version: the note made as it was then.
- (void)versionsPanel:(SNVersionsPanel *)panel restoreVersion:(NSManagedObject *)version;
@end

@interface SNVersionsPanel : NSWindowController <NSTableViewDataSource, NSTableViewDelegate>
- (instancetype)initWithNotes:(SNNotes *)notes note:(SNNote *)note;
@property (nonatomic, strong) IBOutlet NSTableView *versionTable;
@property (nonatomic, strong) IBOutlet NSTextView *previewView;
@property (nonatomic, strong) IBOutlet NSButton *restoreButton;
@property (nonatomic, strong) IBOutlet NSTextField *statusField;
@property (nonatomic, weak, nullable) id<SNVersionsPanelDelegate> delegate;
@property (nonatomic, readonly) SNNote *note;
// The note's versions, the newest first.
@property (nonatomic, readonly) NSArray<NSManagedObject *> *versions;
// Read again (a sync brought more), the one chosen kept.
- (void)reload;
- (IBAction)restore:(nullable id)sender;
- (IBAction)close:(nullable id)sender;
@end

NS_ASSUME_NONNULL_END
