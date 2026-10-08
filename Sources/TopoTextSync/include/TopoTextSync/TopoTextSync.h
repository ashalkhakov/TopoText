#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#import <ODataSync/ODataSyncEngine.h>
#import <ODataSync/ODataSyncMerging.h>
#import <TopoText/TopoText.h>

NS_ASSUME_NONNULL_BEGIN

/* TopoText in an ODataSync store: a note's body edited on two devices, or on
   a device and at the service, while they could not reach each other, is
   merged when they sync, not settled for one side.

   The text is a Binary attribute that holds the TopoText's state (-data); a
   String attribute beside it may hold its plain text, for the service to
   filter and search by. Each says so in its userInfo:

     body       String
     bodyText   Binary   TopoText.text    YES
                         TopoText.string  body

   The entity is a both entity (ODataSync.direction both), and should keep
   version vectors (ODataSync.versions): then a version that already includes
   the other side's is taken as it is, and only edits made without knowing of
   each other meet the resolver.

     sync.resolver = [[TTSyncResolver alloc] init];

   The service and peers store the state like any binary property; the merge
   is the devices'. It is the same whichever side makes it, which is what a
   peer's conflict needs (ODataSyncConflict.withPeer). */

FOUNDATION_EXPORT NSString * const TTSyncTextKey;   /* @"TopoText.text": YES on the Binary attribute */
FOUNDATION_EXPORT NSString * const TTSyncStringKey; /* @"TopoText.string": the String attribute it is mirrored in */

/* A conflict's TopoText attributes merged, the rest left to the fallback. When
   the fallback defers and nothing else differs, the merge stands alone. */
@interface TTSyncResolver : NSObject <ODataSyncResolving>
- (instancetype)initWithFallback:(id<ODataSyncResolving>)fallback NS_DESIGNATED_INITIALIZER;
/* Falling back to ODataSyncMergeFields: what one side changed is taken from it. */
- (instancetype)init;
@property (nonatomic, readonly) id<ODataSyncResolving> fallback;
/* The entity's TopoText attributes, each with the String attribute it is
   mirrored in ("" for none). */
+ (NSDictionary<NSString *, NSString *> *)textAttributesOfEntity:(NSEntityDescription *)entity;
/* Two states merged: either nil (or NSNull, or not TopoText data) is none. */
+ (nullable TopoText *)mergeState:(nullable id)state withState:(nullable id)other;
@end

/* TopoText as a merged attribute (ODataSync's, docs/offline-sync.md 14 in
   ODataKit): the text's deltas move, not its state, and what every copy has
   seen deleted is collected. Declared on the Binary attribute, and
   registered on each engine (the device's, the service's):

     bodyText   Binary   ODataSync.merge  TopoText

     [engine setMerger:[[TTSyncMerger alloc] init] forName:TTSyncMergerName];

   It works on states and deltas as TopoText writes them (-data,
   -deltaSinceVersion:); versions are TTVersion's data. */
FOUNDATION_EXPORT NSString * const TTSyncMergerName; /* @"TopoText" */

@interface TTSyncMerger : NSObject <ODataSyncMerging>
/* After a merge: the attribute's plain-text copy (TopoText.string) set
   again. A subclass sets more of what is derived from the text. */
- (void)mergedAttribute:(NSAttributeDescription *)attribute ofObject:(NSManagedObject *)object;
@end

@interface NSManagedObject (TopoText)
/* The text a TopoText attribute holds, writing as a new replica: an editing
   session's copy. Empty when there is none; when there is none but its
   String attribute has text, that text seeded (+textSeededWithString:), so
   two devices that adopt the same plain text do not end up with it twice. */
- (TopoText *)tt_textForKey:(NSString *)key;
- (TopoText *)tt_textForKey:(NSString *)key replica:(TTReplica)replica;
/* The text's state stored, and its string in the String attribute; neither
   touched when it is what is there already. */
- (void)tt_setText:(TopoText *)text forKey:(NSString *)key;
/* What is stored merged into text, an editor's open copy (after a sync
   changed the object): the edits, for its storage. */
- (NSArray<TTEdit *> *)tt_mergeKey:(NSString *)key intoText:(TopoText *)text;
@end

NS_ASSUME_NONNULL_END
