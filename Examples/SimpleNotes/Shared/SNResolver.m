#import "SNResolver.h"
#import "SNModel.h"

@implementation SNResolver

- (instancetype)init {
    /* Last writer wins: by the stamps, and a delete loses to a change. */
    id<ODataSyncResolving> later = [[ODataSyncLastWriterWins alloc] init];
    return [super initWithFallback:[[ODataSyncMergeFields alloc] initWithFallback:later]];
}

- (ODataSyncResolution *)resolveConflict:(ODataSyncConflict *)conflict {
    ODataSyncResolution *r = [super resolveConflict:conflict];
    if (r.kind != ODataSyncMerge || ![conflict.entity.name isEqualToString:SNNoteEntity]) return r;
    NSMutableDictionary *values = [r.values mutableCopy];
    NSString *body = values[@"body"];
    if ([body isKindOfClass:[NSString class]]) values[@"title"] = SNTitleOfBody(body);
    id a = conflict.local[@"updated"], b = conflict.remote[@"updated"];
    if ([a isKindOfClass:[NSDate class]] && [b isKindOfClass:[NSDate class]]) values[@"updated"] = [a laterDate:b];
    return [ODataSyncResolution mergedValues:values];
}

@end
