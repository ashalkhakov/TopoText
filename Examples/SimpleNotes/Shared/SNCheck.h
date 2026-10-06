// Two devices against a running server, over HTTP: a note made on one
// reaches the other; both edit it apart; both end with both edits. What
// `SimpleNotes --check <root>` runs (and Tests/serve-and-check.sh, in CI).

#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// The number of checks that failed, each said on standard error.
FOUNDATION_EXPORT int SNRunCheck(NSURL *serviceRoot, NSURL *_Nullable modelURL);

NS_ASSUME_NONNULL_END
