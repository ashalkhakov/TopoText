// One SimpleNotes on a store at a time. Started again from the menu (on
// GNUstep nothing else keeps a second copy from starting; on macOS, open
// -n), a copy finds the store held, asks the copy holding it to show its
// window, and quits: two copies syncing one store each overwrite how far
// the other got, at every sync. The store is held by a lock on a file
// beside it, which the system lets go of when the copy ends, however it
// ends. Another store (-SNStore) is another copy's.

#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Whether this copy now holds the store, answering another copy's asking
// with the target's action (on the main thread); NO: another holds it, and
// was asked to show itself. GNUstep's (SNSingleCopy.m): through a message
// port named for the store; macOS's (SNSingleCopy-Apple.m): the other
// brought to the front.
FOUNDATION_EXPORT BOOL SNHoldStore(NSURL *store, id target, SEL action);

// The lock (SNStoreLock.m, POSIX's flock, on Linux and macOS;
// SNStoreLock-Windows.m, LockFileEx): the file at the path locked by this process until it ends;
// NO when another open of it holds it. YES when it cannot be opened at all
// (a store where no lock can be made is not kept from opening).
FOUNDATION_EXPORT BOOL SNLockFileForLife(NSString *path);

NS_ASSUME_NONNULL_END
