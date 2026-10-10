// The app's memory, as the system's allocator keeps it. On GNUstep (Linux,
// glibc): two malloc arenas, not one for each thread that ever ran (each
// keeps what was freed in it), and what was freed given back to the system
// once a minute. On macOS: nothing to do.

#pragma once
#import <Foundation/Foundation.h>

// Before NSApplicationMain.
FOUNDATION_EXPORT void SNTuneMemory(void);
