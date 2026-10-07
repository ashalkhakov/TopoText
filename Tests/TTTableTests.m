// TTTable: a table that merges. Rows and columns are TopoTexts of marks
// (their ids the rows' and columns' identities), each cell a TopoText.

#import <XCTest/XCTest.h>
#import <TopoText/TopoText.h>

@interface TTTableTests : XCTestCase
@end

@implementation TTTableTests

- (void)type:(NSString *)s into:(TTTable *)t row:(NSUInteger)r column:(NSUInteger)c {
    TopoText *cell = [t textAtRow:r column:c];
    [cell insertString:s atIndex:cell.length attributes:nil];
}

- (void)testCellsRowsAndColumns {
    TTTable *t = [TTTable tableWithRows:2 columns:2 replica:1];
    [self type:@"Milk" into:t row:0 column:0];
    [self type:@"2 l" into:t row:0 column:1];
    [self type:@"Eggs" into:t row:1 column:0];
    XCTAssertEqualObjects(t.strings, (@[ @[ @"Milk", @"2 l" ], @[ @"Eggs", @"" ] ]));
    [t insertRowAtIndex:1];
    [t insertColumnAtIndex:0];
    XCTAssertEqualObjects(t.strings, (@[ @[ @"", @"Milk", @"2 l" ], @[ @"", @"", @"" ], @[ @"", @"Eggs", @"" ] ]));
    [t removeColumnAtIndex:2];
    [t removeRowAtIndex:0];
    XCTAssertEqualObjects(t.strings, (@[ @[ @"", @"" ], @[ @"", @"Eggs" ] ]));
    NSError *error = nil;
    TTTable *read = [TTTable tableWithData:t.data replica:2 error:&error];
    XCTAssertEqualObjects(read.strings, t.strings, @"%@", error);
    XCTAssertEqualObjects(read.data, t.data, @"canonical");
    XCTAssertNil([TTTable tableWithData:[NSData dataWithBytes:"nope" length:4] replica:2 error:&error]);
    XCTAssertEqual(error.code, TopoTextErrorCorrupt);
}

- (void)testRowsAddedApartAreBothKeptInOneOrder {
    TTTable *a = [TTTable tableWithRows:1 columns:2 replica:1];
    [self type:@"Milk" into:a row:0 column:0];
    TTTable *b = [a copyWithReplica:2];
    [a insertRowAtIndex:1];
    [self type:@"Eggs" into:a row:1 column:0];
    [b insertRowAtIndex:1];
    [self type:@"Bread" into:b row:1 column:0];
    [self type:@"1 loaf" into:b row:1 column:1];
    TTTable *ab = [a mergedWith:b], *ba = [b mergedWith:a];
    XCTAssertEqual(ab.rowCount, 3u);
    XCTAssertEqualObjects(ab.strings, ba.strings, @"one order on both");
    XCTAssertEqualObjects(ab.data, ba.data);
    NSMutableArray *names = [NSMutableArray array];
    for (NSArray *row in ab.strings) [names addObject:row.firstObject];
    XCTAssertEqualObjects(names.firstObject, @"Milk");
    XCTAssertTrue([names containsObject:@"Eggs"] && [names containsObject:@"Bread"]);
}

- (void)testACellEditedApartMergesAsText {
    TTTable *a = [TTTable tableWithRows:1 columns:1 replica:1];
    [self type:@"tea" into:a row:0 column:0];
    TTTable *b = [a copyWithReplica:2];
    [[a textAtRow:0 column:0] insertString:@"green " atIndex:0 attributes:nil];
    [self type:@" and milk" into:b row:0 column:0];
    [a mergeTable:b];
    XCTAssertEqualObjects(a.strings, @[ @[ @"green tea and milk" ] ]);
}

- (void)testAColumnRemovedTakesWhatWasTypedIntoIt {
    TTTable *a = [TTTable tableWithRows:1 columns:2 replica:1];
    [self type:@"Milk" into:a row:0 column:0];
    TTTable *b = [a copyWithReplica:2];
    [a removeColumnAtIndex:1];
    [self type:@"2 l" into:b row:0 column:1];
    TTTable *ab = [a mergedWith:b], *ba = [b mergedWith:a];
    XCTAssertEqualObjects(ab.strings, @[ @[ @"Milk" ] ]);
    XCTAssertEqualObjects(ab.data, ba.data);
}

#pragma mark convergence

static uint64_t TTTableNext(uint64_t *s) {
    *s ^= *s << 13;
    *s ^= *s >> 7;
    *s ^= *s << 17;
    return *s;
}

/* Three copies edit a table at random and merge at random; once each has
   everything, all are the same, to the byte. */
- (void)testCopiesEditedAtRandomConverge {
    NSUInteger seeds = (NSUInteger)MAX(1, [[NSProcessInfo processInfo].environment[@"TOPOTEXT_SEEDS"] integerValue] ?: 60);
    for (uint64_t seed = 1; seed <= seeds; seed++) {
        uint64_t s = seed * 0x9E3779B97F4A7C15ull;
        TTTable *start = [TTTable tableWithRows:2 columns:2 replica:100];
        NSArray<TTTable *> *copies = @[ [start copyWithReplica:1], [start copyWithReplica:2], [start copyWithReplica:3] ];
        for (int step = 0; step < 120; step++) {
            TTTable *t = copies[TTTableNext(&s) % 3];
            switch (TTTableNext(&s) % 8) {
            case 0: [t insertRowAtIndex:TTTableNext(&s) % (t.rowCount + 1)]; break;
            case 1: if (t.rowCount > 1) [t removeRowAtIndex:TTTableNext(&s) % t.rowCount]; break;
            case 2: [t insertColumnAtIndex:TTTableNext(&s) % (t.columnCount + 1)]; break;
            case 3: if (t.columnCount > 1) [t removeColumnAtIndex:TTTableNext(&s) % t.columnCount]; break;
            case 4: [copies[TTTableNext(&s) % 3] mergeTable:t]; break;
            default: {
                if (!t.rowCount || !t.columnCount) break;
                TopoText *cell = [t textAtRow:TTTableNext(&s) % t.rowCount column:TTTableNext(&s) % t.columnCount];
                if (cell.length && TTTableNext(&s) % 3 == 0) [cell deleteCharactersInRange:NSMakeRange(TTTableNext(&s) % cell.length, 1)];
                else [cell insertString:[NSString stringWithFormat:@"%c", (char)('a' + TTTableNext(&s) % 26)]
                                atIndex:TTTableNext(&s) % (cell.length + 1) attributes:nil];
            }
            }
        }
        for (TTTable *t in copies)
            for (TTTable *other in copies) [t mergeTable:other];
        XCTAssertEqualObjects(copies[0].data, copies[1].data, @"seed %llu", seed);
        XCTAssertEqualObjects(copies[1].data, copies[2].data, @"seed %llu", seed);
        XCTAssertEqualObjects(copies[0].strings, copies[2].strings, @"seed %llu", seed);
        TTTable *read = [TTTable tableWithData:copies[0].data replica:9 error:NULL];
        XCTAssertEqualObjects(read.data, copies[0].data, @"seed %llu: read back", seed);
    }
}

@end
