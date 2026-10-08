// Undo on iOS as the text binding keeps it (by the characters' ids, which a
// sync's merge leaves right), not as UITextView keeps it (by positions,
// which a merge makes wrong). UITextView cannot be told not to keep its
// own; it keeps them in its undo manager, so its undo manager takes only
// the binding's (SNTextBinding's) and drops the rest.

#pragma once
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Takes only what an SNTextBinding registers.
@interface SNUndoManager : NSUndoManager
@end

// A text view whose undo manager is an SNUndoManager: its own (the note's),
// or, followsSuperview, the one of the view it is in (a table's cell).
@interface SNUndoTextView : UITextView
@property (nonatomic) BOOL followsSuperview;
@end

NS_ASSUME_NONNULL_END
