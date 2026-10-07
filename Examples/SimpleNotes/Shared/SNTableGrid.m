#import "SNTableGrid+System.h"
#import "SNNotes.h"

static const unichar SNTableCharacter = 0xFFFC;
/* A column's narrowest. */
static const CGFloat SNMinColumn = 60;

static SNRect SNGridRect(CGFloat x, CGFloat y, CGFloat w, CGFloat h) {
    SNRect r = { { x, y }, { w, h } };
    return r;
}

/* A cell's text, as its binding sees it: the table's TopoText; typed
   into, the grid saves soon. */
@interface SNCellSource : NSObject <SNTextSource>
- (instancetype)initWithText:(TopoText *)text grid:(SNTableGrid *)grid;
@end

@interface SNTableGrid ()
- (void)changed;
@end

@implementation SNCellSource {
    __weak SNTableGrid *_grid;
}
@synthesize text = _text;

- (instancetype)initWithText:(TopoText *)text grid:(SNTableGrid *)grid {
    if ((self = [super init])) {
        _text = text;
        _grid = grid;
    }
    return self;
}

/* While the storage is still processing the edit: saved later, laid out
   once the view is done (-cellChanged:). */
- (void)textDidChange {
    [_grid changed];
}

@end

@implementation SNTableGrid

- (instancetype)initWithNotes:(SNNotes *)notes attachmentID:(NSString *)attachmentID {
    SNAttachment *a = [notes attachmentWithID:attachmentID];
    TTTable *table = a ? [notes tableOfAttachment:a] : nil;
    if (!table) return nil;
    if (!(self = [super initWithFrame:SNGridRect(0, 0, 240, 40)])) return nil;
    _notes = notes;
    _attachmentID = [attachmentID copy];
    _table = table;
    _editable = YES;
    _width = 240;
    _rowHeights = [NSMutableArray array];
    [self systemSetUp];
    [self makeCells];
    return self;
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

+ (NSArray<NSArray *> *)tableActions {
    return @[ @[ @"Add Row Above", @"addRowAbove:" ], @[ @"Add Row Below", @"addRowBelow:" ],
              @[ @"Add Column Before", @"addColumnBefore:" ], @[ @"Add Column After", @"addColumnAfter:" ], @[],
              @[ @"Delete Row", @"deleteRow:" ], @[ @"Delete Column", @"deleteColumn:" ] ];
}

#pragma mark cells

- (void)makeCells {
    /* The old ones let go of first: one typed in, taken away, ends its
       editing, which would save, and a save's notice reload the grid. */
    NSArray *old = _cells, *oldBindings = _bindings;
    _cells = [NSMutableArray array];
    _bindings = [NSMutableArray array];
    for (NSArray<SNTextBinding *> *row in oldBindings)
        for (SNTextBinding *b in row) [b unbind];
    for (NSArray *row in old)
        for (SNGridTextView *tv in row) {
            tv.delegate = nil;
            [tv removeFromSuperview];
        }
    for (NSUInteger r = 0; r < _table.rowCount; r++) {
        NSMutableArray *views = [NSMutableArray array], *bindings = [NSMutableArray array];
        for (NSUInteger c = 0; c < _table.columnCount; c++) {
            SNGridTextView *tv = [self makeCell];
            SNCellSource *source = [[SNCellSource alloc] initWithText:[_table textAtRow:r column:c] grid:self];
            [bindings addObject:[[SNTextBinding alloc] initWithTextView:tv editor:source]];
            tv.editable = _editable;
            [self addSubview:tv];
            [views addObject:tv];
        }
        [_cells addObject:views];
        [_bindings addObject:bindings];
    }
}

- (void)close {
    [self save];
    for (NSArray<SNTextBinding *> *row in _bindings)
        for (SNTextBinding *b in row) [b unbind];
    _bindings = nil;
    [self removeFromSuperview];
}

- (SNTextBinding *)bindingOfCell:(SNGridTextView *)cell {
    NSUInteger r, c;
    return [self findCell:cell row:&r column:&c] ? _bindings[r][c] : nil;
}

- (SNGridTextView *)cellTypedIn {
    for (NSArray *row in _cells)
        for (SNGridTextView *tv in row)
            if ([self cellIsTypedIn:tv]) return tv;
    return nil;
}

- (SNGridTextView *)textViewAtRow:(NSUInteger)row column:(NSUInteger)column {
    return row < _cells.count && column < _cells[row].count ? _cells[row][column] : nil;
}

- (BOOL)findCell:(id)view row:(NSUInteger *)row column:(NSUInteger *)column {
    for (NSUInteger r = 0; r < _cells.count; r++) {
        NSUInteger c = [_cells[r] indexOfObjectIdenticalTo:view];
        if (c != NSNotFound) {
            *row = r;
            *column = c;
            return YES;
        }
    }
    return NO;
}

- (void)noteCell:(SNGridTextView *)cell {
    NSUInteger r, c;
    if ([self findCell:cell row:&r column:&c]) {
        _row = r;
        _col = c;
    }
}

/* The cell typed in now, or the one last typed in. */
- (BOOL)typingRow:(NSUInteger *)row column:(NSUInteger *)column {
    BOOL typing = NO;
    for (NSArray *cells in _cells)
        for (SNGridTextView *tv in cells)
            if ([self cellIsTypedIn:tv]) {
                [self noteCell:tv];
                typing = YES;
            }
    *row = MIN(_row, _table.rowCount ? _table.rowCount - 1 : 0);
    *column = MIN(_col, _table.columnCount ? _table.columnCount - 1 : 0);
    return typing;
}

- (void)setEditable:(BOOL)editable {
    _editable = editable;
    for (NSArray *row in _cells)
        for (SNGridTextView *tv in row) tv.editable = editable;
}

- (void)focusRow:(NSUInteger)row column:(NSUInteger)column {
    SNGridTextView *tv = [self textViewAtRow:row column:column];
    if (!tv) return;
    _row = row;
    _col = column;
    [self typeInCell:tv];
    tv.selectedRange = NSMakeRange(tv.textStorage.length, 0);
}

- (void)beginEditing {
    [self focusRow:0 column:0];
}

#pragma mark laying out

- (SNSize)layoutForWidth:(CGFloat)width {
    _width = width;
    NSUInteger columns = MAX((NSUInteger)1, _table.columnCount);
    /* The columns share the width, a line (a point) between each. */
    _column = MAX(SNMinColumn, floor((width - 1) / columns));
    [_rowHeights removeAllObjects];
    CGFloat y = 0;
    for (NSArray<SNGridTextView *> *row in _cells) {
        CGFloat h = 0;
        for (NSUInteger c = 0; c < row.count; c++) {
            SNGridTextView *tv = row[c];
            tv.frame = SNGridRect(c * _column + 1, y + 1, _column - 1, MAX(tv.frame.size.height, 20));
            h = MAX(h, [self heightOfCell:tv]);
        }
        for (NSUInteger c = 0; c < row.count; c++) row[c].frame = SNGridRect(c * _column + 1, y + 1, _column - 1, h);
        [_rowHeights addObject:@(h + 1)];
        y += h + 1;
    }
    _size.width = _column * columns + 1;
    _size.height = MAX(y, 20) + 1;
    SNRect frame = self.frame;
    frame.size = _size;
    self.frame = frame;
    [self redraw];
    return _size;
}

/* Laid out again as wide as it was; its delegate told when it is no longer
   the size it was. */
- (void)relayout {
    SNSize was = _size;
    [self layoutForWidth:_width];
    if (was.width != _size.width || was.height != _size.height) [_delegate tableGridChangedSize:self];
}

/* The lines: round it, and between each row and column. */
- (void)drawRect:(SNRect)dirty {
    [SNSystemGridColor() setStroke];
    SNPath *path = [SNPath bezierPath];
    path.lineWidth = 1;
    NSUInteger columns = MAX((NSUInteger)1, _table.columnCount);
    CGFloat width = _column * columns + 1, height = _size.height;
    for (NSUInteger c = 0; c <= columns; c++) {
        CGFloat x = c * _column + 0.5;
        SNSystemAddLine(path, (SNPoint){ x, 0 }, (SNPoint){ x, height });
    }
    CGFloat y = 0.5;
    SNSystemAddLine(path, (SNPoint){ 0, y }, (SNPoint){ width, y });
    for (NSNumber *h in _rowHeights) {
        y += h.doubleValue;
        SNSystemAddLine(path, (SNPoint){ 0, y }, (SNPoint){ width, y });
    }
    [path stroke];
}

#pragma mark typing

/* A cell typed in (its binding wrote it into the table, which is saved a
   moment later): the grid as tall as it now needs. */
- (void)cellChanged:(SNGridTextView *)tv {
    NSUInteger r, c;
    if (_loading || ![self findCell:tv row:&r column:&c]) return;
    _row = r;
    _col = c;
    [self relayout];
}

- (void)changed {
    _dirty = YES;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(save) object:nil];
    [self performSelector:@selector(save) withObject:nil afterDelay:0.5];
}

- (void)setString:(NSString *)string atRow:(NSUInteger)row column:(NSUInteger)column {
    SNGridTextView *tv = [self textViewAtRow:row column:column];
    if (!tv) return;
    NSTextStorage *storage = tv.textStorage;
    [storage replaceCharactersInRange:NSMakeRange(0, storage.length) withString:string];
    [[self bindingOfCell:tv] textDidChange];
    [self cellChanged:tv];
}

/* The next cell (by 1) or the one before (by -1); after the last, a row
   added first, as Apple Notes' Tab does. */
- (void)moveFrom:(SNGridTextView *)tv by:(NSInteger)by {
    NSUInteger r, c;
    if (![self findCell:tv row:&r column:&c]) return;
    NSInteger columns = (NSInteger)_table.columnCount, at = (NSInteger)(r * _table.columnCount + c) + by;
    if (at < 0) return;
    if (at >= (NSInteger)(_table.rowCount * _table.columnCount)) {
        if (!_editable) return;
        [_table insertRowAtIndex:_table.rowCount];
        [self structureChanged];
    }
    [self focusRow:(NSUInteger)(at / columns) column:(NSUInteger)(at % columns)];
}

- (void)save {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(save) object:nil];
    if (!_dirty) return;
    /* While a sync runs the store is the engine's: saved after. */
    if (_notes.syncing) {
        [self performSelector:@selector(save) withObject:nil afterDelay:0.5];
        return;
    }
    SNAttachment *a = [_notes attachmentWithID:_attachmentID];
    if (!a) return;
    _dirty = NO;
    [_notes saveTable:_table toAttachment:a];
}

- (void)reloadFromStore {
    if (_loading) return;
    SNAttachment *a = [_notes attachmentWithID:_attachmentID];
    TTTable *stored = a ? [_notes tableOfAttachment:a] : nil;
    if (!stored) return;
    NSUInteger rows = _table.rowCount, columns = _table.columnCount;
    NSMapTable<TopoText *, NSArray<TTEdit *> *> *edits = [_table mergeTableReportingCellEdits:stored];
    _loading = YES;
    if (rows != _table.rowCount || columns != _table.columnCount) {
        /* Rows or columns came or went: the cells made again, the one typed
           in typed in again. */
        NSUInteger r, c;
        BOOL typing = [self typingRow:&r column:&c];
        [self makeCells];
        if (typing) [self focusRow:MIN(r, _table.rowCount - 1) column:MIN(c, _table.columnCount - 1)];
    } else {
        /* Each cell's edits done to its view, the selection moved along. */
        for (NSArray<SNTextBinding *> *row in _bindings)
            for (SNTextBinding *b in row) {
                NSArray<TTEdit *> *done = [edits objectForKey:b.editor.text];
                if (done.count) [b applyEdits:done];
            }
    }
    _loading = NO;
    [self relayout];
}

#pragma mark rows and columns

- (void)structureChanged {
    _loading = YES;
    [self makeCells];
    _loading = NO;
    [self changed];
    [self relayout];
}

- (IBAction)addRowAbove:(id)sender {
    NSUInteger r, c;
    [self typingRow:&r column:&c];
    [_table insertRowAtIndex:r];
    [self structureChanged];
    [self focusRow:r column:c];
}

- (IBAction)addRowBelow:(id)sender {
    NSUInteger r, c;
    [self typingRow:&r column:&c];
    [_table insertRowAtIndex:r + 1];
    [self structureChanged];
    [self focusRow:r + 1 column:c];
}

- (IBAction)addColumnBefore:(id)sender {
    NSUInteger r, c;
    [self typingRow:&r column:&c];
    [_table insertColumnAtIndex:c];
    [self structureChanged];
    [self focusRow:r column:c];
}

- (IBAction)addColumnAfter:(id)sender {
    NSUInteger r, c;
    [self typingRow:&r column:&c];
    [_table insertColumnAtIndex:c + 1];
    [self structureChanged];
    [self focusRow:r column:c + 1];
}

- (IBAction)deleteRow:(id)sender {
    NSUInteger r, c;
    [self typingRow:&r column:&c];
    if (_table.rowCount < 2) return;
    [_table removeRowAtIndex:r];
    [self structureChanged];
    [self focusRow:MIN(r, _table.rowCount - 1) column:c];
}

- (IBAction)deleteColumn:(id)sender {
    NSUInteger r, c;
    [self typingRow:&r column:&c];
    if (_table.columnCount < 2) return;
    [_table removeColumnAtIndex:c];
    [self structureChanged];
    [self focusRow:r column:MIN(c, _table.columnCount - 1)];
}

/* Only while it can be typed in; the last row or column stays. */
- (BOOL)canDo:(SEL)action {
    if (action == @selector(deleteRow:)) return _editable && _table.rowCount > 1;
    if (action == @selector(deleteColumn:)) return _editable && _table.columnCount > 1;
    if (action == @selector(addRowAbove:) || action == @selector(addRowBelow:) || action == @selector(addColumnBefore:) ||
        action == @selector(addColumnAfter:))
        return _editable;
    return NO;
}

@end

#pragma mark a note's tables

@implementation SNTableGrids {
    SNTextBinding *_binding;
    SNNotes *_notes;
    NSMutableDictionary<NSString *, SNTableGrid *> *_byID;
    /* Attachments' kinds, by id: a kind does not change. */
    NSMutableDictionary<NSString *, NSString *> *_kinds;
    CGFloat _lastWidth;
    BOOL _updating;
}

- (instancetype)initWithBinding:(SNTextBinding *)binding notes:(SNNotes *)notes {
    if (!(self = [super init])) return nil;
    _binding = binding;
    _notes = notes;
    _byID = [NSMutableDictionary dictionary];
    _kinds = [NSMutableDictionary dictionary];
    SNSystemObserveResizing(binding.view, self, @selector(resized:));
    [self update];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

- (SNGridTextView *)textView {
    return (SNGridTextView *)_binding.view;
}

- (NSArray<SNTableGrid *> *)grids {
    return _byID.allValues;
}

- (SNTableGrid *)gridForAttachmentID:(NSString *)attachmentID {
    return attachmentID ? _byID[attachmentID] : nil;
}

- (BOOL)isTable:(NSString *)attachmentID {
    NSString *kind = _kinds[attachmentID];
    if (!kind) {
        kind = [_notes attachmentWithID:attachmentID].kind;
        if (kind) _kinds[attachmentID] = kind;
    }
    return [kind isEqual:SNAttachmentKindTable];
}

/* How wide a table may be: the text's width. */
- (CGFloat)availableWidth {
    NSTextContainer *c = self.textView.textContainer;
    CGFloat w = SNSystemContainerWidth(c) - 2 * c.lineFragmentPadding - 4;
    return w > 120 && w < 4000 ? w : 480;
}

/* Wider or narrower: laid out again, once the resizing is done with. */
- (void)resized:(NSNotification *)n {
    if ([self availableWidth] == _lastWidth) return;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(update) object:nil];
    [self performSelector:@selector(update) withObject:nil afterDelay:0];
}

- (void)update {
    if (_updating) return;
    _updating = YES;
    SNGridTextView *tv = self.textView;
    NSTextStorage *storage = _binding.storage;
    NSString *s = storage.string;
    NSMutableArray<NSString *> *ids = [NSMutableArray array];
    NSMutableArray<NSNumber *> *places = [NSMutableArray array];
    for (NSUInteger i = 0; i < s.length; i++) {
        if ([s characterAtIndex:i] != SNTableCharacter) continue;
        NSString *attachmentID = [storage attribute:SNAttachmentAttributeName atIndex:i effectiveRange:NULL];
        /* One grid a table: the same one twice (pasted again) has room only. */
        if (!attachmentID || [ids containsObject:attachmentID] || ![self isTable:attachmentID]) continue;
        [ids addObject:attachmentID];
        [places addObject:@(i)];
    }
    for (NSString *gone in _byID.allKeys) {
        if ([ids containsObject:gone]) continue;
        [_byID[gone] close];
        [_byID removeObjectForKey:gone];
    }
    CGFloat width = [self availableWidth];
    _lastWidth = width;
    BOOL editable = [tv isEditable];   /* gnustep-gui: a setter, no property getter */
    for (NSString *attachmentID in ids) {
        SNTableGrid *grid = _byID[attachmentID];
        if (!grid) {
            grid = [[SNTableGrid alloc] initWithNotes:_notes attachmentID:attachmentID];
            if (!grid) continue;
            grid.delegate = self;
            [tv addSubview:grid];
            _byID[attachmentID] = grid;
        }
        if (grid.editable != editable) grid.editable = editable;
        [_binding setRoomSize:[grid layoutForWidth:width] forAttachmentID:attachmentID];
    }
    for (NSUInteger k = 0; k < ids.count; k++) {
        SNTableGrid *grid = _byID[ids[k]];
        if (grid) [self place:grid at:places[k].unsignedIntegerValue];
    }
    _updating = NO;
}

/* Over its character: the room's top left, its bottom on the line's
   baseline. */
- (void)place:(SNTableGrid *)grid at:(NSUInteger)index {
    SNGridTextView *tv = self.textView;
    NSLayoutManager *lm = tv.layoutManager;
    /* A character's first glyph (gnustep-gui's layout manager has no
       -glyphIndexForCharacterAtIndex:). */
    NSUInteger glyph = [lm glyphRangeForCharacterRange:NSMakeRange(index, 1) actualCharacterRange:NULL].location;
    SNRect line = [lm lineFragmentRectForGlyphAtIndex:glyph effectiveRange:NULL];
    SNPoint at = [lm locationForGlyphAtIndex:glyph];
    SNPoint origin = SNSystemTextOrigin(tv);
    SNSize size = grid.size;
    SNRect frame = SNGridRect(origin.x + line.origin.x + at.x, origin.y + line.origin.y + at.y - size.height, size.width, size.height);
    if (frame.origin.x != grid.frame.origin.x || frame.origin.y != grid.frame.origin.y) grid.frame = frame;
}

- (void)tableGridChangedSize:(SNTableGrid *)grid {
    [self update];
}

- (void)reload {
    for (SNTableGrid *grid in _byID.allValues) [grid reloadFromStore];
    [self update];
}

- (void)removeAll {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    for (SNTableGrid *grid in _byID.allValues) [grid close];
    [_byID removeAllObjects];
}

- (SNGridTextView *)cellTypedIn {
    for (SNTableGrid *grid in _byID.allValues) {
        SNGridTextView *cell = grid.cellTypedIn;
        if (cell) return cell;
    }
    return nil;
}

- (SNTextBinding *)bindingOfCell:(SNGridTextView *)cell {
    for (SNTableGrid *grid in _byID.allValues) {
        SNTextBinding *b = [grid bindingOfCell:cell];
        if (b) return b;
    }
    return nil;
}

@end
