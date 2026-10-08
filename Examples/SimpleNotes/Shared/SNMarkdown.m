#import "SNMarkdown.h"
#import "SNRichText.h"

static NSString * const SNObjectReplacement = @"￼";

#pragma mark - Export

/* Characters that would read as Markdown, escaped. */
static NSString *SNEscapeInline(NSString *text) {
    NSMutableString *out = [NSMutableString stringWithCapacity:text.length];
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if (c == '\\' || c == '*' || c == '_' || c == '~' || c == '`' || c == '[' || c == ']' || c == '<' || c == '>')
            [out appendString:@"\\"];
        [out appendFormat:@"%C", c];
    }
    return out;
}

/* A line that would begin a block (a heading, a list, a quote) escaped there. */
static NSString *SNEscapeLineStart(NSString *line) {
    static NSRegularExpression *start;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        start = [NSRegularExpression regularExpressionWithPattern:@"^(\\s*)(#|[-+]|\\d+[.)])(\\s|$)" options:0 error:NULL];
    });
    NSTextCheckingResult *m = [start firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
    if (!m) return line;
    NSRange marker = [m rangeAtIndex:2];
    /* 1. → 1\. ; # → \# */
    NSUInteger at = [line characterAtIndex:marker.location] >= '0' && [line characterAtIndex:marker.location] <= '9' ? NSMaxRange(marker) - 1
                                                                                                                       : marker.location;
    return [NSString stringWithFormat:@"%@\\%@", [line substringToIndex:at], [line substringFromIndex:at]];
}

static BOOL SNYes(id value) {
    return [value respondsToSelector:@selector(boolValue)] && [value boolValue];
}

/* A run's inline markers, outermost first: link, then bold, italic, strike,
   underline; and what each opens and closes with. */
static NSArray<NSArray<NSString *> *> *SNMarkersOf(NSDictionary *attributes) {
    NSMutableArray *markers = [NSMutableArray array];
    if (SNYes(attributes[SNBoldKey])) [markers addObject:@[ @"**", @"**" ]];
    if (SNYes(attributes[SNItalicKey])) [markers addObject:@[ @"*", @"*" ]];
    if (SNYes(attributes[SNStrikeKey])) [markers addObject:@[ @"~~", @"~~" ]];
    if (SNYes(attributes[SNUnderlineKey])) [markers addObject:@[ @"<u>", @"</u>" ]];
    return markers;
}

/* A paragraph's inline content, its runs grouped by how they look. */
static NSString *SNInlineMarkdown(TopoText *text, NSRange range, id<SNMarkdownExporting> exporter, NSMutableArray<NSString *> *blocks) {
    NSMutableString *out = [NSMutableString string];
    NSUInteger at = range.location;
    NSString *string = text.string;
    while (at < NSMaxRange(range)) {
        NSRange run;
        NSDictionary *attributes = [text attributesAtIndex:at effectiveRange:&run] ?: @{};
        run = NSIntersectionRange(run, NSMakeRange(at, NSMaxRange(range) - at));
        if (run.length == 0) run = NSMakeRange(at, 1);
        NSString *piece = [string substringWithRange:run];
        at = NSMaxRange(run);
        id attachment = attributes[SNAttachmentKey];
        if ([attachment isKindOfClass:[NSString class]] && [piece containsString:SNObjectReplacement]) {
            NSString *md = [exporter markdownOfAttachment:attachment];
            if (!md.length) continue;
            /* A block (a table): on its own, after the paragraph. */
            if ([md containsString:@"\n"]) [blocks addObject:md];
            else [out appendString:md];
            continue;
        }
        piece = [piece stringByReplacingOccurrencesOfString:SNObjectReplacement withString:@""];
        if (!piece.length) continue;
        /* Spaces kept outside the markers: "** x**" is no emphasis. */
        NSUInteger lead = 0, trail = 0;
        while (lead < piece.length && [piece characterAtIndex:lead] == ' ') lead++;
        while (trail < piece.length - lead && [piece characterAtIndex:piece.length - 1 - trail] == ' ') trail++;
        NSString *core = [piece substringWithRange:NSMakeRange(lead, piece.length - lead - trail)];
        NSMutableString *formatted = [SNEscapeInline(core) mutableCopy];
        if (core.length) {
            for (NSArray *marker in SNMarkersOf(attributes).reverseObjectEnumerator) {
                [formatted insertString:marker[0] atIndex:0];
                [formatted appendString:marker[1]];
            }
            id link = attributes[SNLinkKey];
            if ([link isKindOfClass:[NSString class]] && [link length])
                formatted = [NSMutableString stringWithFormat:@"[%@](%@)", formatted,
                                                              [link stringByReplacingOccurrencesOfString:@")" withString:@"%29"]];
        }
        [out appendString:[@"" stringByPaddingToLength:lead withString:@" " startingAtIndex:0]];
        [out appendString:formatted];
        [out appendString:[@"" stringByPaddingToLength:trail withString:@" " startingAtIndex:0]];
    }
    return out;
}

NSString *SNMarkdownOfTableRows(NSArray<NSArray<NSString *> *> *rows) {
    NSUInteger columns = 0;
    for (NSArray *row in rows) columns = MAX(columns, row.count);
    if (!columns) return @"";
    NSMutableString *out = [NSMutableString string];
    void (^line)(NSArray *) = ^(NSArray *cells) {
        [out appendString:@"|"];
        for (NSUInteger c = 0; c < columns; c++) {
            NSString *cell = c < cells.count ? cells[c] : @"";
            cell = [[SNEscapeInline(cell) stringByReplacingOccurrencesOfString:@"|" withString:@"\\|"]
                stringByReplacingOccurrencesOfString:@"\n" withString:@"<br>"];
            [out appendFormat:@" %@ |", cell];
        }
        [out appendString:@"\n"];
    };
    line(rows.firstObject ?: @[]);
    NSMutableArray *rule = [NSMutableArray array];
    for (NSUInteger c = 0; c < columns; c++) [rule addObject:@"---"];
    [out appendFormat:@"| %@ |\n", [rule componentsJoinedByString:@" | "]];
    for (NSUInteger r = 1; r < rows.count; r++) line(rows[r]);
    return [out stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
}

NSString *SNMarkdownOfText(TopoText *text, id<SNMarkdownExporting> exporter) {
    NSString *string = text.string;
    NSMutableArray<NSString *> *out = [NSMutableArray array];   /* blocks, joined by blank lines */
    __block NSMutableArray<NSString *> *code = nil, *list = nil;
    NSMutableDictionary<NSNumber *, NSNumber *> *numbers = [NSMutableDictionary dictionary];
    void (^flush)(void) = ^{
        if (code) [out addObject:[NSString stringWithFormat:@"```\n%@\n```", [code componentsJoinedByString:@"\n"]]];
        if (list) [out addObject:[list componentsJoinedByString:@"\n"]];
    };
    for (NSValue *value in text.paragraphRanges) {
        NSRange paragraph = value.rangeValue;
        NSRange content = paragraph;
        if (content.length && [string characterAtIndex:NSMaxRange(content) - 1] == '\n') content.length--;
        /* A paragraph's attributes: its newline's (or its last character's). */
        NSUInteger at = paragraph.length ? NSMaxRange(paragraph) - 1 : paragraph.location;
        NSDictionary *attributes = at < string.length ? [text attributesAtIndex:at effectiveRange:NULL] : @{};
        NSString *style = attributes[SNStyleKey], *kind = attributes[SNListKey];
        NSInteger indent = [attributes[SNIndentKey] respondsToSelector:@selector(integerValue)] ? MAX(0, [attributes[SNIndentKey] integerValue]) : 0;
        if ([style isEqual:SNStyleMono]) {
            if (list) { flush(); list = nil; }
            if (!code) code = [NSMutableArray array];
            [code addObject:[[string substringWithRange:content] stringByReplacingOccurrencesOfString:SNObjectReplacement withString:@""]];
            continue;
        }
        if (code) { flush(); code = nil; }
        NSMutableArray *blocks = [NSMutableArray array];
        NSString *inline_ = SNInlineMarkdown(text, content, exporter, blocks);
        if ([kind isKindOfClass:[NSString class]] && kind.length) {
            if (!list) {
                list = [NSMutableArray array];
                [numbers removeAllObjects];
            }
            NSString *pad = [@"" stringByPaddingToLength:indent * 4 withString:@" " startingAtIndex:0];
            /* Numbering per level, from 1 where a level begins. */
            for (NSNumber *deeper in numbers.allKeys)
                if (deeper.integerValue > indent) [numbers removeObjectForKey:deeper];
            NSString *marker;
            if ([kind isEqual:SNListCheck]) marker = SNYes(attributes[SNCheckedKey]) ? @"- [x]" : @"- [ ]";
            else if ([kind isEqual:SNListNumber]) {
                NSInteger n = [numbers[@(indent)] integerValue] + 1;
                numbers[@(indent)] = @(n);
                marker = [NSString stringWithFormat:@"%ld.", (long)n];
            } else if ([kind isEqual:SNListBullet]) marker = @"*";
            else marker = @"-";
            if (![kind isEqual:SNListNumber]) [numbers removeObjectForKey:@(indent)];
            [list addObject:[NSString stringWithFormat:@"%@%@ %@", pad, marker, inline_]];
            for (NSString *block in blocks) [list addObject:block];
            continue;
        }
        if (list) { flush(); list = nil; }
        if (!inline_.length && !blocks.count) continue;  /* an empty line of the note */
        NSString *prefix = [style isEqual:SNStyleTitle] ? @"# " : [style isEqual:SNStyleHeading] ? @"## " : [style isEqual:SNStyleSubheading] ? @"### " : @"";
        if (inline_.length) [out addObject:prefix.length ? [prefix stringByAppendingString:inline_] : SNEscapeLineStart(inline_)];
        [out addObjectsFromArray:blocks];
    }
    flush();
    return [[out componentsJoinedByString:@"\n\n"] stringByAppendingString:@"\n"];
}

#pragma mark - Import

/* What a run is, as it is read: its text and attributes. */
@interface SNRun : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSDictionary *attributes;
@end
@implementation SNRun
@end

static NSString *SNDecodeEntities(NSString *s) {
    if (![s containsString:@"&"]) return s;
    NSDictionary *named = @{ @"&amp;": @"&", @"&lt;": @"<", @"&gt;": @">", @"&quot;": @"\"", @"&#39;": @"'", @"&apos;": @"'", @"&nbsp;": @" " };
    for (NSString *k in named) s = [s stringByReplacingOccurrencesOfString:k withString:named[k]];
    return s;
}

/* Inline Markdown as runs. A delimiter opens only when it is closed later
   on the line; else it is text. */
static void SNParseInline(NSString *line, NSDictionary *base, id<SNMarkdownImporting> importer, NSMutableArray<SNRun *> *runs) {
    NSMutableDictionary *now = [base mutableCopy];
    NSMutableString *pending = [NSMutableString string];
    void (^emit)(void) = ^{
        if (!pending.length) return;
        SNRun *r = [SNRun new];
        r.text = SNDecodeEntities(pending);
        r.attributes = now;
        [runs addObject:r];
        [pending setString:@""];
    };
    void (^toggle)(NSString *) = ^(NSString *key) {
        emit();
        if (SNYes(now[key])) [now removeObjectForKey:key];
        else now[key] = @YES;
    };
    NSUInteger i = 0, n = line.length;
    while (i < n) {
        unichar c = [line characterAtIndex:i];
        NSString *rest = [line substringFromIndex:i];
        if (c == '\\' && i + 1 < n && [[NSCharacterSet punctuationCharacterSet] characterIsMember:[line characterAtIndex:i + 1]]) {
            [pending appendFormat:@"%C", [line characterAtIndex:i + 1]];
            i += 2;
            continue;
        }
        if (c == '`') {
            NSRange close = [line rangeOfString:@"`" options:0 range:NSMakeRange(i + 1, n - i - 1)];
            if (close.location != NSNotFound) {
                [pending appendString:[line substringWithRange:NSMakeRange(i + 1, close.location - i - 1)]];
                i = NSMaxRange(close);
                continue;
            }
        }
        /* ![alt](src) and [text](url) */
        if ((c == '!' && [rest hasPrefix:@"!["]) || c == '[') {
            BOOL image = c == '!';
            NSUInteger open = i + (image ? 1 : 0);
            NSRange closeText = [line rangeOfString:@"](" options:0 range:NSMakeRange(open, n - open)];
            NSRange closeURL = closeText.location != NSNotFound ? [line rangeOfString:@")" options:0
                                                                                range:NSMakeRange(NSMaxRange(closeText), n - NSMaxRange(closeText))]
                                                               : NSMakeRange(NSNotFound, 0);
            if (closeText.location != NSNotFound && closeURL.location != NSNotFound) {
                NSString *label = [line substringWithRange:NSMakeRange(open + 1, closeText.location - open - 1)];
                NSString *target = [line substringWithRange:NSMakeRange(NSMaxRange(closeText), closeURL.location - NSMaxRange(closeText))];
                /* "url "title"" → url */
                NSRange space = [target rangeOfString:@" "];
                if (space.location != NSNotFound) target = [target substringToIndex:space.location];
                target = [target stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"<>"]];
                NSString *decoded = target.stringByRemovingPercentEncoding ?: target;
                BOOL web = [target rangeOfString:@"://"].location != NSNotFound || [target hasPrefix:@"mailto:"];
                if (image || (!web && target.length && ![decoded.pathExtension.lowercaseString isEqual:@"md"] &&
                              ![decoded.pathExtension.lowercaseString isEqual:@"html"] && decoded.pathExtension.length)) {
                    NSString *attachment = !web && [importer respondsToSelector:@selector(attachmentForPath:title:image:)]
                                               ? [importer attachmentForPath:decoded title:label image:image] : nil;
                    if (attachment) {
                        emit();
                        SNRun *r = [SNRun new];
                        r.text = SNObjectReplacement;
                        NSMutableDictionary *a = [base mutableCopy];
                        a[SNAttachmentKey] = attachment;
                        r.attributes = a;
                        [runs addObject:r];
                        i = NSMaxRange(closeURL);
                        continue;
                    }
                }
                emit();
                NSMutableDictionary *linked = [now mutableCopy];
                if (web) linked[SNLinkKey] = target;
                SNParseInline(image ? (label.length ? label : decoded.lastPathComponent) : label, linked, importer, runs);
                i = NSMaxRange(closeURL);
                continue;
            }
        }
        /* <https://…> autolinks, and the HTML other apps write */
        if (c == '<') {
            NSRange close = [line rangeOfString:@">" options:0 range:NSMakeRange(i, n - i)];
            if (close.location != NSNotFound) {
                NSString *tag = [line substringWithRange:NSMakeRange(i + 1, close.location - i - 1)];
                NSString *lower = tag.lowercaseString;
                if ([tag rangeOfString:@"://"].location != NSNotFound && ![tag containsString:@" "]) {
                    emit();
                    NSMutableDictionary *linked = [now mutableCopy];
                    linked[SNLinkKey] = tag;
                    SNRun *r = [SNRun new];
                    r.text = tag;
                    r.attributes = linked;
                    [runs addObject:r];
                    i = NSMaxRange(close);
                    continue;
                }
                NSDictionary *toggles = @{ @"b": SNBoldKey, @"strong": SNBoldKey, @"i": SNItalicKey, @"em": SNItalicKey,
                                           @"s": SNStrikeKey, @"del": SNStrikeKey, @"strike": SNStrikeKey, @"u": SNUnderlineKey };
                NSString *name = [[lower stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/ "]]
                    componentsSeparatedByString:@" "].firstObject;
                if (toggles[name]) {
                    emit();
                    if ([lower hasPrefix:@"/"]) [now removeObjectForKey:toggles[name]];
                    else now[toggles[name]] = @YES;
                    i = NSMaxRange(close);
                    continue;
                }
                if ([name isEqual:@"a"]) {
                    emit();
                    if ([lower hasPrefix:@"/"]) {
                        [now removeObjectForKey:SNLinkKey];
                    } else {
                        NSRegularExpression *href = [NSRegularExpression regularExpressionWithPattern:@"href=\"([^\"]*)\"" options:0 error:NULL];
                        NSTextCheckingResult *m = [href firstMatchInString:tag options:0 range:NSMakeRange(0, tag.length)];
                        NSString *url = m ? SNDecodeEntities([tag substringWithRange:[m rangeAtIndex:1]]) : nil;
                        if ([url rangeOfString:@"://"].location != NSNotFound || [url hasPrefix:@"mailto:"]) now[SNLinkKey] = url;
                    }
                    i = NSMaxRange(close);
                    continue;
                }
                if ([name isEqual:@"img"]) {
                    NSRegularExpression *src = [NSRegularExpression regularExpressionWithPattern:@"src=\"([^\"]*)\"" options:0 error:NULL];
                    NSTextCheckingResult *m = [src firstMatchInString:tag options:0 range:NSMakeRange(0, tag.length)];
                    NSString *path = m ? [tag substringWithRange:[m rangeAtIndex:1]] : nil;
                    NSString *attachment = path && [importer respondsToSelector:@selector(attachmentForPath:title:image:)]
                                               ? [importer attachmentForPath:path.stringByRemovingPercentEncoding ?: path title:@"" image:YES] : nil;
                    if (attachment) {
                        emit();
                        SNRun *r = [SNRun new];
                        r.text = SNObjectReplacement;
                        NSMutableDictionary *a = [base mutableCopy];
                        a[SNAttachmentKey] = attachment;
                        r.attributes = a;
                        [runs addObject:r];
                    }
                    i = NSMaxRange(close);
                    continue;
                }
                if ([name isEqual:@"br"]) {
                    [pending appendString:@" "];
                    i = NSMaxRange(close);
                    continue;
                }
                if ([name rangeOfCharacterFromSet:[[NSCharacterSet letterCharacterSet] invertedSet]].location == NSNotFound && name.length) {
                    /* Any other tag: dropped, its text kept. */
                    i = NSMaxRange(close);
                    continue;
                }
            }
        }
        /* **, __, ~~, *, _ */
        NSString *delimiter = nil;
        for (NSString *d in @[ @"**", @"__", @"~~", @"*", @"_" ]) {
            if ([rest hasPrefix:d]) { delimiter = d; break; }
        }
        if (delimiter) {
            NSString *key = [delimiter isEqual:@"~~"] ? SNStrikeKey : delimiter.length == 2 ? SNBoldKey : SNItalicKey;
            BOOL open = SNYes(now[key]);
            NSUInteger after = i + delimiter.length;
            BOOL intraword = [delimiter hasPrefix:@"_"] && i > 0 && after < n &&
                             [[NSCharacterSet alphanumericCharacterSet] characterIsMember:[line characterAtIndex:i - 1]] &&
                             [[NSCharacterSet alphanumericCharacterSet] characterIsMember:[line characterAtIndex:after]];
            BOOL closesLater = [line rangeOfString:delimiter options:0 range:NSMakeRange(after, n - after)].location != NSNotFound;
            BOOL opens = !open && closesLater && after < n && ![[NSCharacterSet whitespaceCharacterSet] characterIsMember:[line characterAtIndex:after]];
            if (!intraword && (open || opens)) {
                toggle(key);
                i = after;
                continue;
            }
        }
        [pending appendFormat:@"%C", c];
        i++;
    }
    emit();
}

/* A table's line as its cells. */
static NSArray<NSString *> *SNCellsOf(NSString *line) {
    NSString *t = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([t hasPrefix:@"|"]) t = [t substringFromIndex:1];
    if ([t hasSuffix:@"|"] && ![t hasSuffix:@"\\|"]) t = [t substringToIndex:t.length - 1];
    NSMutableArray *cells = [NSMutableArray array];
    NSMutableString *cell = [NSMutableString string];
    for (NSUInteger i = 0; i < t.length; i++) {
        unichar c = [t characterAtIndex:i];
        if (c == '\\' && i + 1 < t.length && [t characterAtIndex:i + 1] == '|') {
            [cell appendString:@"|"];
            i++;
        } else if (c == '|') {
            [cells addObject:[cell stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
            [cell setString:@""];
        } else {
            [cell appendFormat:@"%C", c];
        }
    }
    [cells addObject:[cell stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
    NSMutableArray *plain = [NSMutableArray array];
    for (NSString *c in cells) {
        NSMutableArray *runs = [NSMutableArray array];
        SNParseInline([c stringByReplacingOccurrencesOfString:@"<br>" withString:@" "], @{}, nil, runs);
        [plain addObject:[[runs valueForKey:@"text"] componentsJoinedByString:@""]];
    }
    return plain;
}

static BOOL SNIsTableRule(NSString *line) {
    static NSRegularExpression *rule;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        rule = [NSRegularExpression regularExpressionWithPattern:@"^\\s*\\|?\\s*:?-{3,}:?\\s*(\\|\\s*:?-{3,}:?\\s*)*\\|?\\s*$" options:0 error:NULL];
    });
    return [rule firstMatchInString:line options:0 range:NSMakeRange(0, line.length)] != nil;
}

/* What the text is built of: paragraphs, each its runs and attributes. */
@interface SNParagraph : NSObject
@property (nonatomic, strong) NSMutableArray<SNRun *> *runs;
@property (nonatomic, copy) NSDictionary *attributes;
@end
@implementation SNParagraph
@end

TopoText *SNTextOfMarkdown(NSString *markdown, NSString *title, id<SNMarkdownImporting> importer) {
    NSArray<NSString *> *lines = [[markdown stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"] componentsSeparatedByString:@"\n"];
    NSMutableArray<SNParagraph *> *paragraphs = [NSMutableArray array];
    __block SNParagraph *open = nil;   /* a paragraph lines are still joined to */
    SNParagraph * (^add)(NSString *, NSDictionary *) = ^SNParagraph *(NSString *text, NSDictionary *attributes) {
        SNParagraph *p = [SNParagraph new];
        p.runs = [NSMutableArray array];
        p.attributes = attributes;
        SNParseInline(text, @{}, importer, p.runs);
        [paragraphs addObject:p];
        return p;
    };
    NSRegularExpression *heading = [NSRegularExpression regularExpressionWithPattern:@"^\\s{0,3}(#{1,6})\\s+(.*?)\\s*#*\\s*$" options:0 error:NULL];
    NSRegularExpression *item = [NSRegularExpression regularExpressionWithPattern:@"^(\\s*)([-*+]|\\d+[.)])\\s+(\\[([ xX])\\]\\s+)?(.*)$" options:0 error:NULL];
    NSRegularExpression *rule = [NSRegularExpression regularExpressionWithPattern:@"^\\s{0,3}([-*_])(\\s*\\1){2,}\\s*$" options:0 error:NULL];
    NSMutableArray<NSNumber *> *columns = [NSMutableArray array];   /* where each open list level's items begin */
    for (NSUInteger l = 0; l < lines.count; l++) {
        NSString *line = [lines[l] stringByReplacingOccurrencesOfString:@"\t" withString:@"    "];
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (!trimmed.length) {
            open = nil;
            continue;
        }
        NSRange all = NSMakeRange(0, line.length);
        if ([trimmed hasPrefix:@"```"] || [trimmed hasPrefix:@"~~~"]) {
            NSString *fence = [trimmed substringToIndex:3];
            for (l++; l < lines.count && ![[lines[l] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] hasPrefix:fence]; l++) {
                SNParagraph *p = [SNParagraph new];
                SNRun *r = [SNRun new];
                r.text = lines[l];
                r.attributes = @{};
                p.runs = [NSMutableArray arrayWithObject:r];
                p.attributes = @{ SNStyleKey: SNStyleMono };
                [paragraphs addObject:p];
            }
            open = nil;
            [columns removeAllObjects];
            continue;
        }
        NSTextCheckingResult *h = [heading firstMatchInString:line options:0 range:all];
        if (h) {
            NSUInteger depth = [h rangeAtIndex:1].length;
            NSString *style = depth == 1 ? SNStyleTitle : depth == 2 ? SNStyleHeading : SNStyleSubheading;
            add([line substringWithRange:[h rangeAtIndex:2]], @{ SNStyleKey: style });
            open = nil;
            [columns removeAllObjects];
            continue;
        }
        if ([rule firstMatchInString:line options:0 range:all]) {
            open = nil;
            continue;
        }
        if ([trimmed hasPrefix:@"|"] && l + 1 < lines.count && SNIsTableRule(lines[l + 1])) {
            NSMutableArray *rows = [NSMutableArray arrayWithObject:SNCellsOf(line)];
            for (l += 2; l < lines.count && [[lines[l] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] hasPrefix:@"|"]; l++)
                [rows addObject:SNCellsOf(lines[l])];
            l--;
            NSString *attachment = [importer respondsToSelector:@selector(attachmentForTableRows:)] ? [importer attachmentForTableRows:rows] : nil;
            if (attachment) {
                SNParagraph *p = [SNParagraph new];
                SNRun *r = [SNRun new];
                r.text = SNObjectReplacement;
                r.attributes = @{ SNAttachmentKey: attachment };
                p.runs = [NSMutableArray arrayWithObject:r];
                p.attributes = @{};
                [paragraphs addObject:p];
            } else {
                for (NSArray *row in rows) add([row componentsJoinedByString:@"\t"], @{});
            }
            open = nil;
            [columns removeAllObjects];
            continue;
        }
        NSTextCheckingResult *m = [item firstMatchInString:line options:0 range:all];
        if (m) {
            NSUInteger column = [m rangeAtIndex:1].length;
            while (columns.count && columns.lastObject.unsignedIntegerValue > column) [columns removeLastObject];
            if (!columns.count || columns.lastObject.unsignedIntegerValue < column) [columns addObject:@(column)];
            NSString *marker = [line substringWithRange:[m rangeAtIndex:2]];
            NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
            if ([m rangeAtIndex:3].location != NSNotFound) {
                attributes[SNListKey] = SNListCheck;
                if (![[line substringWithRange:[m rangeAtIndex:4]] isEqual:@" "]) attributes[SNCheckedKey] = @YES;
            } else if ([marker isEqual:@"-"]) attributes[SNListKey] = SNListDash;
            else if ([marker isEqual:@"*"] || [marker isEqual:@"+"]) attributes[SNListKey] = SNListBullet;
            else attributes[SNListKey] = SNListNumber;
            if (columns.count > 1) attributes[SNIndentKey] = @(columns.count - 1);
            open = add([line substringWithRange:[m rangeAtIndex:5]], attributes);
            continue;
        }
        BOOL quote = [trimmed hasPrefix:@">"];
        NSString *body = quote ? [[trimmed substringFromIndex:1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] : trimmed;
        BOOL hardBreak = [line hasSuffix:@"  "] || [line hasSuffix:@"\\"];
        if ([body hasSuffix:@"\\"]) body = [body substringToIndex:body.length - 1];
        if (open && !quote) {
            /* A line of the paragraph (or list item) before: joined to it. */
            SNParseInline([@" " stringByAppendingString:body], @{}, importer, open.runs);
        } else {
            if (!(open && quote)) [columns removeAllObjects];
            open = add(body, @{});
        }
        if (hardBreak) open = nil;
    }

    /* The title first, unless it is there already. */
    if (title.length) {
        SNParagraph *first = paragraphs.firstObject;
        NSString *firstText = [[first.runs valueForKey:@"text"] componentsJoinedByString:@""];
        if (!first || ![first.attributes[SNStyleKey] isEqual:SNStyleTitle] ||
            ![[firstText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] isEqual:title]) {
            if (first && [firstText isEqual:title] && !first.attributes[SNListKey]) {
                first.attributes = @{ SNStyleKey: SNStyleTitle };
            } else {
                SNParagraph *p = [SNParagraph new];
                SNRun *r = [SNRun new];
                r.text = title;
                r.attributes = @{};
                p.runs = [NSMutableArray arrayWithObject:r];
                p.attributes = @{ SNStyleKey: SNStyleTitle };
                [paragraphs insertObject:p atIndex:0];
            }
        }
    }

    TopoText *text = [TopoText textWithReplica:0];
    for (NSUInteger i = 0; i < paragraphs.count; i++) {
        SNParagraph *p = paragraphs[i];
        for (SNRun *r in p.runs) {
            if (!r.text.length) continue;
            NSMutableDictionary *a = [r.attributes mutableCopy];
            [a addEntriesFromDictionary:p.attributes];
            [text insertString:r.text atIndex:text.length attributes:a.count ? a : nil];
        }
        if (i + 1 < paragraphs.count) [text insertString:@"\n" atIndex:text.length attributes:p.attributes.count ? p.attributes : nil];
    }
    return text;
}

#pragma mark - HTML

/* A tag's attribute's value (name="…" or name='…'); nil: none. */
static NSString *SNAttributeOf(NSString *tag, NSString *name) {
    NSString *pattern = [NSString stringWithFormat:@"(?:^|\\s)%@\\s*=\\s*(\"([^\"]*)\"|'([^']*)')", name];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:NULL];
    NSTextCheckingResult *m = [re firstMatchInString:tag options:0 range:NSMakeRange(0, tag.length)];
    if (!m) return nil;
    NSRange r = [m rangeAtIndex:2].location != NSNotFound ? [m rangeAtIndex:2] : [m rangeAtIndex:3];
    return [tag substringWithRange:r];
}

NSString *SNMarkdownOfHTML(NSString *html) {
    /* What is in <body>, when it has one. */
    NSRange body = [html rangeOfString:@"<body" options:NSCaseInsensitiveSearch];
    if (body.location != NSNotFound) {
        NSRange open = [html rangeOfString:@">" options:0 range:NSMakeRange(body.location, html.length - body.location)];
        NSRange close = [html rangeOfString:@"</body" options:NSCaseInsensitiveSearch | NSBackwardsSearch];
        if (open.location != NSNotFound)
            html = [html substringWithRange:NSMakeRange(NSMaxRange(open), (close.location != NSNotFound && close.location > open.location ? close.location : html.length) - NSMaxRange(open))];
    }
    NSMutableString *out = [NSMutableString string];
    NSMutableString *target = out;                    /* out, or a table's cell */
    NSMutableArray<NSString *> *lists = [NSMutableArray array];   /* "ul", "ol" */
    NSMutableArray<NSMutableArray<NSString *> *> *rows = nil;
    NSMutableString *cell = nil;
    NSInteger pre = 0;
    BOOL space = YES;   /* the last written was white: spaces between are dropped */
    NSUInteger i = 0, n = html.length;
    while (i < n) {
        unichar c = [html characterAtIndex:i];
        if (c == '<') {
            if ([html rangeOfString:@"<!--" options:NSAnchoredSearch range:NSMakeRange(i, n - i)].location != NSNotFound) {
                NSRange end = [html rangeOfString:@"-->" options:0 range:NSMakeRange(i, n - i)];
                i = end.location == NSNotFound ? n : NSMaxRange(end);
                continue;
            }
            NSRange close = [html rangeOfString:@">" options:0 range:NSMakeRange(i, n - i)];
            if (close.location == NSNotFound) break;
            NSString *tag = [html substringWithRange:NSMakeRange(i + 1, close.location - i - 1)];
            i = NSMaxRange(close);
            BOOL closing = [tag hasPrefix:@"/"];
            NSString *trimmed = [tag stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/ \n\t"]];
            NSString *name = [[trimmed componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].firstObject lowercaseString] ?: @"";
            if ([name isEqual:@"script"] || [name isEqual:@"style"]) {
                if (!closing) {
                    NSRange end = [html rangeOfString:[NSString stringWithFormat:@"</%@", name] options:NSCaseInsensitiveSearch range:NSMakeRange(i, n - i)];
                    i = end.location == NSNotFound ? n : end.location;
                }
                continue;
            }
            if ([name isEqual:@"pre"]) {
                pre += closing ? -1 : 1;
                [target appendString:closing ? @"\n```\n\n" : @"\n\n```\n"];
                space = YES;
                continue;
            }
            if (pre > 0) continue;   /* <code> and the like in a <pre> */
            if (name.length == 2 && [name characterAtIndex:0] == 'h' && [name characterAtIndex:1] >= '1' && [name characterAtIndex:1] <= '6') {
                NSInteger depth = [name characterAtIndex:1] - '0';
                [target appendString:closing ? @"\n\n" : [NSString stringWithFormat:@"\n\n%@ ", [@"" stringByPaddingToLength:MIN(depth, 3) withString:@"#" startingAtIndex:0]]];
                space = YES;
                continue;
            }
            if ([name isEqual:@"p"] || [name isEqual:@"div"] || [name isEqual:@"blockquote"] || [name isEqual:@"figure"] || [name isEqual:@"section"]) {
                if (lists.count && !closing) continue;   /* a <p> in an <li>: the item's */
                if (!lists.count) [target appendString:@"\n\n"];
                space = YES;
                continue;
            }
            if ([name isEqual:@"br"]) {
                [target appendString:cell ? @" " : @"  \n"];
                space = YES;
                continue;
            }
            if ([name isEqual:@"hr"]) {
                [target appendString:@"\n\n---\n\n"];
                space = YES;
                continue;
            }
            if ([name isEqual:@"ul"] || [name isEqual:@"ol"]) {
                if (closing) [lists removeLastObject];
                else [lists addObject:name];
                if (!lists.count) [target appendString:@"\n\n"];
                continue;
            }
            if ([name isEqual:@"li"]) {
                if (closing || !lists.count) continue;
                /* A checkbox in it (Trilium's to-do list): a checklist item. */
                NSRange next = [html rangeOfString:@"<li" options:NSCaseInsensitiveSearch range:NSMakeRange(i, n - i)];
                NSRange ends = [html rangeOfString:@"</li" options:NSCaseInsensitiveSearch range:NSMakeRange(i, n - i)];
                NSUInteger stop = MIN(next.location, ends.location);
                NSString *content = [html substringWithRange:NSMakeRange(i, (stop == NSNotFound ? n : stop) - i)];
                NSRange box = [content rangeOfString:@"type=\"checkbox\"" options:NSCaseInsensitiveSearch];
                NSString *marker;
                if (box.location != NSNotFound) {
                    NSRange input = [content rangeOfString:@"<input" options:NSCaseInsensitiveSearch | NSBackwardsSearch range:NSMakeRange(0, box.location)];
                    NSRange inputEnd = [content rangeOfString:@">" options:0 range:NSMakeRange(box.location, content.length - box.location)];
                    NSString *inputTag = input.location != NSNotFound && inputEnd.location != NSNotFound
                                             ? [content substringWithRange:NSMakeRange(input.location, NSMaxRange(inputEnd) - input.location)] : @"";
                    marker = [inputTag rangeOfString:@"checked" options:NSCaseInsensitiveSearch].location != NSNotFound ? @"- [x]" : @"- [ ]";
                } else {
                    marker = [lists.lastObject isEqual:@"ol"] ? @"1." : @"-";
                }
                [target appendFormat:@"\n%@%@ ", [@"" stringByPaddingToLength:(lists.count - 1) * 4 withString:@" " startingAtIndex:0], marker];
                space = YES;
                continue;
            }
            if ([name isEqual:@"table"]) {
                if (!closing) {
                    rows = [NSMutableArray array];
                } else if (rows) {
                    [out appendFormat:@"\n\n%@\n\n", SNMarkdownOfTableRows(rows)];
                    rows = nil;
                    cell = nil;
                    target = out;
                }
                space = YES;
                continue;
            }
            if (rows && [name isEqual:@"tr"] && !closing) {
                [rows addObject:[NSMutableArray array]];
                continue;
            }
            if (rows && ([name isEqual:@"td"] || [name isEqual:@"th"])) {
                if (!closing) {
                    if (!rows.count) [rows addObject:[NSMutableArray array]];
                    cell = [NSMutableString string];
                    target = cell;
                } else if (cell) {
                    [rows.lastObject addObject:SNDecodeEntities([cell stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]])];
                    cell = nil;
                    target = out;
                }
                space = YES;
                continue;
            }
            if (cell) continue;   /* a cell's text is plain */
            /* Inline: left for import, as tags it reads; others dropped. */
            if ([@[ @"b", @"strong", @"i", @"em", @"u", @"s", @"del", @"strike" ] containsObject:name]) {
                [target appendFormat:@"<%@%@>", closing ? @"/" : @"", name];
                continue;
            }
            if ([name isEqual:@"a"]) {
                NSString *href = SNAttributeOf(tag, @"href");
                [target appendString:closing ? @"</a>" : href ? [NSString stringWithFormat:@"<a href=\"%@\">", href] : @"<a>"];
                continue;
            }
            if ([name isEqual:@"img"]) {
                NSString *src = SNAttributeOf(tag, @"src");
                if (src.length) [target appendFormat:@"<img src=\"%@\">", src];
                continue;
            }
            continue;
        }
        if (pre > 0) {
            /* As it is, entities read. */
            NSRange next = [html rangeOfString:@"<" options:0 range:NSMakeRange(i, n - i)];
            NSUInteger stop = next.location == NSNotFound ? n : next.location;
            [target appendString:SNDecodeEntities([html substringWithRange:NSMakeRange(i, stop - i)])];
            i = stop;
            continue;
        }
        if ([[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:c]) {
            if (!space) [target appendString:@" "];
            space = YES;
            i++;
            continue;
        }
        /* Text: what would read as Markdown escaped (not &: entities stay). */
        if (!cell && (c == '\\' || c == '*' || c == '_' || c == '~' || c == '`' || c == '[' || c == ']' || c == '#' || c == '|'))
            [target appendString:@"\\"];
        [target appendFormat:@"%C", c];
        space = NO;
        i++;
    }
    /* Lines trimmed of the spaces blocks left at their starts. */
    NSMutableArray *lines = [NSMutableArray array];
    BOOL inFence = NO;
    for (NSString *line in [out componentsSeparatedByString:@"\n"]) {
        if ([line hasPrefix:@"```"]) inFence = !inFence;
        if (inFence || [line hasPrefix:@"```"]) {
            [lines addObject:line];
            continue;
        }
        NSUInteger lead = 0;
        while (lead < line.length && [line characterAtIndex:lead] == ' ') lead++;
        /* A list item's indent kept; a hard break's two spaces kept. */
        NSString *rest = [line substringFromIndex:lead];
        BOOL item = [rest hasPrefix:@"- "] || [rest hasPrefix:@"1. "];
        [lines addObject:item ? line : rest];
    }
    NSString *joined = [lines componentsJoinedByString:@"\n"];
    while ([joined containsString:@"\n\n\n"]) joined = [joined stringByReplacingOccurrencesOfString:@"\n\n\n" withString:@"\n\n"];
    return [joined stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}
