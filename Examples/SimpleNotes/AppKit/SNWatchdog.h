// SN_SLOW_MAIN set: where the main thread spends a time it does not answer
// in (a menu slow to open, a click that takes a second), on a machine where
// a debugger is not at hand. On GNUstep, a thread of its own notices the
// main thread has not come round its run loop for 150 ms, and while it has
// not, writes the main thread's stack on stderr every 50 ms: the libraries'
// offsets, which addr2line turns into names against the same build. On
// macOS: nothing (Instruments does this).

#pragma once
#import <Foundation/Foundation.h>

// Before NSApplicationMain.
FOUNDATION_EXPORT void SNWatchMainThread(void);
