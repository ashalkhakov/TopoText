#import "SNResolver.h"
#import "SNModel.h"
#import "SNAttachment.h"

@implementation SNResolver

- (instancetype)init {
    /* Last writer wins: by the stamps, and a delete loses to a change. */
    id<ODataSyncResolving> later = [[ODataSyncLastWriterWins alloc] init];
    return [super initWithFallback:[[ODataSyncMergeFields alloc] initWithFallback:later]];
}

/* A table changed on both sides: both tables merged (TTTable), the rest
   as any attachment's. */
- (ODataSyncResolution *)resolveTable:(ODataSyncConflict *)conflict resolution:(ODataSyncResolution *)r {
    NSData *mine = conflict.local[@"data"], *theirs = conflict.remote[@"data"];
    if (![conflict.local[@"kind"] isEqual:SNAttachmentKindTable] || ![mine isKindOfClass:[NSData class]] ||
        ![theirs isKindOfClass:[NSData class]] || [mine isEqual:theirs])
        return r;
    TTTable *a = [TTTable tableWithData:mine replica:0 error:NULL], *b = [TTTable tableWithData:theirs replica:0 error:NULL];
    if (!a || !b) return r;
    NSMutableDictionary *values = [(r.kind == ODataSyncMerge && r.values ? r.values : conflict.local) mutableCopy];
    values[@"data"] = [a mergedWith:b].data;
    return [ODataSyncResolution mergedValues:values];
}

- (ODataSyncResolution *)resolveConflict:(ODataSyncConflict *)conflict {
    ODataSyncResolution *r = [super resolveConflict:conflict];
    if ([conflict.entity.name isEqualToString:SNAttachmentEntity]) return [self resolveTable:conflict resolution:r];
    if (r.kind != ODataSyncMerge || ![conflict.entity.name isEqualToString:SNNoteEntity]) return r;
    NSMutableDictionary *values = [r.values mutableCopy];
    NSString *body = values[@"body"];
    if ([body isKindOfClass:[NSString class]]) values[@"title"] = SNTitleOfBody(body);
    id a = conflict.local[@"edited"], b = conflict.remote[@"edited"];
    if ([a isKindOfClass:[NSDate class]] && [b isKindOfClass:[NSDate class]]) values[@"edited"] = [a laterDate:b];
    return [ODataSyncResolution mergedValues:values];
}

@end
