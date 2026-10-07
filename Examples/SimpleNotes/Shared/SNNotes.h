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

@class SNNoteEditor;

NS_ASSUME_NONNULL_BEGIN

// On the main thread: something changed (a save, a sync, the server), the
// views read again. userInfo: "status" (text), "synced" (YES after a sync
// that brought or sent something).
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

// On a thread of its own; SNNotesDidChangeNotification when done.
- (void)sync;
// The same, waited for, on this thread (the main one): for tests and the
// self-test.
- (BOOL)syncAndWait:(NSError **)error;

#pragma mark Reading

// By name.
- (NSArray<SNFolder *> *)folders;
// Of a folder (nil: all of them), whose text has text in it (nil: all),
// pinned first, then the latest changed; none deleted.
- (NSArray<SNNote *> *)notesInFolder:(nullable SNFolder *)folder matching:(nullable NSString *)text;
- (NSUInteger)countOfNotesInFolder:(nullable SNFolder *)folder;
// Recently Deleted: the notes deleted, and not yet for good, the latest
// deleted first.
- (NSArray<SNNote *> *)deletedNotesMatching:(nullable NSString *)text;
- (NSUInteger)countOfDeletedNotes;

#pragma mark Changing (saved at once)

- (SNFolder *)addFolderNamed:(NSString *)name;
- (void)renameFolder:(SNFolder *)folder to:(NSString *)name;
// Its notes go to Recently Deleted, as Apple Notes does.
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
// Every note in Recently Deleted, gone for good.
- (void)emptyRecentlyDeleted;
// The notes deleted more than SNRecentlyDeletedDays before now, gone for
// good; done when the notes open and after each sync. How many.
- (NSUInteger)removeNotesDeletedBefore:(NSDate *)date;
- (void)setNote:(SNNote *)note pinned:(BOOL)pinned;
// Into another folder (nil: none); one in Recently Deleted is recovered so.
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

@interface SNNoteEditor : NSObject
@property (nonatomic, readonly) NSManagedObjectID *noteID;
@property (nonatomic, readonly) TopoText *text;
// Whoever shows the text: told of merges, and of the note going.
@property (nonatomic, weak, nullable) id<SNNoteEditorDelegate> delegate;
@property (nonatomic, readonly, getter=isGone) BOOL gone;
// The user changed text: written and saved a moment later.
- (void)textDidChange;
// What the store has merged in, what was typed written; saved.
- (void)flush;
// Flushed, and no longer kept up to date.
- (void)close;
@end

// How long Recently Deleted keeps a note: 30 days, as Apple Notes.
FOUNDATION_EXPORT const NSInteger SNRecentlyDeletedDays;
// A deleted note's days left in Recently Deleted (0 on its last).
FOUNDATION_EXPORT NSInteger SNDaysLeft(SNNote *note);

// Text a sync's outcome is said in.
FOUNDATION_EXPORT NSString *SNDateText(NSDate *date);

NS_ASSUME_NONNULL_END
