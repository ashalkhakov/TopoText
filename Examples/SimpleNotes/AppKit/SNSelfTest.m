#import "SNSelfTest.h"
#import "SNWindowController.h"
#import "SNModel.h"

NSURL *SNSelfTestRoot;

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

@interface SNSelfTest : NSObject
@property (nonatomic, copy) void (^run)(void);
@end
@implementation SNSelfTest
- (void)fire:(NSTimer *)timer { self.run(); }
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
