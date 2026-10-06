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
}

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

- (SNFolder *)selectedFolder {
    NSInteger row = _folderTable.selectedRow;
    return row > 0 && (NSUInteger)row <= _folders.count ? _folders[(NSUInteger)row - 1] : nil;
}

- (SNNote *)selectedNote {
    NSInteger row = _noteTable.selectedRow;
    return row >= 0 && (NSUInteger)row < _list.count ? _list[(NSUInteger)row] : nil;
}

- (void)reloadFolders {
    NSManagedObjectID *selected = [self selectedFolder].objectID;
    BOOL all = _folderTable.selectedRow <= 0;
    _reloading = YES;
    _folders = _notes.folders;
    [_folderTable reloadData];
    NSUInteger row = 0;
    if (!all)
        for (NSUInteger i = 0; i < _folders.count; i++)
            if ([_folders[i].objectID isEqual:selected]) row = i + 1;
    [_folderTable selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    _reloading = NO;
}

- (void)reloadNotes {
    NSManagedObjectID *selected = _editor.noteID ?: [self selectedNote].objectID;
    _reloading = YES;
    _list = [_notes notesInFolder:[self selectedFolder] matching:_searchField.stringValue];
    [_noteTable reloadData];
    NSUInteger row = NSNotFound;
    for (NSUInteger i = 0; i < _list.count; i++)
        if ([_list[i].objectID isEqual:selected]) row = i;
    if (row != NSNotFound) [_noteTable selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    else [_noteTable deselectAll:nil];
    _reloading = NO;
}

- (void)notesChanged:(NSNotification *)n {
    [self reloadFolders];
    [self reloadNotes];
    [self showStatus:n.userInfo[@"status"] ?: @""];
}

#pragma mark tables

- (NSInteger)numberOfRowsInTableView:(NSTableView *)table {
    return (NSInteger)(table == _folderTable ? _folders.count + 1 : _list.count);
}

- (id)tableView:(NSTableView *)table objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    if (table == _folderTable) {
        SNFolder *f = row ? _folders[(NSUInteger)row - 1] : nil;
        NSString *name = row ? (f.name.length ? f.name : @"Untitled") : @"All Notes";
        return [NSString stringWithFormat:@"%@  (%lu)", name, (unsigned long)[_notes countOfNotesInFolder:f]];
    }
    SNNote *note = _list[(NSUInteger)row];
    NSMutableAttributedString *s = [[NSMutableAttributedString alloc] init];
    NSString *title = [NSString stringWithFormat:@"%@%@\n", note.isPinned ? @"★ " : @"", note.title ?: @"New Note"];
    [s appendAttributedString:[[NSAttributedString alloc] initWithString:title
                                                              attributes:@{ NSFontAttributeName: [NSFont boldSystemFontOfSize:13] }]];
    NSString *detail = [NSString stringWithFormat:@"%@  %@", SNDateText(note.updated), note.snippet];
    [s appendAttributedString:[[NSAttributedString alloc] initWithString:detail
                                                              attributes:@{ NSFontAttributeName: [NSFont systemFontOfSize:11],
                                                                            NSForegroundColorAttributeName: [NSColor secondaryLabelColor] }]];
    return s;
}

- (void)tableViewSelectionDidChange:(NSNotification *)n {
    if (_reloading) return;
    if (n.object == _folderTable) {
        [self reloadNotes];
        return;
    }
    SNNote *note = [self selectedNote];
    if (![note.objectID isEqual:_editor.noteID]) [self openNote:note];
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
    _binding = [[SNTextBinding alloc] initWithStorage:_textView.textStorage editor:_editor];
    NSTextView *tv = _textView;
    _binding.getSelection = ^NSRange { return tv.selectedRange; };
    _binding.setSelection = ^(NSRange r) { tv.selectedRange = r; };
    /* Edits from elsewhere: what undo remembers no longer fits the text. */
    _binding.didApplyRemoteEdits = ^{ [tv.undoManager removeAllActions]; };
    __weak SNWindowController *weak = self;
    _editor.didVanish = ^{ [weak openNote:nil]; };
    _textView.editable = YES;
    _textView.typingAttributes = [_binding typingAttributesAt:_textView.textStorage.length];
    _textView.selectedRange = NSMakeRange(_textView.textStorage.length, 0);
}

#pragma mark actions

- (IBAction)newNote:(id)sender {
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
    if (i != NSNotFound) [_folderTable selectRowIndexes:[NSIndexSet indexSetWithIndex:i + 1] byExtendingSelection:NO];
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
    alert.informativeText = @"Its notes are kept, in All Notes.";
    [alert addButtonWithTitle:@"Delete"];
    [alert addButtonWithTitle:@"Cancel"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    [_folderTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    [_notes deleteFolder:f];
}

- (IBAction)deleteNote:(id)sender {
    SNNote *note = [self selectedNote];
    if (!note) return;
    [self openNote:nil];
    [_notes deleteNote:note];
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
        return [self selectedNote] != nil;
    }
    if (a == @selector(deleteNote:)) return [self selectedNote] != nil;
    if (a == @selector(deleteFolder:) || a == @selector(renameFolder:)) return [self selectedFolder] != nil;
    if (a == @selector(sync:)) return _notes.serviceRoot && !_notes.syncing;
    if (a == @selector(toggleBold:) || a == @selector(toggleItalic:) || a == @selector(toggleUnderline:) ||
        a == @selector(toggleStrikethrough:) || a == @selector(styleTitle:) || a == @selector(styleHeading:) || a == @selector(styleBody:))
        return _binding != nil;
    return YES;
}

#pragma mark formatting

/* On the selection, undoably; with none, on what is typed next. */
- (void)format:(void (^)(SNTextBinding *binding, NSRange range))change typing:(NSString *)key {
    if (!_binding) return;
    NSRange range = _textView.selectedRange;
    if (key && !range.length) {
        NSMutableDictionary *t = [SNTextAttributes(_textView.typingAttributes) mutableCopy];
        if ([t[key] boolValue]) [t removeObjectForKey:key]; else t[key] = @YES;
        _textView.typingAttributes = SNViewAttributes(t);
        return;
    }
    if (!key) range = [_textView.string paragraphRangeForRange:range];
    if (![_textView shouldChangeTextInRange:range replacementString:nil]) return;
    change(_binding, range);
    [_textView didChangeText];
    _textView.typingAttributes = [_binding typingAttributesAt:NSMaxRange(_textView.selectedRange)];
}

- (void)toggle:(NSString *)key {
    [self format:^(SNTextBinding *b, NSRange r) { [b toggle:key inRange:r]; } typing:key];
}

- (void)style:(NSString *)style {
    [self format:^(SNTextBinding *b, NSRange r) { [b setStyle:style forParagraphsInRange:r]; } typing:nil];
}

- (IBAction)toggleBold:(id)sender { [self toggle:SNBoldKey]; }
- (IBAction)toggleItalic:(id)sender { [self toggle:SNItalicKey]; }
- (IBAction)toggleUnderline:(id)sender { [self toggle:SNUnderlineKey]; }
- (IBAction)toggleStrikethrough:(id)sender { [self toggle:SNStrikeKey]; }
- (IBAction)styleTitle:(id)sender { [self style:SNStyleTitle]; }
- (IBAction)styleHeading:(id)sender { [self style:SNStyleHeading]; }
- (IBAction)styleBody:(id)sender { [self style:nil]; }

@end
