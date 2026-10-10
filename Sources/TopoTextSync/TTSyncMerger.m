#import "TopoTextSync.h"

NSString * const TTSyncMergerName = @"TopoText";

@implementation TTSyncMerger

/* A state as a text, written as no one (it is only read, merged, collected:
   nothing it writes is an edit of its replica). Nil or empty: an empty text. */
static TopoText *TTTextOfState(NSData *state) {
    if (!state.length) return [TopoText textWithReplica:0];
    return [TopoText textWithData:state replica:0 error:NULL];
}

static TTVersion *TTVersionOfData(NSData *data) {
    return data.length ? [TTVersion versionWithData:data error:NULL] ?: [TTVersion version] : [TTVersion version];
}

- (NSData *)versionOfState:(NSData *)state {
    TopoText *text = TTTextOfState(state);
    return (text ? text.version : [TTVersion version]).data;
}

- (NSData *)deltaOfState:(NSData *)state sinceVersion:(NSData *)version {
    TopoText *text = TTTextOfState(state);
    /* No state it reads (a delta, say): no answer, which the caller fails
       on, not an empty delta, which it would take as nothing to send. */
    if (!text) return nil;
    TTVersion *since = TTVersionOfData(version);
    /* Nothing that copy lacks: an empty delta. */
    if ([since includesVersion:text.version]) return [NSData data];
    return [text deltaSinceVersion:since];
}

- (NSData *)stateByMerging:(NSData *)delta intoState:(NSData *)state error:(NSError **)error {
    TopoText *text = TTTextOfState(state);
    if (!text) {
        if (error) *error = [NSError errorWithDomain:TopoTextErrorDomain code:TopoTextErrorCorrupt
                                            userInfo:@{ NSLocalizedDescriptionKey: @"The stored text is not TopoText data" }];
        return nil;
    }
    if (![text applyData:delta error:error]) return nil;
    return text.data;
}

- (NSData *)versionMeeting:(NSData *)version andVersion:(NSData *)other {
    return [TTVersionOfData(version) versionByMeetingVersion:TTVersionOfData(other)].data;
}

- (NSData *)stateByCollecting:(NSData *)state seenBy:(NSData *)version {
    TopoText *text = state.length ? TTTextOfState(state) : nil;
    if (!text || ![text collectTombstonesSeenBy:TTVersionOfData(version)]) return state;
    return text.data;
}

/* The text's plain copy (TopoText.string) set again: the service filters and
   searches by it, and lists show it. A subclass sets more (a title). */
- (void)mergedAttribute:(NSAttributeDescription *)attribute ofObject:(NSManagedObject *)object {
    id name = attribute.userInfo[TTSyncStringKey];
    if (![name isKindOfClass:[NSString class]] || ![name length] || !object.entity.attributesByName[name]) return;
    NSString *string = [object tt_textForKey:attribute.name].string ?: @"";
    if (![[object valueForKey:name] isEqual:string]) [object setValue:string forKey:name];
}

@end
