// Notes out as Markdown, and in from Markdown (and HTML): what File >
// Export and File > Import do.
//
// Export writes every note (Recently Deleted's not) as a folder, or a zip
// of one: a folder for each folder (smart folders not: their notes are
// others'), a note as <title>.md in its folder's, the notes in none at the
// top; a note's images and files under _attachments/<title>/, its tables
// in it as GFM tables (SNMarkdown.h). Each file dated as its note was last
// edited.
//
// Import reads such a folder (or zip) back, or another app's export: a
// folder of .md files and the folders in it (Obsidian's, Bear's, Joplin's),
// or Trilium's (Export as Markdown or HTML, zipped: its !!!meta.json says
// what each file is; a note with notes under it is a folder, its own text a
// note in it). An image or file a note links to, there in the export, is
// attached to it; a GFM table becomes a table. Everything goes into a new
// folder in the folder given: named after what was imported, or, when that
// is one folder (Trilium's export of one note and those under it, a zip of
// one folder), that folder.
//
// Either runs on a thread of its own, in a context of its own, a few
// hundred notes at a time: as many notes as there are, in little memory,
// and the app goes on meanwhile. What is imported is saved as it goes (a
// sync may send it meanwhile); stopped or failed, what was imported so far
// stays.

#pragma once
#import "SNNotes.h"

NS_ASSUME_NONNULL_BEGIN

@class SNTransfer;

@protocol SNTransferDelegate <NSObject>
// On the main thread: now and then as it goes (a few times a second at
// most), and once when it is done (stopped, failed or not).
- (void)transferDidProgress:(SNTransfer *)transfer;
- (void)transferDidFinish:(SNTransfer *)transfer;
@end

@interface SNTransfer : NSObject

// Every note to url: a folder (made if need be) or, its name ending in
// .zip, a zip.
+ (instancetype)exportOfNotes:(SNNotes *)notes toURL:(NSURL *)url;
// From url: a folder, a .zip, or a .md (.markdown, .txt, .html) file,
// into folder (nil: at the top). A single file goes straight into folder,
// as a note.
+ (instancetype)importIntoNotes:(SNNotes *)notes fromURL:(NSURL *)url folder:(nullable SNFolder *)folder;

@property (nonatomic, weak, nullable) id<SNTransferDelegate> delegate;
@property (nonatomic, readonly) NSURL *URL;
@property (nonatomic, readonly, getter=isImport) BOOL import;

// On a thread of its own; the delegate told.
- (void)start;
// Here, until done (tests): NO and the error when it failed.
- (BOOL)runAndWait:(NSError **)error;
// Stopped at the next note; what is done stays done.
- (void)cancel;

// How far: notes done of those there are (0: not counted yet).
@property (atomic, readonly) NSUInteger done;
@property (atomic, readonly) NSUInteger total;
// What it is doing, in words: "Importing 1,240 of 25,000 notes…".
@property (atomic, readonly, copy) NSString *status;
@property (atomic, readonly, getter=isFinished) BOOL finished;
@property (atomic, readonly, getter=isCancelled) BOOL cancelled;
// Why it failed (nil: it did not).
@property (atomic, readonly, nullable) NSError *error;
// The notes made (import), by ID, in the order made.
@property (atomic, readonly, copy) NSArray<NSManagedObjectID *> *madeNotes;
// What was left out, and why: a line each ("Board.json: a canvas").
@property (atomic, readonly, copy) NSArray<NSString *> *skipped;
// When finished: what happened, in a sentence or two, for an alert.
@property (atomic, readonly, copy) NSString *summary;

@end

NS_ASSUME_NONNULL_END
