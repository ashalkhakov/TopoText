#import "SNiOSSelfTest.h"
#import "SNiOSControllers.h"
#import "SNRichText.h"
#import "SNTableGrid.h"
#import "SNModel.h"

NSURL *SNSelfTestRoot;

/* The grid's links, UIKit's (iOS/SNTableGrid+System.m). */
@interface SNTableGrid (SNSelfTestLinks)
- (nullable NSURL *)linkInCell:(UITextView *)cell atPoint:(CGPoint)point;
- (void)followLink:(NSURL *)url;
@end

static int SNFailed;

static void SNSay(BOOL ok, NSString *what) {
    fprintf(stderr, "%s %s\n", ok ? "PASS" : "FAIL", what.UTF8String);
    if (!ok) SNFailed++;
}

static BOOL SNWait(NSTimeInterval seconds, BOOL (^done)(void)) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!done() && [until timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    return done();
}

/* The window drawn into a picture (the README's screenshots). */
static void SNSnapshot(UIView *v, NSString *path) {
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithBounds:v.bounds];
    UIImage *image = [r imageWithActions:^(UIGraphicsImageRendererContext *c) {
        [v drawViewHierarchyInRect:v.bounds afterScreenUpdates:YES];
    }];
    SNSay([UIImagePNGRepresentation(image) writeToFile:path atomically:YES], [NSString stringWithFormat:@"a snapshot in %@", path]);
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
        fprintf(stderr, "FAIL %s: %s\nFAIL   %s\nself-test: FAILED\n", e.name.UTF8String, e.reason.UTF8String,
                [e.callStackSymbols componentsJoinedByString:@"\nFAIL   "].UTF8String);
        exit(1);
    }
}
@end

void SNStartSelfTest(SNNotes *notes, UINavigationController *navigation) {
    SNSelfTest *test = [SNSelfTest new];
    [NSTimer scheduledTimerWithTimeInterval:1 target:test selector:@selector(fire:) userInfo:nil repeats:NO];
    test.run = ^{
        SNSay(SNWait(30, ^BOOL { return notes.lastSync != nil && !notes.syncing; }), @"the app syncs with the server");
        SNNotesViewController *list = [[SNNotesViewController alloc] initWithNotes:notes folder:nil];
        [navigation pushViewController:list animated:NO];
        SNWait(0.5, ^BOOL { return NO; });
        NSArray *listed = [[list shownRows] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"NOT SELF BEGINSWITH '## '"]];
        SNSay(listed.count == 4, [NSString stringWithFormat:@"the four notes are in the list (%@)", [[list shownRows] componentsJoinedByString:@", "]]);
        SNNote *groceries = [notes notesInFolder:nil matching:@"Groceries"].firstObject;
        SNEditorViewController *editor = [[SNEditorViewController alloc] initWithNotes:notes note:groceries];
        [navigation pushViewController:editor animated:NO];
        SNWait(0.5, ^BOOL { return NO; });
        UITextView *tv = editor.textView;
        SNSay([tv.text hasPrefix:@"Groceries"], @"its text is in the editor's text view");
        tv.selectedRange = NSMakeRange(tv.text.length, 0);
        [tv insertText:@" and tea"];
        tv.selectedRange = NSMakeRange(0, 9);
        [editor bold:nil];
        SNSay([[tv.textStorage attribute:@"SNBold" atIndex:0 effectiveRange:NULL] boolValue], @"Bold from the format bar");
        [navigation popViewControllerAnimated:NO];
        SNWait(0.5, ^BOOL { return NO; });
        [notes sync];
        SNWait(30, ^BOOL { return !notes.syncing; });
        SNSay(notes.pendingCount == 0, @"what was typed went to the server");

        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                             [NSString stringWithFormat:@"sn-selftest-%@.sqlite", [NSProcessInfo processInfo].globallyUniqueString]];
        SNNotes *other = [[SNNotes alloc] initWithStoreURL:[NSURL fileURLWithPath:path] error:NULL];
        other.serviceRoot = notes.serviceRoot;
        NSError *error = nil;
        SNSay([other syncAndWait:&error], [NSString stringWithFormat:@"a second device syncs%@", error ? [@": " stringByAppendingString:error.localizedDescription] : @""]);
        SNNote *there = [other notesInFolder:nil matching:@"Groceries"].firstObject;
        SNSay([there.body hasSuffix:@"coffee beans and tea"], [NSString stringWithFormat:@"the second device has the typing (%@)", there.body]);
        SNSay([[there.text attributesAtIndex:0 effectiveRange:NULL][@"bold"] boolValue], @"and the bold");

        /* A checklist: two lines made one from the format bar, the first
           ticked where its checkbox is, a third item begun by Return. */
        SNNote *weekendHere = [notes notesInFolder:nil matching:@"Weekend"].firstObject;
        SNEditorViewController *we = [[SNEditorViewController alloc] initWithNotes:notes note:weekendHere];
        [navigation pushViewController:we animated:NO];
        SNWait(0.5, ^BOOL { return NO; });
        UITextView *wtv = we.textView;
        NSUInteger first = [wtv.text rangeOfString:@"\n"].location + 1;
        [wtv becomeFirstResponder];
        wtv.selectedRange = NSMakeRange(first, wtv.text.length - first);
        /* Up the responder chain from the text view, as the format bar's
           menu commands go. */
        SNSay([[UIApplication sharedApplication] sendAction:@selector(checklist:) to:nil from:nil forEvent:nil],
              @"Checklist goes up the responder chain");
        SNListLayoutManager *lm = (SNListLayoutManager *)wtv.layoutManager;
        SNSay([lm isKindOfClass:[SNListLayoutManager class]], @"the text view draws list markers");
        CGRect line = [lm lineFragmentRectForGlyphAtIndex:[lm glyphIndexForCharacterAtIndex:first] effectiveRange:NULL];
        SNSay([lm checkboxAtPoint:CGPointMake(12, CGRectGetMidY(line))] == first, @"a checkbox where the first item's is");
        wtv.selectedRange = NSMakeRange(first, 0);
        [we toggleChecked:nil];
        wtv.selectedRange = NSMakeRange(wtv.text.length, 0);
        [wtv insertText:@"\n"];
        [wtv insertText:@"water the plants"];
        /* The ticked item to the bottom; the list ended (Return on an empty
           item), and a photo after it. */
        wtv.selectedRange = NSMakeRange(first, 0);
        [we moveCheckedToBottom:nil];
        wtv.selectedRange = NSMakeRange(wtv.text.length, 0);
        /* As the keyboard types: the delegate asked first (insertText:
           alone does not ask it). */
        for (int i = 0; i < 2; i++)
            if ([we textView:wtv shouldChangeTextInRange:wtv.selectedRange replacementText:@"\n"]) [wtv insertText:@"\n"];
        UIGraphicsImageRenderer *photo = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(64, 48)];
        [we insertImageData:UIImagePNGRepresentation([photo imageWithActions:^(UIGraphicsImageRendererContext *c) {
            [[UIColor systemYellowColor] setFill];
            UIRectFill(CGRectMake(0, 0, 64, 48));
        }])];
        /* A table after it, from the bar, typed into where it is: the
           keyboard's Tab to the next cell, and from the last a row more. */
        if ([we textView:wtv shouldChangeTextInRange:wtv.selectedRange replacementText:@"\n"]) [wtv insertText:@"\n"];
        [we addTable:nil];
        NSString *tableID = [wtv.textStorage attribute:SNAttachmentAttributeName atIndex:wtv.text.length - 1 effectiveRange:NULL];
        SNTableGrid *grid = tableID ? [we gridForAttachmentID:tableID] : nil;
        SNSay(grid && grid.table.rowCount == 2 && [grid textViewAtRow:0 column:0].isFirstResponder, @"a table in the note, its first cell typed in");
        NSArray *cells = @[ @[ @"Bike", @"Saturday" ], @[ @"Grandma", @"Sunday" ] ];
        for (NSUInteger k = 0; k < 4; k++) {
            UITextView *cell = [grid textViewAtRow:k / 2 column:k % 2];
            if (!cell.isFirstResponder) break;
            [cell insertText:cells[k / 2][k % 2]];
            if ([cell.delegate textView:cell shouldChangeTextInRange:cell.selectedRange replacementText:@"\t"]) [cell insertText:@"\t"];
        }
        UITextView *added = [grid textViewAtRow:2 column:0];
        SNSay(grid.table.rowCount == 3 && added.isFirstResponder, @"Tab from the last cell: a row more");
        SNSay([added canPerformAction:@selector(deleteRow:) withSender:nil] || [grid canPerformAction:@selector(deleteRow:) withSender:nil],
              @"Delete Row in the cell's menu");
        [[UIApplication sharedApplication] sendAction:@selector(deleteRow:) to:nil from:nil forEvent:nil];
        SNSay([grid.table.strings isEqual:cells], [NSString stringWithFormat:@"the cells typed, the row deleted (%@)", grid.table.strings]);
        /* A cell's characters formatted, as the note's: Bold from the bar
           over the keyboard (up the responder chain, to the editor). */
        UITextView *bike = [grid textViewAtRow:0 column:0];
        [bike becomeFirstResponder];
        bike.selectedRange = NSMakeRange(0, 4);
        [[UIApplication sharedApplication] sendAction:@selector(bold:) to:nil from:nil forEvent:nil];
        SNSay([[[grid.table textAtRow:0 column:0] attributesAtIndex:0 effectiveRange:NULL][SNBoldKey] boolValue],
              @"Bold in a cell: the cell's text bold");
        /* A hardware keyboard's Shift-Tab: the cell before. */
        [[grid textViewAtRow:1 column:1] becomeFirstResponder];
        BOOL hasBack = NO;
        for (UIKeyCommand *k in grid.keyCommands)
            if ([k.input isEqualToString:@"\t"] && k.modifierFlags == UIKeyModifierShift) hasBack = YES;
        [[UIApplication sharedApplication] sendAction:@selector(previousCell:) to:nil from:nil forEvent:nil];
        SNSay(hasBack && [grid textViewAtRow:1 column:0].isFirstResponder, @"Shift-Tab: the cell before");
        /* A link in a cell, tapped: a note's opened, as one in the note. */
        UITextView *grandma = [grid textViewAtRow:1 column:0];
        NSURL *toGroceries = SNLinkToNote(groceries.id);
        [[grid bindingOfCell:grandma] setLink:toGroceries.absoluteString inRange:NSMakeRange(0, 7)];
        UITextPosition *start = grandma.beginningOfDocument;
        CGRect gr = [grandma firstRectForRange:[grandma textRangeFromPosition:start toPosition:[grandma positionFromPosition:start offset:3]]];
        NSURL *tapped = [grid linkInCell:grandma atPoint:CGPointMake(CGRectGetMidX(gr), CGRectGetMidY(gr))];
        SNSay([tapped isEqual:toGroceries] && [grid linkInCell:grandma atPoint:CGPointMake(grandma.bounds.size.width - 4, CGRectGetMidY(gr))] == nil,
              [NSString stringWithFormat:@"a link in a cell, under a tap there and not beside it (%@)", tapped]);
        if (tapped) [grid followLink:tapped];
        SNWait(0.5, ^BOOL { return NO; });
        UIViewController *opened = navigation.topViewController;
        SNSay(opened != we && [opened isKindOfClass:[SNEditorViewController class]] &&
              [((SNEditorViewController *)opened).textView.text hasPrefix:@"Groceries"], @"followed: the note opened");
        if (opened != we) [navigation popViewControllerAnimated:NO];
        SNWait(0.5, ^BOOL { return NO; });
        NSLayoutManager *tlm = wtv.layoutManager;
        CGRect room = [tlm boundingRectForGlyphRange:[tlm glyphRangeForCharacterRange:NSMakeRange(wtv.text.length - 1, 1) actualCharacterRange:NULL]
                                     inTextContainer:wtv.textContainer];
        room = CGRectOffset(room, wtv.textContainerInset.left, wtv.textContainerInset.top);
        SNSay(grid.superview == wtv && fabs(CGRectGetMinX(grid.frame) - CGRectGetMinX(room)) < 2 && CGRectGetMinY(grid.frame) >= CGRectGetMinY(room) - 2 &&
              CGRectGetMaxY(grid.frame) <= CGRectGetMaxY(room) + 2 && grid.frame.size.height > 40,
              [NSString stringWithFormat:@"the grid over its room (%@, %@)", NSStringFromCGRect(grid.frame), NSStringFromCGRect(room)]);
        [grid save];
        /* From a cell back into the note: the note's bar over the keyboard,
           not the cell's (UIKit kept the cell's, unless told). */
        [wtv.window endEditing:YES];
        SNWait(1, ^BOOL { return NO; });
        [wtv becomeFirstResponder];
        wtv.selectedRange = NSMakeRange(0, 0);
        SNWait(3, ^BOOL { return we.formatBar.window != nil; });
        SNSay(we.formatBar.window != nil && [grid textViewAtRow:0 column:0].inputAccessoryView.window == nil,
              @"from a cell into the note: the note's bar over the keyboard");
        const char *snapshot = getenv("SN_SELF_TEST_SNAPSHOT");
        if (snapshot) {
            /* The bar over the keyboard is in the keyboard's window, which
               a snapshot of this one leaves out: held up a while, for the
               simulator's own screenshot (xcrun simctl io screenshot). */
            fprintf(stderr, "self-test: the keyboard is up\n");
            SNWait(5, ^BOOL { return NO; });
            [wtv resignFirstResponder];
            SNWait(1, ^BOOL { return NO; });
            SNSnapshot(navigation.view.window, @(snapshot));
        }
        [navigation popViewControllerAnimated:NO];
        SNWait(0.5, ^BOOL { return NO; });
        [notes sync];
        SNWait(30, ^BOOL { return !notes.syncing; });
        [other syncAndWait:NULL];
        TopoText *wt = [other notesInFolder:nil matching:@"Weekend"].firstObject.text;
        NSMutableArray *seen = [NSMutableArray array];
        for (NSValue *v in wt.paragraphRanges) {
            NSDictionary *p = [wt paragraphAttributesAtIndex:v.rangeValue.location keys:SNParagraphKeys()];
            [seen addObject:[NSString stringWithFormat:@"%@%@", p[SNListKey] ?: @"-", [p[SNCheckedKey] boolValue] ? @"+" : @""]];
        }
        SNSay([seen isEqual:@[ @"-", @"check", @"check", @"check+", @"-", @"-" ]],
              [NSString stringWithFormat:@"the second device has the checklist, the ticked item at the bottom (%@)", [seen componentsJoinedByString:@" "]]);
        NSString *photoID = wt.length > 2 ? [wt attributesAtIndex:wt.length - 3 effectiveRange:NULL][SNAttachmentKey] : nil;
        SNSay([other attachmentWithID:photoID].data.length > 0, [NSString stringWithFormat:@"and the photo (%@)", photoID]);
        NSString *tableThere = wt.length ? [wt attributesAtIndex:wt.length - 1 effectiveRange:NULL][SNAttachmentKey] : nil;
        SNSay([[other tableOfAttachment:[other attachmentWithID:tableThere]].strings isEqual:cells], @"and the table");
        SNSay([[[[other tableOfAttachment:[other attachmentWithID:tableThere]] textAtRow:0 column:0] attributesAtIndex:0 effectiveRange:NULL][SNBoldKey] boolValue],
              @"its cell's bold too");
        /* A file: a card in a note, shown by Quick Look. */
        SNEditorViewController *ge = [[SNEditorViewController alloc] initWithNotes:notes note:groceries];
        [navigation pushViewController:ge animated:NO];
        SNWait(0.5, ^BOOL { return NO; });
        UITextView *gtv = ge.textView;
        [gtv becomeFirstResponder];
        gtv.selectedRange = NSMakeRange(gtv.text.length, 0);
        if ([ge textView:gtv shouldChangeTextInRange:gtv.selectedRange replacementText:@"\n"]) [gtv insertText:@"\n"];
        NSData *pdf = [@"%PDF-1.4 a lease" dataUsingEncoding:NSUTF8StringEncoding];
        SNSay([ge insertFileData:pdf name:@"Lease.pdf"], @"a file attached");
        NSString *fileID = [gtv.textStorage attribute:SNAttachmentAttributeName atIndex:gtv.text.length - 1 effectiveRange:NULL];
        NSTextAttachment *card = [gtv.textStorage attribute:NSAttachmentAttributeName atIndex:gtv.text.length - 1 effectiveRange:NULL];
        SNSay([[notes attachmentWithID:fileID].kind isEqual:SNAttachmentKindFile] && card.bounds.size.height > 40, @"shown as a card");
        [gtv resignFirstResponder];
        SNWait(0.5, ^BOOL { return NO; });
        SNSay([ge previewFileOfAttachment:fileID], @"written out for Quick Look");
        SNWait(3, ^BOOL { return [navigation.presentedViewController isKindOfClass:[QLPreviewController class]]; });
        SNSay([navigation.presentedViewController isKindOfClass:[QLPreviewController class]],
              [NSString stringWithFormat:@"Quick Look up (%@)", navigation.presentedViewController]);
        [navigation dismissViewControllerAnimated:NO completion:nil];
        SNWait(0.5, ^BOOL { return NO; });
        [navigation popViewControllerAnimated:NO];
        SNWait(0.5, ^BOOL { return NO; });
        /* Undo after a sync changed the note: what was typed here undone,
           what came from the other device kept. */
        SNNote *standup = [notes notesInFolder:nil matching:@"Standup"].firstObject;
        SNEditorViewController *se = [[SNEditorViewController alloc] initWithNotes:notes note:standup];
        [navigation pushViewController:se animated:NO];
        SNWait(0.5, ^BOOL { return NO; });
        UITextView *stv = se.textView;
        [stv becomeFirstResponder];
        stv.selectedRange = NSMakeRange(stv.text.length, 0);
        [stv insertText:@" undo me"];
        SNWait(0.3, ^BOOL { return NO; });
        [notes saveAll];
        [notes sync];
        SNWait(30, ^BOOL { return !notes.syncing; });
        [other syncAndWait:NULL];
        SNNoteEditor *elsewhere = [other editorForNote:[other notesInFolder:nil matching:@"Standup"].firstObject];
        /* In its second line: the title stays. */
        [elsewhere.text insertString:@"(Monday) " atIndex:[elsewhere.text.string rangeOfString:@"\n"].location + 1 attributes:nil];
        [elsewhere textDidChange];
        [elsewhere close];
        [other syncAndWait:NULL];
        [notes sync];
        SNWait(30, ^BOOL { return !notes.syncing && [stv.text containsString:@"(Monday) "]; });
        SNSay([stv.text containsString:@"(Monday) "] && [stv.text hasSuffix:@" undo me"], @"the other device's edit merged into the open note");
        [[UIApplication sharedApplication] sendAction:@selector(undo:) to:nil from:nil forEvent:nil];
        SNSay([stv.text containsString:@"\n(Monday) sync engine"] && ![stv.text containsString:@"undo me"],
              [NSString stringWithFormat:@"Undo after the merge: the typing undone, the other's edit kept (%@)",
                                         [stv.text stringByReplacingOccurrencesOfString:@"\n" withString:@" | "]]);
        [[UIApplication sharedApplication] sendAction:@selector(redo:) to:nil from:nil forEvent:nil];
        SNSay([stv.text hasSuffix:@" undo me"] && [stv.text containsString:@"(Monday) "], @"and Redo");
        [stv resignFirstResponder];
        [navigation popViewControllerAnimated:NO];
        SNWait(0.5, ^BOOL { return NO; });

        /* Folders in folders and tags, in the folder list. */
        [navigation popToRootViewControllerAnimated:NO];
        SNWait(0.5, ^BOOL { return NO; });
        UITableViewController *root = (UITableViewController *)navigation.viewControllers.firstObject;
        [root viewWillAppear:NO];
        UITableView *ft = root.tableView;
        NSMutableArray *folders = [NSMutableArray array];
        for (NSInteger i = 0; i < [ft numberOfRowsInSection:1]; i++) {
            UITableViewCell *c = [root tableView:ft cellForRowAtIndexPath:[NSIndexPath indexPathForRow:i inSection:1]];
            [folders addObject:[NSString stringWithFormat:@"%ld %@", (long)c.indentationLevel,
                                                          ((UIListContentConfiguration *)c.contentConfiguration).text]];
        }
        SNSay([folders containsObject:@"0 Work"] && [folders containsObject:@"1 Projects"],
              [NSString stringWithFormat:@"Projects under Work (%@)", [folders componentsJoinedByString:@", "]]);
        SNSay([ft numberOfRowsInSection:3] == 3, @"the tags listed");
        /* A smart folder from its form: every note tagged #work. */
        SNSmartFilter *workTagged = [[SNSmartFilter alloc] init];
        workTagged.tags = @[ @"work" ];
        SNSmartFolderViewController *form = [(SNFoldersViewController *)root smartFolderEditorFor:nil];
        form.name = @"Work Things";
        form.filter = workTagged;
        [form loadViewIfNeeded];
        [form done:nil];
        [root viewWillAppear:NO];
        UIListContentConfiguration *smartRow = nil;
        for (NSInteger i = 0; i < [ft numberOfRowsInSection:1]; i++) {
            UIListContentConfiguration *c = (UIListContentConfiguration *)[root tableView:ft cellForRowAtIndexPath:[NSIndexPath indexPathForRow:i inSection:1]].contentConfiguration;
            if ([c.text isEqual:@"Work Things"]) smartRow = c;
        }
        SNSay(smartRow && [smartRow.secondaryText isEqual:@"2"] && [smartRow.image isEqual:[UIImage systemImageNamed:@"gearshape"]],
              [NSString stringWithFormat:@"a smart folder from its form, its notes counted (%@)", smartRow.secondaryText]);
        SNFolder *work = nil;
        for (SNFolder *f in notes.folders) if ([f.name isEqual:@"Work"]) work = f;
        SNNotesViewController *workList = [[SNNotesViewController alloc] initWithNotes:notes folder:work];
        [workList loadViewIfNeeded];
        [workList sortFolderByTitle:nil];
        SNSay([[notes sortOrderOfFolder:work] isEqual:@(SNSortByTitle)], @"Sort Folder By Title");
        const char *folderShot = getenv("SN_SELF_TEST_SNAPSHOT");
        if (folderShot) SNSnapshot(navigation.view.window, [[@(folderShot) stringByDeletingPathExtension] stringByAppendingString:@"-folders.png"]);
        SNNotesViewController *tagged = [[SNNotesViewController alloc] initWithNotes:notes tag:@"work"];
        [navigation pushViewController:tagged animated:NO];
        SNWait(0.5, ^BOOL { return NO; });
        SNSay([[tagged shownRows] containsObject:@"Ideas"] && [[tagged shownRows] containsObject:@"Standup notes"] && ![[tagged shownRows] containsObject:@"Weekend"],
              [NSString stringWithFormat:@"#work lists its notes (%@)", [[tagged shownRows] componentsJoinedByString:@", "]]);
        /* Sort By Title, as its menu's command goes: up the chain from the list. */
        SNSortOrder order = notes.sortOrder;
        id target = [tagged targetForAction:@selector(sortByTitle:) withSender:nil];
        [target sortByTitle:nil];
        SNWait(0.5, ^BOOL { return NO; });
        SNSay(target == tagged && [[tagged shownRows] isEqual:(@[ @"Ideas", @"Standup notes" ])],
              [NSString stringWithFormat:@"sorted by title (%@)", [[tagged shownRows] componentsJoinedByString:@", "]]);
        notes.sortOrder = order;
        [navigation popToRootViewControllerAnimated:NO];
        SNWait(0.5, ^BOOL { return NO; });

        /* Deleted, into Recently Deleted on the other device; recovered
           from the editor's Recover, back there too. */
        [notes deleteNote:groceries];
        [notes sync];
        SNWait(30, ^BOOL { return !notes.syncing; });
        [other syncAndWait:NULL];
        SNSay([other deletedNotesMatching:@"Groceries"].count == 1, @"a note deleted here is in Recently Deleted there");
        SNNotesViewController *trash = [[SNNotesViewController alloc] initRecentlyDeletedWithNotes:notes];
        [navigation pushViewController:trash animated:NO];
        SNWait(0.5, ^BOOL { return NO; });
        SNSay([trash.tableView numberOfRowsInSection:0] == 1, @"Recently Deleted lists it");
        SNEditorViewController *deleted = [[SNEditorViewController alloc] initWithNotes:notes note:groceries];
        [navigation pushViewController:deleted animated:NO];
        SNWait(0.5, ^BOOL { return NO; });
        SNSay(!deleted.textView.editable && deleted.navigationItem.rightBarButtonItem != nil, @"read only, with Recover");
        [deleted recover:nil];
        [navigation popToRootViewControllerAnimated:NO];
        [notes sync];
        SNWait(30, ^BOOL { return !notes.syncing; });
        [other syncAndWait:NULL];
        SNSay([other notesInFolder:nil matching:@"Groceries"].count == 1, @"recovered here, back there");
        fprintf(stderr, "self-test: %s\n", SNFailed ? "FAILED" : "passed");
        exit(SNFailed);
    };
}
