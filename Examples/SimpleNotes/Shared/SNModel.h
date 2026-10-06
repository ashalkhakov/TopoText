// SimpleNotes' model (SimpleNotes.xcdatamodeld): the same one on the
// devices and at the server, compiled by Xcode's momc or FreeCoreData's.
//
//   Folder   id (key), name, created, modified, versions
//   Note     id (key), title, body, bodyText, created, updated, pinned,
//            folder (to-one), modified, versions
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

NS_ASSUME_NONNULL_END
