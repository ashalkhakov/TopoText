// Shared items on their way to being notes (SNShares.h).

#import "SNShares.h"
#import "SNMarkdownEscape.h"

/* A title as a file's name: no path in it, not hidden, not too long. */
static NSString *SNFileNameOf(NSString *title) {
    NSString *name = [[[title stringByReplacingOccurrencesOfString:@"/" withString:@"-"] stringByReplacingOccurrencesOfString:@":" withString:@"-"]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    while ([name hasPrefix:@"."]) name = [name substringFromIndex:1];
    if (name.length > 80) name = [name substringToIndex:80];
    return name.length ? name : @"Shared";
}

/* An image's kind, by its first bytes, as its file's extension. */
static NSString *SNImageExtension(NSData *data) {
    const unsigned char *b = data.bytes;
    if (data.length >= 4 && b[0] == 0x89 && b[1] == 'P' && b[2] == 'N' && b[3] == 'G') return @"png";
    if (data.length >= 3 && b[0] == 'G' && b[1] == 'I' && b[2] == 'F') return @"gif";
    if (data.length >= 12 && !memcmp(b + 4, "ftyp", 4) && (!memcmp(b + 8, "heic", 4) || !memcmp(b + 8, "heix", 4) || !memcmp(b + 8, "mif1", 4)))
        return @"heic";
    return @"jpg";
}

BOOL SNWriteShare(NSURL *inbox, NSString *title, NSString *text, NSURL *link, NSArray<NSData *> *images, NSError **error) {
    NSString *body = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
    NSString *firstLine = [body componentsSeparatedByString:@"\n"].firstObject;
    NSString *named = title.length ? title : firstLine.length ? firstLine : link.host.length ? link.host : @"Shared";
    NSMutableArray<NSString *> *blocks = [NSMutableArray array];
    /* A title given: the note's first line (its text then follows). */
    if (title.length) [blocks addObject:[@"# " stringByAppendingString:SNMarkdownEscapeInline(title)]];
    for (NSString *line in [body componentsSeparatedByString:@"\n"]) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length) [blocks addObject:SNMarkdownEscapeLineStart(SNMarkdownEscapeInline(trimmed))];
    }
    if (link) {
        NSString *target = [link.absoluteString stringByReplacingOccurrencesOfString:@")" withString:@"%29"];
        [blocks addObject:[NSString stringWithFormat:@"[%@](%@)", SNMarkdownEscapeInline(link.absoluteString), target]];
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    /* Written under a hidden name, then put in place whole; named for when
       it was shared, to be imported in that order. */
    NSString *uuid = [NSString stringWithFormat:@"%013.0f-%@", [NSDate date].timeIntervalSince1970 * 1000, [NSUUID UUID].UUIDString];
    NSURL *writing = [inbox URLByAppendingPathComponent:[@"." stringByAppendingString:uuid] isDirectory:YES];
    NSURL *done = [inbox URLByAppendingPathComponent:uuid isDirectory:YES];
    if (![fm createDirectoryAtURL:writing withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    for (NSUInteger i = 0; i < images.count; i++) {
        NSString *file = [NSString stringWithFormat:@"image-%lu.%@", (unsigned long)i + 1, SNImageExtension(images[i])];
        if (![images[i] writeToURL:[writing URLByAppendingPathComponent:file] options:NSDataWritingAtomic error:error]) {
            [fm removeItemAtURL:writing error:NULL];
            return NO;
        }
        [blocks addObject:[NSString stringWithFormat:@"![](%@)", file]];
    }
    NSString *markdown = [[blocks componentsJoinedByString:@"\n\n"] stringByAppendingString:@"\n"];
    NSURL *md = [writing URLByAppendingPathComponent:[SNFileNameOf(named) stringByAppendingPathExtension:@"md"]];
    if (![markdown writeToURL:md atomically:YES encoding:NSUTF8StringEncoding error:error] ||
        ![fm moveItemAtURL:writing toURL:done error:error]) {
        [fm removeItemAtURL:writing error:NULL];
        return NO;
    }
    return YES;
}

NSArray<NSURL *> *SNSharesIn(NSURL *inbox) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray *found = [NSMutableArray array];
    NSArray *names = [[fm contentsOfDirectoryAtPath:inbox.path error:NULL] ?: @[] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *name in names) {
        if ([name hasPrefix:@"."]) continue;
        NSString *dir = [inbox.path stringByAppendingPathComponent:name];
        for (NSString *file in [fm contentsOfDirectoryAtPath:dir error:NULL] ?: @[])
            if ([file.pathExtension isEqual:@"md"]) [found addObject:[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:file]]];
    }
    return found;
}
