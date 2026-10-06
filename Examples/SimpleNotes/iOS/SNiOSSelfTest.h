// SimpleNotes for iOS, --self-test <server root>: the app driven from
// within, as the AppKit one is (AppKit/SNSelfTest.h): a folder's notes
// shown, Groceries opened in the editor, text typed, Bold from the format
// bar, back to the list, synced; a second device must have both. PASS or
// FAIL on standard error; the app exits with the number that failed.
//   xcrun simctl launch --console-pty booted io.github.ashalkhakov.SimpleNotes --self-test <root>

#pragma once
#import <UIKit/UIKit.h>
#import "SNNotes.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSURL *_Nullable SNSelfTestRoot;
FOUNDATION_EXPORT void SNStartSelfTest(SNNotes *notes, UINavigationController *navigation);

NS_ASSUME_NONNULL_END
