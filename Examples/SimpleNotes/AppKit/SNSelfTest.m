#import "SNSelfTest.h"
#import "SNWindowController.h"
#import "SNModel.h"
#import "SNRichText.h"
#import "SNTableGrid.h"
#import "SNSmartFolderPanel.h"
#import "SNSyncPanel.h"

NSURL *SNSelfTestRoot;

/* What the Sync window chose. */
@interface SNSyncChoice : NSObject <SNSyncPanelDelegate>
@property (nonatomic, strong) NSURL *root;
@property (nonatomic) BOOL chosen;
@end

@implementation SNSyncChoice
- (void)syncPanel:(SNSyncPanel *)panel didChooseServer:(NSURL *)root signIn:(SNSignIn *)signIn {
    _root = root;
    _chosen = YES;
}
@end

static int SNFailed;

static void SNSay(BOOL ok, NSString *what) {
    fprintf(stderr, "%s %s\n", ok ? "PASS" : "FAIL", what.UTF8String);
    if (!ok) SNFailed++;
}

/* The run loop turned until done says so, or seconds pass. */
static BOOL SNWait(NSTimeInterval seconds, BOOL (^done)(void)) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!done() && [until timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    return done();
}

static void SNFinish(void) {
    fprintf(stderr, "self-test: %s\n", SNFailed ? "FAILED" : "passed");
    exit(SNFailed);
}

/* A small image, as a PNG: what Attach File reads. */
static NSData *SNSelfTestPNG(void) {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:64 pixelsHigh:48 bitsPerSample:8 samplesPerPixel:4
                                                                      hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    [NSGraphicsContext setCurrentContext:context];
    [[NSColor colorWithCalibratedRed:0.99 green:0.78 blue:0.17 alpha:1] setFill];
    NSRectFill(NSMakeRect(0, 0, 64, 48));
    [context flushGraphics];   /* gnustep-back: into the bitmap */
    [NSGraphicsContext restoreGraphicsState];
#ifdef GNUSTEP
    return [rep representationUsingType:NSPNGFileType properties:@{}];
#else
    return [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
#endif
}

@interface SNSelfTest : NSObject
@property (nonatomic, copy) void (^run)(void);
@end
@implementation SNSelfTest
/* An exception is a failure, not a hang: a timer would swallow it, and
   the test never finish. */
- (void)fire:(NSTimer *)timer {
    @try {
        self.run();
    } @catch (NSException *e) {
        fprintf(stderr, "FAIL %s: %s\nself-test: FAILED\n", e.name.UTF8String, e.reason.UTF8String);
        exit(1);
    }
}
@end

void SNStartSelfTest(SNNotes *notes, SNWindowController *window, NSURL *root) {
    /* From a timer, not the main queue: the waits below turn the run loop,
       and what finishes a sync comes back through the main queue. */
    SNSelfTest *test = [SNSelfTest new];
    [NSTimer scheduledTimerWithTimeInterval:0.5 target:test selector:@selector(fire:) userInfo:nil repeats:NO];
    test.run = ^{
        SNSay(SNWait(30, ^BOOL { return notes.lastSync != nil && !notes.syncing; }), @"the app syncs with the server");
        SNSay([window selectNoteTitled:@"Groceries"], [NSString stringWithFormat:@"the note is in the list, and chosen (%@)", [window shownText]]);
        NSTextView *tv = window.textView;
        SNSay([tv.string hasPrefix:@"Groceries"], @"its text is in the window's text view");
        [window.window makeFirstResponder:tv];
        tv.selectedRange = NSMakeRange(tv.string.length, 0);
        [tv insertText:@" and tea"];
        tv.selectedRange = NSMakeRange(0, 9);
        /* From the text view up, as the menu's Bold goes when the window is
           key (an app started from a terminal may have no key window). */
        SNSay([tv tryToPerform:@selector(toggleBold:) with:nil], @"Bold goes up the responder chain");
        /* Written a moment after the last keystroke, then synced. */
        SNWait(2, ^BOOL { return NO; });
        [notes sync];
        SNWait(30, ^BOOL { return !notes.syncing; });
        SNSay(notes.pendingCount == 0, @"what was typed went to the server");

        /* Another device sees it. */
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                             [NSString stringWithFormat:@"sn-selftest-%@.sqlite", [NSProcessInfo processInfo].globallyUniqueString]];
        SNNotes *other = [[SNNotes alloc] initWithStoreURL:[NSURL fileURLWithPath:path] error:NULL];
        other.serviceRoot = root;
        NSError *error = nil;
        SNSay([other syncAndWait:&error], [NSString stringWithFormat:@"a second device syncs%@", error ? [@": " stringByAppendingString:error.localizedDescription] : @""]);
        SNNote *there = nil;
        for (SNNote *n in [other notesInFolder:nil matching:@"Groceries"]) there = n;
        SNSay([there.body hasSuffix:@"coffee beans and tea"], [NSString stringWithFormat:@"the second device has the typing (%@)", there.body]);
        SNSay([[there.text attributesAtIndex:0 effectiveRange:NULL][@"bold"] boolValue], @"and the bold");

        /* A checklist: two lines made one from the Format menu, the first
           ticked by a click on its checkbox, a third item begun by Return. */
        SNSay([window selectNoteTitled:@"Weekend"], @"another note chosen");
        NSString *s = tv.string;
        NSRange lines = NSMakeRange(NSMaxRange([s lineRangeForRange:NSMakeRange(0, 0)]), 0);
        lines.length = s.length - lines.location;
        tv.selectedRange = lines;
        SNSay([tv tryToPerform:@selector(toggleChecklist:) with:nil], @"Checklist from the menu");
        NSLayoutManager *lm = tv.layoutManager;
        SNSay([lm isKindOfClass:[SNListLayoutManager class]], @"the text view draws list markers");
        NSRect line = [lm lineFragmentRectForGlyphAtIndex:[lm glyphRangeForCharacterRange:NSMakeRange(lines.location, 1) actualCharacterRange:NULL].location
                                    effectiveRange:NULL];
        NSUInteger box = [(SNListLayoutManager *)lm checkboxAtPoint:NSMakePoint(10, NSMidY(line))];
        SNSay(box == lines.location, [NSString stringWithFormat:@"a checkbox where the first item's is (%lu)", (unsigned long)box]);
        if (box != NSNotFound) [window textView:window.textView clickedCheckboxAtIndex:box];
        tv.selectedRange = NSMakeRange(tv.string.length, 0);
        [tv insertNewline:nil];
        [tv insertText:@"water the plants"];
        SNWait(2, ^BOOL { return NO; });
        [notes sync];
        SNWait(30, ^BOOL { return !notes.syncing; });
        [other syncAndWait:NULL];
        SNNote *weekend = nil;
        for (SNNote *n in [other notesInFolder:nil matching:@"Weekend"]) weekend = n;
        TopoText *wt = weekend.text;
        NSArray *paras = wt.paragraphRanges;
        NSMutableArray *seen = [NSMutableArray array];
        for (NSValue *v in paras) {
            NSDictionary *p = [wt paragraphAttributesAtIndex:v.rangeValue.location keys:SNParagraphKeys()];
            [seen addObject:[NSString stringWithFormat:@"%@%@", p[SNListKey] ?: @"-", [p[SNCheckedKey] boolValue] ? @"+" : @""]];
        }
        SNSay([seen isEqual:@[ @"-", @"check+", @"check", @"check" ]] && [weekend.body hasSuffix:@"water the plants"],
              [NSString stringWithFormat:@"the second device has the checklist, the first item ticked (%@)", [seen componentsJoinedByString:@" "]]);

        /* The ticked item to the bottom, from the Format menu; an image
           attached; a link to another note followed. */
        tv.selectedRange = NSMakeRange(lines.location, 0);
        SNSay([tv tryToPerform:@selector(moveCheckedToBottom:) with:nil], @"Move Checked to Bottom from the menu");
        tv.selectedRange = NSMakeRange(tv.string.length, 0);
        [tv insertNewline:nil];
        [tv insertNewline:nil];   /* on the empty item: the list ends */
        SNSay([window attachImageData:SNSelfTestPNG()], @"an image attached");
        /* A table after it, from the Format menu, typed into where it is:
           Tab to the next cell, and from the last one a row more. */
        [tv insertNewline:nil];
        SNSay([tv tryToPerform:@selector(addTable:) with:nil], @"Insert Table from the menu");
        NSString *tableID = [tv.textStorage attribute:SNAttachmentAttributeName atIndex:tv.string.length - 1 effectiveRange:NULL];
        SNTableGrid *grid = tableID ? [window gridForAttachmentID:tableID] : nil;
        SNSay(grid && grid.table.rowCount == 2 && grid.table.columnCount == 2 && tv.window.firstResponder == [grid textViewAtRow:0 column:0],
              @"a table in the note, its first cell typed in");
        NSArray *cells = @[ @[ @"Bike", @"Saturday" ], @[ @"Grandma", @"Sunday morning, before lunch" ] ];
        for (NSUInteger k = 0; k < 4; k++) {
            NSTextView *cell = (NSTextView *)tv.window.firstResponder;
            [cell insertText:cells[k / 2][k % 2]];
            [cell doCommandBySelector:@selector(insertTab:)];
        }
        SNSay(grid.table.rowCount == 3 && tv.window.firstResponder == [grid textViewAtRow:2 column:0],
              [NSString stringWithFormat:@"Tab from the last cell: a row more (%lu)", (unsigned long)grid.table.rowCount]);
        SNSay([tv.window.firstResponder tryToPerform:@selector(deleteRow:) with:nil] && grid.table.rowCount == 2,
              @"Delete Row from the menu");
        SNSay([grid.table.strings isEqual:cells], [NSString stringWithFormat:@"the cells typed (%@)", grid.table.strings]);
        /* A cell's characters formatted, as the note's: Bold from the menu,
           on what is selected in the cell; a cell's paragraphs not. */
        NSTextView *bike = (NSTextView *)[grid textViewAtRow:0 column:0];
        [tv.window makeFirstResponder:bike];
        bike.selectedRange = NSMakeRange(0, 4);
        SNSay([bike tryToPerform:@selector(toggleBold:) with:nil] &&
              [[[grid.table textAtRow:0 column:0] attributesAtIndex:0 effectiveRange:NULL][SNBoldKey] boolValue],
              @"Bold in a cell, from the menu: the cell's text bold");
        /* Undo in a cell: its typing undone, as the note's is. (Here all of
           the test is one event of the run loop, one undo group: begun
           afresh, so Undo has only this.) */
        SNWait(0.3, ^BOOL { return NO; });
        [tv.window.undoManager removeAllActions];
        bike.selectedRange = NSMakeRange(4, 0);
        [bike insertText:@"s"];
        SNWait(0.3, ^BOOL { return NO; });
        BOOL typedS = [[grid.table textAtRow:0 column:0].string isEqual:@"Bikes"];
        SNSay(typedS && [bike tryToPerform:@selector(undo:) with:nil] && [[grid.table textAtRow:0 column:0].string isEqual:@"Bike"] &&
              [bike.string isEqual:@"Bike"], [NSString stringWithFormat:@"Undo in a cell (%@)", [grid.table textAtRow:0 column:0].string]);
        SNWait(0.3, ^BOOL { return NO; });
        NSMenuItem *titleItem = [[NSMenuItem alloc] initWithTitle:@"Title" action:@selector(styleTitle:) keyEquivalent:@""];
        SNSay(![window validateMenuItem:titleItem], @"no Title in a cell");
        /* Over its place in the text, which keeps its room. */
        NSLayoutManager *tlm = tv.layoutManager;
        NSUInteger tg = [tlm glyphRangeForCharacterRange:NSMakeRange(tv.string.length - 1, 1) actualCharacterRange:NULL].location;
        NSRect room = [tlm boundingRectForGlyphRange:NSMakeRange(tg, 1) inTextContainer:tv.textContainer];
        room = NSOffsetRect(room, tv.textContainerOrigin.x, tv.textContainerOrigin.y);
        SNSay(grid.superview == tv && fabs(NSMinX(grid.frame) - NSMinX(room)) < 2 && NSMinY(grid.frame) >= NSMinY(room) - 2 &&
              NSMaxY(grid.frame) <= NSMaxY(room) + 2 && NSHeight(grid.frame) > 40,
              [NSString stringWithFormat:@"the grid over its room (%@, %@)", NSStringFromRect(grid.frame), NSStringFromRect(room)]);
        [grid save];
        SNWait(2, ^BOOL { return NO; });
        [notes sync];
        SNWait(30, ^BOOL { return !notes.syncing; });
        [other syncAndWait:NULL];
        for (SNNote *n in [other notesInFolder:nil matching:@"Weekend"]) weekend = n;
        wt = weekend.text;
        NSArray *lines2 = [wt.string componentsSeparatedByString:@"\n"];
        SNSay(lines2.count == 6 && [lines2[3] isEqual:@"fix the bike"],
              [NSString stringWithFormat:@"the second device has it at the bottom (%@)", [lines2 componentsJoinedByString:@" | "]]);
        NSString *imageID = wt.length > 2 ? [wt attributesAtIndex:wt.length - 3 effectiveRange:NULL][SNAttachmentKey] : nil;
        SNAttachment *image = imageID ? [other attachmentWithID:imageID] : nil;
        SNSay(image.data.length > 0 && image.width.doubleValue == 64, [NSString stringWithFormat:@"and the image (%@, %@)", imageID, image.type]);
        NSString *tableThereID = wt.length ? [wt attributesAtIndex:wt.length - 1 effectiveRange:NULL][SNAttachmentKey] : nil;
        SNAttachment *tableThere = tableThereID ? [other attachmentWithID:tableThereID] : nil;
        SNSay([[other tableOfAttachment:tableThere].strings isEqual:cells],
              [NSString stringWithFormat:@"and the table (%@)", [other tableOfAttachment:tableThere].strings]);
        SNSay([[[[other tableOfAttachment:tableThere] textAtRow:0 column:0] attributesAtIndex:0 effectiveRange:NULL][SNBoldKey] boolValue],
              @"its cell's bold too");
        SNNote *groceries = nil;
        for (SNNote *n in [notes notesInFolder:nil matching:@"Groceries"]) groceries = n;
        [window textView:window.textView clickedOnLink:SNLinkToNote(groceries.id) atIndex:0];
        SNSay([tv.string hasPrefix:@"Groceries"], @"a link to a note opens it");
        [window selectNoteTitled:@"Weekend"];
        /* Folders in folders, and tags, in the sidebar. */
        NSArray *sidebar = [window sidebarRows];
        SNSay([sidebar containsObject:@"Work"] && [sidebar containsObject:@"  Projects"],
              [NSString stringWithFormat:@"Projects in Work in the sidebar (%@)", [sidebar componentsJoinedByString:@" | "]]);
        SNSay([sidebar containsObject:@"Tags"] && [sidebar containsObject:@"  #family"] && [sidebar containsObject:@"  #work"],
              @"the tags in the notes, under Tags");
        SNSay([window showTag:@"work"] && [[window shownText] hasPrefix:@"#work chosen"] && [[window shownRows] containsObject:@"Standup notes"] && [[window shownRows] containsObject:@"Ideas"] && ![[window shownRows] containsObject:@"Weekend"],
              [NSString stringWithFormat:@"#work lists its notes (%@)", [window shownText]]);
        SNSay([window showFolderNamed:@"Projects"] && [[[window shownRows] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"NOT SELF BEGINSWITH '## '"]] isEqual:@[ @"Ideas" ]],
              [NSString stringWithFormat:@"a folder in a folder lists its notes (%@)", [window shownText]]);
        /* Projects to the top, here; there too. */
        SNFolder *projects = nil;
        for (SNFolder *f in notes.folders) if ([f.name isEqual:@"Projects"]) projects = f;
        SNSay([notes moveFolder:projects toFolder:nil] && [[window sidebarRows] containsObject:@"Projects"], @"Projects moved to the top");
        [notes sync];
        SNWait(30, ^BOOL { return !notes.syncing; });
        [other syncAndWait:NULL];
        SNSay([[[other foldersInFolder:nil] valueForKey:@"name"] containsObject:@"Projects"], @"and on the second device");
        /* Sorted by title, grouped: pinned first. */
        SNSortOrder order = notes.sortOrder;
        BOOL grouped = notes.groupsByDate;
        [window showAllNotes];
        SNSay([tv tryToPerform:@selector(sortByTitle:) with:nil] &&
              [[window shownRows] isEqual:(@[ @"## Pinned", @"Groceries", @"## Notes", @"Ideas", @"Standup notes", @"Weekend" ])],
              [NSString stringWithFormat:@"Sort By Title from the menu (%@)", [[window shownRows] componentsJoinedByString:@" | "]]);
        notes.sortOrder = order;
        notes.groupsByDate = grouped;
        [window showAllNotes];
        [window selectNoteTitled:@"Weekend"];
        /* A folder sorted its own way, from View > Sort Folder By; synced. */
        SNFolder *work = nil;
        for (SNFolder *f in notes.folders) if ([f.name isEqual:@"Work"]) work = f;
        [window showFolderNamed:@"Work"];
        NSMenuItem *byTitle = [[NSMenuItem alloc] initWithTitle:@"Title" action:@selector(sortFolderByTitle:) keyEquivalent:@""];
        SNSay([tv tryToPerform:@selector(sortFolderByTitle:) with:nil] && [[notes sortOrderOfFolder:work] isEqual:@(SNSortByTitle)] &&
              [window validateMenuItem:byTitle] && byTitle.state == NSControlStateValueOn,
              @"Sort Folder By Title from the menu, ticked");
        [window showAllNotes];
        NSMenuItem *byTitleHere = [[NSMenuItem alloc] initWithTitle:@"Title" action:@selector(sortFolderByTitle:) keyEquivalent:@""];
        SNSay(![window validateMenuItem:byTitleHere], @"not for All Notes");
        /* A smart folder: every note tagged #work, from any folder. */
        SNSmartFilter *workTagged = [[SNSmartFilter alloc] init];
        workTagged.tags = @[ @"work" ];
        [notes addSmartFolderNamed:@"Work Things" filter:workTagged inFolder:nil];
        SNWait(0.5, ^BOOL { return NO; });
        SNSay([[window sidebarRows] containsObject:@"Work Things"] && [window showFolderNamed:@"Work Things"] &&
              [[window shownRows] containsObject:@"Standup notes"] && [[window shownRows] containsObject:@"Ideas"] &&
              ![[window shownRows] containsObject:@"Weekend"],
              [NSString stringWithFormat:@"a smart folder lists the notes its rules take (%@)", [[window shownRows] componentsJoinedByString:@" | "]]);
        /* Its panel (SmartFolderPanel.xib) loads, and shows the rules. */
        SNSmartFolderPanel *panel = [[SNSmartFolderPanel alloc] initWithName:@"Work Things" filter:workTagged];
        SNSay(panel.window && panel.nameField && panel.tagsField && panel.editedPopUp.numberOfItems == 6 &&
              panel.checklistsPopUp.numberOfItems == 4 && panel.pinnedBox, @"the smart folder panel loads");
        /* The Sync window: this computer only warned of; a server that asks
           for no sign-in chosen as it is (learnt from its $metadata). */
        SNSyncPanel *sync = [[SNSyncPanel alloc] initWithServer:nil];
        SNSyncChoice *choice = [[SNSyncChoice alloc] init];
        sync.delegate = choice;
        SNSay(sync.window && sync.serverField && sync.codeLabel && sync.localButton.state == NSControlStateValueOn && !sync.warningLabel.isHidden,
              @"the Sync window loads, this computer only warned of");
        [sync syncWithServer:nil];
        sync.serverField.stringValue = notes.serviceRoot.absoluteString;
        [sync ok:nil];
        SNWait(10, ^BOOL { return choice.chosen; });
        SNSay(choice.chosen && [choice.root isEqual:notes.serviceRoot] && sync.warningLabel.isHidden && sync.signIn.kind == SNSignInNone,
              [NSString stringWithFormat:@"a server with no sign-in chosen (%@)", choice.root]);
        NSMenuItem *editSmart = [[NSMenuItem alloc] initWithTitle:@"Edit" action:@selector(editSmartFolder:) keyEquivalent:@""];
        SNSay([window validateMenuItem:editSmart], @"Edit Smart Folder for it");
        [notes sync];
        SNWait(30, ^BOOL { return !notes.syncing; });
        [other syncAndWait:NULL];
        SNFolder *workThere = nil, *smartThere = nil;
        for (SNFolder *f in other.folders) {
            if ([f.name isEqual:@"Work"]) workThere = f;
            if ([f.name isEqual:@"Work Things"]) smartThere = f;
        }
        SNSay([[other sortOrderOfFolder:workThere] isEqual:@(SNSortByTitle)] && [other countOfNotesInFolder:smartThere] == 2,
              @"the folder's order and the smart folder on the second device");
        /* Undo after a sync changed the note: what was typed here undone,
           what came from the other device kept. */
        [window showAllNotes];
        [window selectNoteTitled:@"Standup notes"];
        tv.selectedRange = NSMakeRange(tv.string.length, 0);
        [tv insertText:@" undo me"];
        SNWait(0.3, ^BOOL { return NO; });
        [notes saveAll];
        [notes sync];
        SNWait(30, ^BOOL { return !notes.syncing; });
        [other syncAndWait:NULL];
        SNNote *standupThere = [other notesInFolder:nil matching:@"Standup"].firstObject;
        SNNoteEditor *elsewhere = [other editorForNote:standupThere];
        /* In its second line: the title stays. */
        [elsewhere.text insertString:@"(Monday) " atIndex:[elsewhere.text.string rangeOfString:@"\n"].location + 1 attributes:nil];
        [elsewhere textDidChange];
        [elsewhere close];
        [other syncAndWait:NULL];
        [notes sync];
        SNWait(30, ^BOOL { return !notes.syncing && [tv.string containsString:@"(Monday) "]; });
        SNSay([tv.string containsString:@"(Monday) "] && [tv.string hasSuffix:@" undo me"], @"the other device's edit merged into the open note");
        SNSay([tv tryToPerform:@selector(undo:) with:nil] && [tv.string containsString:@"\n(Monday) sync engine"] && ![tv.string containsString:@"undo me"],
              [NSString stringWithFormat:@"Undo after the merge: the typing undone, the other's edit kept (%@)", [tv.string stringByReplacingOccurrencesOfString:@"\n" withString:@" | "]]);
        SNSay([tv tryToPerform:@selector(redo:) with:nil] && [tv.string hasSuffix:@" undo me"] && [tv.string containsString:@"(Monday) "],
              @"and Redo");
        /* A file: a card in the note, written out to be opened. */
        [window showAllNotes];
        [window selectNoteTitled:@"Weekend"];
        tv.selectedRange = NSMakeRange(tv.string.length, 0);
        [tv insertNewline:nil];
        NSData *pdf = [@"%PDF-1.4 a lease" dataUsingEncoding:NSUTF8StringEncoding];
        SNSay([window attachFileData:pdf name:@"Lease.pdf"], @"a file attached");
        NSString *fileID = [tv.textStorage attribute:SNAttachmentAttributeName atIndex:tv.string.length - 1 effectiveRange:NULL];
        NSTextAttachment *card = [tv.textStorage attribute:NSAttachmentAttributeName atIndex:tv.string.length - 1 effectiveRange:NULL];
        SNAttachment *lease = fileID ? [notes attachmentWithID:fileID] : nil;
        NSURL *written = lease ? [notes fileURLOfAttachment:lease] : nil;
        SNSay([lease.kind isEqual:SNAttachmentKindFile] && card.attachmentCell.cellSize.height > 40 &&
              [written.lastPathComponent isEqual:@"Lease.pdf"] && [[NSData dataWithContentsOfURL:written] isEqual:pdf],
              [NSString stringWithFormat:@"shown as a card, written out to be opened (%@)", written.path]);

        /* SN_SELF_TEST_SNAPSHOT=<path.png>: the window as it is now, drawn
           into a picture (the README's screenshots). */
        const char *snapshot = getenv("SN_SELF_TEST_SNAPSHOT");
        if (snapshot) {
            tv.selectedRange = NSMakeRange(tv.string.length, 0);
            NSView *v = window.window.contentView;
            /* Drawn whole first: gnustep-gui's cacheDisplayInRect: copies
               what the window last displayed. */
            [window.window display];
            NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:v.bounds];
            [v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];
#ifdef GNUSTEP
            NSData *png = [rep representationUsingType:NSPNGFileType properties:@{}];
#else
            NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
#endif
            SNSay([png writeToFile:@(snapshot) atomically:YES], [NSString stringWithFormat:@"a snapshot in %s", snapshot]);
        }

        /* Deleted from the window, into Recently Deleted on the other device;
           recovered from Recently Deleted, back there too. */
        [window showAllNotes];
        [window selectNoteTitled:@"Groceries"];
        [tv tryToPerform:@selector(deleteNote:) with:nil];
        [notes sync];
        SNWait(30, ^BOOL { return !notes.syncing; });
        [other syncAndWait:NULL];
        SNSay([other notesInFolder:nil matching:@"Groceries"].count == 0 && [other deletedNotesMatching:@"Groceries"].count == 1,
              @"a note deleted here is in Recently Deleted there");
        [window showRecentlyDeleted];
        SNSay([window selectNoteTitled:@"Groceries"] && !tv.isEditable, @"in Recently Deleted, read only");
        [tv tryToPerform:@selector(recoverNote:) with:nil];
        [notes sync];
        SNWait(30, ^BOOL { return !notes.syncing; });
        [other syncAndWait:NULL];
        SNSay([other notesInFolder:nil matching:@"Groceries"].count == 1, @"recovered here, back there");
        for (NSString *suffix in @[ @"", @"-wal", @"-shm" ])
            [[NSFileManager defaultManager] removeItemAtPath:[path stringByAppendingString:suffix] error:NULL];
        SNFinish();
    };
}
