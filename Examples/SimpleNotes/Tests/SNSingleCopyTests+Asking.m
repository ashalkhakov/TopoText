// On GNUstep: another copy started on a store asks the one holding it, by
// its message port, to show itself (SNSingleCopy.m). The two copies are two
// claims in this process.

#import "SNSingleCopyTests.h"
#import "SNSingleCopy.h"

@interface SNSingleCopyAsked : NSObject
@property (nonatomic) NSUInteger asked;
@end

@implementation SNSingleCopyAsked
/* What the copy holding the store is asked to do. */
- (void)showNotes:(id)sender {
    _asked++;
}
@end

@implementation SNSingleCopyTests (Asking)

- (void)testAnotherCopyAsksTheOneHoldingTheStoreToShowItself {
    NSURL *store = [NSURL fileURLWithPath:[self temporaryPath]];
    SNSingleCopyAsked *first = [[SNSingleCopyAsked alloc] init];
    XCTAssertTrue(SNHoldStore(store, first, @selector(showNotes:)));
    XCTAssertFalse(SNHoldStore(store, first, @selector(showNotes:)), @"held: the second does not open it");
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!first.asked && until.timeIntervalSinceNow > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    XCTAssertEqual(first.asked, 1u, @"the one holding it was asked to show itself");
}

@end
