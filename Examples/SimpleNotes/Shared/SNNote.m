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

- (NSString *)editedKey {
    return [self.entity.attributesByName objectForKey:@"edited"] ? @"edited" : @"updated";
}

- (NSDate *)lastEdited {
    NSString *key = [self editedKey];
    [self willAccessValueForKey:key];
    NSDate *d = [self primitiveValueForKey:key];
    [self didAccessValueForKey:key];
    return d;
}

- (void)setLastEdited:(NSDate *)date {
    NSString *key = [self editedKey];
    [self willChangeValueForKey:key];
    [self setPrimitiveValue:date forKey:key];
    [self didChangeValueForKey:key];
}

- (NSString *)snippet {
    return SNSnippetOfBody(self.body ?: @"");
}

@end
