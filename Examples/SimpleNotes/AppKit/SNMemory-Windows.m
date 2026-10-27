#import "SNMemory.h"
#include <malloc.h>

/* Given back once a minute: a list read again, a sync, a large note opened,
   each allocate and free a lot, and the C runtime's heap keeps what is
   freed. */
@interface SNMemoryTrimmer : NSObject
@end

@implementation SNMemoryTrimmer
- (void)trim:(NSTimer *)timer {
    _heapmin();
}
@end

void SNTuneMemory(void) {
    static SNMemoryTrimmer *trimmer;
    trimmer = [[SNMemoryTrimmer alloc] init];
    [NSTimer scheduledTimerWithTimeInterval:60 target:trimmer selector:@selector(trim:) userInfo:nil repeats:YES];
}
