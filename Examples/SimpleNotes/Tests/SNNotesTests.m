// SimpleNotes' devices against its service, in one process: two devices,
// each with a store of its own, and the server's ODataService with
// ODataSync's part (SNServer's, without the HTTP).

#import <XCTest/XCTest.h>
#import <ODataService/ODataService.h>
#import <ODataSync/ODataSyncService.h>
#import "SNModel.h"
#import "SNNotes.h"

@interface SNNotesTests : XCTestCase <SNNoteEditorDelegate>
@end

@implementation SNNotesTests {
    NSMutableArray<NSURL *> *_files;
    /* What an open editor was told was merged into it. */
    NSMutableArray<TTEdit *> *_merged;
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
    /* Its dates too ("updated", before version 3, never synced on Apple's
       Core Data: key-value coding read NSManagedObject's -isUpdated). */
    XCTAssertNotNil(there.edited);
    XCTAssertEqualWithAccuracy(there.edited.timeIntervalSinceReferenceDate, note.edited.timeIntervalSinceReferenceDate, 1);
    XCTAssertEqualWithAccuracy(there.created.timeIntervalSinceReferenceDate, note.created.timeIntervalSinceReferenceDate, 1);
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
    [a deleteNoteImmediately:[self onlyNote:a]];
    [self edit:[self onlyNote:b] on:b with:^(TopoText *t) { [t insertString:@"!" atIndex:t.length attributes:nil]; }];
    [self sync:a];
    [self sync:b];
    [self sync:a];
    XCTAssertEqualObjects([self onlyNote:b].body, @"keep me!");
    XCTAssertEqualObjects([self onlyNote:a].body, @"keep me!", @"back where it was deleted");
}

- (void)noteEditor:(SNNoteEditor *)editor didMergeEdits:(NSArray<TTEdit *> *)edits {
    [_merged addObjectsFromArray:edits];
}

/* An editor open through a sync: what came is merged into what it shows,
   and what was typed meanwhile is kept and sent. */
- (void)testAnOpenEditorIsMergedWith {
    SNNotes *a = [self device], *b = [self device];
    [self edit:[a addNoteInFolder:nil] on:a with:^(TopoText *t) { [t insertString:@"one two" atIndex:0 attributes:nil]; }];
    [self sync:a];
    [self sync:b];
    SNNoteEditor *open = [b editorForNote:[self onlyNote:b]];
    NSMutableArray *merged = _merged = [NSMutableArray array];
    open.delegate = self;
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

- (void)testAFolderDeletedSendsItsNotesToRecentlyDeleted {
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
    XCTAssertEqual([b notesInFolder:nil matching:nil].count, 0u);
    XCTAssertEqual(b.countOfDeletedNotes, 2u, @"its notes, in Recently Deleted");
    /* Recovered, a note whose folder is gone comes back to All Notes. */
    [b recoverNote:[b deletedNotesMatching:nil].firstObject];
    [self sync:b];
    [self sync:a];
    XCTAssertEqual([a notesInFolder:nil matching:nil].count, 1u);
    XCTAssertNil([a notesInFolder:nil matching:nil].firstObject.folder);
}

#pragma mark Recently Deleted

- (void)testADeletedNoteIsInRecentlyDeletedEverywhere {
    SNNotes *a = [self device], *b = [self device];
    [self edit:[a addNoteInFolder:[a addFolderNamed:@"Home"]] on:a with:^(TopoText *t) { [t insertString:@"Old list" atIndex:0 attributes:nil]; }];
    [self sync:a];
    [self sync:b];
    [a deleteNote:[self onlyNote:a]];
    XCTAssertEqual([a notesInFolder:nil matching:nil].count, 0u, @"gone from the lists");
    XCTAssertEqual([a countOfNotesInFolder:a.folders.firstObject], 0u);
    XCTAssertEqual([a notesInFolder:nil matching:@"Old"].count, 0u, @"and from search");
    XCTAssertEqual([a deletedNotesMatching:nil].count, 1u, @"in Recently Deleted");
    XCTAssertEqual(SNDaysLeft([a deletedNotesMatching:nil].firstObject), SNRecentlyDeletedDays);
    [self sync:a];
    [self sync:b];
    XCTAssertEqual([b notesInFolder:nil matching:nil].count, 0u);
    XCTAssertEqualObjects([b deletedNotesMatching:@"Old"].firstObject.body, @"Old list", @"deleted there too, and found there");
    /* Recovered on the other device: back in its folder, everywhere. */
    [b recoverNote:[b deletedNotesMatching:nil].firstObject];
    [self sync:b];
    [self sync:a];
    XCTAssertEqual(a.countOfDeletedNotes, 0u);
    XCTAssertEqualObjects([a notesInFolder:a.folders.firstObject matching:nil].firstObject.body, @"Old list");
}

- (void)testAnEditToANoteDeletedElsewhereIsKeptInIt {
    SNNotes *a = [self device], *b = [self device];
    [self edit:[a addNoteInFolder:nil] on:a with:^(TopoText *t) { [t insertString:@"draft" atIndex:0 attributes:nil]; }];
    [self sync:a];
    [self sync:b];
    [a deleteNote:[self onlyNote:a]];
    [self edit:[self onlyNote:b] on:b with:^(TopoText *t) { [t insertString:@" two" atIndex:t.length attributes:nil]; }];
    [self sync:a];
    [self sync:b];
    [self sync:a];
    for (SNNotes *d in @[ a, b ]) {
        XCTAssertEqual([d notesInFolder:nil matching:nil].count, 0u, @"deleted, on both");
        XCTAssertEqualObjects([d deletedNotesMatching:nil].firstObject.body, @"draft two", @"with the edit, to recover");
    }
}

- (void)testNotesDeletedMoreThanThirtyDaysAgoGoForGood {
    SNNotes *a = [self device], *b = [self device];
    SNNote *old = [a addNoteInFolder:nil], *recent = [a addNoteInFolder:nil];
    [a deleteNote:old];
    [a deleteNote:recent];
    [self sync:a];
    [self sync:b];
    XCTAssertEqual(b.countOfDeletedNotes, 2u);
    /* A month on, for the first of them. */
    old.deletedAt = [NSDate dateWithTimeIntervalSinceNow:-(SNRecentlyDeletedDays + 1) * 86400.0];
    XCTAssertEqual([a removeNotesDeletedBefore:[NSDate dateWithTimeIntervalSinceNow:-SNRecentlyDeletedDays * 86400.0]], 1u);
    XCTAssertEqual(a.countOfDeletedNotes, 1u);
    [self sync:a];
    [self sync:b];
    XCTAssertEqual(b.countOfDeletedNotes, 1u, @"gone for good there too");
}

- (void)testDeleteImmediatelyAndDeleteAll {
    SNNotes *a = [self device], *b = [self device];
    for (int i = 0; i < 3; i++) [a deleteNote:[a addNoteInFolder:nil]];
    [a addNoteInFolder:nil];
    [self sync:a];
    [self sync:b];
    [b deleteNoteImmediately:[b deletedNotesMatching:nil].firstObject];
    XCTAssertEqual(b.countOfDeletedNotes, 2u);
    [b emptyRecentlyDeleted];
    XCTAssertEqual(b.countOfDeletedNotes, 0u);
    [self sync:b];
    [self sync:a];
    XCTAssertEqual(a.countOfDeletedNotes, 0u);
    XCTAssertEqual([a notesInFolder:nil matching:nil].count, 1u, @"the note not deleted, kept");
}

#pragma mark Moving

- (void)testMovingANoteBetweenFolders {
    SNNotes *a = [self device], *b = [self device];
    SNFolder *home = [a addFolderNamed:@"Home"], *work = [a addFolderNamed:@"Work"];
    SNNote *note = [a addNoteInFolder:home];
    [self sync:a];
    [self sync:b];
    [a moveNote:note toFolder:work];
    XCTAssertEqual([a countOfNotesInFolder:home], 0u);
    XCTAssertEqual([a countOfNotesInFolder:work], 1u);
    [self sync:a];
    [self sync:b];
    SNFolder *bWork = nil;
    for (SNFolder *f in b.folders) if ([f.name isEqual:@"Work"]) bWork = f;
    XCTAssertEqual([b countOfNotesInFolder:bWork], 1u, @"moved there too");
    /* Out of Recently Deleted, by moving it: recovered. */
    [b deleteNote:[self onlyNote:b]];
    [b moveNote:[b deletedNotesMatching:nil].firstObject toFolder:bWork];
    XCTAssertEqual(b.countOfDeletedNotes, 0u);
    XCTAssertEqual([b countOfNotesInFolder:bWork], 1u);
}

- (void)testPinnedFirst {
    SNNotes *a = [self device];
    SNNote *old = [a addNoteInFolder:nil];
    [self edit:old on:a with:^(TopoText *t) { [t insertString:@"old" atIndex:0 attributes:nil]; }];
    old.edited = [NSDate dateWithTimeIntervalSinceNow:-3600];
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

#pragma mark folders in folders

- (NSArray<NSString *> *)treeOf:(SNNotes *)d {
    NSMutableArray *names = [NSMutableArray array];
    for (SNFolder *f in d.folderTree)
        [names addObject:[[@"" stringByPaddingToLength:[d depthOfFolder:f] * 2 withString:@" " startingAtIndex:0] stringByAppendingString:f.name]];
    return names;
}

- (SNFolder *)folderNamed:(NSString *)name on:(SNNotes *)d {
    for (SNFolder *f in d.folders) if ([f.name isEqual:name]) return f;
    return nil;
}

- (void)testFoldersInFolders {
    SNNotes *a = [self device], *b = [self device];
    SNFolder *work = [a addFolderNamed:@"Work"], *home = [a addFolderNamed:@"Home"];
    SNFolder *projects = [a addFolderNamed:@"Projects" inFolder:work];
    SNFolder *archive = [a addFolderNamed:@"Archive" inFolder:projects];
    [a addNoteInFolder:archive];
    XCTAssertEqualObjects([self treeOf:a], (@[ @"Home", @"Work", @"  Projects", @"    Archive" ]));
    XCTAssertEqualObjects([a foldersInFolder:nil], (@[ home, work ]));
    XCTAssertTrue([a folder:archive isInFolder:work]);
    XCTAssertEqual([a countOfNotesInFolder:work], 0u, @"a folder's own notes");
    XCTAssertFalse([a moveFolder:work toFolder:archive], @"not into a folder in it");
    XCTAssertFalse([a moveFolder:work toFolder:work]);
    XCTAssertEqualObjects([self treeOf:a], (@[ @"Home", @"Work", @"  Projects", @"    Archive" ]));
    XCTAssertTrue([a moveFolder:projects toFolder:home]);
    [self sync:a];
    [self sync:b];
    XCTAssertEqualObjects([self treeOf:b], (@[ @"Home", @"  Projects", @"    Archive", @"Work" ]));
    XCTAssertEqual([b countOfNotesInFolder:[self folderNamed:@"Archive" on:b]], 1u);
    /* Moved back to the top, there too. */
    XCTAssertTrue([b moveFolder:[self folderNamed:@"Projects" on:b] toFolder:nil]);
    [self sync:b];
    [self sync:a];
    XCTAssertEqualObjects([self treeOf:a], (@[ @"Home", @"Projects", @"  Archive", @"Work" ]));
}

- (void)testFoldersMovedIntoEachOtherApartAreCutTheSameWayEverywhere {
    SNNotes *a = [self device], *b = [self device];
    [a addFolderNamed:@"X"];
    [a addFolderNamed:@"Y"];
    [self sync:a];
    [self sync:b];
    /* Apart: X into Y here, Y into X there. */
    XCTAssertTrue([a moveFolder:[self folderNamed:@"X" on:a] toFolder:[self folderNamed:@"Y" on:a]]);
    XCTAssertTrue([b moveFolder:[self folderNamed:@"Y" on:b] toFolder:[self folderNamed:@"X" on:b]]);
    [self sync:a];
    [self sync:b];
    [self sync:a];
    NSArray *tree = [self treeOf:a];
    XCTAssertEqualObjects([self treeOf:b], tree, @"the same on both");
    XCTAssertEqual(tree.count, 2u, @"both kept: %@", tree);
    XCTAssertEqual([a foldersInFolder:nil].count, 1u, @"one at the top, the other in it: %@", tree);
    /* And either can be moved out again. */
    SNFolder *inner = a.folderTree.lastObject;
    XCTAssertTrue([a moveFolder:inner toFolder:nil]);
    XCTAssertEqual([a foldersInFolder:nil].count, 2u);
}

- (void)testDeletingAFolderDeletesTheFoldersInIt {
    SNNotes *a = [self device], *b = [self device];
    SNFolder *work = [a addFolderNamed:@"Work"];
    SNFolder *projects = [a addFolderNamed:@"Projects" inFolder:work];
    [a addFolderNamed:@"Home"];
    [a addNoteInFolder:work];
    [a addNoteInFolder:projects];
    [self sync:a];
    [self sync:b];
    [b deleteFolder:[self folderNamed:@"Work" on:b]];
    XCTAssertEqualObjects([self treeOf:b], @[ @"Home" ]);
    XCTAssertEqual(b.countOfDeletedNotes, 2u);
    [self sync:b];
    [self sync:a];
    XCTAssertEqualObjects([self treeOf:a], @[ @"Home" ]);
    XCTAssertEqual(a.countOfDeletedNotes, 2u, @"their notes in Recently Deleted everywhere");
}

#pragma mark tags

- (void)testTagsAreWordsAfterAHash {
    XCTAssertEqualObjects(SNTagsInText(@"#Groceries for the #weekend-trip, #2024 and #q3_plan"), (@[ @"groceries", @"weekend-trip", @"q3_plan" ]));
    XCTAssertEqualObjects(SNTagsInText(@"issue#12 a#b # #"), @[], @"after a space or at the start, a letter in it");
    XCTAssertEqualObjects(SNTagsInText(@"#Work\n#work #WORK"), @[ @"work" ], @"one tag whatever its case");
    NSArray *ranges = SNTagRangesInText(@"buy #milk.");
    XCTAssertEqual(ranges.count, 1u);
    XCTAssertTrue(NSEqualRanges([ranges.firstObject rangeValue], NSMakeRange(4, 5)));
}

- (void)testNotesByTag {
    SNNotes *a = [self device], *b = [self device];
    SNNote *one = [a addNoteInFolder:[a addFolderNamed:@"Home"]], *two = [a addNoteInFolder:nil], *three = [a addNoteInFolder:nil];
    [self edit:one on:a with:^(TopoText *t) { [t insertString:@"Groceries #home #Errands" atIndex:0 attributes:nil]; }];
    [self edit:two on:a with:^(TopoText *t) { [t insertString:@"Bike\nfix it #errands" atIndex:0 attributes:nil]; }];
    [self edit:three on:a with:^(TopoText *t) { [t insertString:@"Old #errands" atIndex:0 attributes:nil]; }];
    [a deleteNote:three];
    XCTAssertEqualObjects(a.tags, (@[ @"errands", @"home" ]));
    XCTAssertEqual([a countOfNotesTagged:@"errands"], 2u, @"not the deleted one");
    XCTAssertEqual([a notesTagged:@"Errands" matching:@"bike"].count, 1u);
    [self sync:a];
    [self sync:b];
    XCTAssertEqualObjects(b.tags, (@[ @"errands", @"home" ]), @"tags are in the text, and sync with it");
    XCTAssertEqual([b countOfNotesTagged:@"home"], 1u);
}

#pragma mark sorting and grouping

/* Each group's heading ("" for none) and its notes' titles. */
- (NSArray *)titlesOf:(NSArray<SNNoteGroup *> *)groups {
    NSMutableArray *out = [NSMutableArray array];
    for (SNNoteGroup *g in groups) [out addObject:@[ g.title ?: @"", [g.notes valueForKey:@"title"] ]];
    return out;
}

- (void)testSortingAndGroupingByDate {
    SNNotes *a = [self device];
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *noon = [cal components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:[NSDate date]];
    noon.hour = 12;
    NSDate *now = [cal dateFromComponents:noon];
    NSMutableArray *notes = [NSMutableArray array];
    NSArray *made = @[ @[ @"Banana", @0, @5 ], @[ @"apple", @1, @0 ], @[ @"Cherry", @3, @2 ], @[ @"Date", @20, @1 ], @[ @"Elder", @400, @400 ] ];
    for (NSArray *m in made) {
        SNNote *n = [a addNoteInFolder:nil];
        n.title = m[0];
        n.edited = [now dateByAddingTimeInterval:-[m[1] integerValue] * 86400.0];
        n.created = [now dateByAddingTimeInterval:-[m[2] integerValue] * 86400.0];
        [notes addObject:n];
    }
    [a setNote:notes[3] pinned:YES];
    NSDateFormatter *year = [[NSDateFormatter alloc] init];
    year.dateFormat = @"yyyy";
    NSString *old = [year stringFromDate:[now dateByAddingTimeInterval:-400 * 86400.0]];
    XCTAssertEqualObjects([self titlesOf:SNGroupNotes(notes, SNSortByDateEdited, YES, now)],
                          (@[ @[ @"Pinned", @[ @"Date" ] ], @[ @"Today", @[ @"Banana" ] ], @[ @"Yesterday", @[ @"apple" ] ],
                              @[ @"Previous 7 Days", @[ @"Cherry" ] ], @[ old, @[ @"Elder" ] ] ]));
    XCTAssertEqualObjects([self titlesOf:SNGroupNotes(notes, SNSortByDateCreated, YES, now)],
                          (@[ @[ @"Pinned", @[ @"Date" ] ], @[ @"Today", @[ @"apple" ] ], @[ @"Previous 7 Days", @[ @"Cherry", @"Banana" ] ],
                              @[ old, @[ @"Elder" ] ] ]));
    XCTAssertEqualObjects([self titlesOf:SNGroupNotes(notes, SNSortByTitle, YES, now)],
                          (@[ @[ @"Pinned", @[ @"Date" ] ], @[ @"Notes", @[ @"apple", @"Banana", @"Cherry", @"Elder" ] ] ]));
    [a setNote:notes[3] pinned:NO];
    XCTAssertEqualObjects([self titlesOf:SNGroupNotes(notes, SNSortByDateEdited, NO, now)],
                          (@[ @[ @"", @[ @"Banana", @"apple", @"Cherry", @"Date", @"Elder" ] ] ]), @"one list, no headings");
    /* The device's choice, for its lists. */
    SNSortOrder was = a.sortOrder;
    a.sortOrder = SNSortByTitle;
    XCTAssertEqualObjects([[a notesInFolder:nil matching:nil] valueForKey:@"title"], (@[ @"apple", @"Banana", @"Cherry", @"Date", @"Elder" ]));
    a.sortOrder = was;
}

/* A folder sorted its own way (View > Sort Folder By), on every device;
   the others as the device sorts. */
- (void)testAFolderHasItsOwnOrderEverywhere {
    SNNotes *a = [self device], *b = [self device];
    SNFolder *home = [a addFolderNamed:@"Home"];
    NSArray *titles = @[ @"Cherry", @"apple", @"Banana" ];
    for (NSString *t in titles) [self edit:[a addNoteInFolder:home] on:a with:^(TopoText *text) {
        [text insertString:t atIndex:0 attributes:nil];
    }];
    XCTAssertNil([a sortOrderOfFolder:home], @"the device's, to begin with");
    [a setSortOrder:@(SNSortByTitle) ofFolder:home];
    XCTAssertEqual([a sortOrderForFolder:home], SNSortByTitle);
    XCTAssertEqual([a sortOrderForFolder:nil], a.sortOrder, @"All Notes: the device's");
    XCTAssertEqualObjects([[a notesInFolder:home matching:nil] valueForKey:@"title"], (@[ @"apple", @"Banana", @"Cherry" ]));
    [self sync:a];
    [self sync:b];
    SNFolder *there = [b foldersInFolder:nil].firstObject;
    XCTAssertEqualObjects([b sortOrderOfFolder:there], @(SNSortByTitle), @"synced with the folder");
    XCTAssertEqualObjects([[b notesInFolder:there matching:nil] valueForKey:@"title"], (@[ @"apple", @"Banana", @"Cherry" ]));
    [b setSortOrder:nil ofFolder:there];
    XCTAssertNil([b sortOrderOfFolder:there], @"back to the device's");
}

#pragma mark smart folders

- (void)testASmartFolderHasTheNotesItsRulesTake {
    SNNotes *a = [self device], *b = [self device];
    SNFolder *home = [a addFolderNamed:@"Home"], *work = [a addFolderNamed:@"Work"];
    SNNote *groceries = [a addNoteInFolder:home], *standup = [a addNoteInFolder:work], *ideas = [a addNoteInFolder:nil];
    [self edit:groceries on:a with:^(TopoText *t) {
        [t insertString:@"Groceries #errands\nmilk\neggs" atIndex:0 attributes:nil];
        [t addParagraphAttributes:@{ @"list": @"check" } range:NSMakeRange(19, 5)];
        [t addParagraphAttributes:@{ @"list": @"check", @"checked": @YES } range:NSMakeRange(24, 4)];
    }];
    [self edit:standup on:a with:^(TopoText *t) { [t insertString:@"Standup #work #errands" atIndex:0 attributes:nil]; }];
    [self edit:ideas on:a with:^(TopoText *t) { [t insertString:@"Ideas #work" atIndex:0 attributes:nil]; }];
    [a setNote:ideas pinned:YES];

    SNSmartFilter *errands = [[SNSmartFilter alloc] init];
    errands.tags = @[ @"errands" ];
    SNFolder *smart = [a addSmartFolderNamed:@"Errands" filter:errands inFolder:nil];
    XCTAssertTrue([a isSmartFolder:smart]);
    XCTAssertFalse([a isSmartFolder:home]);
    XCTAssertEqualObjects([NSSet setWithArray:[[a notesInFolder:smart matching:nil] valueForKey:@"title"]],
                          ([NSSet setWithObjects:@"Groceries #errands", @"Standup #work #errands", nil]), @"from every folder");
    XCTAssertEqual([a countOfNotesInFolder:smart], 2u);
    XCTAssertEqual([a notesInFolder:smart matching:@"standup"].count, 1u, @"and searched");

    /* All of the rules, or any. */
    SNSmartFilter *f = [[SNSmartFilter alloc] init];
    f.tags = @[ @"work", @"errands" ];
    XCTAssertEqualObjects([self titles:a filter:f], [NSSet setWithObject:@"Standup #work #errands"], @"both tags");
    f.anyTag = YES;
    XCTAssertEqual([self titles:a filter:f].count, 3u, @"either tag");
    SNSmartFilter *g = [[SNSmartFilter alloc] init];
    g.checklists = SNChecklistRuleUnticked;
    XCTAssertEqualObjects([self titles:a filter:g], [NSSet setWithObject:@"Groceries #errands"], @"an item not ticked");
    g.pinnedOnly = YES;
    XCTAssertEqual([self titles:a filter:g].count, 0u, @"and pinned: none");
    g.matchesAny = YES;
    XCTAssertEqual([self titles:a filter:g].count, 2u, @"or pinned: two");
    XCTAssertEqualObjects([SNSmartFilter filterWithString:g.string], g, @"kept as text, read back the same");

    /* Nothing goes into it; a note made in it is in no folder. */
    [a moveNote:groceries toFolder:smart];
    XCTAssertEqual(groceries.folder, home);
    XCTAssertNil([a addNoteInFolder:smart].folder);
    XCTAssertFalse([a moveFolder:work toFolder:smart]);

    [self sync:a];
    [self sync:b];
    SNFolder *there = nil;
    for (SNFolder *x in [b folders])
        if ([x.name isEqual:@"Errands"]) there = x;
    XCTAssertEqualObjects([b filterOfFolder:there], errands, @"its rules synced with it");
    XCTAssertEqual([b countOfNotesInFolder:there], 2u);
}

- (NSSet *)titles:(SNNotes *)device filter:(SNSmartFilter *)filter {
    NSMutableSet *out = [NSMutableSet set];
    for (SNNote *n in [device notesInFolder:nil matching:nil])
        if ([filter matchesNote:n now:[NSDate date]]) [out addObject:n.title];
    return out;
}

#pragma mark attachments

- (void)testAnAttachmentGoesToTheOtherDevice {
    SNNotes *a = [self device], *b = [self device];
    SNNote *note = [a addNoteInFolder:nil];
    NSData *data = [NSData dataWithBytes:"\x89PNG not really" length:16];
    SNAttachment *image = [a addImageToNote:note data:data type:@"image/png" width:40 height:30];
    [self edit:note on:a with:^(TopoText *t) {
        [t insertString:@"Photo \uFFFC" atIndex:0 attributes:nil];
        [t addAttributes:@{ @"attachment": image.id } range:NSMakeRange(6, 1)];
    }];
    XCTAssertEqualObjects(note.title, @"Photo", @"the attachment's character is not a word");
    [self sync:a];
    [self sync:b];
    SNNote *there = [self onlyNote:b];
    NSString *attachmentID = [there.text attributesAtIndex:6 effectiveRange:NULL][@"attachment"];
    SNAttachment *came = [b attachmentWithID:attachmentID];
    XCTAssertEqualObjects(came.data, data);
    XCTAssertEqualObjects(came.type, @"image/png");
    XCTAssertEqual(came.note, there);
    /* Gone with its note. */
    [b deleteNote:there];
    [b deleteNoteImmediately:there];
    XCTAssertNil([b attachmentWithID:attachmentID]);
    [self sync:b];
    [self sync:a];
    XCTAssertNil([a attachmentWithID:attachmentID], @"and everywhere");
}

- (void)testAFileGoesToTheOtherDevice {
    SNNotes *a = [self device], *b = [self device];
    SNNote *note = [a addNoteInFolder:nil];
    NSData *pdf = [@"%PDF-1.4 a little document" dataUsingEncoding:NSUTF8StringEncoding];
    SNAttachment *file = [a addFileToNote:note data:pdf name:@"Lease.pdf" type:@"application/pdf"];
    XCTAssertEqualObjects(file.kind, SNAttachmentKindFile);
    [self sync:a];
    [self sync:b];
    SNAttachment *came = [b attachmentWithID:file.id];
    XCTAssertEqualObjects(came.data, pdf);
    XCTAssertEqualObjects(came.name, @"Lease.pdf");
    XCTAssertEqualObjects(came.type, @"application/pdf");
    XCTAssertEqualObjects([a addFileToNote:note data:pdf name:@"x" type:nil].type, @"application/octet-stream", @"a type, always");
}

- (void)testATableEditedOnTwoDevicesIsMerged {
    SNNotes *a = [self device], *b = [self device];
    SNNote *note = [a addNoteInFolder:nil];
    SNAttachment *made = [a addTableToNote:note rows:1 columns:2];
    TTTable *t = [a tableOfAttachment:made];
    [[t textAtRow:0 column:0] insertString:@"Milk" atIndex:0 attributes:nil];
    [a saveTable:t toAttachment:made];
    [self sync:a];
    [self sync:b];
    /* Apart: a row on one, a cell on the other. */
    TTTable *ta = [a tableOfAttachment:made];
    [ta insertRowAtIndex:1];
    [[ta textAtRow:1 column:0] insertString:@"Eggs" atIndex:0 attributes:nil];
    [a saveTable:ta toAttachment:made];
    SNAttachment *there = [b attachmentWithID:made.id];
    TTTable *tb = [b tableOfAttachment:there];
    [[tb textAtRow:0 column:1] insertString:@"2 l" atIndex:0 attributes:nil];
    [b saveTable:tb toAttachment:there];
    [self sync:a];
    [self sync:b];
    [self sync:a];
    NSArray *want = @[ @[ @"Milk", @"2 l" ], @[ @"Eggs", @"" ] ];
    XCTAssertEqualObjects([a tableOfAttachment:made].strings, want);
    XCTAssertEqualObjects([b tableOfAttachment:there].strings, want);
}

@end
