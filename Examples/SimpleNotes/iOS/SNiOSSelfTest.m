#import "SNiOSSelfTest.h"
#import "SNiOSControllers.h"

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
        fprintf(stderr, "self-test: %s\n", SNFailed ? "FAILED" : "passed");
        exit(SNFailed);
    };
}
