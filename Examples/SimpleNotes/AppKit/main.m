// SimpleNotes on AppKit (macOS and GNUstep). MainMenu.xib makes the rest.
//
//   SimpleNotes --check <server root>    two devices against a running
//                                         server, no window (SNCheck.h)
//   SimpleNotes --self-test <root>       the app driven from within
//                                         (SNSelfTest.h)
//   SimpleNotes -SNStore /tmp/b.sqlite   a second device on this machine

#import <AppKit/AppKit.h>
#import "SNCheck.h"
#import "SNSelfTest.h"
#import "SNMemory.h"

int main(int argc, const char *argv[]) {
    for (int i = 1; i + 1 < argc; i++)
        if (!strcmp(argv[i], "--check")) {
            @autoreleasepool {
                return SNRunCheck([NSURL URLWithString:@(argv[i + 1])], nil);
            }
        }
    for (int i = 1; i + 1 < argc; i++)
        if (!strcmp(argv[i], "--self-test")) SNSelfTestRoot = [NSURL URLWithString:@(argv[i + 1])];
    SNTuneMemory();
    return NSApplicationMain(argc, argv);
}
