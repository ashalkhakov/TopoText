// sn-check <service root> [model.momd]: SNRunCheck, as a tool (the
// AppKit app's --check, where there is no app).
#import "SNCheck.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            fprintf(stderr, "usage: sn-check <service root> [model.momd]\n");
            return 2;
        }
        NSURL *model = argc > 2 ? [NSURL fileURLWithPath:@(argv[2])] : nil;
        return SNRunCheck([NSURL URLWithString:@(argv[1])], model);
    }
}
