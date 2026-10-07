#import "TopoText.h"
#import "TTInternal.h"

/* A row's or a column's mark in its order's text: what the character is
   does not matter, its id does. */
static NSString * const TTTableMark = @"•";

/* The data's first bytes, and its version. */
static const char TTTableMagic[4] = { 'T', 'T', 'B', 1 };

static void TTTablePutVarint(NSMutableData *d, uint64_t v) {
    uint8_t b[10];
    int n = 0;
    do {
        b[n] = v & 0x7f;
        v >>= 7;
        if (v) b[n] |= 0x80;
        n++;
    } while (v);
    [d appendBytes:b length:(NSUInteger)n];
}

static BOOL TTTableGetVarint(NSData *d, NSUInteger *at, uint64_t *v) {
    const uint8_t *bytes = d.bytes;
    uint64_t value = 0;
    for (int shift = 0; shift < 64; shift += 7) {
        if (*at >= d.length) return NO;
        uint8_t b = bytes[(*at)++];
        value |= (uint64_t)(b & 0x7f) << shift;
        if (!(b & 0x80)) {
            *v = value;
            return YES;
        }
    }
    return NO;
}

static void TTTablePutData(NSMutableData *d, NSData *part) {
    TTTablePutVarint(d, part.length);
    [d appendData:part];
}

static NSData *TTTableGetData(NSData *d, NSUInteger *at) {
    uint64_t n;
    if (!TTTableGetVarint(d, at, &n) || n > d.length - *at) return nil;
    NSData *part = [d subdataWithRange:NSMakeRange(*at, (NSUInteger)n)];
    *at += (NSUInteger)n;
    return part;
}

@implementation TTTable {
    TopoText *_rows;
    TopoText *_columns;
    /* "row id key/column id key": a cell's text; a cell never written has
       none. */
    NSMutableDictionary<NSString *, TopoText *> *_cells;
}

- (instancetype)initWithReplica:(TTReplica)replica rows:(TopoText *)rows columns:(TopoText *)columns
                          cells:(NSMutableDictionary *)cells {
    if (!(self = [super init])) return nil;
    _replica = rows.replica ?: replica;
    _rows = rows;
    _columns = columns;
    _cells = cells;
    return self;
}

+ (instancetype)tableWithRows:(NSUInteger)rows columns:(NSUInteger)columns replica:(TTReplica)replica {
    TopoText *r = [TopoText textWithReplica:replica];
    TopoText *c = [TopoText textWithReplica:r.replica];
    TTTable *table = [[self alloc] initWithReplica:r.replica rows:r columns:c cells:[NSMutableDictionary dictionary]];
    for (NSUInteger i = 0; i < rows; i++) [table insertRowAtIndex:i];
    for (NSUInteger i = 0; i < columns; i++) [table insertColumnAtIndex:i];
    return table;
}

+ (instancetype)tableWithData:(NSData *)data replica:(TTReplica)replica error:(NSError **)error {
    if (!replica) replica = [TopoText randomReplica];
    NSUInteger at = sizeof TTTableMagic;
    if (data.length < at || memcmp(data.bytes, TTTableMagic, 3) != 0) {
        if (error) *error = TTMakeError(TopoTextErrorCorrupt, @"Not a TopoText table");
        return nil;
    }
    if (((const uint8_t *)data.bytes)[3] != TTTableMagic[3]) {
        if (error) *error = TTMakeError(TopoTextErrorFormat, @"A table written by a newer TopoText");
        return nil;
    }
    NSData *rowsData = TTTableGetData(data, &at), *columnsData = TTTableGetData(data, &at);
    TopoText *rows = rowsData ? [TopoText textWithData:rowsData replica:replica error:error] : nil;
    TopoText *columns = columnsData ? [TopoText textWithData:columnsData replica:replica error:error] : nil;
    uint64_t count;
    if (!rows || !columns || !TTTableGetVarint(data, &at, &count)) {
        if (error && !*error) *error = TTMakeError(TopoTextErrorCorrupt, @"Damaged TopoText table");
        return nil;
    }
    NSMutableDictionary *cells = [NSMutableDictionary dictionary];
    for (uint64_t i = 0; i < count; i++) {
        NSData *keyData = TTTableGetData(data, &at), *cellData = TTTableGetData(data, &at);
        NSString *key = keyData ? [[NSString alloc] initWithData:keyData encoding:NSUTF8StringEncoding] : nil;
        TopoText *cell = cellData ? [TopoText textWithData:cellData replica:replica error:error] : nil;
        if (!key || !cell) {
            if (error && !*error) *error = TTMakeError(TopoTextErrorCorrupt, @"Damaged TopoText table");
            return nil;
        }
        cells[key] = cell;
    }
    if (at != data.length) {
        if (error) *error = TTMakeError(TopoTextErrorCorrupt, @"Damaged TopoText table");
        return nil;
    }
    return [[self alloc] initWithReplica:replica rows:rows columns:columns cells:cells];
}

- (id)copyWithZone:(NSZone *)zone {
    return [self copyWithReplica:_replica];
}

- (TTTable *)copyWithReplica:(TTReplica)replica {
    TopoText *rows = [_rows copyWithReplica:replica];
    NSMutableDictionary *cells = [NSMutableDictionary dictionary];
    for (NSString *key in _cells) cells[key] = [_cells[key] copyWithReplica:rows.replica];
    return [[TTTable alloc] initWithReplica:rows.replica rows:rows columns:[_columns copyWithReplica:rows.replica] cells:cells];
}

- (NSData *)data {
    NSMutableData *d = [NSMutableData dataWithBytes:TTTableMagic length:sizeof TTTableMagic];
    TTTablePutData(d, _rows.data);
    TTTablePutData(d, _columns.data);
    /* Cells never written are not kept; those that are, by key. */
    NSMutableArray *keys = [NSMutableArray array];
    for (NSString *key in _cells)
        if (_cells[key].version.replicas.count) [keys addObject:key];
    [keys sortUsingSelector:@selector(compare:)];
    TTTablePutVarint(d, keys.count);
    for (NSString *key in keys) {
        TTTablePutData(d, [key dataUsingEncoding:NSUTF8StringEncoding]);
        TTTablePutData(d, _cells[key].data);
    }
    return d;
}

- (NSUInteger)rowCount {
    return _rows.length;
}

- (NSUInteger)columnCount {
    return _columns.length;
}

/* The id of an order's character at index, its row's or column's identity. */
static NSString *TTTableKeyAt(TopoText *order, NSUInteger index) {
    return [order anchorAtIndex:index + 1].key;
}

- (NSString *)keyOfRow:(NSUInteger)row column:(NSUInteger)column {
    if (row >= _rows.length || column >= _columns.length)
        [NSException raise:NSRangeException format:@"No cell at row %lu, column %lu of a %lux%lu table",
                           (unsigned long)row, (unsigned long)column, (unsigned long)_rows.length, (unsigned long)_columns.length];
    return [NSString stringWithFormat:@"%@/%@", TTTableKeyAt(_rows, row), TTTableKeyAt(_columns, column)];
}

- (TopoText *)textAtRow:(NSUInteger)row column:(NSUInteger)column {
    NSString *key = [self keyOfRow:row column:column];
    TopoText *cell = _cells[key];
    if (!cell) _cells[key] = cell = [TopoText textWithReplica:_replica];
    return cell;
}

- (NSArray<NSArray<NSString *> *> *)strings {
    NSMutableArray *rows = [NSMutableArray array];
    for (NSUInteger r = 0; r < _rows.length; r++) {
        NSMutableArray *row = [NSMutableArray array];
        for (NSUInteger c = 0; c < _columns.length; c++) [row addObject:_cells[[self keyOfRow:r column:c]].string ?: @""];
        [rows addObject:row];
    }
    return rows;
}

- (void)insertRowAtIndex:(NSUInteger)index {
    [_rows insertString:TTTableMark atIndex:index attributes:nil];
}

- (void)removeRowAtIndex:(NSUInteger)index {
    [_rows deleteCharactersInRange:NSMakeRange(index, 1)];
}

- (void)insertColumnAtIndex:(NSUInteger)index {
    [_columns insertString:TTTableMark atIndex:index attributes:nil];
}

- (void)removeColumnAtIndex:(NSUInteger)index {
    [_columns deleteCharactersInRange:NSMakeRange(index, 1)];
}

- (void)mergeTable:(TTTable *)other {
    [_rows mergeText:other->_rows];
    [_columns mergeText:other->_columns];
    for (NSString *key in other->_cells) {
        TopoText *mine = _cells[key];
        if (mine) [mine mergeText:other->_cells[key]];
        else _cells[key] = [other->_cells[key] copyWithReplica:_replica];
    }
}

- (TTTable *)mergedWith:(TTTable *)other {
    TTTable *merged = [self copy];
    [merged mergeTable:other];
    return merged;
}

@end
