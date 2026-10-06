// SimpleNotes --self-test <server root>: the app as it runs, driven from
// within, against a server with a note titled Groceries (Tests/seed.py):
// the note chosen in the list, text typed into the window's text view,
// Bold from the menu (the responder chain), saved and synced; then a second
// device, syncing from the server, must have both. PASS or FAIL for each;
// the app exits with the number that failed. In CI under xvfb-run.

#pragma once
#import <AppKit/AppKit.h>
#import "SNNotes.h"

@class SNWindowController;

NS_ASSUME_NONNULL_BEGIN

// Set by main from --self-test, before the app starts: then it runs on a
// store of its own and tests itself.
FOUNDATION_EXPORT NSURL *_Nullable SNSelfTestRoot;

FOUNDATION_EXPORT void SNStartSelfTest(SNNotes *notes, SNWindowController *window, NSURL *root);

NS_ASSUME_NONNULL_END
