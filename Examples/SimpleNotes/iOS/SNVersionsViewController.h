// Version History (the note's ... menu): a note's versions, which the
// server keeps (SNVersions.h) and every device downloads, the newest
// first; one chosen beside the note as it is now (what restoring it brings
// back, and what goes), and Restore.

#pragma once
#import <UIKit/UIKit.h>
#import "SNNotes.h"

NS_ASSUME_NONNULL_BEGIN

@interface SNVersionsViewController : UITableViewController
- (instancetype)initWithNotes:(SNNotes *)notes note:(SNNote *)note;
@property (nonatomic, readonly) NSArray<NSManagedObject *> *versions;
@end

@interface SNVersionViewController : UIViewController
- (instancetype)initWithNotes:(SNNotes *)notes note:(SNNote *)note version:(NSManagedObject *)version;
@property (nonatomic, readonly) UITextView *previewView;
// Restore (its bar button): the note as it was then; back to the note.
- (IBAction)restore:(nullable id)sender;
@end

NS_ASSUME_NONNULL_END
