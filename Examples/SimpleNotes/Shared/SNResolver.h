// How SimpleNotes settles a note or a folder changed on two sides at once.
//
//   the body       merged, TopoText's (TTSyncResolver): both sides' edits
//   the title      the merged body's first line
//   updated        the later of the two
//   anything else  from the side that changed it; changed on both, the
//                  later writer's (the modified stamps)
//   deleted on one side, changed on the other: the change stands, so an
//                  edit is never lost to a deletion made without seeing it
//
// The same whichever side asks, as a peer's conflict needs.

#pragma once
#import <TopoTextSync/TopoTextSync.h>

NS_ASSUME_NONNULL_BEGIN

@interface SNResolver : TTSyncResolver
- (instancetype)init;
@end

NS_ASSUME_NONNULL_END
