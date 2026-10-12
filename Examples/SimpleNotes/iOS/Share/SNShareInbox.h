// The inbox on iOS (SNShares.h): in the container of the App Group the app
// and its Share extension share. Both have this file.

#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const SNShareAppGroup;   // @"group.io.github.ashalkhakov.SimpleNotes"
// The inbox; nil where there is no such group (not signed for it).
FOUNDATION_EXPORT NSURL *_Nullable SNShareAppGroupInbox(void);

NS_ASSUME_NONNULL_END
