#import <AppKit/AppKit.h>
#import "SNWatchdog.h"
#include <execinfo.h>
#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static pthread_t SNMainThread;
static _Atomic long long SNLastBeat;   /* ms; 0: the run loop not yet round */

static long long SNNow(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (long long)t.tv_sec * 1000 + t.tv_nsec / 1000000;
}

/* On the main thread, interrupted: its stack, as it is. backtrace_symbols_fd
   writes without allocating, so the thread may be anywhere, malloc too. */
static void SNSample(int sig) {
    void *frames[64];
    int n = backtrace(frames, 64);
    static const char head[] = "SN_SLOW_MAIN sample:\n";
    write(STDERR_FILENO, head, sizeof head - 1);
    backtrace_symbols_fd(frames, n, STDERR_FILENO);
}

@interface SNWatchdog : NSObject
@end

@implementation SNWatchdog

/* On the main thread, in the modes it runs in (menus track in their own). */
- (void)beat:(NSTimer *)timer {
    SNLastBeat = SNNow();
}

/* On a thread of its own. */
- (void)watch:(id)unused {
    long long stalledAt = 0;
    int samples = 0;
    for (;;) {
        usleep(50 * 1000);
        long long beat = SNLastBeat, now = SNNow();
        if (!beat) continue;
        if (now - beat > 150) {
            if (!stalledAt) {
                stalledAt = beat;
                samples = 0;
                fprintf(stderr, "SN_SLOW_MAIN: the main thread has not come round for %lld ms\n", now - beat);
            }
            pthread_kill(SNMainThread, SIGPROF);
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
    SNMainThread = pthread_self();
    /* backtrace loads what it unwinds with on its first call: here, not in
       the signal handler. */
    void *frame;
    backtrace(&frame, 1);
    struct sigaction action;
    memset(&action, 0, sizeof action);
    action.sa_handler = SNSample;
    action.sa_flags = SA_RESTART;
    sigemptyset(&action.sa_mask);
    sigaction(SIGPROF, &action, NULL);
    static SNWatchdog *watchdog;
    watchdog = [[SNWatchdog alloc] init];
    NSTimer *timer = [NSTimer timerWithTimeInterval:0.02 target:watchdog selector:@selector(beat:) userInfo:nil repeats:YES];
    /* By name: GNUstep's run loop takes NSRunLoopCommonModes as a mode of
       its own, which nothing runs in. */
    for (NSString *mode in @[ NSDefaultRunLoopMode, NSModalPanelRunLoopMode, NSEventTrackingRunLoopMode ])
        [[NSRunLoop currentRunLoop] addTimer:timer forMode:mode];
    [NSThread detachNewThreadSelector:@selector(watch:) toTarget:watchdog withObject:nil];
}
