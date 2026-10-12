// Text escaped for Markdown (SNMarkdownEscape.h).

#import "SNMarkdownEscape.h"

/* Characters that would read as Markdown, escaped. */
NSString *SNMarkdownEscapeInline(NSString *text) {
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
NSString *SNMarkdownEscapeLineStart(NSString *line) {
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
