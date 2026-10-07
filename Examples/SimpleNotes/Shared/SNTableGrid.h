// A table in a note, edited in place, as Apple Notes' are: a grid of text
// views, one a cell, laid over the table's place in the note (its
// attachment's character, which keeps the grid's room). Typed into, a cell's
// text is the table's (TTTable), saved a moment later and merged with what a
// sync brought meanwhile. AppKit's (macOS, GNUstep) and UIKit's.
//
//   Tab           the next cell; in the last one, a new row first
//   Shift-Tab     the cell before
//   Return        a new line in the cell
//   Format > Table, a cell's menu (iOS: the bar over the keyboard):
//                 rows and columns added and deleted
//
// A cell's text is formatted as a note's characters are (bold, italic,
// underline, strikethrough, links), by a binding of its own
// (SNTextBinding); not its paragraphs (no styles, no lists), as in Apple
// Notes.
//
// The grid's logic is here (SNTableGrid.m); its cells, their events and
// menus are each system's (SNTableGrid+System.m in AppKit/ and iOS/).

#pragma once
#import <Foundation/Foundation.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
typedef UIView SNGridView;
typedef UITextView SNGridTextView;
#else
#import <AppKit/AppKit.h>
typedef NSView SNGridView;
typedef NSTextView SNGridTextView;
#endif
#import <TopoText/TopoText.h>
#import "SNRichText.h"

@class SNNotes, SNTableGrid;

NS_ASSUME_NONNULL_BEGIN

@protocol SNTableGridDelegate <NSObject>
// The grid's size changed (a cell grew, a row came): its room in the note
// to change, and it to be put back over it.
- (void)tableGridChangedSize:(SNTableGrid *)grid;
@end

@interface SNTableGrid : SNGridView
// nil: no such table (not come yet).
- (nullable instancetype)initWithNotes:(SNNotes *)notes attachmentID:(NSString *)attachmentID;
@property (nonatomic, readonly, copy) NSString *attachmentID;
// The table as edited here: a session's copy (a replica of its own).
@property (nonatomic, readonly) TTTable *table;
@property (nonatomic, weak, nullable) id<SNTableGridDelegate> delegate;
// Laid out as wide as width allows: its size.
- (SNSize)layoutForWidth:(CGFloat)width;
@property (nonatomic, readonly) SNSize size;
// Typed into, or only read (a note in Recently Deleted).
@property (nonatomic, getter=isEditable) BOOL editable;
// The first cell typed into next.
- (void)beginEditing;
// What a sync brought, merged in and shown.
- (void)reloadFromStore;
// What was typed, merged into what is stored and saved (now, not later).
- (void)save;
// Saved, its cells no longer bound to the table (taken out of the note).
- (void)close;
// A cell's view; a cell's text set as typing it would (tests, self-tests).
- (nullable SNGridTextView *)textViewAtRow:(NSUInteger)row column:(NSUInteger)column;
// A cell's binding (to format what is selected in it); the cell typed in
// (nil: none).
- (nullable SNTextBinding *)bindingOfCell:(SNGridTextView *)cell;
- (nullable SNGridTextView *)cellTypedIn;
- (void)setString:(NSString *)string atRow:(NSUInteger)row column:(NSUInteger)column;

// The cell typed in's row and column (to the responder chain, from a cell).
- (IBAction)addRowAbove:(nullable id)sender;
- (IBAction)addRowBelow:(nullable id)sender;
- (IBAction)addColumnBefore:(nullable id)sender;
- (IBAction)addColumnAfter:(nullable id)sender;
- (IBAction)deleteRow:(nullable id)sender;
- (IBAction)deleteColumn:(nullable id)sender;
@end

// A note's tables, each kept over its place: made for each table's
// character, sized, put where it is after every edit, merge or resize.
@interface SNTableGrids : NSObject <SNTableGridDelegate>
// The binding's text view's tables; the binding keeps their rooms.
- (instancetype)initWithBinding:(SNTextBinding *)binding notes:(SNNotes *)notes;
// Each table's grid made, sized and put where it is now (after an edit, a
// merge, a resize).
- (void)update;
// What syncs brought, into each.
- (void)reload;
// Saved and taken away (the note closed).
- (void)removeAll;
- (nullable SNTableGrid *)gridForAttachmentID:(NSString *)attachmentID;
// The cell typed in, in any of them, and its binding (nil: none; the
// note's text is).
- (nullable SNGridTextView *)cellTypedIn;
- (nullable SNTextBinding *)bindingOfCell:(SNGridTextView *)cell;
@property (nonatomic, readonly) NSArray<SNTableGrid *> *grids;
@end

NS_ASSUME_NONNULL_END
