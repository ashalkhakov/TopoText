#import "SNWindowController.h"
#import "SNRichText.h"
#import "SNModel.h"
#import "SNTableGrid.h"
#import "SNSmartFolderPanel.h"
#import "SNTransfer.h"

@implementation SNTextPanel
- (IBAction)ok:(id)sender { [NSApp stopModal]; }
- (IBAction)cancel:(id)sender { [NSApp abortModal]; }
@end

NSString *SNAskForText(NSString *title, NSString *message, NSString *initial) {
    SNTextPanel *panel = [[SNTextPanel alloc] initWithWindowNibName:@"TextPanel"];
    NSWindow *window = panel.window;
    window.title = title;
    panel.messageField.stringValue = message;
    panel.textField.stringValue = initial;
    [window center];
    [window makeFirstResponder:panel.textField];
    NSModalResponse r = [NSApp runModalForWindow:window];
    [window orderOut:nil];
    return r == NSModalResponseStop ? panel.textField.stringValue : nil;
}

@implementation SNWindowController {
    SNNotes *_notes;
    /* Move To being filled: GNUstep's -[NSMenu update] asks its delegate
       again for each item added (through -menuChanged). */
    BOOL _fillingMoveTo;
    /* The sidebar, as last read: the folders at the top, each folder's
       (by object ID), and the tags. */
    NSArray<SNFolder *> *_topFolders;
    NSDictionary<NSManagedObjectID *, NSArray<SNFolder *> *> *_children;
    NSArray<NSString *> *_tags;
    /* What the user collapsed: folders' object IDs, and the tags. */
    NSMutableSet *_collapsed;
    /* The note list: notes, and the headings of their groups (strings). */
    NSArray *_rows;
    SNNoteEditor *_editor;
    SNTextBinding *_binding;
    /* The open note's tables, each over its place in the text. */
    SNTableGrids *_grids;
    BOOL _reloading;
    /* What the window shows: All Notes, a folder, or Recently Deleted. The
       folder table's selection follows it, not the other way round: rows
       move as folders come and go (by a sync, too). */
    NSManagedObjectID *_shownFolder;
    BOOL _showsDeleted;
    NSString *_shownTag;
}

/* What a note dragged onto a folder carries, and a folder dragged into
   another. */
static NSString * const SNNoteDragType = @"io.github.ashalkhakov.SimpleNotes.note";
static NSString * const SNFolderDragType = @"io.github.ashalkhakov.SimpleNotes.folder";
/* The sidebar's rows that are not folders: All Notes, Recently Deleted,
   and the Tags heading. A tag's row is the tag's string, with its #. */
static NSString * const SNAllNotesItem = @"SNAllNotes";
static NSString * const SNDeletedItem = @"SNRecentlyDeleted";
static NSString * const SNTagsItem = @"SNTags";
/* The Move To submenu, found by its tag (MainMenu.xib). */
static const NSInteger SNMoveToMenuTag = 7001;

- (instancetype)initWithNotes:(SNNotes *)notes {
    if (!(self = [super initWithWindowNibName:@"NotesWindow"])) return nil;
    _notes = notes;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(notesChanged:)
                                                 name:SNNotesDidChangeNotification object:notes];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)windowDidLoad {
    [super windowDidLoad];
    [_textView useListLayoutManager];
    /* Undo is the binding's: by the characters' ids, so it survives a
       sync's edits; the text view's own (by positions) would not. */
    _textView.allowsUndo = NO;
    _textView.textContainerInset = NSMakeSize(14, 14);
    _textView.textContainer.widthTracksTextView = YES;
    /* The whole pane is the note's: a click below its last line is in it
       too (GNUstep's text view keeps to its text, unless told). */
    NSSize pane = _textView.enclosingScrollView.contentSize;
    _textView.minSize = NSMakeSize(0, pane.height);
    _textView.maxSize = NSMakeSize(FLT_MAX, FLT_MAX);
    _textView.verticallyResizable = YES;
    _textView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [_textView setFrameSize:NSMakeSize(pane.width, MAX(pane.height, _textView.frame.size.height))];
    /* Notes are dragged onto folders: to move them, or onto Recently
       Deleted to delete them. */
    [_folderTable registerForDraggedTypes:@[ SNNoteDragType, SNFolderDragType ]];
    [_folderTable setDraggingSourceOperationMask:NSDragOperationMove forLocal:YES];
    _collapsed = [NSMutableSet set];
    [_noteTable setDraggingSourceOperationMask:NSDragOperationMove forLocal:YES];
    NSMenuItem *moveTo = nil;
    for (NSMenuItem *top in [NSApp mainMenu].itemArray)
        if ((moveTo = (NSMenuItem *)[top.submenu itemWithTag:SNMoveToMenuTag])) break;
    moveTo.submenu.delegate = self;
    [self reloadFolders];
    [self reloadNotes];
    [self showStatus:_notes.status];
}

- (void)showStatus:(NSString *)status {
    /* This computer only: said each time, as nothing backs the notes up. */
    NSString *where = _notes.serviceRoot ? _notes.serviceRoot.host : @"on this computer only, not synced or backed up (Sync… to sync)";
    _statusField.stringValue = [NSString stringWithFormat:@"%@ — %@", status, where];
    _syncButton.enabled = _notes.serviceRoot && !_notes.syncing;
}

- (BOOL)windowShouldClose:(NSWindow *)sender {
    [self closeEditor];
    return YES;
}

#pragma mark reading

- (BOOL)showsDeleted {
    return _showsDeleted;
}

- (SNFolder *)folderWithID:(NSManagedObjectID *)objectID {
    SNFolder *f = objectID ? (SNFolder *)[_notes.context existingObjectWithID:objectID error:NULL] : nil;
    return f.isDeleted ? nil : f;
}

- (SNFolder *)selectedFolder {
    return _showsDeleted || _shownTag ? nil : [self folderWithID:_shownFolder];
}

/* The sidebar's item for what the window shows. */
- (id)shownItem {
    if (_showsDeleted) return SNDeletedItem;
    if (_shownTag) return [self itemForTag:[@"#" stringByAppendingString:_shownTag]];
    return [self selectedFolder] ?: SNAllNotesItem;
}

/* The one string each tag's row is, kept across reloads. */
- (NSString *)itemForTag:(NSString *)tag {
    for (NSString *t in _tags) if ([t isEqualToString:tag]) return t;
    return nil;
}

/* What the user chose in the sidebar. */
- (void)showItem:(id)item {
    _showsDeleted = item == SNDeletedItem;
    _shownTag = [item isKindOfClass:[NSString class]] && [item hasPrefix:@"#"] ? [item substringFromIndex:1] : nil;
    _shownFolder = [item isKindOfClass:[SNFolder class]] ? [item objectID] : nil;
}

/* An item chosen from here: shown, and its notes listed. */
- (void)chooseItem:(id)item {
    [self showItem:item];
    [self selectShownItem];
    [self reloadNotes];
}

- (void)selectShownItem {
    _reloading = YES;
    id item = [self shownItem];
    for (id f = [item isKindOfClass:[SNFolder class]] ? [_notes parentOfFolder:item] : nil; f; f = [_notes parentOfFolder:f])
        [_folderTable expandItem:f];
    NSInteger row = [_folderTable rowForItem:item];
    if (row < 0) row = [_folderTable rowForItem:SNAllNotesItem];
    [_folderTable selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
    _reloading = NO;
}

- (SNNote *)selectedNote {
    NSInteger row = _noteTable.selectedRow;
    id r = row >= 0 && (NSUInteger)row < _rows.count ? _rows[(NSUInteger)row] : nil;
    return [r isKindOfClass:[SNNote class]] ? r : nil;
}

- (void)reloadFolders {
    _reloading = YES;
    _topFolders = [_notes foldersInFolder:nil];
    NSMutableDictionary *children = [NSMutableDictionary dictionary];
    for (SNFolder *f in _notes.folderTree) {
        SNFolder *parent = [_notes parentOfFolder:f];
        if (!parent) continue;
        NSMutableArray *in = children[parent.objectID] ?: (children[parent.objectID] = [NSMutableArray array]);
        [in addObject:f];
    }
    _children = children;
    /* A tag's row keeps its string while the tag is there. */
    NSMutableArray *tags = [NSMutableArray array];
    for (NSString *t in _notes.tags) {
        NSString *tag = [@"#" stringByAppendingString:t];
        [tags addObject:[self itemForTag:tag] ?: tag];
    }
    _tags = tags;
    [_folderTable reloadData];
    for (SNFolder *f in _notes.folderTree)
        if (_children[f.objectID] && ![_collapsed containsObject:f.objectID]) [_folderTable expandItem:f];
    if (_tags.count && ![_collapsed containsObject:SNTagsItem]) [_folderTable expandItem:SNTagsItem];
    /* A folder gone (deleted, here or elsewhere), or a tag: All Notes. */
    if (_shownFolder && ![self selectedFolder]) _shownFolder = nil;
    if (_shownTag && ![self itemForTag:[@"#" stringByAppendingString:_shownTag]]) _shownTag = nil;
    _reloading = NO;
    [self selectShownItem];
}

- (void)reloadNotes {
    /* The note chosen in the list, else the one open: a note being closed
       saves as it goes, and must not take the choice back to itself. */
    NSManagedObjectID *selected = [self selectedNote].objectID ?: _editor.noteID;
    _reloading = YES;
    NSString *search = _searchField.stringValue;
    if ([self showsDeleted]) {
        _rows = [_notes deletedNotesMatching:search];
    } else {
        NSArray *notes = _shownTag ? [_notes notesTagged:_shownTag matching:search] : [_notes notesInFolder:[self selectedFolder] matching:search];
        NSMutableArray *rows = [NSMutableArray array];
        SNSortOrder order = [_notes sortOrderForFolder:_shownTag ? nil : [self selectedFolder]];
        for (SNNoteGroup *g in [_notes groupsOfNotes:notes sortedBy:order]) {
            if (g.title) [rows addObject:g.title];
            [rows addObjectsFromArray:g.notes];
        }
        _rows = rows;
    }
    [_noteTable reloadData];
    NSUInteger row = NSNotFound;
    for (NSUInteger i = 0; i < _rows.count; i++)
        if ([_rows[i] isKindOfClass:[SNNote class]] && [[_rows[i] objectID] isEqual:selected]) row = i;
    if (row != NSNotFound) [_noteTable selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    else [_noteTable deselectAll:nil];
    _reloading = NO;
    /* The open note left this list (deleted, recovered, moved, here or
       elsewhere): closed. One still here follows whether it is deleted. */
    if (_editor && row == NSNotFound) [self openNote:nil];
    else if (_editor) {
        _textView.editable = ![_rows[row] deletedAt];
        [_grids update];
    }
}

- (void)notesChanged:(NSNotification *)n {
    [self reloadFolders];
    [self reloadNotes];
    /* An attachment can come after the text that has it; a table's cells
       can have been typed into elsewhere. */
    [_binding refreshAttachments];
    [_grids reload];
    [self showStatus:n.userInfo[@"status"] ?: @""];
}

#pragma mark the sidebar

- (NSInteger)outlineView:(NSOutlineView *)outline numberOfChildrenOfItem:(id)item {
    if (!item) return (NSInteger)_topFolders.count + 2 + (_tags.count ? 1 : 0);
    if (item == SNTagsItem) return (NSInteger)_tags.count;
    if ([item isKindOfClass:[SNFolder class]]) return (NSInteger)_children[[item objectID]].count;
    return 0;
}

- (id)outlineView:(NSOutlineView *)outline child:(NSInteger)index ofItem:(id)item {
    NSUInteger i = (NSUInteger)index;
    if (item == SNTagsItem) return _tags[i];
    if (item) return _children[[item objectID]][i];
    if (i == 0) return SNAllNotesItem;
    if (i <= _topFolders.count) return _topFolders[i - 1];
    return i == _topFolders.count + 1 ? SNDeletedItem : SNTagsItem;
}

- (BOOL)outlineView:(NSOutlineView *)outline isItemExpandable:(id)item {
    return item == SNTagsItem || ([item isKindOfClass:[SNFolder class]] && _children[[item objectID]].count);
}

- (id)outlineView:(NSOutlineView *)outline objectValueForTableColumn:(NSTableColumn *)column byItem:(id)item {
    if (item == SNTagsItem)
        return [[NSAttributedString alloc] initWithString:@"Tags" attributes:@{ NSFontAttributeName: [NSFont boldSystemFontOfSize:11],
                                                                               NSForegroundColorAttributeName: [NSColor secondaryLabelColor] }];
    if (item == SNDeletedItem)
        return [NSString stringWithFormat:@"Recently Deleted  (%lu)", (unsigned long)_notes.countOfDeletedNotes];
    if ([item isKindOfClass:[SNFolder class]]) {
        SNFolder *f = item;
        /* A smart folder: a gear before its name, as Apple Notes' icon. */
        return [NSString stringWithFormat:@"%@%@  (%lu)", [_notes isSmartFolder:f] ? @"\u2699\uFE0E " : @"",
                                          f.name.length ? f.name : @"Untitled", (unsigned long)[_notes countOfNotesInFolder:f]];
    }
    if (item == SNAllNotesItem) return [NSString stringWithFormat:@"All Notes  (%lu)", (unsigned long)[_notes countOfNotesInFolder:nil]];
    return [NSString stringWithFormat:@"%@  (%lu)", item, (unsigned long)[_notes countOfNotesTagged:[item substringFromIndex:1]]];
}

- (BOOL)outlineView:(NSOutlineView *)outline shouldSelectItem:(id)item {
    return item != SNTagsItem;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)n {
    if (_reloading) return;
    id item = [_folderTable itemAtRow:_folderTable.selectedRow];
    if (!item) return;
    [self showItem:item];
    [self reloadNotes];
}

/* What the user collapsed stays so through reloads. */
- (void)outlineViewItemDidCollapse:(NSNotification *)n {
    if (_reloading) return;
    id item = n.userInfo[@"NSObject"];
    [_collapsed addObject:[item isKindOfClass:[SNFolder class]] ? [item objectID] : item];
}

- (void)outlineViewItemDidExpand:(NSNotification *)n {
    if (_reloading) return;
    id item = n.userInfo[@"NSObject"];
    [_collapsed removeObject:[item isKindOfClass:[SNFolder class]] ? [item objectID] : item];
}

#pragma mark the note list

- (NSInteger)numberOfRowsInTableView:(NSTableView *)table {
    return (NSInteger)_rows.count;
}

- (id)tableView:(NSTableView *)table objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    id r = _rows[(NSUInteger)row];
    if ([r isKindOfClass:[NSString class]])
        return [[NSAttributedString alloc] initWithString:r attributes:@{ NSFontAttributeName: [NSFont boldSystemFontOfSize:11],
                                                                          NSForegroundColorAttributeName: [NSColor secondaryLabelColor] }];
    SNNote *note = r;
    NSMutableAttributedString *s = [[NSMutableAttributedString alloc] init];
    NSString *title = [NSString stringWithFormat:@"%@%@\n", note.isPinned ? @"★ " : @"", note.title ?: @"New Note"];
    [s appendAttributedString:[[NSAttributedString alloc] initWithString:title
                                                              attributes:@{ NSFontAttributeName: [NSFont boldSystemFontOfSize:13] }]];
    NSInteger left = SNDaysLeft(note);
    NSString *when = note.deletedAt ? (left == 1 ? @"1 day left" : [NSString stringWithFormat:@"%ld days left", (long)left]) : SNDateText(note.edited);
    NSString *detail = [NSString stringWithFormat:@"%@  %@", when, note.snippet];
    [s appendAttributedString:[[NSAttributedString alloc] initWithString:detail
                                                              attributes:@{ NSFontAttributeName: [NSFont systemFontOfSize:11],
                                                                            NSForegroundColorAttributeName: [NSColor secondaryLabelColor] }]];
    return s;
}

/* A group's heading: a row of its own, lower, not chosen. */
- (BOOL)tableView:(NSTableView *)table isGroupRow:(NSInteger)row {
    return [_rows[(NSUInteger)row] isKindOfClass:[NSString class]];
}

- (CGFloat)tableView:(NSTableView *)table heightOfRow:(NSInteger)row {
    return [_rows[(NSUInteger)row] isKindOfClass:[NSString class]] ? 20 : table.rowHeight;
}

- (BOOL)tableView:(NSTableView *)table shouldSelectRow:(NSInteger)row {
    return [_rows[(NSUInteger)row] isKindOfClass:[SNNote class]];
}

- (void)tableViewSelectionDidChange:(NSNotification *)n {
    if (_reloading) return;
    SNNote *note = [self selectedNote];
    if (![note.objectID isEqual:_editor.noteID]) [self openNote:note];
}

#pragma mark dragging notes and folders

- (BOOL)tableView:(NSTableView *)table writeRowsWithIndexes:(NSIndexSet *)rows toPasteboard:(NSPasteboard *)pasteboard {
    id r = rows.firstIndex < _rows.count ? _rows[rows.firstIndex] : nil;
    if (table != _noteTable || ![r isKindOfClass:[SNNote class]]) return NO;
    [pasteboard declareTypes:@[ SNNoteDragType ] owner:nil];
    return [pasteboard setString:[r objectID].URIRepresentation.absoluteString forType:SNNoteDragType];
}

- (BOOL)outlineView:(NSOutlineView *)outline writeItems:(NSArray *)items toPasteboard:(NSPasteboard *)pasteboard {
    SNFolder *f = items.firstObject;
    if (![f isKindOfClass:[SNFolder class]]) return NO;
    [pasteboard declareTypes:@[ SNFolderDragType ] owner:nil];
    return [pasteboard setString:f.objectID.URIRepresentation.absoluteString forType:SNFolderDragType];
}

- (id)draggedObject:(id<NSDraggingInfo>)info type:(NSString *)type {
    NSString *uri = [[info draggingPasteboard] stringForType:type];
    NSManagedObjectID *objectID = uri ? [_notes.context.persistentStoreCoordinator managedObjectIDForURIRepresentation:[NSURL URLWithString:uri]] : nil;
    return objectID ? [_notes.context existingObjectWithID:objectID error:NULL] : nil;
}

/* A note onto a folder, All Notes (out of its folder) or Recently Deleted;
   a folder into another, or onto All Notes (to the top). */
- (NSDragOperation)outlineView:(NSOutlineView *)outline validateDrop:(id<NSDraggingInfo>)info proposedItem:(id)item
            proposedChildIndex:(NSInteger)index {
    if ([[info draggingPasteboard] stringForType:SNNoteDragType]) {
        if (![item isKindOfClass:[SNFolder class]] && item != SNAllNotesItem && item != SNDeletedItem) return NSDragOperationNone;
        /* Nothing goes into a smart folder: its rules choose. */
        if ([_notes isSmartFolder:item]) return NSDragOperationNone;
    } else {
        SNFolder *dragged = [self draggedObject:info type:SNFolderDragType];
        if (!dragged) return NSDragOperationNone;
        if (!item || item == SNAllNotesItem) item = SNAllNotesItem;
        else if (![item isKindOfClass:[SNFolder class]] || item == dragged || [_notes folder:item isInFolder:dragged] ||
                 [_notes isSmartFolder:item])
            return NSDragOperationNone;
    }
    [outline setDropItem:item dropChildIndex:NSOutlineViewDropOnItemIndex];
    return NSDragOperationMove;
}

- (BOOL)outlineView:(NSOutlineView *)outline acceptDrop:(id<NSDraggingInfo>)info item:(id)item childIndex:(NSInteger)index {
    SNFolder *into = [item isKindOfClass:[SNFolder class]] ? item : nil;
    SNNote *note = [self draggedObject:info type:SNNoteDragType];
    if ([note isKindOfClass:[SNNote class]]) {
        if (item == SNDeletedItem) [_notes deleteNote:note];
        else [_notes moveNote:note toFolder:into];
        return YES;
    }
    SNFolder *folder = [self draggedObject:info type:SNFolderDragType];
    return [folder isKindOfClass:[SNFolder class]] && [_notes moveFolder:folder toFolder:into];
}

#pragma mark the Move To menu

/* The folders, indented as in the sidebar: what each item says, the folder
   it moves the note to (NSNull: none), and whether it is the note's. */
- (NSArray<NSArray *> *)moveToItems {
    SNNote *note = [self selectedNote];
    NSMutableArray *items = [NSMutableArray array];
    [items addObject:@[ @"No Folder", [NSNull null], @(note && !note.folder && !note.deletedAt) ]];
    for (SNFolder *f in _notes.folderTree) {
        if ([_notes isSmartFolder:f]) continue;
        NSString *indent = [@"" stringByPaddingToLength:[_notes depthOfFolder:f] * 3 withString:@" " startingAtIndex:0];
        [items addObject:@[ [indent stringByAppendingString:f.name.length ? f.name : @"Untitled"], f, @(note.folder == f && !note.deletedAt) ]];
    }
    return items;
}

/* Filled only when what it says changes: GNUstep updates menus often,
   and Eau's menu bar is told of every change. */
- (void)menuNeedsUpdate:(NSMenu *)menu {
    if (_fillingMoveTo) return;
    NSArray<NSArray *> *items = [self moveToItems];
    NSMutableArray *shown = [NSMutableArray array];
    for (NSMenuItem *item in menu.itemArray) {
        if (item.isSeparatorItem) continue;
        [shown addObject:@[ item.title, item.representedObject ?: [NSNull null], @(item.state == NSControlStateValueOn) ]];
    }
    if ([shown isEqual:items]) return;
    _fillingMoveTo = YES;
    [menu removeAllItems];
    for (NSArray *i in items) {
        NSMenuItem *item = (NSMenuItem *)[menu addItemWithTitle:i[0] action:@selector(moveNoteToFolder:) keyEquivalent:@""];
        item.target = self;
        if (i[1] != [NSNull null]) item.representedObject = i[1];
        if ([i[2] boolValue]) item.state = NSControlStateValueOn;
        if (i == items.firstObject && items.count > 1) [menu addItem:[NSMenuItem separatorItem]];
    }
    _fillingMoveTo = NO;
}

- (IBAction)moveNoteToFolder:(id)sender {
    SNNote *note = [self selectedNote];
    if (note) [_notes moveNote:note toFolder:[sender representedObject]];
}

- (NSString *)shownText {
    id item = [_folderTable itemAtRow:_folderTable.selectedRow];
    NSString *shown = [item isKindOfClass:[SNFolder class]] ? [item name] : item;
    NSMutableArray *titles = [NSMutableArray array];
    for (id r in _rows)
        if ([r isKindOfClass:[SNNote class]]) [titles addObject:[r title] ?: @""];
    return [NSString stringWithFormat:@"%@ chosen, of %ld rows; notes %@", shown, (long)_folderTable.numberOfRows, titles];
}

- (NSArray<NSString *> *)shownRows {
    NSMutableArray *rows = [NSMutableArray array];
    for (id r in _rows) [rows addObject:[r isKindOfClass:[SNNote class]] ? [r title] ?: @"" : [@"## " stringByAppendingString:r]];
    return rows;
}

- (NSArray<NSString *> *)sidebarRows {
    NSMutableArray *rows = [NSMutableArray array];
    for (NSInteger i = 0; i < _folderTable.numberOfRows; i++) {
        id item = [_folderTable itemAtRow:i];
        NSString *name = [item isKindOfClass:[SNFolder class]] ? [item name] : item == SNAllNotesItem ? @"All Notes"
                       : item == SNDeletedItem ? @"Recently Deleted" : item == SNTagsItem ? @"Tags" : item;
        [rows addObject:[[@"" stringByPaddingToLength:(NSUInteger)[_folderTable levelForRow:i] * 2 withString:@" " startingAtIndex:0]
                            stringByAppendingString:name]];
    }
    return rows;
}

- (void)showAllNotes {
    [self chooseItem:SNAllNotesItem];
}

- (void)showRecentlyDeleted {
    [self chooseItem:SNDeletedItem];
}

- (BOOL)showFolderNamed:(NSString *)name {
    for (SNFolder *f in _notes.folders)
        if ([f.name isEqual:name]) {
            [self chooseItem:f];
            return YES;
        }
    return NO;
}

- (BOOL)showTag:(NSString *)tag {
    NSString *item = [self itemForTag:[@"#" stringByAppendingString:tag.lowercaseString]];
    if (!item) return NO;
    [self chooseItem:item];
    return YES;
}

- (BOOL)showNote:(SNNote *)note {
    if (note.deletedAt) [self showRecentlyDeleted];
    else if (_shownTag || [self showsDeleted] || (note.folder != [self selectedFolder] && [self selectedFolder])) [self showAllNotes];
    for (NSUInteger pass = 0; pass < 2; pass++) {
        for (NSUInteger i = 0; i < _rows.count; i++)
            if (_rows[i] == note) {
                [_noteTable selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
                [_noteTable scrollRowToVisible:(NSInteger)i];
                return YES;
            }
        /* Not listed: a search hides it. */
        _searchField.stringValue = @"";
        [self reloadNotes];
    }
    return NO;
}

- (BOOL)selectNoteTitled:(NSString *)title {
    for (NSUInteger i = 0; i < _rows.count; i++)
        if ([_rows[i] isKindOfClass:[SNNote class]] && [[_rows[i] title] isEqual:title]) {
            [_noteTable selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
            return YES;
        }
    return NO;
}

- (IBAction)searchChanged:(id)sender {
    [self reloadNotes];
}

#pragma mark the note

- (void)closeEditor {
    [_grids removeAll];
    _grids = nil;
    [_binding unbind];
    _binding = nil;
    /* Let go of first: closing saves, and the list reloads meanwhile. */
    SNNoteEditor *closing = _editor;
    _editor = nil;
    [closing close];
}

- (void)openNote:(SNNote *)note {
    [self closeEditor];
    [_textView.undoManager removeAllActions];
    if (!note) {
        [_textView.textStorage setAttributedString:[[NSAttributedString alloc] init]];
        _textView.editable = NO;
        return;
    }
    _editor = [_notes editorForNote:note];
    _editor.delegate = self;
    _binding = [[SNTextBinding alloc] initWithTextView:_textView editor:_editor];
    /* In Recently Deleted, a note is read, not written: Recover first. */
    _textView.editable = !note.deletedAt;
    _textView.selectedRange = NSMakeRange(_textView.textStorage.length, 0);
    [_binding selectionDidChange];
    _grids = [[SNTableGrids alloc] initWithBinding:_binding notes:_notes];
}

#pragma mark the editor's delegate

/* What a sync brought into the open note, into the text view. */
- (void)noteEditor:(SNNoteEditor *)editor didMergeEdits:(NSArray<TTEdit *> *)edits {
    if (editor != _editor) return;
    [_binding applyEdits:edits];
    [_grids update];
}

- (void)noteEditorDidVanish:(SNNoteEditor *)editor {
    if (editor == _editor) [self openNote:nil];
}

#pragma mark the text view's delegate

/* A link to a note opens it here; any other, in its own application. */
- (BOOL)textView:(NSTextView *)tv clickedOnLink:(id)link atIndex:(NSUInteger)index {
    NSURL *url = [link isKindOfClass:[NSURL class]] ? link : [link isKindOfClass:[NSString class]] ? SNURLOfLink(link) : nil;
    if (!url) return NO;
    NSString *noteID = SNNoteIDInLink(url);
    if (noteID) {
        SNNote *note = [_notes noteWithID:noteID];
        if (!note || ![self showNote:note]) NSBeep();
        return YES;
    }
    return [[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)textView:(SNTextView *)tv clickedCheckboxAtIndex:(NSUInteger)index {
    NSRange r = NSMakeRange(index, 0);
    if (![self beginFormattingAt:r]) return;
    [_binding toggleCheckedForParagraphsInRange:r];
    [self endFormatting];
    if (_notes.movesCheckedToBottom) [self moveCheckedToBottomAt:index];
}

/* Undoably: a move keeps the list's length, so the text view's undo of
   "this range, replaced" puts the old order back. */
- (void)moveCheckedToBottomAt:(NSUInteger)index {
    NSRange list = [_binding checklistRangeAt:index];
    if (list.location == NSNotFound || !_textView.isEditable) return;
    NSRange sel = _textView.selectedRange;
    if (![_textView shouldChangeTextInRange:list replacementString:[_textView.string substringWithRange:list]]) return;
    if ([_binding moveCheckedToBottomOfChecklistAt:index]) [_textView didChangeText];
    _textView.selectedRange = sel;
}

/* Typing in lists, as Apple Notes has it (SNTextBinding). */
- (BOOL)textView:(NSTextView *)tv shouldChangeTextInRange:(NSRange)range replacementString:(NSString *)string {
    if (tv != _textView || !_binding) return YES;
    return [_binding shouldChangeTextInRange:range replacementString:string];
}

- (void)textDidChange:(NSNotification *)n {
    if (n.object != _textView) return;
    [_binding textDidChange];
    /* The tables after what changed moved with it. */
    [_grids update];
}

- (void)textViewDidChangeSelection:(NSNotification *)n {
    if (n.object == _textView) [_binding selectionDidChange];
}

/* Shift-Tab: an item outdented. */
- (BOOL)textView:(NSTextView *)tv doCommandBySelector:(SEL)command {
    if (tv != _textView || !_binding || command != @selector(insertBacktab:)) return NO;
    if (![_binding paragraphAttributesAt:tv.selectedRange.location][SNListKey]) return NO;
    [self decreaseIndentation:nil];
    return YES;
}

#pragma mark actions

- (IBAction)newNote:(id)sender {
    /* Not in Recently Deleted or a tag: a new note is written in All Notes. */
    if ([self showsDeleted] || _shownTag) [self chooseItem:SNAllNotesItem];
    SNNote *note = [_notes addNoteInFolder:[self selectedFolder]];
    _searchField.stringValue = @"";
    [self openNote:note];
    [self reloadNotes];
    [self.window makeFirstResponder:_textView];
}

/* In the folder chosen; at the top when none is. */
- (IBAction)newFolder:(id)sender {
    SNFolder *parent = [self selectedFolder];
    NSString *message = parent ? [NSString stringWithFormat:@"Name of the new folder in “%@”:", parent.name ?: @""] : @"Name of the new folder:";
    NSString *name = SNAskForText(@"New Folder", message, @"New Folder");
    if (!name.length) return;
    SNFolder *f = [_notes addFolderNamed:name inFolder:parent];
    [self reloadFolders];
    [self chooseItem:f];
}

/* A smart folder, as Apple Notes': its name and rules asked for. */
- (IBAction)newSmartFolder:(id)sender {
    SNSmartFolderPanel *panel = [[SNSmartFolderPanel alloc] initWithName:@"Smart Folder" filter:[[SNSmartFilter alloc] init]];
    if (![panel runModal]) return;
    SNFolder *f = [_notes addSmartFolderNamed:panel.name filter:panel.filter inFolder:nil];
    [self reloadFolders];
    [self chooseItem:f];
}

- (IBAction)editSmartFolder:(id)sender {
    SNFolder *f = [self selectedFolder];
    SNSmartFilter *filter = f ? [_notes filterOfFolder:f] : nil;
    if (!filter) return;
    SNSmartFolderPanel *panel = [[SNSmartFolderPanel alloc] initWithName:f.name ?: @"" filter:filter];
    if (![panel runModal]) return;
    [_notes renameFolder:f to:panel.name];
    [_notes setFilter:panel.filter ofFolder:f];
}

- (IBAction)importNotes:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseDirectories = YES;
    panel.canChooseFiles = YES;
    panel.allowsMultipleSelection = YES;
    panel.message = @"A folder of Markdown files, a zip of one (Trilium's export, say), or Markdown files.";
    panel.prompt = @"Import";
    if ([panel runModal] != NSModalResponseOK) return;
    SNFolder *into = [_notes isSmartFolder:[self selectedFolder]] ? nil : [self selectedFolder];
    for (NSURL *url in panel.URLs) {
        NSError *error = nil;
        if ([_notes importFromURL:url intoFolder:into error:&error]) continue;
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = [NSString stringWithFormat:@"“%@” was not imported.", url.lastPathComponent];
        alert.informativeText = error.localizedDescription ?: @"";
        [alert runModal];
    }
    [self reloadFolders];
    [self reloadNotes];
}

- (IBAction)exportAllNotes:(id)sender {
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.nameFieldStringValue = @"Notes.zip";
    panel.message = @"Every note as Markdown, in a zip (or, the name without .zip, a folder).";
    panel.prompt = @"Export";
    if ([panel runModal] != NSModalResponseOK || !panel.URL) return;
    NSError *error = nil;
    if ([_notes exportMarkdownToURL:panel.URL error:&error]) return;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"The notes were not exported.";
    alert.informativeText = error.localizedDescription ?: @"";
    [alert runModal];
}

- (IBAction)renameFolder:(id)sender {
    SNFolder *f = [self selectedFolder];
    if (!f) return;
    NSString *name = SNAskForText(@"Rename Folder", @"New name of the folder:", f.name ?: @"");
    if (name.length) [_notes renameFolder:f to:name];
}

- (IBAction)deleteFolder:(id)sender {
    SNFolder *f = [self selectedFolder];
    if (!f) return;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"Delete the folder “%@”?", f.name ?: @""];
    alert.informativeText = [_notes isSmartFolder:f] ? @"Its notes stay where they are." : [_notes foldersInFolder:f].count
        ? @"The folders in it are deleted too. Their notes go to Recently Deleted, where they can be recovered for 30 days."
        : @"Its notes go to Recently Deleted, where they can be recovered for 30 days.";
    [alert addButtonWithTitle:@"Delete"];
    [alert addButtonWithTitle:@"Cancel"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    [self chooseItem:SNAllNotesItem];
    [_notes deleteFolder:f];
}

- (IBAction)deleteNote:(id)sender {
    SNNote *note = [self selectedNote];
    if (!note) return;
    if (note.deletedAt) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = [NSString stringWithFormat:@"Delete “%@” immediately?", note.title ?: @"New Note"];
        alert.informativeText = @"It is deleted on every device, and cannot be recovered.";
        [alert addButtonWithTitle:@"Delete"];
        [alert addButtonWithTitle:@"Cancel"];
        if ([alert runModal] != NSAlertFirstButtonReturn) return;
        [self openNote:nil];
        [_notes deleteNoteImmediately:note];
        return;
    }
    [self openNote:nil];
    [_notes deleteNote:note];
}

- (IBAction)recoverNote:(id)sender {
    SNNote *note = [self selectedNote];
    if (note.deletedAt) [_notes recoverNote:note];
}

- (IBAction)emptyRecentlyDeleted:(id)sender {
    if (!_notes.countOfDeletedNotes) return;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Delete every note in Recently Deleted?";
    alert.informativeText = @"They are deleted on every device, and cannot be recovered.";
    [alert addButtonWithTitle:@"Delete All"];
    [alert addButtonWithTitle:@"Cancel"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    [self openNote:nil];
    [_notes emptyRecentlyDeleted];
}

- (IBAction)togglePinned:(id)sender {
    SNNote *note = [self selectedNote];
    if (note) [_notes setNote:note pinned:!note.isPinned];
}

- (IBAction)sync:(id)sender {
    [_notes sync];
}

- (IBAction)findNote:(id)sender {
    [self.window makeFirstResponder:_searchField];
}

#pragma mark links

/* On the selection; with none, on the link the insertion point is in. */
- (IBAction)addLink:(id)sender {
    SNTextBinding *binding;
    NSTextView *tv = [self formattedTextView:&binding];
    if (!binding || !tv.isEditable) return;
    NSRange range = tv.selectedRange;
    NSString *current = [binding linkAt:range.length ? range.location : (range.location ? range.location - 1 : 0)];
    if (!range.length && current) {
        NSRange whole;
        [tv.textStorage attribute:SNLinkAttributeName atIndex:range.location ? range.location - 1 : 0
            longestEffectiveRange:&whole inRange:NSMakeRange(0, tv.textStorage.length)];
        range = whole;
    }
    if (!range.length) {
        NSBeep();
        return;
    }
    NSString *link = SNAskForText(@"Add Link", @"Link (a web address, or a link to a note; empty: none):", current ?: @"https://");
    if (!link) return;
    if (![tv shouldChangeTextInRange:range replacementString:nil]) return;
    [binding setLink:[link isEqualToString:@"https://"] ? nil : link inRange:range];
    [tv didChangeText];
}

/* Images shown as images; any other file as a card, opened from it. */
- (IBAction)attachFile:(id)sender {
    if (!_binding || !_textView.isEditable || [self typingInTable]) return;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowsMultipleSelection = YES;
    if ([panel runModal] != NSModalResponseOK) return;
    for (NSURL *url in panel.URLs) {
        NSData *data = [NSData dataWithContentsOfURL:url];
        if ([self attachImageData:data] || [self attachFileData:data name:url.lastPathComponent]) continue;
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = data.length > SNAttachmentMaxFileBytes
            ? [NSString stringWithFormat:@"“%@” is larger than 25 MB.", url.lastPathComponent]
            : [NSString stringWithFormat:@"“%@” could not be read.", url.lastPathComponent];
        [alert runModal];
    }
}

- (BOOL)attachFileData:(NSData *)data name:(NSString *)name {
    if (!_binding || !_textView.isEditable || !data) return NO;
    NSRange r = _textView.selectedRange;
    if (![_textView shouldChangeTextInRange:r replacementString:@"\uFFFC"]) return NO;
    if (![_binding insertFileData:data name:name inRange:r]) return NO;
    [_textView didChangeText];
    _textView.selectedRange = NSMakeRange(r.location + 1, 0);
    return YES;
}

/* A file's card double-clicked: the file opened in its own application. */
- (void)textView:(NSTextView *)tv doubleClickedOnCell:(id<NSTextAttachmentCell>)cell inRect:(NSRect)rect atIndex:(NSUInteger)index {
    if (tv != _textView) return;
    [self openFileOfAttachment:[_binding attachmentIDAt:index]];
}

- (BOOL)openFileOfAttachment:(NSString *)attachmentID {
    SNAttachment *a = attachmentID ? [_notes attachmentWithID:attachmentID] : nil;
    NSURL *url = a ? [_notes fileURLOfAttachment:a] : nil;
    return url && [[NSWorkspace sharedWorkspace] openURL:url];
}

- (BOOL)attachImageData:(NSData *)data {
    if (!_binding || !_textView.isEditable) return NO;
    NSRange r = _textView.selectedRange;
    if (![_textView shouldChangeTextInRange:r replacementString:@"\uFFFC"]) return NO;
    if (![_binding insertImageData:data inRange:r]) return NO;
    [_textView didChangeText];
    _textView.selectedRange = NSMakeRange(r.location + 1, 0);
    return YES;
}

- (NSString *)insertTableWithRows:(NSUInteger)rows columns:(NSUInteger)columns {
    if (!_binding || !_textView.isEditable || [self typingInTable]) return nil;
    NSRange r = _textView.selectedRange;
    if (![_textView shouldChangeTextInRange:r replacementString:@"\uFFFC"]) return nil;
    NSString *made = [_binding insertTableWithRows:rows columns:columns inRange:r];
    if (made) [_textView didChangeText];
    _textView.selectedRange = NSMakeRange(r.location + 1, 0);
    [_grids update];
    return made;
}

/* Two rows, two columns, as Apple Notes' are, its first cell typed in. */
- (IBAction)addTable:(id)sender {
    NSString *made = [self insertTableWithRows:2 columns:2];
    [[_grids gridForAttachmentID:made] beginEditing];
}

- (SNTableGrid *)gridForAttachmentID:(NSString *)attachmentID {
    return [_grids gridForAttachmentID:attachmentID];
}

- (IBAction)copyNoteLink:(id)sender {
    SNNote *note = [self selectedNote];
    if (!note.id) return;
    NSString *link = SNLinkToNote(note.id).absoluteString;
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb declareTypes:@[ NSPasteboardTypeString ] owner:nil];
    [pb setString:link forType:NSPasteboardTypeString];
}

#pragma mark sorting and grouping

/* The device's choice; every list follows it (SNNotes says so). */
- (IBAction)sortByDateEdited:(id)sender { _notes.sortOrder = SNSortByDateEdited; }
- (IBAction)sortByDateCreated:(id)sender { _notes.sortOrder = SNSortByDateCreated; }
- (IBAction)sortByTitle:(id)sender { _notes.sortOrder = SNSortByTitle; }
- (IBAction)toggleGroupByDate:(id)sender { _notes.groupsByDate = !_notes.groupsByDate; }
/* View > Sort Folder By: the folder shown, its own order (Default: the
   device's), synced with it. */
- (void)sortFolderBy:(NSNumber *)order {
    SNFolder *f = [self selectedFolder];
    if (f) [_notes setSortOrder:order ofFolder:f];
}
- (IBAction)sortFolderByDefault:(id)sender { [self sortFolderBy:nil]; }
- (IBAction)sortFolderByDateEdited:(id)sender { [self sortFolderBy:@(SNSortByDateEdited)]; }
- (IBAction)sortFolderByDateCreated:(id)sender { [self sortFolderBy:@(SNSortByDateCreated)]; }
- (IBAction)sortFolderByTitle:(id)sender { [self sortFolderBy:@(SNSortByTitle)]; }

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    SEL a = item.action;
    if (a == @selector(togglePinned:)) {
        item.title = [self selectedNote].isPinned ? @"Unpin Note" : @"Pin Note";
        return [self selectedNote] != nil && ![self selectedNote].deletedAt;
    }
    if (a == @selector(deleteNote:)) {
        item.title = [self selectedNote].deletedAt ? @"Delete Immediately…" : @"Delete Note";
        return [self selectedNote] != nil;
    }
    if (a == @selector(recoverNote:)) return [self selectedNote].deletedAt != nil;
    if (a == @selector(emptyRecentlyDeleted:)) return _notes.countOfDeletedNotes > 0;
    if (a == @selector(moveNoteToFolder:)) return [self selectedNote] != nil;
    if (a == @selector(deleteFolder:) || a == @selector(renameFolder:)) return [self selectedFolder] != nil;
    if (a == @selector(editSmartFolder:)) return [_notes isSmartFolder:[self selectedFolder]];
    if (a == @selector(sortFolderByDefault:) || a == @selector(sortFolderByDateEdited:) || a == @selector(sortFolderByDateCreated:) ||
        a == @selector(sortFolderByTitle:)) {
        SNFolder *f = [self selectedFolder];
        NSNumber *own = f ? [_notes sortOrderOfFolder:f] : nil;
        NSNumber *mine = a == @selector(sortFolderByDateEdited:) ? @(SNSortByDateEdited) : a == @selector(sortFolderByDateCreated:) ? @(SNSortByDateCreated)
                       : a == @selector(sortFolderByTitle:) ? @(SNSortByTitle) : nil;
        item.state = f && (mine ? [own isEqual:mine] : !own) ? NSControlStateValueOn : NSControlStateValueOff;
        return f != nil;
    }
    if (a == @selector(sync:)) return _notes.serviceRoot && !_notes.syncing;
    if (a == @selector(copyNoteLink:)) return [self selectedNote] != nil;
    if (a == @selector(addLink:)) return _binding != nil && _textView.isEditable;
    if (a == @selector(attachFile:) || a == @selector(addTable:)) return _binding != nil && _textView.isEditable && ![self typingInTable];
    if (a == @selector(moveCheckedToBottom:))
        return _binding != nil && _textView.isEditable && ![self typingInTable] && [_binding checklistRangeAt:_textView.selectedRange.location].location != NSNotFound;
    if (a == @selector(toggleKeepCheckedAtBottom:)) {
        item.state = _notes.movesCheckedToBottom ? NSControlStateValueOn : NSControlStateValueOff;
        return YES;
    }
    SNSortOrder order = _notes.sortOrder;
    if (a == @selector(sortByDateEdited:)) item.state = order == SNSortByDateEdited ? NSControlStateValueOn : NSControlStateValueOff;
    if (a == @selector(sortByDateCreated:)) item.state = order == SNSortByDateCreated ? NSControlStateValueOn : NSControlStateValueOff;
    if (a == @selector(sortByTitle:)) item.state = order == SNSortByTitle ? NSControlStateValueOn : NSControlStateValueOff;
    if (a == @selector(toggleGroupByDate:)) {
        item.state = _notes.groupsByDate ? NSControlStateValueOn : NSControlStateValueOff;
        return order != SNSortByTitle;
    }
    BOOL enabled = NO;
    if ([self validateFormatItem:item enabled:&enabled]) return enabled;
    return YES;
}

#pragma mark formatting

/* What character formatting and links go on: a table's cell typed in, or
   else the note's text; and its binding. */
- (NSTextView *)formattedTextView:(SNTextBinding **)binding {
    NSTextView *cell = (NSTextView *)[_grids cellTypedIn];
    SNTextBinding *b = cell ? [_grids bindingOfCell:cell] : nil;
    *binding = b ?: _binding;
    return b ? cell : _textView;
}

/* A table's cell typed in: its paragraphs are not formatted (no styles, no
   lists, as Apple Notes' cells), and nothing is put in it but text. */
- (BOOL)typingInTable {
    return [_grids cellTypedIn] != nil;
}

/* Paragraph formatting, undoably: begun over the paragraphs a range
   touches, ended once the binding has changed them. */
- (BOOL)beginFormattingAt:(NSRange)range {
    if (!_binding || !_textView.isEditable || [self typingInTable]) return NO;
    return [_textView shouldChangeTextInRange:[_binding paragraphsRangeForRange:range] replacementString:nil];
}

- (void)endFormatting {
    [_textView didChangeText];
}

/* On the selection, undoably; with none, on what is typed next. */
- (void)toggle:(NSString *)key {
    SNTextBinding *binding;
    NSTextView *tv = [self formattedTextView:&binding];
    if (!binding || !tv.isEditable) return;
    NSRange range = tv.selectedRange;
    if (!range.length) {
        [binding toggle:key inRange:range];
        return;
    }
    if (![tv shouldChangeTextInRange:range replacementString:nil]) return;
    [binding toggle:key inRange:range];
    [tv didChangeText];
}

- (void)style:(NSString *)style {
    NSRange r = _textView.selectedRange;
    if (![self beginFormattingAt:r]) return;
    [_binding setStyle:style forParagraphsInRange:r];
    [self endFormatting];
}

- (void)list:(NSString *)list {
    NSRange r = _textView.selectedRange;
    if (![self beginFormattingAt:r]) return;
    [_binding toggleList:list forParagraphsInRange:r];
    [self endFormatting];
}

- (void)indentBy:(NSInteger)by {
    NSRange r = _textView.selectedRange;
    if (![self beginFormattingAt:r]) return;
    [_binding indentParagraphsInRange:r by:by];
    [self endFormatting];
}

- (IBAction)toggleBold:(id)sender { [self toggle:SNBoldKey]; }
- (IBAction)toggleItalic:(id)sender { [self toggle:SNItalicKey]; }
- (IBAction)toggleUnderline:(id)sender { [self toggle:SNUnderlineKey]; }
- (IBAction)toggleStrikethrough:(id)sender { [self toggle:SNStrikeKey]; }
- (IBAction)styleTitle:(id)sender { [self style:SNStyleTitle]; }
- (IBAction)styleHeading:(id)sender { [self style:SNStyleHeading]; }
- (IBAction)styleSubheading:(id)sender { [self style:SNStyleSubheading]; }
- (IBAction)styleBody:(id)sender { [self style:nil]; }
- (IBAction)styleMono:(id)sender { [self style:SNStyleMono]; }
- (IBAction)toggleBulletList:(id)sender { [self list:SNListBullet]; }
- (IBAction)toggleDashList:(id)sender { [self list:SNListDash]; }
- (IBAction)toggleNumberList:(id)sender { [self list:SNListNumber]; }
- (IBAction)toggleChecklist:(id)sender { [self list:SNListCheck]; }
- (IBAction)toggleChecked:(id)sender {
    NSRange r = _textView.selectedRange;
    if (![self beginFormattingAt:r]) return;
    [_binding toggleCheckedForParagraphsInRange:r];
    [self endFormatting];
    if (_notes.movesCheckedToBottom) [self moveCheckedToBottomAt:r.location];
}

- (IBAction)moveCheckedToBottom:(id)sender {
    [self moveCheckedToBottomAt:_textView.selectedRange.location];
}

- (IBAction)toggleKeepCheckedAtBottom:(id)sender {
    _notes.movesCheckedToBottom = !_notes.movesCheckedToBottom;
    if (_notes.movesCheckedToBottom) [self moveCheckedToBottomAt:_textView.selectedRange.location];
}
- (IBAction)increaseIndentation:(id)sender { [self indentBy:1]; }
- (IBAction)decreaseIndentation:(id)sender { [self indentBy:-1]; }

/* A Format menu item (NO for any other): whether it applies, and ticked when the selection
   is so already. */
- (BOOL)validateFormatItem:(NSMenuItem *)item enabled:(BOOL *)enabledOut {
    SEL a = item.action;
    static NSDictionary *styles, *lists, *inline_;
    if (!styles) {
        styles = @{ NSStringFromSelector(@selector(styleTitle:)): SNStyleTitle, NSStringFromSelector(@selector(styleHeading:)): SNStyleHeading,
                    NSStringFromSelector(@selector(styleSubheading:)): SNStyleSubheading, NSStringFromSelector(@selector(styleMono:)): SNStyleMono,
                    NSStringFromSelector(@selector(styleBody:)): @"" };
        lists = @{ NSStringFromSelector(@selector(toggleBulletList:)): SNListBullet, NSStringFromSelector(@selector(toggleDashList:)): SNListDash,
                   NSStringFromSelector(@selector(toggleNumberList:)): SNListNumber, NSStringFromSelector(@selector(toggleChecklist:)): SNListCheck };
        inline_ = @{ NSStringFromSelector(@selector(toggleBold:)): SNBoldKey, NSStringFromSelector(@selector(toggleItalic:)): SNItalicKey,
                     NSStringFromSelector(@selector(toggleUnderline:)): SNUnderlineKey, NSStringFromSelector(@selector(toggleStrikethrough:)): SNStrikeKey };
    }
    NSString *name = NSStringFromSelector(a);
    BOOL other = a == @selector(toggleChecked:) || a == @selector(increaseIndentation:) || a == @selector(decreaseIndentation:);
    if (!styles[name] && !lists[name] && !inline_[name] && !other) return NO;
    BOOL enabled = _binding != nil && _textView.isEditable;
    if (inline_[name]) {
        SNTextBinding *binding;
        NSTextView *tv = [self formattedTextView:&binding];
        item.state = enabled && [binding range:tv.selectedRange has:inline_[name]] ? NSControlStateValueOn : NSControlStateValueOff;
        *enabledOut = enabled;
        return YES;
    }
    if ([self typingInTable]) enabled = NO;
    NSDictionary *p = enabled ? [_binding paragraphAttributesAt:_textView.selectedRange.location] : @{};
    BOOL on = NO;
    if (styles[name]) on = [styles[name] length] ? [p[SNStyleKey] isEqual:styles[name]] : (!p[SNStyleKey] && !p[SNListKey]);
    else if (lists[name]) on = [p[SNListKey] isEqual:lists[name]];
    else if (a == @selector(toggleChecked:)) {
        on = [p[SNCheckedKey] boolValue];
        enabled = enabled && [p[SNListKey] isEqual:SNListCheck];
    }
    else if (a == @selector(decreaseIndentation:)) enabled = enabled && p[SNIndentKey] != nil;
    item.state = on ? NSControlStateValueOn : NSControlStateValueOff;
    *enabledOut = enabled;
    return YES;
}

@end
