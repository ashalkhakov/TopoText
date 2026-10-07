#import "SNResolver.h"
#import "SNModel.h"
#import "SNAttachment.h"
#import "SNSmartFilter.h"

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

/* A smart folder's rules changed on both sides: merged rule by rule
   (SNSmartFilter), not the whole of them the later side's. */
- (ODataSyncResolution *)resolveFilter:(ODataSyncConflict *)conflict resolution:(ODataSyncResolution *)r {
    if (r.kind != ODataSyncMerge || ![conflict.localChanges containsObject:@"filter"] || ![conflict.remoteChanges containsObject:@"filter"])
        return r;
    id b = conflict.base[@"filter"], l = conflict.local[@"filter"], m = conflict.remote[@"filter"];
    SNSmartFilter *base = [b isKindOfClass:[NSString class]] ? [SNSmartFilter filterWithString:b] : [[SNSmartFilter alloc] init];
    SNSmartFilter *local = [l isKindOfClass:[NSString class]] ? [SNSmartFilter filterWithString:l] : nil;
    SNSmartFilter *remote = [m isKindOfClass:[NSString class]] ? [SNSmartFilter filterWithString:m] : nil;
    if (!base || !local || !remote) return r;
    /* The later side, as last writer wins tells it: by the stamps, else
       (from a peer) by the rules themselves, the same whichever side asks. */
    id ls = conflict.local[@"modified"], rs = conflict.remote[@"modified"];
    NSComparisonResult order = [ls isKindOfClass:[NSString class]] && [rs isKindOfClass:[NSString class]] ? [ls compare:rs] : NSOrderedSame;
    if (order == NSOrderedSame && conflict.withPeer) order = [l compare:m];
    SNSmartFilter *merged = [SNSmartFilter filterMergingBase:base local:local remote:remote localLater:order == NSOrderedDescending];
    NSMutableDictionary *values = [r.values mutableCopy];
    values[@"filter"] = merged.string;
    return [ODataSyncResolution mergedValues:values];
}

- (ODataSyncResolution *)resolveConflict:(ODataSyncConflict *)conflict {
    ODataSyncResolution *r = [super resolveConflict:conflict];
    if ([conflict.entity.name isEqualToString:SNAttachmentEntity]) return [self resolveTable:conflict resolution:r];
    if ([conflict.entity.name isEqualToString:SNFolderEntity]) return [self resolveFilter:conflict resolution:r];
    if (r.kind != ODataSyncMerge || ![conflict.entity.name isEqualToString:SNNoteEntity]) return r;
    NSMutableDictionary *values = [r.values mutableCopy];
    NSString *body = values[@"body"];
    if ([body isKindOfClass:[NSString class]]) values[@"title"] = SNTitleOfBody(body);
    id a = conflict.local[@"edited"], b = conflict.remote[@"edited"];
    if ([a isKindOfClass:[NSDate class]] && [b isKindOfClass:[NSDate class]]) values[@"edited"] = [a laterDate:b];
    return [ODataSyncResolution mergedValues:values];
}

@end
