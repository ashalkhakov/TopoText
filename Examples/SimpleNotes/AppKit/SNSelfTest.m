#import "SNSelfTest.h"
#import "SNWindowController.h"
#import "SNAppController.h"
#import "SNModel.h"
#import "SNRichText.h"
#import "SNTableGrid.h"
#import "SNSmartFolderPanel.h"
#import "SNSyncPanel.h"
#import "SNPeersWindow.h"
#import "SNTransferPanel.h"

NSURL *SNSelfTestRoot;

/* What the Sync window chose. */
/* A sign-in's secrets kept in memory: the self-test leaves the keychain
   alone (a rebuilt app is another app to it, and is asked about). */
@interface SNSelfTestSecrets : NSObject <ODataSecretStoring>
@end

/* Lets go of a transfer panel when it says it closed, as the window does. */
@interface SNSelfTestPanelHolder : NSObject <SNTransferPanelDelegate>
@property (nonatomic, strong) SNTransferPanel *panel;
@end

@implementation SNSelfTestPanelHolder
- (void)transferPanelDidClose:(SNTransferPanel *)panel {
    _panel = nil;
}
@end

@implementation SNSelfTestSecrets {
    NSMutableDictionary *_all;
}
- (NSDictionary *)secretsForAccount:(NSString *)account { return _all[account]; }
- (BOOL)setSecrets:(NSDictionary *)secrets forAccount:(NSString *)account {
    if (!_all) _all = [NSMutableDictionary dictionary];
    _all[account] = secrets;
    return YES;
}
@end

@interface SNSyncChoice : NSObject <SNSyncPanelDelegate>
@property (nonatomic, strong) NSURL *root;
@property (nonatomic) BOOL chosen;
@end

@implementation SNSyncChoice
- (void)syncPanel:(SNSyncPanel *)panel didChooseServer:(NSURL *)root signIn:(ODataSignIn *)signIn {
    _root = root;
    _chosen = YES;
}
@end

static int SNFailed;

/* A window as it is now, drawn into a picture (the README's screenshots). */
static BOOL SNSnapshotWindow(NSWindow *w, NSString *path) {
    NSView *v = w.contentView;
    /* Drawn whole first: gnustep-gui's cacheDisplayInRect: copies what the
       window last displayed. */
    [w display];
    NSBitmapImageRep *rep = [v bitmapImageRepForCachingDisplayInRect:v.bounds];
    [v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];
#ifdef GNUSTEP
    NSData *png = [rep representationUsingType:NSPNGFileType properties:@{}];
#else
    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
#endif
    return [png writeToFile:path atomically:YES];
}

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
        /* Find and Replace: Edit > Find > Find… for the note, and a Replace
           All as the find bar (the Find panel on GNUstep) does one: asked,
           replaced, told. */
        NSMenuItem *findItem = [[NSMenuItem alloc] initWithTitle:@"Find…" action:@selector(performFindPanelAction:) keyEquivalent:@"f"];
        findItem.tag = NSFindPanelActionShowFindPanel;
        SNSay([window validateMenuItem:findItem] && [tv respondsToSelector:@selector(findAndReplace:)], @"Find… for the note");
        NSRange eggs = [tv.string rangeOfString:@"eggs"];
        if ([tv shouldChangeTextInRanges:@[ [NSValue valueWithRange:eggs] ] replacementStrings:@[ @"free-range eggs" ]]) {
            [tv.textStorage replaceCharactersInRange:eggs withString:@"free-range eggs"];
            [tv didChangeText];
        }
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
        SNSay([there.body containsString:@"milk, free-range eggs, bread"], @"and what was replaced");
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
        sync.secrets = [[SNSelfTestSecrets alloc] init];
        SNSyncChoice *choice = [[SNSyncChoice alloc] init];
        sync.delegate = choice;
        SNSay(sync.window && sync.serverField && sync.codeLabel && sync.localButton.state == NSControlStateValueOn && !sync.warningLabel.isHidden,
              @"the Sync window loads, this computer only warned of");
        [sync syncWithServer:nil];
        sync.serverField.stringValue = notes.serviceRoot.absoluteString;
        [sync ok:nil];
        SNWait(10, ^BOOL { return choice.chosen; });
        SNSay(choice.chosen && [choice.root isEqual:notes.serviceRoot] && sync.warningLabel.isHidden && sync.signIn.kind == ODataSignInNone,
              [NSString stringWithFormat:@"a server with no sign-in chosen (%@)", choice.root]);
        /* Devices Nearby: its window, and the peer token the server (no
           sign-in: none to give) does not give. */
        NSURL *peersDir = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
                                                     [NSString stringWithFormat:@"sn-selftest-peers-%@", [NSProcessInfo processInfo].globallyUniqueString]]];
        NSError *peersError = nil;
        SNPeers *peers = [[SNPeers alloc] initWithNotes:notes directory:peersDir error:&peersError];
        SNPeersWindow *nearby = peers ? [[SNPeersWindow alloc] initWithPeers:peers] : nil;
        SNSay(nearby.window && nearby.devicesTable.dataSource == nearby && nearby.serveButton.state == NSControlStateValueOff && nearby.tokenButton.isEnabled,
              [NSString stringWithFormat:@"the Devices Nearby window loads (%@)", peersError.localizedDescription ?: @"an identity made"]);
        [nearby close];
        [peers stop];
        [peers.trust.identity removeWithError:NULL];
        [[NSFileManager defaultManager] removeItemAtURL:peersDir error:NULL];
        /* Move To, filled from the folders: filling it again when nothing
           changed adds nothing (GNUstep's -update asked a delegate again
           for each item added, without end, and froze the app); and typing
           fills it not at all (GNUstep updated a menu with a delegate at
           each key typed, which read every folder each time). */
        NSMenu *moveTo = nil;
        for (NSMenuItem *top in [NSApp mainMenu].itemArray)
            if ((moveTo = [top.submenu itemWithTag:7001].submenu)) break;
        __block NSUInteger added = 0;
        id observer = [[NSNotificationCenter defaultCenter] addObserverForName:NSMenuDidAddItemNotification object:moveTo queue:nil
                                                                    usingBlock:^(NSNotification *n) { added++; }];
        [window fillMoveToMenus];
        NSUInteger first = added, filled = moveTo.numberOfItems;
        [moveTo update];
        [window fillMoveToMenus];
        NSUInteger again = added;
        /* The keys go to the menus first (their key equivalents), then to
           the window, which takes them as no text. */
        [window.window makeFirstResponder:window.window];
        for (NSString *key in @[ @"a", @"b", @"c" ]) {
            NSEvent *down = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0
                                         windowNumber:window.window.windowNumber context:nil characters:key charactersIgnoringModifiers:key
                                            isARepeat:NO keyCode:0];
            [NSApp sendEvent:down];
        }
        [[NSNotificationCenter defaultCenter] removeObserver:observer];
        SNSay(moveTo.delegate == nil && filled > 1 && first <= filled && again == first && added == first,
              [NSString stringWithFormat:@"Move To is filled once, not as keys are typed (%lu items; %lu added, then %lu, then %lu)",
                                         (unsigned long)filled, (unsigned long)first, (unsigned long)(again - first), (unsigned long)(added - again)]);
        /* Another note chosen, in another folder: its mark moved, nothing
           filled again (Eau's menu bar looks itself up at every item added
           or removed: a second on each note chosen, with many folders). */
        NSUInteger beforeChoosing = added;
        observer = [[NSNotificationCenter defaultCenter] addObserverForName:NSMenuDidAddItemNotification object:moveTo queue:nil
                                                                 usingBlock:^(NSNotification *n) { added++; }];
        BOOL chose = [window selectNoteTitled:@"Standup notes"];
        [window fillMoveToMenus];
        [[NSNotificationCenter defaultCenter] removeObserver:observer];
        NSMutableArray *checked = [NSMutableArray array];
        for (NSMenuItem *item in moveTo.itemArray)
            if (item.state == NSControlStateValueOn) [checked addObject:[item.title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
        SNSay(chose && added == beforeChoosing && [checked isEqual:@[ @"Work" ]],
              [NSString stringWithFormat:@"another note chosen: Move To's mark moved, nothing added (%lu added; %@)",
                                         (unsigned long)(added - beforeChoosing), [checked componentsJoinedByString:@", "]]);
        /* Move Folder To (where dragging in the sidebar does not work):
           Projects into Home, and back into Work. */
        NSMenu *moveFolderTo = nil;
        for (NSMenuItem *top in [NSApp mainMenu].itemArray)
            if ((moveFolderTo = [top.submenu itemWithTag:7002].submenu)) break;
        BOOL (^moveFolder)(NSString *, NSString *) = ^BOOL(NSString *folder, NSString *into) {
            if (![window showFolderNamed:folder]) return NO;
            for (NSMenuItem *item in moveFolderTo.itemArray)
                if ([[item.title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] isEqual:into]) {
                    [window moveFolderToFolder:item];
                    return YES;
                }
            return NO;
        };
        SNFolder *moved = nil;
        for (SNFolder *f in notes.folders)
            if ([f.name isEqual:@"Projects"]) moved = f;
        BOOL intoHome = moveFolder(@"Projects", @"Home") && [[notes parentOfFolder:moved].name isEqual:@"Home"];
        BOOL backInWork = moveFolder(@"Projects", @"Work") && [[notes parentOfFolder:moved].name isEqual:@"Work"];
        SNSay(moveFolderTo.delegate == nil && intoHome && backInWork, @"Move Folder To moves a folder into another, and back");
        /* Export, in its panel (TransferPanel.xib): done, and said so. */
        NSURL *exported = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
                                                     [NSString stringWithFormat:@"sn-selftest-%@.zip", [NSProcessInfo processInfo].globallyUniqueString]]];
        SNTransfer *export = [SNTransfer exportOfNotes:notes toURL:exported];
        SNTransferPanel *transferPanel = [[SNTransferPanel alloc] initWithTransfer:export];
        BOOL loaded = transferPanel.window && transferPanel.progressBar && transferPanel.button;
        BOOL ran = [export runAndWait:NULL];
        SNSay(loaded && ran && export.done == export.total && export.total > 0 && [transferPanel.button.title isEqual:@"Close"] &&
              [transferPanel.detailField.stringValue containsString:@"exported"],
              [NSString stringWithFormat:@"an export in its panel (%@)", export.summary]);
        /* Closed by its button, and let go of (GNUstep freed the button in
           its own action, observers and all, and the app stopped). */
        SNSelfTestPanelHolder *holder = [[SNSelfTestPanelHolder alloc] init];
        holder.panel = transferPanel;
        transferPanel.delegate = holder;
        __weak SNTransferPanel *closed = transferPanel;
        transferPanel = nil;
        [holder.panel.button performClick:nil];
        SNWait(2, ^BOOL { return holder.panel == nil && closed == nil; });
        SNSay(holder.panel == nil, [NSString stringWithFormat:@"Close lets go of the panel (%@)", closed ? @"still held elsewhere" : @"freed"]);
        [[NSFileManager defaultManager] removeItemAtURL:exported error:NULL];
        [window showFolderNamed:@"Work Things"];
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

        /* A quote, a highlight and a colour, from the Format menu. */
        tv.selectedRange = NSMakeRange(tv.string.length, 0);
        [tv insertNewline:nil];
        [tv insertText:@"Bring a warm jacket"];
        NSUInteger said = tv.string.length - 19;
        SNSay([tv tryToPerform:@selector(toggleBlockQuote:) with:nil] &&
              [[tv.textStorage attribute:SNQuoteAttributeName atIndex:said effectiveRange:NULL] boolValue], @"Block Quote from the menu");
        NSMenuItem *mint = [[NSMenuItem alloc] initWithTitle:@"Mint" action:@selector(applyHighlightColor:) keyEquivalent:@""];
        mint.tag = 4;
        tv.selectedRange = NSMakeRange(said + 8, 4);
        [tv tryToPerform:@selector(applyHighlightColor:) with:mint];
        NSMenuItem *purple = [[NSMenuItem alloc] initWithTitle:@"Purple" action:@selector(applyTextColor:) keyEquivalent:@""];
        purple.tag = 1;
        tv.selectedRange = NSMakeRange(said + 13, 6);
        [tv tryToPerform:@selector(applyTextColor:) with:purple];
        SNSay([[tv.textStorage attribute:SNHighlightAttributeName atIndex:said + 8 effectiveRange:NULL] isEqual:@"mint"] &&
              [[tv.textStorage attribute:SNColorAttributeName atIndex:said + 13 effectiveRange:NULL] isEqual:@"purple"] &&
              [window validateMenuItem:purple] && purple.state == NSControlStateValueOn,
              @"Highlight and Text Color from the menu");

        /* Export as PDF: the note on paper, pages of it. Beside the snapshot
           when one is asked for, else a file of its own, gone after. */
        const char *snapshot = getenv("SN_SELF_TEST_SNAPSHOT");
        NSString *pdfPath = snapshot ? [@(snapshot).stringByDeletingPathExtension stringByAppendingPathExtension:@"pdf"]
                                     : [NSTemporaryDirectory() stringByAppendingPathComponent:
                                           [NSString stringWithFormat:@"sn-selftest-%@.pdf", [NSProcessInfo processInfo].globallyUniqueString]];
        BOOL printed = [window exportNoteAsPDFTo:pdfPath];
        NSData *pdfData = [NSData dataWithContentsOfFile:pdfPath];
        SNSay(printed && pdfData.length > 1000 && [[[NSString alloc] initWithData:[pdfData subdataWithRange:NSMakeRange(0, 5)]
                                                                           encoding:NSASCIIStringEncoding] isEqual:@"%PDF-"],
              [NSString stringWithFormat:@"Export as PDF (%lu bytes)", (unsigned long)pdfData.length]);
        if (!snapshot) [[NSFileManager defaultManager] removeItemAtPath:pdfPath error:NULL];

        /* SN_SELF_TEST_SNAPSHOT=<path.png>: the window as it is now, drawn
           into a picture (the README's screenshots). */
        if (snapshot) {
            tv.selectedRange = NSMakeRange(tv.string.length, 0);
            SNSay(SNSnapshotWindow(window.window, @(snapshot)), [NSString stringWithFormat:@"a snapshot in %s", snapshot]);
        }

        /* The panes' widths, kept as they are left (the list's as a list,
           while the gallery widens it), and put back at a launch. The
           widths the user had are put back after: a Debug build shares
           their defaults. */
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        id usersWidths = [defaults objectForKey:@"SNPaneWidths"];
        NSSplitView *split = window.panes;
        CGFloat divider = split.dividerThickness;
        [split setPosition:150 ofDividerAtIndex:0];
        [split setPosition:150 + divider + 230 ofDividerAtIndex:1];
        NSArray *kept = [defaults arrayForKey:@"SNPaneWidths"], *keptFirst = kept;
        BOOL keptBoth = kept.count == 2 && fabs([kept[0] doubleValue] - 150) <= 2 && fabs([kept[1] doubleValue] - 230) <= 2;
        [tv tryToPerform:@selector(showAsGallery:) with:nil];
        [window.window setContentSize:NSMakeSize(NSWidth([window.window.contentView frame]) + 20, NSHeight([window.window.contentView frame]))];
        kept = [defaults arrayForKey:@"SNPaneWidths"];
        BOOL keptList = kept.count == 2 && fabs([kept[1] doubleValue] - 230) <= 2;
        [tv tryToPerform:@selector(showAsList:) with:nil];
        [split setPosition:200 ofDividerAtIndex:0];
        [split setPosition:500 ofDividerAtIndex:1];
        [defaults setObject:@[ @150, @230 ] forKey:@"SNPaneWidths"];
        [window placePanes];
        CGFloat folders = NSWidth([split.subviews[0] frame]), list = NSWidth([split.subviews[1] frame]);
        SNSay(keptBoth && keptList && fabs(folders - 150) <= 2 && fabs(list - 230) <= 2,
              [NSString stringWithFormat:@"the panes' widths kept, the list's as a list, and put back (%@; %@; %.0f, %.0f)",
                                         [keptFirst componentsJoinedByString:@", "], [kept componentsJoinedByString:@", "], folders, list]);
        if (usersWidths) [defaults setObject:usersWidths forKey:@"SNPaneWidths"];
        else [defaults removeObjectForKey:@"SNPaneWidths"];

        /* View > as Gallery: the notes as cards, Weekend's with its photo;
           a card chosen opens its note. */
        SNNote *weekendNote = [notes notesInFolder:nil matching:@"Weekend"].firstObject;
        SNNote *groceriesNote = [notes notesInFolder:nil matching:@"Groceries"].firstObject;
        SNSay([tv tryToPerform:@selector(showAsGallery:) with:nil] && !window.gallery.view.isHidden && window.noteTable.enclosingScrollView.isHidden &&
              [window.gallery.shownNotes containsObject:weekendNote] && [window.gallery.shownNotes containsObject:groceriesNote],
              [NSString stringWithFormat:@"View as Gallery: the notes as cards (%lu)", (unsigned long)window.gallery.shownNotes.count]);
        SNWait(5, ^BOOL { return [window.gallery pictureOfNote:weekendNote] != nil; });
        SNSay([window.gallery pictureOfNote:weekendNote] != nil, @"and Weekend's card its photo");
        if (snapshot) SNSnapshotWindow(window.window, [@(snapshot).stringByDeletingPathExtension stringByAppendingString:@"-gallery.png"]);
        [window gallery:window.gallery didChooseNote:groceriesNote];
        SNSay([tv.string hasPrefix:@"Groceries"], @"a card chosen opens its note");
        SNSay([tv tryToPerform:@selector(showAsList:) with:nil] && window.gallery.view.isHidden && !window.noteTable.enclosingScrollView.isHidden,
              @"View as List: the list again");
        /* View > Show Attachments: the photo, the file; one chosen shows its
           note, where it is. */
        SNSay([tv tryToPerform:@selector(showAttachments:) with:nil] && window.attachmentsWindow.window.isVisible &&
              window.attachmentsWindow.shownItems.count == 1 && [window.attachmentsWindow.shownItems.firstObject.noteID isEqual:weekendNote.objectID],
              [NSString stringWithFormat:@"Show Attachments: the photo (%lu)", (unsigned long)window.attachmentsWindow.shownItems.count]);
        if (snapshot) SNWait(1, ^BOOL { return NO; });
        if (snapshot) SNSnapshotWindow(window.attachmentsWindow.window, [@(snapshot).stringByDeletingPathExtension stringByAppendingString:@"-attachments.png"]);
        window.attachmentsWindow.showsFiles = YES;
        SNAttachmentItem *leaseItem = window.attachmentsWindow.shownItems.firstObject;
        SNSay(window.attachmentsWindow.shownItems.count == 1 && [leaseItem.name isEqual:@"Lease.pdf"], @"and, under Files, the file");
        [window attachmentsWindow:window.attachmentsWindow didChooseAttachment:leaseItem];
        SNSay([tv.string hasPrefix:@"Weekend"] && tv.selectedRange.location < tv.string.length &&
              [[tv.textStorage attribute:SNAttachmentAttributeName atIndex:tv.selectedRange.location effectiveRange:NULL] isEqual:leaseItem.attachmentID],
              @"one chosen shows its note, where it is");
        [window.attachmentsWindow close];

        /* Services > Add to SimpleNotes: another app's selection, a note at
           the top, shown. */
        NSPasteboard *shared = [NSPasteboard pasteboardWithUniqueName];
        [shared declareTypes:@[ NSPasteboardTypeString ] owner:nil];
        [shared setString:@"Quote of the day\nNotes merge what was written apart." forType:NSPasteboardTypeString];
        NSString *serviceError = nil;
        [(SNAppController *)NSApp.delegate addToSimpleNotes:shared userData:nil error:&serviceError];
        SNSay(!serviceError && [tv.string hasPrefix:@"Quote of the day\nNotes merge"] && [[window selectedNote].title isEqual:@"Quote of the day"],
              [NSString stringWithFormat:@"Services > Add to SimpleNotes: a note, shown (%@)", serviceError ?: [window selectedNote].title]);
        [shared releaseGlobally];
        [window selectNoteTitled:@"Weekend"];

        /* Collapsed sections: a heading's chevron clicked hides what is
           under it, the text as it was; Expand All Sections shows it. */
        tv.selectedRange = NSMakeRange(tv.string.length, 0);
        [tv insertNewline:nil];
        [tv insertText:@"Packing"];
        NSUInteger packing = tv.string.length - 7;
        [tv tryToPerform:@selector(styleHeading:) with:nil];
        [tv insertNewline:nil];
        [tv insertText:@"socks"];
        [tv insertNewline:nil];
        [tv insertText:@"boots"];
        NSUInteger socks = packing + 8;
        NSString *before = tv.string;
        SNListLayoutManager *slm = (SNListLayoutManager *)tv.layoutManager;
        NSRect headingLine = [slm lineFragmentRectForGlyphAtIndex:[slm glyphRangeForCharacterRange:NSMakeRange(packing, 1) actualCharacterRange:NULL].location
                                                   effectiveRange:NULL];
        NSUInteger chevron = [slm sectionToggleAtPoint:NSMakePoint(-7, NSMidY(headingLine))];
        SNSay(chevron == packing, [NSString stringWithFormat:@"a chevron beside the heading (%lu)", (unsigned long)chevron]);
        /* Clicked as the user does: a mouse down where it is drawn, to the
           view the window finds there (macOS's text view leaves its inset
           to the clip view). Not through -sendEvent:, which keeps a first
           click in a window not key (the app runs in the background). */
        NSPoint at = [tv convertPoint:NSMakePoint(tv.textContainerOrigin.x - 7, tv.textContainerOrigin.y + NSMidY(headingLine)) toView:nil];
        NSEvent *down = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:at modifierFlags:0 timestamp:0
                                       windowNumber:tv.window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
        /* Its mouse up queued: a click the text view takes as its own
           (selecting) waits for one. */
        [NSApp postEvent:[NSEvent mouseEventWithType:NSEventTypeLeftMouseUp location:at modifierFlags:0 timestamp:0
                                        windowNumber:tv.window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:0]
                 atStart:NO];
        [[((NSView *)tv.window.contentView).superview hitTest:at] mouseDown:down];
        SNSay([tv.textStorage attribute:SNHiddenAttributeName atIndex:socks effectiveRange:NULL] != nil &&
              [tv.textStorage attribute:SNHiddenAttributeName atIndex:packing effectiveRange:NULL] == nil && [tv.string isEqual:before],
              @"clicked, what is under it is hidden, the text as it was");
        if (snapshot) SNSnapshotWindow(window.window, [@(snapshot).stringByDeletingPathExtension stringByAppendingString:@"-collapsed.png"]);
        SNSay([tv tryToPerform:@selector(expandAllSections:) with:nil] &&
              [tv.textStorage attribute:SNHiddenAttributeName atIndex:socks effectiveRange:NULL] == nil, @"Expand All Sections shows it again");

        /* File > Version History: the versions the server kept of Groceries
           (its text as seeded, kept as the first typing came); the oldest
           restored, the note as it was then. */
        [window selectNoteTitled:@"Groceries"];
        [notes sync];
        SNWait(30, ^BOOL { return !notes.syncing; });
        SNSay([tv tryToPerform:@selector(showVersionHistory:) with:nil] && window.versionsPanel.window.isVisible &&
              window.versionsPanel.versions.count >= 1,
              [NSString stringWithFormat:@"Version History: the server's versions (%lu)", (unsigned long)window.versionsPanel.versions.count]);
        SNVersionsPanel *history = window.versionsPanel;
        NSManagedObject *oldest = history.versions.lastObject;
        NSString *then = oldest ? [notes textOfVersion:oldest].string : nil;
        [history.versionTable selectRowIndexes:[NSIndexSet indexSetWithIndex:history.versions.count - 1] byExtendingSelection:NO];
        if (snapshot) SNSnapshotWindow(history.window, [@(snapshot).stringByDeletingPathExtension stringByAppendingString:@"-versions.png"]);
        SNSay([then hasPrefix:@"Groceries"] && history.restoreButton.isEnabled && history.previewView.string.length > 0,
              [NSString stringWithFormat:@"the oldest beside the note (%@)", [then stringByReplacingOccurrencesOfString:@"\n" withString:@" | "]]);
        [history restore:nil];
        SNSay(then && [tv.string isEqual:then], [NSString stringWithFormat:@"Restore This Version: the note as it was (%@)",
                                                  [tv.string stringByReplacingOccurrencesOfString:@"\n" withString:@" | "]]);
        [history close:nil];

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
