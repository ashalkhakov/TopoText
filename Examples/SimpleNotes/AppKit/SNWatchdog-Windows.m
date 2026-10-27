#import <AppKit/AppKit.h>
#import "SNWatchdog.h"
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static HANDLE SNMainThread;
static volatile LONG64 SNLastBeat;   /* ms; 0: the run loop not yet round */

/* The main thread's stack, as it is: the thread suspended, its frames
   unwound from its context by the tables the compiler leaves for it, and
   only once it runs again written out (as module+offset), so that nothing
   the thread may hold, the heap's lock or stderr's, is waited on. */
static void SNSample(void) {
    DWORD64 frames[64];
    int n = 0;
    if (SuspendThread(SNMainThread) == (DWORD)-1) return;
    CONTEXT context;
    memset(&context, 0, sizeof context);
    context.ContextFlags = CONTEXT_FULL;
    if (GetThreadContext(SNMainThread, &context)) {
        while (n < 64 && context.Rip) {
            frames[n++] = context.Rip;
            DWORD64 base;
            PRUNTIME_FUNCTION function = RtlLookupFunctionEntry(context.Rip, &base, NULL);
            if (!function) {
                /* A leaf: its return address is on top of the stack. */
                context.Rip = *(DWORD64 *)context.Rsp;
                context.Rsp += 8;
                continue;
            }
            PVOID handlerData;
            DWORD64 establisher;
            RtlVirtualUnwind(UNW_FLAG_NHANDLER, base, context.Rip, function, &context, &handlerData, &establisher, NULL);
        }
    }
    ResumeThread(SNMainThread);
    fprintf(stderr, "SN_SLOW_MAIN sample:\n");
    for (int i = 0; i < n; i++) {
        HMODULE module;
        char path[MAX_PATH] = "?";
        if (GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                               (LPCSTR)frames[i], &module)) {
            GetModuleFileNameA(module, path, sizeof path);
            const char *name = strrchr(path, '\\');
            fprintf(stderr, "%s+0x%llx\n", name ? name + 1 : path, (unsigned long long)(frames[i] - (DWORD64)module));
        } else {
            fprintf(stderr, "?+0x%llx\n", (unsigned long long)frames[i]);
        }
    }
}

@interface SNWatchdog : NSObject
@end

@implementation SNWatchdog

/* On the main thread, in the modes it runs in (menus track in their own). */
- (void)beat:(NSTimer *)timer {
    SNLastBeat = (LONG64)GetTickCount64();
}

/* On a thread of its own. */
- (void)watch:(id)unused {
    long long stalledAt = 0;
    int samples = 0;
    for (;;) {
        Sleep(50);
        long long beat = SNLastBeat, now = (long long)GetTickCount64();
        if (!beat) continue;
        if (now - beat > 150) {
            if (!stalledAt) {
                stalledAt = beat;
                samples = 0;
                fprintf(stderr, "SN_SLOW_MAIN: the main thread has not come round for %lld ms\n", now - beat);
            }
            SNSample();
            samples++;
        } else if (stalledAt) {
            fprintf(stderr, "SN_SLOW_MAIN: round again after %lld ms (%d samples)\n", beat - stalledAt, samples);
            stalledAt = 0;
        }
    }
}

@end

void SNWatchMainThread(void) {
    if (!getenv("SN_SLOW_MAIN")) return;
    /* GetCurrentThread is a stand-in that means "the calling thread": the
       watching thread needs a real handle to the main one. */
    if (!DuplicateHandle(GetCurrentProcess(), GetCurrentThread(), GetCurrentProcess(), &SNMainThread,
                         THREAD_SUSPEND_RESUME | THREAD_GET_CONTEXT | THREAD_QUERY_INFORMATION, FALSE, 0)) return;
    static SNWatchdog *watchdog;
    watchdog = [[SNWatchdog alloc] init];
    NSTimer *timer = [NSTimer timerWithTimeInterval:0.02 target:watchdog selector:@selector(beat:) userInfo:nil repeats:YES];
    /* By name: GNUstep's run loop takes NSRunLoopCommonModes as a mode of
       its own, which nothing runs in. */
    for (NSString *mode in @[ NSDefaultRunLoopMode, NSModalPanelRunLoopMode, NSEventTrackingRunLoopMode ])
        [[NSRunLoop currentRunLoop] addTimer:timer forMode:mode];
    [NSThread detachNewThreadSelector:@selector(watch:) toTarget:watchdog withObject:nil];
}
