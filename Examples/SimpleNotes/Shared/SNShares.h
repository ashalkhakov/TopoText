// What is shared into SimpleNotes from other apps (the iOS Share
// extension's, the Services menu's) on its way to being a note: a folder in
// an inbox, a Markdown file named as the note is titled and its images
// beside it, which the app imports (SNTransfer: a note at the top, its
// images attached) and takes out of the inbox. Foundation only: the Share
// extension writes them, without the app.

#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// A shared item written into inbox (made if need be): its title (nil: the
// text's first line, else the link's host), its text (its lines the
// note's paragraphs), a link, and images (their data as they came: JPEG,
// PNG, HEIC...). Whole or not at all: the app never sees half of one.
FOUNDATION_EXPORT BOOL SNWriteShare(NSURL *inbox, NSString *_Nullable title, NSString *_Nullable text, NSURL *_Nullable link,
                                    NSArray<NSData *> *images, NSError **error);
// The items waiting in an inbox, the oldest first: each its Markdown file.
FOUNDATION_EXPORT NSArray<NSURL *> *SNSharesIn(NSURL *inbox);

NS_ASSUME_NONNULL_END
