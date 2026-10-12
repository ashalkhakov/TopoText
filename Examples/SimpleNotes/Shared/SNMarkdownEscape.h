// Text escaped for Markdown, so that it reads back as the text it was:
// what export writes (SNMarkdown) and what the Share extension writes
// (SNShares). Foundation only.

#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Characters that would read as Markdown (emphasis, links, code, HTML)
// escaped.
FOUNDATION_EXPORT NSString *SNMarkdownEscapeInline(NSString *text);
// A line that would begin a block (a heading, a list, a quote) escaped
// there.
FOUNDATION_EXPORT NSString *SNMarkdownEscapeLineStart(NSString *line);

NS_ASSUME_NONNULL_END
