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
// modelURL (nil: the main bundle's SimpleNotes.momd).
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
// pinned first, then the latest changed.
- (NSArray<SNNote *> *)notesInFolder:(nullable SNFolder *)folder matching:(nullable NSString *)text;
- (NSUInteger)countOfNotesInFolder:(nullable SNFolder *)folder;

#pragma mark Changing (saved at once)

- (SNFolder *)addFolderNamed:(NSString *)name;
- (void)renameFolder:(SNFolder *)folder to:(NSString *)name;
// Its notes stay, in no folder.
- (void)deleteFolder:(SNFolder *)folder;
- (SNNote *)addNoteInFolder:(nullable SNFolder *)folder;
- (void)deleteNote:(SNNote *)note;
- (void)setNote:(SNNote *)note pinned:(BOOL)pinned;
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

@interface SNNoteEditor : NSObject
@property (nonatomic, readonly) NSManagedObjectID *noteID;
@property (nonatomic, readonly) TopoText *text;
// Remote edits merged into text, in order, for the view's storage.
@property (nonatomic, copy, nullable) void (^didMerge)(NSArray<TTEdit *> *edits);
// The note was deleted (here or elsewhere): the editor is done.
@property (nonatomic, copy, nullable) void (^didVanish)(void);
@property (nonatomic, readonly, getter=isGone) BOOL gone;
// The user changed text: written and saved a moment later.
- (void)textDidChange;
// What the store has merged in, what was typed written; saved.
- (void)flush;
// Flushed, and no longer kept up to date.
- (void)close;
@end

// Text a sync's outcome is said in.
FOUNDATION_EXPORT NSString *SNDateText(NSDate *date);

NS_ASSUME_NONNULL_END
