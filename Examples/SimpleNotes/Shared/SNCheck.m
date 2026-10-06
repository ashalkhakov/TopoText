#import "SNCheck.h"
#import "SNModel.h"
#import "SNNotes.h"

static int SNFailures;

static void SNExpect(BOOL ok, NSString *what) {
    fprintf(stderr, "%s %s\n", ok ? "PASS" : "FAIL", what.UTF8String);
    if (!ok) SNFailures++;
}

static void SNType(SNNotes *device, SNNote *note, void (^typing)(TopoText *text)) {
    SNNoteEditor *e = [device editorForNote:note];
    typing(e.text);
    [e textDidChange];
    [e close];
}

static SNNote *SNFind(SNNotes *device, NSString *identifier) {
    for (SNNote *n in [device notesInFolder:nil matching:nil])
        if ([n.id isEqual:identifier]) return n;
    return nil;
}

int SNRunCheck(NSURL *root, NSURL *modelURL) {
    SNFailures = 0;
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSProcessInfo processInfo].globallyUniqueString];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    NSMutableArray<SNNotes *> *devices = [NSMutableArray array];
    for (NSString *name in @[ @"a.sqlite", @"b.sqlite" ]) {
        NSError *error = nil;
        SNNotes *d = [[SNNotes alloc] initWithStoreURL:[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:name]]
                                              modelURL:modelURL error:&error];
        if (!d) {
            fprintf(stderr, "FAIL a device's store: %s\n", error.localizedDescription.UTF8String);
            return 1;
        }
        d.serviceRoot = root;
        [devices addObject:d];
    }
    SNNotes *a = devices[0], *b = devices[1];
    BOOL (^sync)(SNNotes *, NSString *) = ^BOOL(SNNotes *d, NSString *who) {
        NSError *error = nil;
        BOOL ok = [d syncAndWait:&error];
        SNExpect(ok, [NSString stringWithFormat:@"%@ syncs%@", who, ok ? @"" : [@": " stringByAppendingString:error.localizedDescription ?: @"?"]]);
        return ok;
    };

    SNNote *made = [a addNoteInFolder:[a addFolderNamed:@"Check"]];
    NSString *identifier = made.id;
    SNType(a, made, ^(TopoText *t) { [t insertString:@"Checklist\nmilk" atIndex:0 attributes:nil]; });
    if (sync(a, @"a") && sync(b, @"b")) {
        SNNote *there = SNFind(b, identifier);
        SNExpect([there.body isEqual:@"Checklist\nmilk"], @"the note reaches the other device");
        SNExpect([there.folder.name isEqual:@"Check"], @"in its folder");
        if (there) {
            SNType(a, SNFind(a, identifier), ^(TopoText *t) { [t insertString:@"My " atIndex:0 attributes:nil]; });
            SNType(b, there, ^(TopoText *t) {
                [t insertString:@"\neggs" atIndex:t.length attributes:nil];
                [t addAttributes:@{ @"bold": @YES } range:NSMakeRange(0, 9)];
            });
            sync(a, @"a");
            sync(b, @"b");
            sync(a, @"a");
            SNNote *na = SNFind(a, identifier), *nb = SNFind(b, identifier);
            SNExpect([na.body isEqual:@"My Checklist\nmilk\neggs"], [NSString stringWithFormat:@"edits made apart are both kept (%@)", na.body]);
            SNExpect([na.bodyText isEqual:nb.bodyText], @"both devices have the same text");
            SNExpect([na.title isEqual:@"My Checklist"], @"the title is the merged first line");
            SNExpect([[na.text attributesAtIndex:5 effectiveRange:NULL][@"bold"] boolValue], @"the bold made on the other device");
            [a deleteNote:na];
            sync(a, @"a");
            sync(b, @"b");
            SNExpect(!SNFind(b, identifier) && [b deletedNotesMatching:@"Checklist"].count == 1,
                     @"a note deleted there is in Recently Deleted here");
            [b deleteNoteImmediately:[b deletedNotesMatching:@"Checklist"].firstObject];
            [b deleteFolder:b.folders.firstObject];
            sync(b, @"b");
            sync(a, @"a");
            SNExpect(a.countOfDeletedNotes == 0 && a.folders.count == 0, @"deleted for good, gone everywhere");
        }
    }
    [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
    fprintf(stderr, "%s\n", SNFailures ? "check: FAILED" : "check: passed");
    return SNFailures;
}
