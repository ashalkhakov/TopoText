// The note's text view (NotesWindow.xib): list markers drawn by an
// SNListLayoutManager, and a click on a checklist item's checkbox ticks it
// instead of moving the insertion point.

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SNTextView : NSTextView
// A checkbox clicked: its paragraph's first character's index.
@property (nonatomic, copy, nullable) void (^clickedCheckbox)(NSUInteger paragraph);
// Its layout manager made an SNListLayoutManager (once, from the XIB's).
- (void)useListLayoutManager;
@end

NS_ASSUME_NONNULL_END
