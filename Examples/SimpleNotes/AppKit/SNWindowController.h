// SimpleNotes' window, on AppKit (macOS and GNUstep): folders, the notes
// of the one chosen, and the note being written, with what the last sync
// did below. NotesWindow.xib: frames and autoresizing, cell-based tables,
// what GNUstep's xib loader and Apple's both read.

#pragma once
#import <AppKit/AppKit.h>
#import "SNNotes.h"
#import "SNTextView.h"

NS_ASSUME_NONNULL_BEGIN

@interface SNWindowController : NSWindowController <NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate, NSMenuDelegate>
- (instancetype)initWithNotes:(SNNotes *)notes;
@property (nonatomic, strong) IBOutlet NSTableView *folderTable;
@property (nonatomic, strong) IBOutlet NSTableView *noteTable;
@property (nonatomic, strong) IBOutlet NSSearchField *searchField;
@property (nonatomic, strong) IBOutlet SNTextView *textView;
@property (nonatomic, strong) IBOutlet NSTextField *statusField;
@property (nonatomic, strong) IBOutlet NSButton *syncButton;
// The open note written, before the app quits.
- (void)closeEditor;
// The note of that title chosen in the list, as a click would (the self-test).
- (BOOL)selectNoteTitled:(NSString *)title;
// All Notes, or Recently Deleted, chosen in the folder list.
- (void)showAllNotes;
- (void)showRecentlyDeleted;
// What the window shows, in words: the folder chosen and the notes listed
// (a self-test's failures say it).
- (NSString *)shownText;

// The menus' actions (the window's delegate is in the responder chain).
- (IBAction)newNote:(nullable id)sender;
- (IBAction)newFolder:(nullable id)sender;
- (IBAction)deleteNote:(nullable id)sender;
- (IBAction)deleteFolder:(nullable id)sender;
// Recently Deleted: a note back, or gone for good; all of them gone.
- (IBAction)recoverNote:(nullable id)sender;
- (IBAction)emptyRecentlyDeleted:(nullable id)sender;
// The Move To menu's items: the note into the folder an item names.
- (IBAction)moveNoteToFolder:(nullable id)sender;
- (IBAction)renameFolder:(nullable id)sender;
- (IBAction)togglePinned:(nullable id)sender;
- (IBAction)sync:(nullable id)sender;
- (IBAction)toggleBold:(nullable id)sender;
- (IBAction)toggleItalic:(nullable id)sender;
- (IBAction)toggleUnderline:(nullable id)sender;
- (IBAction)toggleStrikethrough:(nullable id)sender;
- (IBAction)styleTitle:(nullable id)sender;
- (IBAction)styleHeading:(nullable id)sender;
- (IBAction)styleSubheading:(nullable id)sender;
- (IBAction)styleBody:(nullable id)sender;
- (IBAction)styleMono:(nullable id)sender;
- (IBAction)toggleBulletList:(nullable id)sender;
- (IBAction)toggleDashList:(nullable id)sender;
- (IBAction)toggleNumberList:(nullable id)sender;
- (IBAction)toggleChecklist:(nullable id)sender;
- (IBAction)toggleChecked:(nullable id)sender;
- (IBAction)increaseIndentation:(nullable id)sender;
- (IBAction)decreaseIndentation:(nullable id)sender;
- (IBAction)findNote:(nullable id)sender;
- (IBAction)searchChanged:(nullable id)sender;
@end

// A line of text asked for, in TextPanel.xib, modally.
@interface SNTextPanel : NSWindowController
@property (nonatomic, strong) IBOutlet NSTextField *messageField;
@property (nonatomic, strong) IBOutlet NSTextField *textField;
- (IBAction)ok:(nullable id)sender;
- (IBAction)cancel:(nullable id)sender;
@end

// What was typed; nil when cancelled.
FOUNDATION_EXPORT NSString *_Nullable SNAskForText(NSString *title, NSString *message, NSString *initial);

NS_ASSUME_NONNULL_END
