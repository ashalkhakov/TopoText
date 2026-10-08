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
// folder named after what was imported, in the folder given.

#pragma once
#import "SNNotes.h"

NS_ASSUME_NONNULL_BEGIN

@interface SNNotes (Transfer)

// To url: a folder (made, or one empty) or, its name ending in .zip, a zip.
- (BOOL)exportMarkdownToURL:(NSURL *)url error:(NSError **)error;
// The same, as a zip's bytes.
- (NSData *)markdownZip;

// From url: a folder, a .zip, or a .md (.markdown, .txt, .html) file,
// into folder (nil: at the top). A single file goes straight into folder,
// as a note; anything else, into a new folder named after it. The notes
// made (none, and the error, when nothing could be read).
- (nullable NSArray<SNNote *> *)importFromURL:(NSURL *)url intoFolder:(nullable SNFolder *)folder error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
