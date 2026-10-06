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
@end

// SNEditorViewController.xib: the text view, and the format bar.
@interface SNEditorViewController : UIViewController <UITextViewDelegate>
- (instancetype)initWithNotes:(SNNotes *)notes note:(SNNote *)note;
@property (nonatomic, strong) IBOutlet UITextView *textView;
// Over the keyboard: the text view's input accessory.
@property (nonatomic, strong) IBOutlet UIToolbar *formatBar;
- (IBAction)bold:(nullable id)sender;
- (IBAction)italic:(nullable id)sender;
- (IBAction)underline:(nullable id)sender;
- (IBAction)strikethrough:(nullable id)sender;
- (IBAction)title:(nullable id)sender;
- (IBAction)heading:(nullable id)sender;
- (IBAction)body:(nullable id)sender;
@end

NS_ASSUME_NONNULL_END
