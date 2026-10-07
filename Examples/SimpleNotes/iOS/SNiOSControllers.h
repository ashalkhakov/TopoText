// SimpleNotes on iOS: folders, then a folder's notes, then the note; the
// server's address in a sheet. The device and the rich text are the
// shared ones (Shared/), as on AppKit.

#pragma once
#import <UIKit/UIKit.h>
#import "SNNotes.h"

NS_ASSUME_NONNULL_BEGIN

// The server's root, as the user set it.
FOUNDATION_EXPORT NSString * const SNServerDefaultsKey;   // @"SNServer"

@interface SNFoldersViewController : UITableViewController
- (instancetype)initWithNotes:(SNNotes *)notes;
@end

@interface SNNotesViewController : UITableViewController <UISearchResultsUpdating>
// A folder's notes (nil: all of them).
- (instancetype)initWithNotes:(SNNotes *)notes folder:(nullable SNFolder *)folder;
// Recently Deleted: recovered, or deleted for good, from here.
- (instancetype)initRecentlyDeletedWithNotes:(SNNotes *)notes;
@end

// SNEditorViewController.xib: the text view, and the format bar.
@interface SNEditorViewController : UIViewController <UITextViewDelegate, UIGestureRecognizerDelegate, SNNoteEditorDelegate>
- (instancetype)initWithNotes:(SNNotes *)notes note:(SNNote *)note;
@property (nonatomic, strong) IBOutlet UITextView *textView;
// Over the keyboard: the text view's input accessory.
@property (nonatomic, strong) IBOutlet UIToolbar *formatBar;
// Its menus: the paragraph's style (Aa), and lists and indentation.
@property (nonatomic, strong) IBOutlet UIBarButtonItem *styleItem;
@property (nonatomic, strong) IBOutlet UIBarButtonItem *listItem;
- (IBAction)bold:(nullable id)sender;
- (IBAction)italic:(nullable id)sender;
- (IBAction)underline:(nullable id)sender;
- (IBAction)strikethrough:(nullable id)sender;
- (IBAction)title:(nullable id)sender;
- (IBAction)heading:(nullable id)sender;
- (IBAction)subheading:(nullable id)sender;
- (IBAction)body:(nullable id)sender;
- (IBAction)mono:(nullable id)sender;
- (IBAction)bulletList:(nullable id)sender;
- (IBAction)dashList:(nullable id)sender;
- (IBAction)numberList:(nullable id)sender;
- (IBAction)checklist:(nullable id)sender;
// Mark as Checked: the checklist items selected ticked (or unticked).
- (IBAction)toggleChecked:(nullable id)sender;
- (IBAction)indent:(nullable id)sender;
- (IBAction)outdent:(nullable id)sender;
// A note in Recently Deleted, recovered (the button over it).
- (IBAction)recover:(nullable id)sender;
@end

NS_ASSUME_NONNULL_END
