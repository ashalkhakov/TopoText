#import "SNNote.h"
#import "SNModel.h"
#import <TopoTextSync/TopoTextSync.h>

@implementation SNNote

- (TopoText *)text {
    return [self tt_textForKey:@"bodyText"];
}

- (void)setText:(TopoText *)text {
    [self tt_setText:text forKey:@"bodyText"];
    NSString *title = SNTitleOfBody(text.string);
    if (![self.title isEqualToString:title]) self.title = title;
}

- (BOOL)isPinned {
    return self.pinned.boolValue;
}

- (NSString *)snippet {
    return SNSnippetOfBody(self.body ?: @"");
}

@end
