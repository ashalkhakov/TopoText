// A note's history, kept at the server (model version 7: NoteVersion), so
// that every device has the same one: they download it (ODataSync down)
// and never write it. On a write to a note's text, the text it had before
// is kept as a version, when the note's last one is SNVersionInterval old
// or older; then its versions are thinned. Edits a device makes offline
// make no version of their own: they come as one write when it syncs.

#pragma once
#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN

// How far apart a note's versions are at the least (default: 10 minutes).
FOUNDATION_EXPORT NSTimeInterval SNVersionInterval;

// Of a note's versions' dates (in any order), at now, the indexes of those
// to let go: every one of the last day is kept, the latest of each hour of
// the last week, the latest of each day of the last 30 days, none older.
FOUNDATION_EXPORT NSIndexSet *SNVersionsToForget(NSArray<NSDate *> *dates, NSDate *now);

// The text a note has now kept as its version (a copy without what was
// deleted from it: as small as its text), before a write changes it, when
// its last version is old enough; its versions thinned. In the note's
// context, saved with the write. NO: none kept (too soon, no text, or a
// model without versions).
FOUNDATION_EXPORT BOOL SNKeepVersionOfNote(NSManagedObject *note, NSDate *now);

// A note's versions let go of (the note deleted for good).
FOUNDATION_EXPORT void SNForgetVersionsOfNote(NSManagedObject *note);

NS_ASSUME_NONNULL_END
