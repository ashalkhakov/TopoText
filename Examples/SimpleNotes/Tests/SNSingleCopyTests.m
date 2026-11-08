// One SimpleNotes on a store (SNSingleCopy.h): the lock beside it taken
// once. On GNUstep, another copy's asking answered by the copy holding it
// too (SNSingleCopyTests+Asking.m).

#import "SNSingleCopyTests.h"
#import "SNSingleCopy.h"

@implementation SNSingleCopyTests

- (NSString *)temporaryPath {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:
                                       [NSString stringWithFormat:@"sn-copy-%@", [NSProcessInfo processInfo].globallyUniqueString]];
}

- (void)testAFileIsLockedOnce {
    NSString *path = [self temporaryPath];
    XCTAssertTrue(SNLockFileForLife(path));
    XCTAssertFalse(SNLockFileForLife(path), @"held: another open of it does not get it");
    XCTAssertTrue(SNLockFileForLife([self temporaryPath]), @"another store's: its own");
}

@end
