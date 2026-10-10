#import "SNMemory.h"
#include <malloc.h>
#include <stdlib.h>

/* Given back once a minute: a list read again, a sync, a large note opened,
   each allocate and free a lot, and glibc keeps what is freed. */
@interface SNMemoryTrimmer : NSObject
@end

@implementation SNMemoryTrimmer
- (void)trim:(NSTimer *)timer {
    malloc_trim(0);
}
@end

void SNTuneMemory(void) {
    /* MALLOC_ARENA_MAX, when set, is the user's. */
    if (!getenv("MALLOC_ARENA_MAX")) mallopt(M_ARENA_MAX, 2);
    static SNMemoryTrimmer *trimmer;
    trimmer = [[SNMemoryTrimmer alloc] init];
    [NSTimer scheduledTimerWithTimeInterval:60 target:trimmer selector:@selector(trim:) userInfo:nil repeats:YES];
}
