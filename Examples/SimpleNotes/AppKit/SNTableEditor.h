// A table's cells, rows and columns edited (TableEditor.xib), in a panel
// of its own: a table in a note is drawn there, and edited here.

#import <AppKit/AppKit.h>
#import <TopoText/TopoText.h>

NS_ASSUME_NONNULL_BEGIN

@interface SNTableEditor : NSWindowController <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, strong) IBOutlet NSTableView *tableView;
// The table edited in place, modally, until Done.
+ (void)editTable:(TTTable *)table;
- (IBAction)addRow:(nullable id)sender;
- (IBAction)removeRow:(nullable id)sender;
- (IBAction)addColumn:(nullable id)sender;
- (IBAction)removeColumn:(nullable id)sender;
- (IBAction)done:(nullable id)sender;
@end

NS_ASSUME_NONNULL_END
