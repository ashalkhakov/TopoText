// SNNotesTests' fixture, for its tests in other files (SNNotesTests+Peers.m):
// the server's service as simplenotes-server serves it, in the process, and
// devices on it, each with a store of its own.

#pragma once
#import <XCTest/XCTest.h>
#import <ODataSync/ODataSyncService.h>
#import "SNNotes.h"

NS_ASSUME_NONNULL_BEGIN

@interface SNNotesTests : XCTestCase <SNNoteEditorDelegate>
// The service's sync part (ODataSync's), as the server has it.
@property (nonatomic, readonly) ODataSyncService *histories;
// A new store's URL, its files removed after the test.
- (NSURL *)temporaryStore;
// A file or directory removed after the test.
- (void)removeAfterTest:(NSURL *)url;
// A device on a store of its own, syncing with the service; synced.
- (SNNotes *)device;
- (void)sync:(SNNotes *)device;
// The service again, a notebook for each user, who signs in with a token
// signed by the key returned; a device signed in as subject (nil: no one).
- (NSDictionary *)serveNotebooksPerUser;
- (SNNotes *)deviceOf:(nullable NSString *)subject key:(NSDictionary *)key;
// The run loop turned until done says so, or 10 (seconds) have gone by.
- (void)waitUntil:(BOOL (^)(void))done;
- (void)waitUntil:(BOOL (^)(void))done for:(NSTimeInterval)seconds;
@end

NS_ASSUME_NONNULL_END
