#import "SNWindowController.h"
#import "SNRichText.h"

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
    NSArray<SNFolder *> *_folders;
    NSArray<SNNote *> *_list;
    SNNoteEditor *_editor;
    SNTextBinding *_binding;
    BOOL _reloading;
    /* What the window shows: All Notes, a folder, or Recently Deleted. The
       folder table's selection follows it, not the other way round: rows
       move as folders come and go (by a sync, too). */
    NSManagedObjectID *_shownFolder;
    BOOL _showsDeleted;
}

/* What a note dragged onto a folder carries. */
static NSString * const SNNoteDragType = @"io.github.ashalkhakov.SimpleNotes.note";
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
    [_folderTable registerForDraggedTypes:@[ SNNoteDragType ]];
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
    NSString *where = _notes.serviceRoot ? _notes.serviceRoot.host : @"this device only (Server… to sync)";
    _statusField.stringValue = [NSString stringWithFormat:@"%@ — %@", status, where];
    _syncButton.enabled = _notes.serviceRoot && !_notes.syncing;
}

- (BOOL)windowShouldClose:(NSWindow *)sender {
    [self closeEditor];
    return YES;
}

#pragma mark reading

/* The folder list: All Notes, the folders, then Recently Deleted. */
- (NSInteger)deletedRow {
    return (NSInteger)_folders.count + 1;
}

- (BOOL)showsDeleted {
    return _showsDeleted;
}

- (SNFolder *)selectedFolder {
    if (_showsDeleted || !_shownFolder) return nil;
    for (SNFolder *f in _folders) if ([f.objectID isEqual:_shownFolder]) return f;
    return nil;
}

/* What the user chose in the folder table. */
- (void)showRow:(NSInteger)row {
    _showsDeleted = row == [self deletedRow];
    _shownFolder = row > 0 && (NSUInteger)row <= _folders.count ? _folders[(NSUInteger)row - 1].objectID : nil;
}

/* The row chosen from here: shown, and its notes listed. */
- (void)chooseRow:(NSInteger)row {
    [self showRow:row];
    _reloading = YES;
    [_folderTable selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
    _reloading = NO;
    [self reloadNotes];
}

- (SNNote *)selectedNote {
    NSInteger row = _noteTable.selectedRow;
    return row >= 0 && (NSUInteger)row < _list.count ? _list[(NSUInteger)row] : nil;
}

- (void)reloadFolders {
    _reloading = YES;
    _folders = _notes.folders;
    [_folderTable reloadData];
    /* A folder gone (deleted, here or elsewhere): All Notes. */
    if (_shownFolder && ![self selectedFolder]) _shownFolder = nil;
    NSUInteger row = _showsDeleted ? (NSUInteger)[self deletedRow] : 0;
    for (NSUInteger i = 0; i < _folders.count; i++)
        if ([_folders[i].objectID isEqual:_shownFolder]) row = i + 1;
    [_folderTable selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    _reloading = NO;
}

- (void)reloadNotes {
    NSManagedObjectID *selected = _editor.noteID ?: [self selectedNote].objectID;
    _reloading = YES;
    _list = [self showsDeleted] ? [_notes deletedNotesMatching:_searchField.stringValue]
                                : [_notes notesInFolder:[self selectedFolder] matching:_searchField.stringValue];
    [_noteTable reloadData];
    NSUInteger row = NSNotFound;
    for (NSUInteger i = 0; i < _list.count; i++)
        if ([_list[i].objectID isEqual:selected]) row = i;
    if (row != NSNotFound) [_noteTable selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    else [_noteTable deselectAll:nil];
    _reloading = NO;
    /* The open note left this list (deleted, recovered, moved, here or
       elsewhere): closed. One still here follows whether it is deleted. */
    if (_editor && row == NSNotFound) [self openNote:nil];
    else if (_editor) _textView.editable = !_list[row].deletedAt;
}

- (void)notesChanged:(NSNotification *)n {
    [self reloadFolders];
    [self reloadNotes];
    [self showStatus:n.userInfo[@"status"] ?: @""];
}

#pragma mark tables

- (NSInteger)numberOfRowsInTableView:(NSTableView *)table {
    return (NSInteger)(table == _folderTable ? _folders.count + 2 : _list.count);
}

- (id)tableView:(NSTableView *)table objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    if (table == _folderTable) {
        if (row == [self deletedRow])
            return [NSString stringWithFormat:@"Recently Deleted  (%lu)", (unsigned long)_notes.countOfDeletedNotes];
        SNFolder *f = row ? _folders[(NSUInteger)row - 1] : nil;
        NSString *name = row ? (f.name.length ? f.name : @"Untitled") : @"All Notes";
        return [NSString stringWithFormat:@"%@  (%lu)", name, (unsigned long)[_notes countOfNotesInFolder:f]];
    }
    SNNote *note = _list[(NSUInteger)row];
    NSMutableAttributedString *s = [[NSMutableAttributedString alloc] init];
    NSString *title = [NSString stringWithFormat:@"%@%@\n", note.isPinned ? @"★ " : @"", note.title ?: @"New Note"];
    [s appendAttributedString:[[NSAttributedString alloc] initWithString:title
                                                              attributes:@{ NSFontAttributeName: [NSFont boldSystemFontOfSize:13] }]];
    NSInteger left = SNDaysLeft(note);
    NSString *when = note.deletedAt ? (left == 1 ? @"1 day left" : [NSString stringWithFormat:@"%ld days left", (long)left]) : SNDateText(note.updated);
    NSString *detail = [NSString stringWithFormat:@"%@  %@", when, note.snippet];
    [s appendAttributedString:[[NSAttributedString alloc] initWithString:detail
                                                              attributes:@{ NSFontAttributeName: [NSFont systemFontOfSize:11],
                                                                            NSForegroundColorAttributeName: [NSColor secondaryLabelColor] }]];
    return s;
}

- (void)tableViewSelectionDidChange:(NSNotification *)n {
    if (_reloading) return;
    if (n.object == _folderTable) {
        [self showRow:_folderTable.selectedRow];
        [self reloadNotes];
        return;
    }
    SNNote *note = [self selectedNote];
    if (![note.objectID isEqual:_editor.noteID]) [self openNote:note];
}

#pragma mark dragging notes onto folders

- (BOOL)tableView:(NSTableView *)table writeRowsWithIndexes:(NSIndexSet *)rows toPasteboard:(NSPasteboard *)pasteboard {
    if (table != _noteTable || rows.firstIndex >= _list.count) return NO;
    NSURL *uri = _list[rows.firstIndex].objectID.URIRepresentation;
    [pasteboard declareTypes:@[ SNNoteDragType ] owner:nil];
    return [pasteboard setString:uri.absoluteString forType:SNNoteDragType];
}

- (NSDragOperation)tableView:(NSTableView *)table validateDrop:(id<NSDraggingInfo>)info proposedRow:(NSInteger)row
       proposedDropOperation:(NSTableViewDropOperation)operation {
    if (table != _folderTable || row < 0 || row > [self deletedRow]) return NSDragOperationNone;
    [table setDropRow:row dropOperation:NSTableViewDropOn];
    return NSDragOperationMove;
}

- (BOOL)tableView:(NSTableView *)table acceptDrop:(id<NSDraggingInfo>)info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)operation {
    NSString *uri = [[info draggingPasteboard] stringForType:SNNoteDragType];
    NSManagedObjectID *objectID = uri ? [_notes.context.persistentStoreCoordinator managedObjectIDForURIRepresentation:[NSURL URLWithString:uri]] : nil;
    SNNote *note = objectID ? (SNNote *)[_notes.context existingObjectWithID:objectID error:NULL] : nil;
    if (!note) return NO;
    if (row == [self deletedRow]) [_notes deleteNote:note];
    else [_notes moveNote:note toFolder:row > 0 ? _folders[(NSUInteger)row - 1] : nil];
    return YES;
}

#pragma mark the Move To menu

- (void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];
    SNNote *note = [self selectedNote];
    NSMenuItem *none = (NSMenuItem *)[menu addItemWithTitle:@"No Folder" action:@selector(moveNoteToFolder:) keyEquivalent:@""];
    none.target = self;
    if (note && !note.folder && !note.deletedAt) none.state = NSControlStateValueOn;
    if (_folders.count) [menu addItem:[NSMenuItem separatorItem]];
    for (SNFolder *f in _folders) {
        NSMenuItem *item = (NSMenuItem *)[menu addItemWithTitle:f.name.length ? f.name : @"Untitled" action:@selector(moveNoteToFolder:) keyEquivalent:@""];
        item.target = self;
        item.representedObject = f;
        if (note.folder == f && !note.deletedAt) item.state = NSControlStateValueOn;
    }
}

- (IBAction)moveNoteToFolder:(id)sender {
    SNNote *note = [self selectedNote];
    if (note) [_notes moveNote:note toFolder:[sender representedObject]];
}

- (NSString *)shownText {
    return [NSString stringWithFormat:@"folder row %ld of %ld, notes %@", (long)_folderTable.selectedRow, (long)_folderTable.numberOfRows,
                                      [_list valueForKey:@"title"]];
}

- (void)showAllNotes {
    [self chooseRow:0];
}

- (void)showRecentlyDeleted {
    [self chooseRow:[self deletedRow]];
}

- (BOOL)selectNoteTitled:(NSString *)title {
    for (NSUInteger i = 0; i < _list.count; i++)
        if ([_list[i].title isEqual:title]) {
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
    [_binding unbind];
    _binding = nil;
    [_editor close];
    _editor = nil;
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
}

#pragma mark the editor's delegate

/* What a sync brought into the open note, into the text view. */
- (void)noteEditor:(SNNoteEditor *)editor didMergeEdits:(NSArray<TTEdit *> *)edits {
    if (editor == _editor) [_binding applyEdits:edits];
}

- (void)noteEditorDidVanish:(SNNoteEditor *)editor {
    if (editor == _editor) [self openNote:nil];
}

#pragma mark the text view's delegate

- (void)textView:(SNTextView *)tv clickedCheckboxAtIndex:(NSUInteger)index {
    NSRange r = NSMakeRange(index, 0);
    if (![self beginFormattingAt:r]) return;
    [_binding toggleCheckedForParagraphsInRange:r];
    [self endFormatting];
}

/* Typing in lists, as Apple Notes has it (SNTextBinding). */
- (BOOL)textView:(NSTextView *)tv shouldChangeTextInRange:(NSRange)range replacementString:(NSString *)string {
    if (tv != _textView || !_binding) return YES;
    return [_binding shouldChangeTextInRange:range replacementString:string];
}

- (void)textDidChange:(NSNotification *)n {
    if (n.object == _textView) [_binding textDidChange];
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
    /* Not in Recently Deleted: a new note is written in All Notes. */
    if ([self showsDeleted]) [self chooseRow:0];
    SNNote *note = [_notes addNoteInFolder:[self selectedFolder]];
    _searchField.stringValue = @"";
    [self openNote:note];
    [self reloadNotes];
    [self.window makeFirstResponder:_textView];
}

- (IBAction)newFolder:(id)sender {
    NSString *name = SNAskForText(@"New Folder", @"Name of the new folder:", @"New Folder");
    if (!name.length) return;
    SNFolder *f = [_notes addFolderNamed:name];
    [self reloadFolders];
    NSUInteger i = [_folders indexOfObject:f];
    if (i != NSNotFound) [self chooseRow:(NSInteger)i + 1];
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
    alert.informativeText = @"Its notes go to Recently Deleted, where they can be recovered for 30 days.";
    [alert addButtonWithTitle:@"Delete"];
    [alert addButtonWithTitle:@"Cancel"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    [self chooseRow:0];
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
    if (a == @selector(sync:)) return _notes.serviceRoot && !_notes.syncing;
    BOOL enabled = NO;
    if ([self validateFormatItem:item enabled:&enabled]) return enabled;
    return YES;
}

#pragma mark formatting

/* Paragraph formatting, undoably: begun over the paragraphs a range
   touches, ended once the binding has changed them. */
- (BOOL)beginFormattingAt:(NSRange)range {
    if (!_binding || !_textView.isEditable) return NO;
    return [_textView shouldChangeTextInRange:[_binding paragraphsRangeForRange:range] replacementString:nil];
}

- (void)endFormatting {
    [_textView didChangeText];
}

/* On the selection, undoably; with none, on what is typed next. */
- (void)toggle:(NSString *)key {
    if (!_binding) return;
    NSRange range = _textView.selectedRange;
    if (!range.length) {
        [_binding toggle:key inRange:range];
        return;
    }
    if (![_textView shouldChangeTextInRange:range replacementString:nil]) return;
    [_binding toggle:key inRange:range];
    [_textView didChangeText];
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
    NSDictionary *p = enabled ? [_binding paragraphAttributesAt:_textView.selectedRange.location] : @{};
    BOOL on = NO;
    if (styles[name]) on = [styles[name] length] ? [p[SNStyleKey] isEqual:styles[name]] : (!p[SNStyleKey] && !p[SNListKey]);
    else if (lists[name]) on = [p[SNListKey] isEqual:lists[name]];
    else if (inline_[name]) on = enabled && [_binding range:_textView.selectedRange has:inline_[name]];
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
