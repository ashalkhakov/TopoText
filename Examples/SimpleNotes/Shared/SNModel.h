// SimpleNotes' model (SimpleNotes.xcdatamodeld): the same one on the
// devices and at the server, compiled by Xcode's momc or FreeCoreData's.
//
//   Folder   id (key), name, created, parent (to-one: the folder it is
//            in), children, notes, modified, versions
//   Note     id (key), title, body, bodyText, created, edited, pinned,
//            deletedAt, folder (to-one), modified, versions
//
// Versions: 1, the first; 2 adds Note.deletedAt (Recently Deleted); 3 adds
// Folder.parent (folders in folders), and renames Note.updated edited:
// on Apple's Core Data, "updated" is NSManagedObject's own (-isUpdated), and
// what key-value coding reads and writes for it (ODataKit, a sync) is that.
//
// Both are ODataSync both entities: either side changes them. A note's body
// is a TopoText (bodyText), merged when two devices edited it apart; body
// and title are its plain text and first line, for lists and for the
// service's $filter and $search. modified is the hybrid logical clock last
// writer wins orders by; versions the version vector.

#pragma once
#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const SNFolderEntity;  // @"Folder"
FOUNDATION_EXPORT NSString * const SNNoteEntity;    // @"Note"

// The compiled model in a bundle's resources (SimpleNotes.momd).
FOUNDATION_EXPORT NSURL *_Nullable SNModelURLInBundle(NSBundle *bundle);
// A new model each call, from the compiled one (a coordinator takes one for
// itself, and the device's and the server's each add their bookkeeping);
// nil when it is not there.
FOUNDATION_EXPORT NSManagedObjectModel *_Nullable SNModelAt(NSURL *_Nullable url);
// The one in the main bundle.
FOUNDATION_EXPORT NSManagedObjectModel *_Nullable SNModel(void);

// The first line of a body, trimmed: a note's title ("New Note" for none).
FOUNDATION_EXPORT NSString *SNTitleOfBody(NSString *body);
// What a list shows under the title: the rest, on one line.
FOUNDATION_EXPORT NSString *SNSnippetOfBody(NSString *body);

// A body sent by a device on an older version of the model, as this one
// has it: Updated (version 1, 2) is Edited now. For the server's
// upgradeBody.
FOUNDATION_EXPORT NSDictionary<NSString *, id> *SNUpgradeBody(NSDictionary<NSString *, id> *body, NSEntityDescription *entity);

// Tags, as Apple Notes has them: # and a word typed in a note's text
// (letters, digits, - and _, at least one letter), at the start or after a
// space. Where they are in text, each range its # included.
FOUNDATION_EXPORT NSArray<NSValue *> *SNTagRangesInText(NSString *text);
// Web addresses in text, as Apple Notes links them while one types:
// http:// and https:// ones, and www. ones; a trailing full stop, comma or
// closing bracket not theirs.
FOUNDATION_EXPORT NSArray<NSValue *> *SNLinkRangesInText(NSString *text);
// A link to a note (simplenotes://note/<id>), and the note's id in one
// (nil: not a link to a note).
FOUNDATION_EXPORT NSURL *SNLinkToNote(NSString *noteID);
FOUNDATION_EXPORT NSString *_Nullable SNNoteIDInLink(NSURL *_Nullable link);
// What a link typed or detected opens: as given when it has a scheme, else
// https:// (www.example.com).
FOUNDATION_EXPORT NSURL *_Nullable SNURLOfLink(NSString *text);
// The tags in text, lowercase (one tag whatever its case), each once, in
// order, without their #.
FOUNDATION_EXPORT NSArray<NSString *> *SNTagsInText(NSString *text);

NS_ASSUME_NONNULL_END
