// Notes out as Markdown and back in (SNMarkdown, SNTransfer), and another
// app's export read: a folder of Markdown, Trilium's zip with its
// !!!meta.json, HTML.

#import <XCTest/XCTest.h>
#import "SNRichText.h"
#import "SNModel.h"
#import "SNNotes.h"
#import "SNMarkdown.h"
#import "SNTransfer.h"
#import "SNZip.h"

/* A 1 x 1 PNG. */
static NSData *SNTinyPNG(void) {
    return [[NSData alloc] initWithBase64EncodedString:@"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
                                               options:0];
}

@interface SNTransferTests : XCTestCase
@end

@implementation SNTransferTests {
    NSMutableArray<NSURL *> *_files;
    NSDictionary *_paragraph;   /* the last paragraph appended's */
}

- (void)setUp {
    _files = [NSMutableArray array];
}

- (void)tearDown {
    for (NSURL *url in _files) [[NSFileManager defaultManager] removeItemAtURL:url error:NULL];
}

- (NSURL *)temporary:(NSString *)extension {
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
                                            [NSString stringWithFormat:@"sn-%@%@", [NSProcessInfo processInfo].globallyUniqueString, extension]]];
    [_files addObject:url];
    return url;
}

- (SNNotes *)device {
    NSError *error = nil;
    NSURL *store = [self temporary:@".sqlite"];
    for (NSString *suffix in @[ @"-wal", @"-shm" ]) [_files addObject:[NSURL fileURLWithPath:[store.path stringByAppendingString:suffix]]];
    SNNotes *d = [[SNNotes alloc] initWithStoreURL:store modelURL:SNModelURLInBundle([NSBundle bundleForClass:[self class]]) error:&error];
    XCTAssertNotNil(d, @"%@", error);
    return d;
}

/* A paragraph appended, its attributes on it and on the newline before it
   ends the one before (as SimpleNotes keeps them: SNRichText.h). */
- (void)append:(NSString *)string to:(TopoText *)text attributes:(NSDictionary *)attributes {
    if (text.length) {
        [text insertString:@"\n" atIndex:text.length attributes:_paragraph];
    }
    _paragraph = attributes;
    [text insertString:string atIndex:text.length attributes:attributes];
}

- (NSDictionary *)paragraphAttributesOf:(TopoText *)text at:(NSUInteger)index {
    NSRange p = [text.paragraphRanges[index] rangeValue];
    NSMutableDictionary *a = [[text attributesAtIndex:p.location effectiveRange:NULL] mutableCopy];
    for (NSString *k in @[ SNBoldKey, SNItalicKey, SNStrikeKey, SNUnderlineKey, SNLinkKey, SNAttachmentKey ]) [a removeObjectForKey:k];
    return a;
}

#pragma mark Markdown

- (void)testATextIsWrittenAsMarkdown {
    TopoText *text = [TopoText textWithReplica:1];
    [self append:@"Groceries" to:text attributes:@{ SNStyleKey: SNStyleTitle }];
    [self append:@"Some " to:text attributes:nil];
    [text insertString:@"bold" atIndex:text.length attributes:@{ SNBoldKey: @YES }];
    [text insertString:@" and a " atIndex:text.length attributes:nil];
    [text insertString:@"link" atIndex:text.length attributes:@{ SNLinkKey: @"https://example.com/" }];
    [text insertString:@" * star" atIndex:text.length attributes:nil];
    [self append:@"milk" to:text attributes:@{ SNListKey: SNListCheck, SNCheckedKey: @YES }];
    [self append:@"eggs" to:text attributes:@{ SNListKey: SNListCheck }];
    [self append:@"one" to:text attributes:@{ SNListKey: SNListNumber }];
    [self append:@"two" to:text attributes:@{ SNListKey: SNListNumber }];
    [self append:@"deeper" to:text attributes:@{ SNListKey: SNListBullet, SNIndentKey: @1 }];
    [self append:@"let x = 1" to:text attributes:@{ SNStyleKey: SNStyleMono }];
    [self append:@"# not a heading" to:text attributes:nil];
    NSString *md = SNMarkdownOfText(text, nil);
    XCTAssertEqualObjects(md, @"# Groceries\n\n"
                               "Some **bold** and a [link](https://example.com/) \\* star\n\n"
                               "- [x] milk\n- [ ] eggs\n1. one\n2. two\n    * deeper\n\n"
                               "```\nlet x = 1\n```\n\n"
                               "\\# not a heading\n");
}

- (void)testMarkdownIsReadBackAsItWasWritten {
    TopoText *text = [TopoText textWithReplica:1];
    [self append:@"Plans" to:text attributes:@{ SNStyleKey: SNStyleTitle }];
    [self append:@"Steps" to:text attributes:@{ SNStyleKey: SNStyleHeading }];
    [self append:@"first" to:text attributes:@{ SNListKey: SNListDash }];
    [self append:@"nested" to:text attributes:@{ SNListKey: SNListCheck, SNIndentKey: @1 }];
    [self append:@"Plain " to:text attributes:nil];
    [text insertString:@"italic" atIndex:text.length attributes:@{ SNItalicKey: @YES }];
    [text insertString:@", " atIndex:text.length attributes:nil];
    [text insertString:@"gone" atIndex:text.length attributes:@{ SNStrikeKey: @YES }];
    [text insertString:@", " atIndex:text.length attributes:nil];
    [text insertString:@"under" atIndex:text.length attributes:@{ SNUnderlineKey: @YES }];
    [text insertString:@" 2*3_4" atIndex:text.length attributes:nil];
    TopoText *back = SNTextOfMarkdown(SNMarkdownOfText(text, nil), @"Plans", nil);
    XCTAssertEqualObjects(back.string, text.string);
    for (NSUInteger p = 0; p < text.paragraphRanges.count; p++)
        XCTAssertEqualObjects([self paragraphAttributesOf:back at:p], [self paragraphAttributesOf:text at:p], @"paragraph %lu", (unsigned long)p);
    NSUInteger at = [back.string rangeOfString:@"italic"].location;
    XCTAssertEqualObjects([back attributesAtIndex:at effectiveRange:NULL][SNItalicKey], @YES);
    at = [back.string rangeOfString:@"gone"].location;
    XCTAssertEqualObjects([back attributesAtIndex:at effectiveRange:NULL][SNStrikeKey], @YES);
    at = [back.string rangeOfString:@"under"].location;
    XCTAssertEqualObjects([back attributesAtIndex:at effectiveRange:NULL][SNUnderlineKey], @YES);
    at = [back.string rangeOfString:@"2*3"].location;
    XCTAssertNil([back attributesAtIndex:at effectiveRange:NULL][SNItalicKey]);
}

- (void)testOtherAppsMarkdownIsRead {
    NSString *md = @"Intro line one\ncontinued here.\n\n"
                    "+ plus item\n  1) numbered\n\n"
                    "__bold__ and _it_ and <b>html</b> and <https://example.org>\n\n"
                    "> quoted\n\n"
                    "#### Deep heading\n";
    TopoText *text = SNTextOfMarkdown(md, @"Imported", nil);
    XCTAssertEqualObjects(text.string, @"Imported\nIntro line one continued here.\nplus item\nnumbered\nbold and it and html and https://example.org\nquoted\nDeep heading");
    XCTAssertEqualObjects([self paragraphAttributesOf:text at:0][SNStyleKey], SNStyleTitle);
    XCTAssertEqualObjects([self paragraphAttributesOf:text at:2][SNListKey], SNListBullet);
    XCTAssertEqualObjects([self paragraphAttributesOf:text at:3][SNListKey], SNListNumber);
    XCTAssertEqualObjects([self paragraphAttributesOf:text at:3][SNIndentKey], @1);
    XCTAssertEqualObjects([self paragraphAttributesOf:text at:6][SNStyleKey], SNStyleSubheading);
    NSUInteger at = [text.string rangeOfString:@"bold"].location;
    XCTAssertEqualObjects([text attributesAtIndex:at effectiveRange:NULL][SNBoldKey], @YES);
    at = [text.string rangeOfString:@"html"].location;
    XCTAssertEqualObjects([text attributesAtIndex:at effectiveRange:NULL][SNBoldKey], @YES);
    at = [text.string rangeOfString:@"https://"].location;
    XCTAssertEqualObjects([text attributesAtIndex:at effectiveRange:NULL][SNLinkKey], @"https://example.org");
}

- (void)testHTMLIsReadAsMarkdown {
    NSString *html = @"<html><head><title>x</title></head><body><h1>Trip</h1><p>Pack <strong>light</strong> &amp; early.</p>"
                      "<ul class=\"todo-list\"><li><label><input type=\"checkbox\" checked=\"checked\" disabled=\"disabled\"><span>passport</span></label></li>"
                      "<li><label><input type=\"checkbox\" disabled=\"disabled\"><span>tickets</span></label></li></ul>"
                      "<ol><li>first<ul><li>inner</li></ul></li></ol>"
                      "<pre><code>a &lt; b\nc</code></pre>"
                      "<table><tr><th>A</th><th>B</th></tr><tr><td>1</td><td>2</td></tr></table></body></html>";
    NSString *md = SNMarkdownOfHTML(html);
    XCTAssertEqualObjects(md, @"# Trip\n\nPack <strong>light</strong> &amp; early.\n\n"
                               "- [x] passport\n- [ ] tickets\n\n"
                               "1. first\n    - inner\n\n"
                               "```\na < b\nc\n```\n\n"
                               "| A | B |\n| --- | --- |\n| 1 | 2 |");
    TopoText *text = SNTextOfMarkdown(md, @"Trip", nil);
    XCTAssertTrue([text.string hasPrefix:@"Trip\nPack light & early.\npassport\ntickets\nfirst\ninner\na < b\nc\n"], @"%@", text.string);
}

#pragma mark Zip

- (void)testAZipIsReadAsItWasWritten {
    SNZipWriter *w = [[SNZipWriter alloc] init];
    NSMutableData *big = [NSMutableData data];
    for (int i = 0; i < 1000; i++) [big appendData:[@"compressible " dataUsingEncoding:NSUTF8StringEncoding]];
    [w addData:big atPath:@"Folder/Ünïcode.md" date:nil];
    [w addData:[@"x" dataUsingEncoding:NSUTF8StringEncoding] atPath:@"small.txt" date:nil];
    NSData *zip = w.data;
    XCTAssertLessThan(zip.length, big.length / 4);
    SNZipReader *r = [[SNZipReader alloc] initWithData:zip];
    XCTAssertEqualObjects(r.paths, (@[ @"Folder/Ünïcode.md", @"small.txt" ]));
    XCTAssertEqualObjects([r dataAtPath:@"Folder/Ünïcode.md"], big);
    XCTAssertEqualObjects([r dataAtPath:@"small.txt"], [@"x" dataUsingEncoding:NSUTF8StringEncoding]);
    XCTAssertNotNil([r dateAtPath:@"small.txt"]);
    XCTAssertNil([[SNZipReader alloc] initWithData:[@"not a zip at all, no" dataUsingEncoding:NSUTF8StringEncoding]]);
}

#pragma mark Export and import

- (void)testNotesExportedAreImportedBackWithTheirFoldersAndAttachments {
    SNNotes *a = [self device];
    SNFolder *work = [a addFolderNamed:@"Work"];
    SNFolder *inner = [a addFolderNamed:@"Projects" inFolder:work];
    SNNote *top = [a addNoteInFolder:nil];
    TopoText *t = top.text;
    [t insertString:@"Loose" atIndex:0 attributes:@{ SNStyleKey: SNStyleTitle }];
    top.text = t;
    SNNote *rich = [a addNoteInFolder:inner];
    SNAttachment *image = [a addImageToNote:rich data:SNTinyPNG() type:@"image/png" width:1 height:1];
    SNAttachment *file = [a addFileToNote:rich data:[@"%PDF-1.4" dataUsingEncoding:NSUTF8StringEncoding] name:@"spec (v2).pdf" type:@"application/pdf"];
    SNAttachment *table = [a addTableToNote:rich rows:2 columns:2];
    TTTable *cells = [a tableOfAttachment:table];
    [[cells textAtRow:0 column:0] insertString:@"Name" atIndex:0 attributes:nil];
    [[cells textAtRow:1 column:1] insertString:@"a|b" atIndex:0 attributes:nil];
    [a saveTable:cells toAttachment:table];
    t = rich.text;
    [t insertString:@"Roadmap\nSee " atIndex:0 attributes:nil];
    [t setAttributes:@{ SNStyleKey: SNStyleTitle } range:NSMakeRange(0, 8)];
    [t insertString:@"￼" atIndex:t.length attributes:@{ SNAttachmentKey: image.id }];
    [t insertString:@" and ￼" atIndex:t.length attributes:nil];
    [t setAttributes:@{ SNAttachmentKey: file.id } range:NSMakeRange(t.length - 1, 1)];
    [t insertString:@"\n￼" atIndex:t.length attributes:nil];
    [t setAttributes:@{ SNAttachmentKey: table.id } range:NSMakeRange(t.length - 1, 1)];
    rich.text = t;
    SNNote *gone = [a addNoteInFolder:work];
    [a deleteNote:gone];
    [a save];

    NSURL *zip = [self temporary:@".zip"];
    NSError *error = nil;
    XCTAssertTrue([a exportMarkdownToURL:zip error:&error], @"%@", error);
    SNZipReader *r = [[SNZipReader alloc] initWithData:[NSData dataWithContentsOfURL:zip]];
    XCTAssertEqualObjects([NSSet setWithArray:r.paths], ([NSSet setWithArray:@[ @"Loose.md", @"Work/Projects/Roadmap.md", @"Work/Projects/_attachments/Roadmap/image.png",
                                                                                @"Work/Projects/_attachments/Roadmap/spec (v2).pdf" ]]));
    NSString *md = [[NSString alloc] initWithData:[r dataAtPath:@"Work/Projects/Roadmap.md"] encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(md, @"# Roadmap\n\nSee ![](_attachments/Roadmap/image.png) and [spec (v2).pdf](_attachments/Roadmap/spec%20%28v2%29.pdf)\n\n"
                               "| Name |  |\n| --- | --- |\n|  | a\\|b |\n");

    SNNotes *b = [self device];
    NSArray *made = [b importFromURL:zip intoFolder:nil error:&error];
    XCTAssertEqual(made.count, 2u, @"%@", error);
    SNFolder *imported = [b foldersInFolder:nil].firstObject;
    XCTAssertEqualObjects(imported.name, zip.lastPathComponent.stringByDeletingPathExtension);
    XCTAssertEqualObjects([b notesInFolder:imported matching:nil].firstObject.title, @"Loose");
    SNFolder *projects = [b foldersInFolder:[b foldersInFolder:imported].firstObject].firstObject;
    XCTAssertEqualObjects(projects.name, @"Projects");
    SNNote *back = [b notesInFolder:projects matching:nil].firstObject;
    XCTAssertEqualObjects(back.body, rich.body);
    XCTAssertEqual(back.attachments.count, 3u);
    NSMutableDictionary *kinds = [NSMutableDictionary dictionary];
    for (SNAttachment *x in back.attachments) kinds[x.kind] = x;
    XCTAssertEqualObjects([kinds[SNAttachmentKindImage] data], SNTinyPNG());
    XCTAssertEqualObjects([kinds[SNAttachmentKindFile] name], @"spec (v2).pdf");
    XCTAssertEqualObjects([b tableOfAttachment:kinds[SNAttachmentKindTable]].strings, (@[ @[ @"Name", @"" ], @[ @"", @"a|b" ] ]));
}

- (void)testATriliumExportIsImported {
    NSDictionary *meta = @{ @"formatVersion": @2, @"appVersion": @"0.63.0", @"files": @[ @{
        @"noteId": @"r1", @"title": @"Journal", @"type": @"text", @"notePosition": @10,
        @"dataFileName": @"Journal.md", @"dirFileName": @"Journal",
        @"children": @[
            @{ @"noteId": @"c2", @"title": @"Second", @"type": @"text", @"notePosition": @20, @"dataFileName": @"Second.md" },
            @{ @"noteId": @"c1", @"title": @"First", @"type": @"text", @"notePosition": @10, @"dataFileName": @"First.md",
               @"attachments": @[ @{ @"attachmentId": @"a1", @"title": @"pic.png", @"role": @"image", @"dataFileName": @"First_pic.png" } ] },
            @{ @"noteId": @"c3", @"title": @"Script", @"type": @"code", @"notePosition": @30, @"dataFileName": @"Script.js" },
            @{ @"noteId": @"c1", @"title": @"First", @"isClone": @YES, @"notePosition": @40 },
            @{ @"noteId": @"c4", @"title": @"Board", @"type": @"canvas", @"notePosition": @50, @"dataFileName": @"Board.json" },
        ] } ] };
    SNZipWriter *w = [[SNZipWriter alloc] init];
    [w addData:[NSJSONSerialization dataWithJSONObject:meta options:0 error:NULL] atPath:@"!!!meta.json" date:nil];
    [w addData:[@"# Journal\n\nKept daily.\n" dataUsingEncoding:NSUTF8StringEncoding] atPath:@"Journal.md" date:nil];
    [w addData:[@"# First\n\nA picture: ![pic](First_pic.png)\n" dataUsingEncoding:NSUTF8StringEncoding] atPath:@"Journal/First.md" date:nil];
    [w addData:SNTinyPNG() atPath:@"Journal/First_pic.png" date:nil];
    [w addData:[@"Second's text." dataUsingEncoding:NSUTF8StringEncoding] atPath:@"Journal/Second.md" date:nil];
    [w addData:[@"console.log(1)\n" dataUsingEncoding:NSUTF8StringEncoding] atPath:@"Journal/Script.js" date:nil];
    [w addData:[@"{}" dataUsingEncoding:NSUTF8StringEncoding] atPath:@"Journal/Board.json" date:nil];
    NSURL *zip = [self temporary:@".zip"];
    [w.data writeToURL:zip atomically:YES];

    SNNotes *d = [self device];
    NSError *error = nil;
    NSArray<SNNote *> *made = [d importFromURL:zip intoFolder:nil error:&error];
    XCTAssertEqualObjects([made valueForKey:@"title"], (@[ @"First", @"Second", @"Script", @"Journal" ]), @"%@", error);
    SNFolder *journal = [d foldersInFolder:[d foldersInFolder:nil].firstObject].firstObject;
    XCTAssertEqualObjects(journal.name, @"Journal");
    XCTAssertEqual([d notesInFolder:journal matching:nil].count, 4u);
    SNNote *first = made[0];
    XCTAssertEqualObjects(first.body, @"First\nA picture: ￼");
    XCTAssertEqualObjects([first.attachments.anyObject kind], SNAttachmentKindImage);
    XCTAssertEqualObjects(made[1].body, @"Second\nSecond's text.");
    XCTAssertEqualObjects(made[2].body, @"Script\nconsole.log(1)");
    XCTAssertEqualObjects([self paragraphAttributesOf:made[2].text at:1][SNStyleKey], SNStyleMono);
}

- (void)testAFolderOfMarkdownIsImported {
    NSURL *dir = [self temporary:@""];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtURL:[dir URLByAppendingPathComponent:@"Recipes/assets"] withIntermediateDirectories:YES attributes:nil error:NULL];
    [[@"Flour, water.\n\n![](assets/bread.png)" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:[dir URLByAppendingPathComponent:@"Recipes/Bread.md"] atomically:YES];
    [SNTinyPNG() writeToURL:[dir URLByAppendingPathComponent:@"Recipes/assets/bread.png"] atomically:YES];
    [[@"Top note" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:[dir URLByAppendingPathComponent:@"Readme.txt"] atomically:YES];
    [[@"ignored" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:[dir URLByAppendingPathComponent:@"data.csv"] atomically:YES];

    SNNotes *d = [self device];
    NSError *error = nil;
    NSArray<SNNote *> *made = [d importFromURL:dir intoFolder:nil error:&error];
    XCTAssertEqualObjects([made valueForKey:@"title"], (@[ @"Readme", @"Bread" ]), @"%@", error);
    XCTAssertEqualObjects(made[1].folder.name, @"Recipes");
    XCTAssertEqual(made[1].attachments.count, 1u);
    XCTAssertEqualObjects(made[1].body, @"Bread\nFlour, water.\n￼");

    /* One file: straight into the folder given. */
    SNFolder *f = [d addFolderNamed:@"Here"];
    made = [d importFromURL:[dir URLByAppendingPathComponent:@"Recipes/Bread.md"] intoFolder:f error:&error];
    XCTAssertEqual(made.count, 1u, @"%@", error);
    XCTAssertEqualObjects(made[0].folder, f);
    XCTAssertEqual(made[0].attachments.count, 1u);
}

@end
