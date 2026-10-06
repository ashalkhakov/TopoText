// SimpleNotes' devices against its service, in one process: two devices,
// each with a store of its own, and the server's ODataService with
// ODataSync's part (SNServer's, without the HTTP).

#import <XCTest/XCTest.h>
#import <ODataService/ODataService.h>
#import <ODataSync/ODataSyncService.h>
#import "SNModel.h"
#import "SNNotes.h"

@interface SNNotesTests : XCTestCase
@end

@implementation SNNotesTests {
    NSMutableArray<NSURL *> *_files;
    ODataService *_service;
    ODataSyncService *_histories;
    NSPersistentStoreCoordinator *_server;
}

- (NSURL *)temporaryStore {
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
                                            [NSString stringWithFormat:@"sn-%@.sqlite", [NSProcessInfo processInfo].globallyUniqueString]]];
    [_files addObject:url];
    return url;
}

- (void)setUp {
    _files = [NSMutableArray array];
    NSManagedObjectModel *model = SNModelAt(SNModelURLInBundle([NSBundle bundleForClass:[self class]]));
    [ODataSyncService addBookkeepingToModel:model configuration:nil];
    _server = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    NSError *error = nil;
    XCTAssertNotNil([_server addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:[self temporaryStore]
                                                options:@{ NSPersistentHistoryTrackingKey: @YES } error:&error], @"%@", error);
    _service = [[ODataService alloc] initWithPersistentStoreCoordinator:_server serviceRoot:[NSURL URLWithString:@"http://notes.test/odata/"]];
    _histories = [[ODataSyncService alloc] initWithService:_service];
}

- (void)tearDown {
    for (NSURL *url in _files)
        for (NSString *suffix in @[ @"", @"-wal", @"-shm" ])
            [[NSFileManager defaultManager] removeItemAtPath:[url.path stringByAppendingString:suffix] error:NULL];
}

- (SNNotes *)device {
    NSError *error = nil;
    SNNotes *d = [[SNNotes alloc] initWithStoreURL:[self temporaryStore] modelURL:SNModelURLInBundle([NSBundle bundleForClass:[self class]]) error:&error];
    XCTAssertNotNil(d, @"%@", error);
    d.transport = _service;
    d.serviceRoot = [NSURL URLWithString:@"http://notes.test/odata/"];
    return d;
}

- (void)sync:(SNNotes *)device {
    NSError *error = nil;
    XCTAssertTrue([device syncAndWait:&error], @"%@", error);
    XCTAssertEqual(device.engine.issues.count, 0u, @"%@", device.engine.issues);
}

/* Typed into a note, as an editor does it. */
- (void)edit:(SNNote *)note on:(SNNotes *)device with:(void (^)(TopoText *text))typing {
    SNNoteEditor *e = [device editorForNote:note];
    typing(e.text);
    [e textDidChange];
    [e close];
}

- (SNNote *)onlyNote:(SNNotes *)device {
    NSArray *notes = [device notesInFolder:nil matching:nil];
    XCTAssertEqual(notes.count, 1u);
    return notes.firstObject;
}

- (void)testANoteGoesToTheOtherDevice {
    SNNotes *a = [self device], *b = [self device];
    SNFolder *folder = [a addFolderNamed:@"Home"];
    SNNote *note = [a addNoteInFolder:folder];
    [self edit:note on:a with:^(TopoText *t) {
        [t insertString:@"Groceries\nMilk, eggs" atIndex:0 attributes:nil];
        [t addAttributes:@{ @"style": @"title" } range:NSMakeRange(0, 9)];
    }];
    XCTAssertEqualObjects(note.title, @"Groceries");
    [self sync:a];
    [self sync:b];
    SNNote *there = [self onlyNote:b];
    XCTAssertEqualObjects(there.title, @"Groceries");
    XCTAssertEqualObjects(there.body, @"Groceries\nMilk, eggs");
    XCTAssertEqualObjects(there.folder.name, @"Home");
    TopoText *text = there.text;
    XCTAssertEqualObjects([text attributesAtIndex:0 effectiveRange:NULL], @{ @"style": @"title" });
    XCTAssertEqual([b notesInFolder:nil matching:@"eggs"].count, 1u);
    XCTAssertEqual([b notesInFolder:nil matching:@"bacon"].count, 0u);
}

- (void)testEditsMadeApartAreBothKept {
    SNNotes *a = [self device], *b = [self device];
    [self edit:[a addNoteInFolder:nil] on:a with:^(TopoText *t) {
        [t insertString:@"Trip\npack bags" atIndex:0 attributes:nil];
    }];
    [self sync:a];
    [self sync:b];
    /* Apart: a renames the trip, b adds a line. */
    [self edit:[self onlyNote:a] on:a with:^(TopoText *t) {
        [t insertString:@"Paris " atIndex:0 attributes:nil];
    }];
    [self edit:[self onlyNote:b] on:b with:^(TopoText *t) {
        [t insertString:@"\nbook hotel" atIndex:t.length attributes:nil];
    }];
    [self sync:a];
    [self sync:b];
    [self sync:a];
    for (SNNotes *d in @[ a, b ]) {
        SNNote *n = [self onlyNote:d];
        XCTAssertEqualObjects(n.body, @"Paris Trip\npack bags\nbook hotel");
        XCTAssertEqualObjects(n.title, @"Paris Trip", @"the title, of the merged body");
    }
    XCTAssertEqualObjects([self onlyNote:a].bodyText, [self onlyNote:b].bodyText);
}

- (void)testAnEditOutlivesADeletionThatDidNotSeeIt {
    SNNotes *a = [self device], *b = [self device];
    [self edit:[a addNoteInFolder:nil] on:a with:^(TopoText *t) { [t insertString:@"keep me" atIndex:0 attributes:nil]; }];
    [self sync:a];
    [self sync:b];
    [a deleteNote:[self onlyNote:a]];
    [self edit:[self onlyNote:b] on:b with:^(TopoText *t) { [t insertString:@"!" atIndex:t.length attributes:nil]; }];
    [self sync:a];
    [self sync:b];
    [self sync:a];
    XCTAssertEqualObjects([self onlyNote:b].body, @"keep me!");
    XCTAssertEqualObjects([self onlyNote:a].body, @"keep me!", @"back where it was deleted");
}

/* An editor open through a sync: what came is merged into what it shows,
   and what was typed meanwhile is kept and sent. */
- (void)testAnOpenEditorIsMergedWith {
    SNNotes *a = [self device], *b = [self device];
    [self edit:[a addNoteInFolder:nil] on:a with:^(TopoText *t) { [t insertString:@"one two" atIndex:0 attributes:nil]; }];
    [self sync:a];
    [self sync:b];
    SNNoteEditor *open = [b editorForNote:[self onlyNote:b]];
    NSMutableArray *merged = [NSMutableArray array];
    open.didMerge = ^(NSArray<TTEdit *> *edits) { [merged addObjectsFromArray:edits]; };
    [self edit:[self onlyNote:a] on:a with:^(TopoText *t) { [t insertString:@"zero " atIndex:0 attributes:nil]; }];
    [self sync:a];
    /* Typed on b, not yet written, when b syncs. */
    [open.text insertString:@" three" atIndex:open.text.length attributes:nil];
    [open textDidChange];
    [self sync:b];
    XCTAssertEqualObjects(open.text.string, @"zero one two three");
    XCTAssertEqual(merged.count, 1u, @"%@", merged);
    XCTAssertEqual([(TTEdit *)merged.firstObject kind], TTEditInsert);
    [open close];
    [self sync:b];
    [self sync:a];
    XCTAssertEqualObjects([self onlyNote:a].body, @"zero one two three");
}

- (void)testAFolderDeletedKeepsItsNotes {
    SNNotes *a = [self device], *b = [self device];
    SNFolder *work = [a addFolderNamed:@"Work"];
    [a addNoteInFolder:work];
    [a addNoteInFolder:work];
    [self sync:a];
    [self sync:b];
    XCTAssertEqual([b countOfNotesInFolder:b.folders.firstObject], 2u);
    [a deleteFolder:work];
    [self sync:a];
    [self sync:b];
    XCTAssertEqual(b.folders.count, 0u);
    XCTAssertEqual([b notesInFolder:nil matching:nil].count, 2u);
}

- (void)testPinnedFirst {
    SNNotes *a = [self device];
    SNNote *old = [a addNoteInFolder:nil];
    [self edit:old on:a with:^(TopoText *t) { [t insertString:@"old" atIndex:0 attributes:nil]; }];
    old.updated = [NSDate dateWithTimeIntervalSinceNow:-3600];
    SNNote *recent = [a addNoteInFolder:nil];
    [self edit:recent on:a with:^(TopoText *t) { [t insertString:@"recent" atIndex:0 attributes:nil]; }];
    XCTAssertEqualObjects([[a notesInFolder:nil matching:nil] valueForKey:@"title"], (@[ @"recent", @"old" ]));
    [a setNote:old pinned:YES];
    XCTAssertEqualObjects([[a notesInFolder:nil matching:nil] valueForKey:@"title"], (@[ @"old", @"recent" ]));
}

- (void)testOfflineChangesWait {
    SNNotes *a = [self device];
    a.serviceRoot = nil;
    [a addNoteInFolder:nil];
    XCTAssertFalse([a syncAndWait:NULL], @"no server: nothing to sync with");
    a.transport = _service;
    a.serviceRoot = [NSURL URLWithString:@"http://notes.test/odata/"];
    XCTAssertEqual(a.pendingCount, 1u);
    [self sync:a];
    XCTAssertEqual(a.pendingCount, 0u);
}

@end
