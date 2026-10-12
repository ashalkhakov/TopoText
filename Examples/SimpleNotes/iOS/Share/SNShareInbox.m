// The inbox on iOS (SNShareInbox.h).

#import "SNShareInbox.h"

NSString * const SNShareAppGroup = @"group.io.github.ashalkhakov.SimpleNotes";

NSURL *SNShareAppGroupInbox(void) {
    NSURL *group = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:SNShareAppGroup];
    return group ? [group URLByAppendingPathComponent:@"Inbox" isDirectory:YES] : nil;
}
