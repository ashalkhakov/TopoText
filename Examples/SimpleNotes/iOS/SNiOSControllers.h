// SimpleNotes on iOS: folders, then a folder's notes, then the note; the
// server's address in a sheet. The device and the rich text are the
// shared ones (Shared/), as on AppKit.

#pragma once
#import <UIKit/UIKit.h>
#import "SNNotes.h"
#import <PhotosUI/PhotosUI.h>
#import <QuickLook/QuickLook.h>
#import "SNSmartFolderViewController.h"

NS_ASSUME_NONNULL_BEGIN

// The server's root, as the user set it.
FOUNDATION_EXPORT NSString * const SNServerDefaultsKey;   // @"SNServer"

@interface SNFoldersViewController : UITableViewController <SNSmartFolderViewControllerDelegate>
- (instancetype)initWithNotes:(SNNotes *)notes;
// The smart folder form, for a new one (folder nil) or one to edit.
- (SNSmartFolderViewController *)smartFolderEditorFor:(nullable SNFolder *)folder;
@end

@interface SNNotesViewController : UITableViewController <UISearchResultsUpdating>
// A folder's notes (nil: all of them).
- (instancetype)initWithNotes:(SNNotes *)notes folder:(nullable SNFolder *)folder;
// The notes tagged so.
- (instancetype)initWithNotes:(SNNotes *)notes tag:(NSString *)tag;
// Sort By and Group By Date (its ... menu's).
- (IBAction)sortByDateEdited:(nullable id)sender;
- (IBAction)sortByDateCreated:(nullable id)sender;
- (IBAction)sortByTitle:(nullable id)sender;
- (IBAction)toggleGroupByDate:(nullable id)sender;
// Sort Folder By: the folder shown, its own order (Default: the device's).
- (IBAction)sortFolderByDefault:(nullable id)sender;
- (IBAction)sortFolderByDateEdited:(nullable id)sender;
- (IBAction)sortFolderByDateCreated:(nullable id)sender;
- (IBAction)sortFolderByTitle:(nullable id)sender;
// The groups listed: their headings and notes' titles, as in shownRows.
- (NSArray<NSString *> *)shownRows;
// Recently Deleted: recovered, or deleted for good, from here.
- (instancetype)initRecentlyDeletedWithNotes:(SNNotes *)notes;
@end

@class SNTableGrid;

// SNEditorViewController.xib: the text view, and the format bar.
@interface SNEditorViewController : UIViewController <UITextViewDelegate, UIGestureRecognizerDelegate, SNNoteEditorDelegate,
                                                       PHPickerViewControllerDelegate, UIDocumentPickerDelegate,
                                                       QLPreviewControllerDataSource>
- (instancetype)initWithNotes:(SNNotes *)notes note:(SNNote *)note;
@property (nonatomic, strong) IBOutlet UITextView *textView;
// Over the keyboard: the text view's input accessory, as Apple Notes'
// (an iPhone's width): a table, Aa (styles, and bold, italic, underline,
// strikethrough), a checklist, lists, the paperclip (a photo, a link), and
// the keyboard put away.
@property (nonatomic, strong) IBOutlet UIToolbar *formatBar;
@property (nonatomic, strong) IBOutlet UIBarButtonItem *styleItem;
@property (nonatomic, strong) IBOutlet UIBarButtonItem *listItem;
@property (nonatomic, strong) IBOutlet UIBarButtonItem *attachItem;
- (IBAction)hideKeyboard:(nullable id)sender;
// A link followed: a note's opened here, any other in its own application
// (one tapped in a table's cell too, up the responder chain).
- (void)openLink:(NSURL *)url;
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
// A link on the selection (or the one at the insertion point changed).
- (IBAction)addLink:(nullable id)sender;
// Photos into the note (the photo picker).
- (IBAction)attachPhoto:(nullable id)sender;
// Files into the note (the document picker): an image as one, any other
// as a card, which a tap shows (Quick Look).
- (IBAction)attachFile:(nullable id)sender;
// A file's data into the note at the insertion point, as a file picked.
- (BOOL)insertFileData:(NSData *)data name:(NSString *)name;
// A file attachment shown (Quick Look), as its card tapped.
- (BOOL)previewFileOfAttachment:(NSString *)attachmentID;
// An image's data into the note at the insertion point (as a photo picked).
- (void)insertImageData:(NSData *)data;
// A table at the insertion point (2 x 2), its first cell typed in. A table
// is edited where it is, its grid over it (SNTableGrid): its rows and
// columns from the bar over the keyboard, or a cell's menu.
- (IBAction)addTable:(nullable id)sender;
// A table put in the note, not typed in: its attachment's id.
- (nullable NSString *)insertTableWithRows:(NSUInteger)rows columns:(NSUInteger)columns;
// The note's table's grid (nil: none).
- (nullable SNTableGrid *)gridForAttachmentID:(NSString *)attachmentID;
// Mark as Checked: the checklist items selected ticked (or unticked).
- (IBAction)toggleChecked:(nullable id)sender;
// Move Checked to Bottom, and Keep Checked at Bottom (every tick).
- (IBAction)moveCheckedToBottom:(nullable id)sender;
- (IBAction)toggleKeepCheckedAtBottom:(nullable id)sender;
- (IBAction)indent:(nullable id)sender;
- (IBAction)outdent:(nullable id)sender;
// A note in Recently Deleted, recovered (the button over it).
- (IBAction)recover:(nullable id)sender;
@end

NS_ASSUME_NONNULL_END
