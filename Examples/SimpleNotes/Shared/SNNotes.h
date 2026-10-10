// SimpleNotes' device: every note in a store of its own (SQLite, kept
// across launches), kept in sync with the server by ODataSync. Foundation
// and Core Data only: the AppKit and UIKit apps are views over it.
//
// Works offline: every change is saved here first and waits in the outbox;
// a sync brings down what changed at the server and sends up what waits.
// One runs on its own thread while the views go on: saves made meanwhile
// wait for it to finish, and a note open in an editor is merged with what
// came down before it is written again (SNNoteEditor).

#pragma once
#import <CoreData/CoreData.h>
#import <ODataSync/ODataSync.h>
#import <TopoText/TopoText.h>
#import "SNNote.h"
#import "SNFolder.h"
#import "SNAttachment.h"
#import "SNTextSource.h"
#import "SNSmartFilter.h"

@class SNNoteEditor, SNNoteGroup;

// How lists of notes are sorted: pinned notes first, then by this.
typedef NS_ENUM(NSInteger, SNSortOrder) {
    SNSortByDateEdited,    // the latest edited first (Apple Notes' default)
    SNSortByDateCreated,   // the latest made first
    SNSortByTitle,         // A to Z
};

NS_ASSUME_NONNULL_BEGIN

// On the main thread: something changed (a save, a sync, the server), the
// views read again. userInfo: "status" (text), "synced" (YES after a sync
// that brought or sent something), "statusOnly" (YES when only the status
// changed, as a sync goes, or one that brought nothing: nothing to read
// again), "edited" (a save of notes' text alone, their tags the same: the
// set of their IDs; the lists and the sidebar stand, but for their rows).
FOUNDATION_EXPORT NSNotificationName const SNNotesDidChangeNotification;

@interface SNNotes : NSObject

// The store at storeURL, made the first time, of the compiled model at
// modelURL (nil: the main bundle's SimpleNotes.momd). One an older version
// of the model made is migrated first (SNMigration.h); what it had not
// sent yet goes at the next sync.
- (nullable instancetype)initWithStoreURL:(NSURL *)storeURL modelURL:(nullable NSURL *)modelURL
                                    error:(NSError **)error NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithStoreURL:(NSURL *)storeURL error:(NSError **)error;
// In the user's Application Support, under name.
+ (NSURL *)defaultStoreURLNamed:(NSString *)name;

// The main queue's: what the views show and change.
@property (nonatomic, readonly) NSManagedObjectContext *context;
@property (nonatomic, readonly) ODataSyncEngine *engine;

// The server's service root (http://host:8080/odata/); nil: none, the notes
// stay here. Another server takes what waits here, and what is here.
@property (nonatomic, copy, nullable) NSURL *serviceRoot;
// How the server is reached: nil, the network; an ODataService in the
// process (tests), or a transport of the app's own.
@property (nonatomic, strong, nullable) id<ODataTransport> transport;
// The server's credentials and headers.
@property (nonatomic, strong, nullable) ODataConfiguration *configuration;

// Syncs now and then (seconds; 0: never, the default), and a little after
// each change.
@property (nonatomic) NSTimeInterval syncInterval;
@property (nonatomic, readonly, getter=isSyncing) BOOL syncing;
@property (nonatomic, readonly, copy) NSString *status;
@property (nonatomic, readonly, nullable) NSDate *lastSync;
// Changes not sent yet.
- (NSUInteger)pendingCount;

// On a thread of its own; SNNotesDidChangeNotification when done. Asked
// for while one runs: once more after it, for what changed meanwhile.
- (void)sync;
// Every note's text exchanged with the server again at a sync, now: what
// each lacks of the other's, both ways. A repair, after a server that
// dropped text it was sent (ODataKit's, before it merged text sent after
// it had collected a note's deletions) while saying it had it.
- (void)resendAllNotes;
// The same, waited for, on this thread (the main one): for tests and the
// self-test.
- (BOOL)syncAndWait:(NSError **)error;
// The server's remote (nil: none): what a peer token is asked of.
@property (nonatomic, readonly, nullable) ODataSyncRemote *serverRemote;
// One remote alone (a peer met now and then; the server stays the one
// -sync syncs with), named in the status. NO while a sync runs.
- (BOOL)syncWithRemote:(ODataSyncRemote *)remote named:(NSString *)name;
// The same, waited for (tests).
- (BOOL)syncWithRemote:(ODataSyncRemote *)remote andWait:(NSError **)error;

#pragma mark Reading

// Every folder, by name.
- (NSArray<SNFolder *> *)folders;
// Of a folder (nil: all of them), whose text has text in it (nil: all),
// sorted (the folder's order: -sortOrderForFolder:); none deleted. A
// folder's own notes, not its folders', as Apple Notes lists them; a smart
// folder's, every note its rules take.
- (NSArray<SNNote *> *)notesInFolder:(nullable SNFolder *)folder matching:(nullable NSString *)text;
- (NSUInteger)countOfNotesInFolder:(nullable SNFolder *)folder;
// An image in a note: its data (as SNRichText makes it, a JPEG or a PNG no
// larger than SNAttachmentMaxPixels across), and its size; saved and synced
// like a note. The note's text then refers to it by its id.
- (SNAttachment *)addImageToNote:(SNNote *)note data:(NSData *)data type:(NSString *)type
                           width:(double)width height:(double)height;
// A table in a note (rows x columns, empty), saved and synced; the note's
// text then refers to it by its id.
- (SNAttachment *)addTableToNote:(SNNote *)note rows:(NSUInteger)rows columns:(NSUInteger)columns;
// A file in a note (any but an image: a PDF, a document), its name and
// type (MIME) kept; saved and synced like a note (model version 5).
- (SNAttachment *)addFileToNote:(SNNote *)note data:(NSData *)data name:(NSString *)name type:(nullable NSString *)type;
// A file attachment written out, under its name, for another application
// to open (or Quick Look to show): in a temporary folder of its own. nil:
// not a file, or not come yet.
- (nullable NSURL *)fileURLOfAttachment:(SNAttachment *)attachment;
// A table attachment's table, to edit: a copy of its own, written as a new
// replica (an editing session's). nil: not a table.
- (nullable TTTable *)tableOfAttachment:(SNAttachment *)attachment;
// The table edited, merged into what is stored (a sync may have brought
// edits meanwhile) and saved.
- (void)saveTable:(TTTable *)table toAttachment:(SNAttachment *)attachment;
// The attachment of that id; nil: none here (yet: a note's text can come
// before its attachment in a sync).
- (nullable SNAttachment *)attachmentWithID:(NSString *)attachmentID;
// The note of that id (SNLinkToNote's), deleted or not; nil: none here.
- (nullable SNNote *)noteWithID:(NSString *)noteID;
// Recently Deleted: the notes deleted, and not yet for good, the latest
// deleted first.
- (NSArray<SNNote *> *)deletedNotesMatching:(nullable NSString *)text;
- (NSUInteger)countOfDeletedNotes;

#pragma mark Folders in folders

// The folders in a folder (nil: at the top), by name.
- (NSArray<SNFolder *> *)foldersInFolder:(nullable SNFolder *)folder;
// Every folder, each one followed by those in it, by name at each level:
// for lists and menus, indented by -depthOfFolder:.
- (NSArray<SNFolder *> *)folderTree;
// The folder a folder is in, as shown: nil at the top. Folders in each
// other round in a circle (two devices each moved one into the other) are
// cut at the one whose id sorts first, which goes to the top: the same on
// every device, and nothing lost.
- (nullable SNFolder *)parentOfFolder:(SNFolder *)folder;
// 0 at the top.
- (NSUInteger)depthOfFolder:(SNFolder *)folder;
// Whether folder is in ancestor, at any depth.
- (BOOL)folder:(SNFolder *)folder isInFolder:(SNFolder *)ancestor;

#pragma mark Smart folders

// A folder whose notes are those its rules take (SNSmartFilter), from
// every folder, as Apple Notes' smart folders; nothing is moved into it,
// and a note made in it is made in no folder.
- (SNFolder *)addSmartFolderNamed:(NSString *)name filter:(SNSmartFilter *)filter inFolder:(nullable SNFolder *)parent;
// Its rules; nil: not a smart folder (or a model before version 5).
- (nullable SNSmartFilter *)filterOfFolder:(SNFolder *)folder;
- (void)setFilter:(SNSmartFilter *)filter ofFolder:(SNFolder *)folder;
- (BOOL)isSmartFolder:(nullable SNFolder *)folder;

#pragma mark Tags

// Every tag in the notes (Recently Deleted's not), by name, without #.
- (NSArray<NSString *> *)tags;
// The notes tagged so, sorted; whose text has text in it (nil: all).
- (NSArray<SNNote *> *)notesTagged:(NSString *)tag matching:(nullable NSString *)text;
- (NSUInteger)countOfNotesTagged:(NSString *)tag;
// Every tag and how many notes have it, in one pass over the notes: for a
// list of them all (-countOfNotesTagged: is a pass each).
- (NSDictionary<NSString *, NSNumber *> *)tagCounts;

#pragma mark Sorting and grouping

// This device's choice (user defaults SNSortOrder, SNGroupByDate), for
// every list: by date edited and grouped by date unless set otherwise.
@property (nonatomic) SNSortOrder sortOrder;
@property (nonatomic) BOOL groupsByDate;
// A folder's own order (View > Sort Folder By, as Apple Notes'), synced
// with it; nil: the device's (sortOrder).
- (nullable NSNumber *)sortOrderOfFolder:(SNFolder *)folder;
- (void)setSortOrder:(nullable NSNumber *)order ofFolder:(SNFolder *)folder;
// What a folder's list is sorted by: its own order, else the device's
// (All Notes, a tag: the device's).
- (SNSortOrder)sortOrderForFolder:(nullable SNFolder *)folder;
// A checklist item ticked goes to the bottom of its list at once (user
// defaults SNMoveCheckedToBottom; off, as Apple Notes' "Manually").
@property (nonatomic) BOOL movesCheckedToBottom;
// A sorted list in the groups a list shows: Pinned first; then, grouped by
// date, Today, Yesterday, Previous 7 Days, Previous 30 Days, the months of
// this year, and the years before (by the date sorted by); else the rest,
// as Notes when some are pinned.
- (NSArray<SNNoteGroup *> *)groupsOfNotes:(NSArray<SNNote *> *)notes;
// The same, the notes sorted by order (a folder's own).
- (NSArray<SNNoteGroup *> *)groupsOfNotes:(NSArray<SNNote *> *)notes sortedBy:(SNSortOrder)order;
// A list as a window shows it, in its groups: a folder's (nil: All Notes)
// or a tag's, whose text has text in it (nil: all). By a date, only the
// notes' IDs are read for it, sorted and grouped by the store: each note is
// a fault, read when it is first shown. (By title, a tag's or a smart
// folder's: every note read, as -notesInFolder:matching: reads them.)
- (NSArray<SNNoteGroup *> *)groupsInFolder:(nullable SNFolder *)folder tag:(nullable NSString *)tag matching:(nullable NSString *)text;

#pragma mark Changing (saved at once)

// At the top, or in a folder.
- (SNFolder *)addFolderNamed:(NSString *)name;
- (SNFolder *)addFolderNamed:(NSString *)name inFolder:(nullable SNFolder *)parent;
- (void)renameFolder:(SNFolder *)folder to:(NSString *)name;
// Into another folder (nil: to the top). Not into itself, or a folder in
// it: NO, and nothing changes.
- (BOOL)moveFolder:(SNFolder *)folder toFolder:(nullable SNFolder *)parent;
// With the folders in it; all their notes go to Recently Deleted, as Apple
// Notes does.
- (void)deleteFolder:(SNFolder *)folder;
- (SNNote *)addNoteInFolder:(nullable SNFolder *)folder;
// To Recently Deleted, where it stays SNRecentlyDeletedDays, and can be
// recovered meanwhile. Deleted elsewhere, it is so here too: a deletion is
// a change like any other, and syncs.
- (void)deleteNote:(SNNote *)note;
// Back from Recently Deleted, into its folder (or none, its folder gone).
- (void)recoverNote:(SNNote *)note;
// Gone for good, everywhere: from Recently Deleted (Delete Immediately).
- (void)deleteNoteImmediately:(SNNote *)note;
// Every note in Recently Deleted, gone for good: off the main thread, a
// batch at a time, said in the status; Recently Deleted shows none at once.
- (void)emptyRecentlyDeleted;
// Notes being deleted for good, off the main thread (Recently Deleted
// emptied, or notes deleted SNRecentlyDeletedDays ago gone).
@property (nonatomic, readonly, getter=isRemoving) BOOL removing;
// The notes deleted more than SNRecentlyDeletedDays before now, gone for
// good, here and now; how many. (When the notes open and after each sync,
// those are deleted off the main thread.)
- (NSUInteger)removeNotesDeletedBefore:(NSDate *)date;
- (void)setNote:(SNNote *)note pinned:(BOOL)pinned;
// Into another folder (nil: none); one in Recently Deleted is recovered so.
// Not into a smart folder: nothing changes.
- (void)moveNote:(SNNote *)note toFolder:(nullable SNFolder *)folder;
// What the context has, saved (later, when a sync is running).
- (void)save;
// What the open editors have written, then saved: before the app goes to
// the background, or quits.
- (void)saveAll;

#pragma mark Editing

// The note's text, for an editor: one open copy (a TopoText session of its
// own replica), kept merged with what syncs bring.
- (SNNoteEditor *)editorForNote:(SNNote *)note;

@end

@protocol SNNoteEditorDelegate <NSObject>
// Remote edits merged into the editor's text, in order, for the view's
// storage (SNTextBinding's -applyEdits:).
- (void)noteEditor:(SNNoteEditor *)editor didMergeEdits:(NSArray<TTEdit *> *)edits;
@optional
// The note was deleted (here or elsewhere): the editor is done.
- (void)noteEditorDidVanish:(SNNoteEditor *)editor;
@end

@interface SNNoteEditor : NSObject <SNTextSource>
@property (nonatomic, readonly) NSManagedObjectID *noteID;
@property (nonatomic, readonly) TopoText *text;
// Whoever shows the text: told of merges, and of the note going.
@property (nonatomic, weak, nullable) id<SNNoteEditorDelegate> delegate;
@property (nonatomic, readonly, getter=isGone) BOOL gone;
// A table added to the note (SNNotes' -addTableToNote:...), its id.
- (NSString *)addTableWithRows:(NSUInteger)rows columns:(NSUInteger)columns;
// An image added to the note (SNNotes' -addImageToNote:...), its id; an
// attachment's, by id.
- (NSString *)addImageData:(NSData *)data type:(NSString *)type width:(double)width height:(double)height;
// A file added to the note (SNNotes' -addFileToNote:...), its id.
- (NSString *)addFileData:(NSData *)data name:(NSString *)name type:(nullable NSString *)type;
- (nullable SNAttachment *)attachmentWithID:(NSString *)attachmentID;
// The user changed text: written and saved a moment later.
- (void)textDidChange;
// What the store has merged in, what was typed written; saved.
- (void)flush;
// Flushed, and no longer kept up to date.
- (void)close;
@end

// Notes under a heading in a list (nil: none).
@interface SNNoteGroup : NSObject
- (instancetype)initWithTitle:(nullable NSString *)title notes:(NSArray<SNNote *> *)notes;
@property (nonatomic, readonly, copy, nullable) NSString *title;
@property (nonatomic, readonly, copy) NSArray<SNNote *> *notes;
@end

// The groups of notes sorted so, at now: -groupsOfNotes:'s, for any date.
FOUNDATION_EXPORT NSArray<SNNoteGroup *> *SNGroupNotes(NSArray<SNNote *> *notes, SNSortOrder order, BOOL byDate, NSDate *now);

// How long Recently Deleted keeps a note: 30 days, as Apple Notes.
FOUNDATION_EXPORT const NSInteger SNRecentlyDeletedDays;
// A deleted note's days left in Recently Deleted (0 on its last).
FOUNDATION_EXPORT NSInteger SNDaysLeft(SNNote *note);

// Text a sync's outcome is said in.
FOUNDATION_EXPORT NSString *SNDateText(NSDate *date);

NS_ASSUME_NONNULL_END
