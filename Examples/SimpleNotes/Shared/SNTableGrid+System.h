// What the table grid's shared logic (SNTableGrid.m) and each system's
// part of it (AppKit/ and iOS/SNTableGrid+System.m) have of each other.

#pragma once
#import "SNTableGrid.h"
#import "SNTextSystem.h"

NS_ASSUME_NONNULL_BEGIN

@interface SNTableGrid () {
  @package
    SNNotes *_notes;
    /* Each row's cells' views, top down, each left to right; each one's
       binding to its text, the same. */
    NSMutableArray<NSMutableArray<SNGridTextView *> *> *_cells;
    NSMutableArray<NSMutableArray<SNTextBinding *> *> *_bindings;
    NSMutableArray<NSNumber *> *_rowHeights;
    CGFloat _width, _column;
    /* The cell last typed in, for an action from a menu not the cell's. */
    NSUInteger _row, _col;
    /* Typed since last saved; cells being set (not typed into). */
    BOOL _dirty, _loading;
    /* What each system keeps (UIKit: the bar over the keyboard). */
    id _systemState;
}
#pragma mark shared, for the system's part
// A cell typed in (its binding has written it): laid out again.
- (void)cellChanged:(SNGridTextView *)cell;
// The cell typed in now (to act on).
- (void)noteCell:(SNGridTextView *)cell;
// Tab (by 1), Shift-Tab (by -1).
- (void)moveFrom:(SNGridTextView *)cell by:(NSInteger)by;
// The actions it can take now.
- (BOOL)canDo:(SEL)action;
// The actions' titles and selectors, in a menu's order (nil: a separator).
+ (NSArray<NSArray *> *)tableActions;
@end

@interface SNTableGrid (System)
// Set up as the system's views are (once).
- (void)systemSetUp;
// A cell's view, empty (its binding fills it).
- (SNGridTextView *)makeCell;
// Its height, as wide as it is, its text wrapped.
- (CGFloat)heightOfCell:(SNGridTextView *)cell;
- (BOOL)cellIsTypedIn:(SNGridTextView *)cell;
- (void)typeInCell:(SNGridTextView *)cell;
- (void)redraw;
@end

NS_ASSUME_NONNULL_END
