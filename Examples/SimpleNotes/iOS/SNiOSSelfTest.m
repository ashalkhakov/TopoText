#import "SNiOSSelfTest.h"
#import "SNiOSControllers.h"
#import "SNRichText.h"

NSURL *SNSelfTestRoot;

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

@interface SNSelfTest : NSObject
@property (nonatomic, copy) void (^run)(void);
@end
@implementation SNSelfTest
- (void)fire:(NSTimer *)timer { self.run(); }
@end

void SNStartSelfTest(SNNotes *notes, UINavigationController *navigation) {
    SNSelfTest *test = [SNSelfTest new];
    [NSTimer scheduledTimerWithTimeInterval:1 target:test selector:@selector(fire:) userInfo:nil repeats:NO];
    test.run = ^{
        SNSay(SNWait(30, ^BOOL { return notes.lastSync != nil && !notes.syncing; }), @"the app syncs with the server");
        SNNotesViewController *list = [[SNNotesViewController alloc] initWithNotes:notes folder:nil];
        [navigation pushViewController:list animated:NO];
        SNWait(0.5, ^BOOL { return NO; });
        SNSay([list.tableView numberOfRowsInSection:0] == 4, @"the four notes are in the list");
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
        const char *snapshot = getenv("SN_SELF_TEST_SNAPSHOT");
        if (snapshot) {
            [wtv resignFirstResponder];
            SNWait(1, ^BOOL { return NO; });
            UIView *v = navigation.view.window;
            UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithBounds:v.bounds];
            UIImage *image = [r imageWithActions:^(UIGraphicsImageRendererContext *c) {
                [v drawViewHierarchyInRect:v.bounds afterScreenUpdates:YES];
            }];
            SNSay([UIImagePNGRepresentation(image) writeToFile:@(snapshot) atomically:YES], @"a snapshot");
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
        SNSay([seen isEqual:@[ @"-", @"check+", @"check", @"check" ]] && [wt.string hasSuffix:@"water the plants"],
              [NSString stringWithFormat:@"the second device has the checklist, the first item ticked (%@)", [seen componentsJoinedByString:@" "]]);

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
