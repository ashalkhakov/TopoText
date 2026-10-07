#import "SNTableEditor.h"

@implementation SNTableEditor {
    TTTable *_table;
    NSCell *_cellTemplate;
}

+ (void)editTable:(TTTable *)table {
    SNTableEditor *editor = [[SNTableEditor alloc] initWithWindowNibName:@"TableEditor"];
    editor->_table = table;
    NSWindow *window = editor.window;
    [editor reloadColumns];
    [window center];
    [NSApp runModalForWindow:window];
    [window orderOut:nil];
}

/* A column of the view for each of the table's, numbered. */
- (void)reloadColumns {
    NSTableColumn *first = _tableView.tableColumns.firstObject;   /* typed: gnustep-gui's array is not */
    if (!_cellTemplate) _cellTemplate = [first.dataCell copy];
    _tableView.allowsColumnSelection = YES;
    for (NSTableColumn *c in [_tableView.tableColumns copy]) [_tableView removeTableColumn:c];
    for (NSUInteger i = 0; i < _table.columnCount; i++) {
        NSTableColumn *c = [[NSTableColumn alloc] initWithIdentifier:[NSString stringWithFormat:@"%lu", (unsigned long)i]];
        [c.headerCell setStringValue:[NSString stringWithFormat:@"%lu", (unsigned long)i + 1]];
        c.dataCell = [_cellTemplate copy];
        c.editable = YES;
        c.width = 140;
        c.resizingMask = NSTableColumnUserResizingMask | NSTableColumnAutoresizingMask;
        [_tableView addTableColumn:c];
    }
    [_tableView reloadData];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv {
    return (NSInteger)_table.rowCount;
}

- (id)tableView:(NSTableView *)tv objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    NSUInteger c = (NSUInteger)[(NSString *)column.identifier integerValue];
    if ((NSUInteger)row >= _table.rowCount || c >= _table.columnCount) return @"";
    return [_table textAtRow:(NSUInteger)row column:c].string;
}

/* A cell changed: its text made the new one by the least edit, so what
   another device typed into it meanwhile merges in. */
- (void)tableView:(NSTableView *)tv setObjectValue:(id)value forTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    NSUInteger c = (NSUInteger)[(NSString *)column.identifier integerValue];
    if ((NSUInteger)row >= _table.rowCount || c >= _table.columnCount) return;
    [[_table textAtRow:(NSUInteger)row column:c] setString:[value description] ?: @""];
}

/* What is being typed in a cell, kept first. */
- (void)endEditing {
    [self.window makeFirstResponder:nil];
}

- (IBAction)addRow:(id)sender {
    [self endEditing];
    NSInteger selected = _tableView.selectedRow;
    [_table insertRowAtIndex:selected >= 0 ? (NSUInteger)selected + 1 : _table.rowCount];
    [_tableView reloadData];
}

- (IBAction)removeRow:(id)sender {
    [self endEditing];
    if (!_table.rowCount) return;
    NSInteger selected = _tableView.selectedRow;
    [_table removeRowAtIndex:selected >= 0 ? (NSUInteger)selected : _table.rowCount - 1];
    [_tableView reloadData];
}

- (IBAction)addColumn:(id)sender {
    [self endEditing];
    NSInteger selected = _tableView.selectedColumn;
    [_table insertColumnAtIndex:selected >= 0 ? (NSUInteger)selected + 1 : _table.columnCount];
    [self reloadColumns];
}

- (IBAction)removeColumn:(id)sender {
    [self endEditing];
    if (_table.columnCount <= 1) return;
    NSInteger selected = _tableView.selectedColumn;
    [_table removeColumnAtIndex:selected >= 0 ? (NSUInteger)selected : _table.columnCount - 1];
    [self reloadColumns];
}

- (IBAction)done:(id)sender {
    [self endEditing];
    [NSApp stopModal];
}

@end
