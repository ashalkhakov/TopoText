// A store made by an older version of SimpleNotes' model, brought to the
// current one before it is opened: the model's versions are all in the
// compiled model (SimpleNotes.momd), each one's store recognised with the
// bookkeeping its users add (ODataSync's, the device's or the server's).
//
// Core Data's automatic migration cannot do it: it looks for the model a
// store was made with among the app's compiled models, and a store with
// ODataSync's entities in it was made with none of them as they are.
//
// NSMigrationManager carries the store over whole, on Apple's Core Data
// and FreeCoreData alike: its metadata (ODataSync's replica ID) and its
// history, so a change made before the update and not yet sent is still
// in the history ODataSync reads, and goes at the next sync.

#pragma once
#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN

// What adds bookkeeping to a model: ODataSyncEngine (a device's),
// ODataSyncService (the server's).
@protocol SNBookkeeper <NSObject>
+ (void)addBookkeepingToModel:(NSManagedObjectModel *)model configuration:(nullable NSString *)configuration;
@end

// Each version of the compiled model at momdURL, oldest first by name.
FOUNDATION_EXPORT NSArray<NSManagedObjectModel *> *SNModelVersions(NSURL *momdURL);

// The store at storeURL (SQLite) brought to the current version, with
// the bookkeeper's bookkeeping added to each version. Nothing to do (no
// store yet, or one of the current version): YES. A store of no version the
// model has: NO, with the error. The store before is kept beside it (.old).
FOUNDATION_EXPORT BOOL SNMigrateStore(NSURL *storeURL, NSURL *momdURL, Class<SNBookkeeper> bookkeeper, NSError **error);

// A store moved to another: a server's storage changed (SQLite to
// PostgreSQL, say). Everything in the store at from (its type fromType,
// opened with fromOptions) is copied into the one at to, when that one
// has nothing in it yet: every row of model (its bookkeeping too, and the
// store's metadata), by Core Data's -migratePersistentStore:. History is
// not copied: it begins again with the copy. The store at from is left as
// it was. *moved: whether it was copied (NO: the one at to has rows
// already, and is left alone). NO, and the error, when either does not
// open, or the copy is not saved.
FOUNDATION_EXPORT BOOL SNMoveStore(NSManagedObjectModel *model, NSString *fromType, NSURL *from, NSDictionary *_Nullable fromOptions,
                                   NSString *toType, NSURL *to, NSDictionary *_Nullable toOptions, BOOL *moved, NSError **error);

NS_ASSUME_NONNULL_END
