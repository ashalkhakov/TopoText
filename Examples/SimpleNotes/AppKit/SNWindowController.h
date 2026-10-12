// SimpleNotes' window, on AppKit (macOS and GNUstep): folders, the notes
// of the one chosen, and the note being written, with what the last sync
// did below. NotesWindow.xib: frames and autoresizing, cell-based tables,
// what GNUstep's xib loader and Apple's both read.

#pragma once
#import <AppKit/AppKit.h>
#import "SNNotes.h"
#import "SNTextView.h"
#import "SNTransferPanel.h"
#import "SNGallery.h"

NS_ASSUME_NONNULL_BEGIN

@class SNTableGrid;

@interface SNWindowController : NSWindowController <NSWindowDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTableViewDataSource,
                                                    NSTableViewDelegate, SNTextViewDelegate, SNNoteEditorDelegate,
                                                    SNTransferPanelDelegate, SNGalleryDelegate, SNAttachmentsWindowDelegate>
- (instancetype)initWithNotes:(SNNotes *)notes;
// The sidebar: All Notes, the folders (folders in folders under them),
// Recently Deleted, and the tags.
@property (nonatomic, strong) IBOutlet NSOutlineView *folderTable;
@property (nonatomic, strong) IBOutlet NSTableView *noteTable;
@property (nonatomic, strong) IBOutlet NSSearchField *searchField;
@property (nonatomic, strong) IBOutlet SNTextView *textView;
@property (nonatomic, strong) IBOutlet NSTextField *statusField;
@property (nonatomic, strong) IBOutlet NSButton *syncButton;
// The open note written, before the app quits.
- (void)closeEditor;
// The note of that title chosen in the list, as a click would (the self-test).
- (BOOL)selectNoteTitled:(NSString *)title;
// All Notes, Recently Deleted, a folder or a tag, chosen in the sidebar.
- (void)showAllNotes;
// The note chosen in the list (nil: none).
- (nullable SNNote *)selectedNote;

- (void)showRecentlyDeleted;
- (BOOL)showFolderNamed:(NSString *)name;
- (BOOL)showTag:(NSString *)tag;
// What the window shows, in words: the folder chosen and the notes listed
// (a self-test's failures say it).
- (NSString *)shownText;
// Move To and Move Folder To filled from the folders and what is chosen
// (done as they change; for the self-test).
- (void)fillMoveToMenus;
// The sidebar's rows, indented two spaces a level; the note list's, a
// group's heading "## " and its title.
- (NSArray<NSString *> *)sidebarRows;
- (NSArray<NSString *> *)shownRows;

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
// The Move Folder To menu's items: the folder chosen into the folder an
// item names (none: to the top).
- (IBAction)moveFolderToFolder:(nullable id)sender;
- (IBAction)renameFolder:(nullable id)sender;
// File > New Smart Folder…, Edit Smart Folder… (SNSmartFolderPanel).
- (IBAction)newSmartFolder:(nullable id)sender;
- (IBAction)editSmartFolder:(nullable id)sender;
// File > Import Notes…: a folder, a zip or a Markdown file (SNTransfer.h),
// into the folder chosen; File > Export All Notes…: as Markdown, a zip
// (or a folder: the name given without .zip).
- (IBAction)importNotes:(nullable id)sender;
- (IBAction)exportAllNotes:(nullable id)sender;
// View > Sort Folder By: the folder shown, sorted its own way (Default:
// as View > Sort By says for all).
- (IBAction)sortFolderByDefault:(nullable id)sender;
- (IBAction)sortFolderByDateEdited:(nullable id)sender;
- (IBAction)sortFolderByDateCreated:(nullable id)sender;
- (IBAction)sortFolderByTitle:(nullable id)sender;
- (IBAction)togglePinned:(nullable id)sender;
- (IBAction)sync:(nullable id)sender;
// Every note's text exchanged with the server again, both ways (a repair).
- (IBAction)resendAllNotes:(nullable id)sender;
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
// Format > Move Checked to Bottom, and Keep Checked at Bottom (every tick).
- (IBAction)moveCheckedToBottom:(nullable id)sender;
- (IBAction)toggleKeepCheckedAtBottom:(nullable id)sender;
- (IBAction)decreaseIndentation:(nullable id)sender;
// Format > Block Quote (Command-'): the paragraphs quoted, or not.
- (IBAction)toggleBlockQuote:(nullable id)sender;
// Format > Collapse All Sections and Expand All Sections: every heading's
// (a chevron beside each collapses or expands one, as Apple Notes').
- (IBAction)collapseAllSections:(nullable id)sender;
- (IBAction)expandAllSections:(nullable id)sender;
// Format > Highlight and Text Color: the item's tag the colour (0 none,
// then SNColorNames' order: purple, pink, orange, mint, blue).
- (IBAction)applyHighlightColor:(nullable id)sender;
- (IBAction)applyTextColor:(nullable id)sender;
// View > as List (Command-1) and as Gallery (Command-2): the notes as rows
// or as cards, in the list's place (the pane wider for cards), from now
// on; a card chosen opens its note as a row does.
- (IBAction)showAsList:(nullable id)sender;
- (IBAction)showAsGallery:(nullable id)sender;
@property (nonatomic, readonly) SNGallery *gallery;
// View > Show Attachments (Command-3): every image and file in the notes,
// in a window of its own; one chosen shows its note, where it is.
- (IBAction)showAttachments:(nullable id)sender;
@property (nonatomic, readonly, nullable) SNAttachmentsWindow *attachmentsWindow;
// Edit > Find > Search: the notes' search field.
// File > Print… (Command-P) and Export as PDF…: the open note laid out on
// paper, as it is now (what was typed and not yet saved too): its lists,
// colours, images, files' cards, tables (drawn as they look), in the
// paper's light colours.
- (IBAction)printNote:(nullable id)sender;
- (IBAction)exportNoteAsPDF:(nullable id)sender;
// The open note as a PDF at path, with no panel (Export as PDF's, once a
// file is chosen); NO: none written.
- (BOOL)exportNoteAsPDFTo:(NSString *)path;
- (IBAction)findNote:(nullable id)sender;
// Edit > Find's actions in the note (Find…, Find and Replace…, Find Next,
// ...), from wherever the window's focus is (the notes' list): the note's
// text view takes them, as when it has the focus.
- (IBAction)performFindPanelAction:(nullable id)sender;
- (IBAction)findAndReplace:(nullable id)sender;
- (IBAction)centerSelectionInVisibleArea:(nullable id)sender;
// Format > Add Link… (a link on the selection, or the one at the insertion
// point changed), and File > Copy Link to Note (simplenotes://note/<id>,
// pasted as a link it opens the note).
- (IBAction)addLink:(nullable id)sender;
- (IBAction)copyNoteLink:(nullable id)sender;
// File > Attach File…: files into the note, at the insertion point: an
// image shown as one, any other file as a card (one pasted or dropped is
// one too).
- (IBAction)attachFile:(nullable id)sender;
// An image's data into the note at the insertion point, undoably (NO: not
// an image, or no note open).
- (BOOL)attachImageData:(NSData *)data;
// Any other file, as a card (a PDF, a document), undoably; NO: none open,
// or larger than 25 MB.
- (BOOL)attachFileData:(NSData *)data name:(NSString *)name;
// A file attachment opened in its own application (a card double-clicked).
- (BOOL)openFileOfAttachment:(NSString *)attachmentID;
// Format > Table > Insert Table: a table in the note at the insertion
// point, its first cell typed in. (Not -insertTable:, NSTextView's own,
// which the note's text view, first in the responder chain, would take.) A table is edited where it is, its grid
// over it (SNTableGrid): its rows and columns from Format > Table, or a
// cell's menu.
- (IBAction)addTable:(nullable id)sender;
// A table put in the note (rows x columns), undoably, not typed in: its
// attachment's id.
- (nullable NSString *)insertTableWithRows:(NSUInteger)rows columns:(NSUInteger)columns;
// The open note's table's grid (nil: none).
- (nullable SNTableGrid *)gridForAttachmentID:(NSString *)attachmentID;
// The note shown and chosen, as a link to it opens it (NO: not here).
- (BOOL)showNote:(SNNote *)note;
// View > Sort By, and Group By Date.
- (IBAction)sortByDateEdited:(nullable id)sender;
- (IBAction)sortByDateCreated:(nullable id)sender;
- (IBAction)sortByTitle:(nullable id)sender;
- (IBAction)toggleGroupByDate:(nullable id)sender;
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
