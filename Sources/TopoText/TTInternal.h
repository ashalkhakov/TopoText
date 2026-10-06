#import "TopoText.h"

NS_ASSUME_NONNULL_BEGIN

/* One key's register on a character. A birth register (clock 0, replica 0)
   is the value the character was typed with; any later set wins over it.
   An NSNull value: the key removed. Immutable, so runs share them. */
@interface TTRegister : NSObject {
@public
    id _value;
    uint64_t _clock;
    TTReplica _replica;
}
+ (instancetype)registerWithValue:(id)value clock:(uint64_t)clock replica:(TTReplica)replica;
@end

static inline BOOL TTRegisterWins(TTRegister *a, TTRegister *b) {
    return a->_clock > b->_clock || (a->_clock == b->_clock && a->_replica > b->_replica);
}

/* Characters (_r, _c) to (_r, _c + _len - 1), contiguous in document order:
   each after the one before it, the first after its origin (_or, _oc), or
   after the document start when _or is 0. A deleted run keeps its ids and
   loses its text and attributes. */
@interface TTRun : NSObject {
@public
    TTReplica _r;
    uint64_t _c;
    NSUInteger _len;
    TTReplica _or;
    uint64_t _oc;
    BOOL _deleted;
    NSString *_text;
    NSDictionary<NSString *, TTRegister *> *_attrs;
}
@end

/* What the wire carries: runs new to the receiver, in document order (so an
   origin always comes before what follows it); changes to characters it has,
   deletions and registers; and the sender's version. */
@interface TTPayload : NSObject
@property (nonatomic, strong) NSMutableArray<TTRun *> *inserts;
@property (nonatomic, strong) NSMutableArray<TTRun *> *updates;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *version;
/* Copied in, coalesced with the run before when they are one run. */
- (void)addInsert:(TTRun *)run;
- (void)addUpdate:(TTRun *)run;
@end

NSData *TTEncodePayload(TTPayload *payload);
TTPayload *_Nullable TTDecodePayload(NSData *data, NSError **error);

NSData *TTEncodeVersion(NSDictionary<NSNumber *, NSNumber *> *clocks);
NSDictionary<NSNumber *, NSNumber *> *_Nullable TTDecodeVersion(NSData *data, NSError **error);

BOOL TTValueIsCodable(id value);
NSError *TTMakeError(TopoTextError code, NSString *reason);

@interface TTVersion ()
- (instancetype)initWithClocks:(NSDictionary<NSNumber *, NSNumber *> *)clocks;
- (NSDictionary<NSNumber *, NSNumber *> *)clocks;
@end

@interface TTEdit ()
+ (instancetype)editWithKind:(TTEditKind)kind range:(NSRange)range string:(nullable NSString *)string
                  attributes:(nullable NSDictionary *)attributes;
@end

NS_ASSUME_NONNULL_END
