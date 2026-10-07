// The note's text view (NotesWindow.xib): list markers drawn by an
// SNListLayoutManager, and a click on a checklist item's checkbox told to
// its delegate instead of moving the insertion point.

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@class SNTextView;

@protocol SNTextViewDelegate <NSTextViewDelegate>
@optional
// A checkbox clicked: its paragraph's first character's index (as
// -textView:clickedOnLink:atIndex: says a link's).
- (void)textView:(SNTextView *)textView clickedCheckboxAtIndex:(NSUInteger)index;
@end

@interface SNTextView : NSTextView
// Its layout manager made an SNListLayoutManager (once, from the XIB's).
- (void)useListLayoutManager;
@end

NS_ASSUME_NONNULL_END
