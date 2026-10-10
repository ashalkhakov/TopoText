// A note's text as Markdown, and back (CommonMark with GFM's tables, task
// lists and strikethrough): what export writes and import reads, one mapping
// both ways.
//
//   title, heading, subheading   # , ## , ###
//   mono paragraphs              a fenced code block
//   bullet, dash, number, check  * , - , 1. , - [ ] / - [x]  (indent: 4 spaces a level)
//   bold, italic, strike         **…**, *…*, ~~…~~
//   underline                    <u>…</u>
//   link                         [text](url)
//   attachment                   what the delegate makes of it (an image's
//                                ![](file), a file's [name](file), a table)
//
// Import reads more than export writes, as other apps write it: + lists,
// __bold__ and _italic_, setext-less headings deeper than ###, block quotes,
// <b>, <i>, <s>, <a href>, <img src>, entities.

#pragma once
#import <Foundation/Foundation.h>
#import <TopoText/TopoText.h>

NS_ASSUME_NONNULL_BEGIN

// Export: what an attachment is written as.
@protocol SNMarkdownExporting <NSObject>
// The Markdown for an attachment the text has (by its id): inline (an
// image's, a file's link) or a block (a table's, several lines). nil: left
// out.
- (nullable NSString *)markdownOfAttachment:(NSString *)attachmentID;
@end

// Import: what a link to a file, an image or a table becomes.
@protocol SNMarkdownImporting <NSObject>
@optional
// An image (or a file: image NO) at a path relative to the Markdown file,
// as an attachment of the note being made: its id. nil: not there (left as
// a link, or as its text).
- (nullable NSString *)attachmentForPath:(NSString *)path title:(NSString *)title image:(BOOL)image;
// A table's rows (each a list of its cells' text), as an attachment: its id.
// nil: written as lines of text.
- (nullable NSString *)attachmentForTableRows:(NSArray<NSArray<NSString *> *> *)rows;
@end

FOUNDATION_EXPORT NSString *SNMarkdownOfText(TopoText *text, id<SNMarkdownExporting> _Nullable exporter);

// title: the note's (a file's name, say); when the Markdown does not begin
// with it as a heading, it begins the text, as its title paragraph.
FOUNDATION_EXPORT TopoText *SNTextOfMarkdown(NSString *markdown, NSString *_Nullable title, id<SNMarkdownImporting> _Nullable importer);

// HTML (a note another app exported so: Trilium's default) as the Markdown
// import reads: its blocks (p, h1..h6, ul/ol/li and checkboxes, pre,
// table, blockquote, hr) as lines, its inline tags left for import to read.
FOUNDATION_EXPORT NSString *SNMarkdownOfHTML(NSString *html);

// A table's rows as a GFM table (the first row its header).
FOUNDATION_EXPORT NSString *SNMarkdownOfTableRows(NSArray<NSArray<NSString *> *> *rows);

NS_ASSUME_NONNULL_END
