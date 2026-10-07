#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/* TopoText, a rich text that merges: copies edited apart, on devices that are
   offline or on the other side of a server, become the same text again by
   exchanging what each has. Nothing is lost and nothing is asked of the user.

   The shape is Apple Notes' topotext. Every UTF-16 unit ever typed has an id,
   (replica, clock): the replica is who typed it, the clock a Lamport counter
   every edit ticks. A character is inserted after another one, its origin;
   characters typed in one go are a run, ids (replica, clock) to
   (replica, clock + length - 1), each after the one before it. Deleting a
   character tombstones it: it keeps its place, and so its id still anchors
   what others insert next to it.

   Order is RGA's. The children of a character, those inserted after it, come
   newest first by (clock, replica), so text typed at a place lands where the
   typist saw it, two people typing at one place get one run each and never
   interleave, and the order is the same whichever copy heard of what first.

   Attributes are registers on the character, not on a range, one per key, the
   last writer's standing: bold set here and italic there, at once, are both
   kept. A bold set on existing characters does not spread to a run inserted
   inside the span concurrently. That is the Notes race, kept on purpose: the
   inserted run keeps the attributes it was typed with.

   Values are property-list types: NSString, NSNumber, NSData, NSDate, and
   arrays and string-keyed dictionaries of them. NSNull removes a key. An
   editor maps its fonts and colours to such values and back.

   Not thread-safe: one queue at a time, as an NSMutableAttributedString. */

typedef uint64_t TTReplica; /* 0 is none: the document start, and birth registers */

FOUNDATION_EXPORT NSString * const TopoTextErrorDomain;
typedef NS_ENUM(NSInteger, TopoTextError) {
    TopoTextErrorCorrupt = 1,     /* not TopoText data, or damaged */
    TopoTextErrorFormat,          /* written by a newer TopoText */
    TopoTextErrorMissingHistory,  /* a delta made for a copy that had seen more than this one */
};

/* One character's id. */
@interface TTId : NSObject <NSCopying, NSSecureCoding>
@property (nonatomic, readonly) TTReplica replica;
@property (nonatomic, readonly) uint64_t clock;
+ (instancetype)idWithReplica:(TTReplica)replica clock:(uint64_t)clock;
- (NSString *)key; /* "replica:clock" */
@end

/* What a copy has seen: for each replica, the clock of its latest edit. */
@interface TTVersion : NSObject <NSCopying, NSSecureCoding>
+ (instancetype)version; /* nothing seen */
+ (nullable instancetype)versionWithData:(NSData *)data error:(NSError **)error;
- (NSData *)data;
- (NSArray<NSNumber *> *)replicas;
- (uint64_t)clockForReplica:(TTReplica)replica;
- (BOOL)includesVersion:(TTVersion *)other;
- (TTVersion *)versionByMergingVersion:(TTVersion *)other;
@end

typedef NS_ENUM(NSInteger, TTEditKind) {
    TTEditInsert,      /* string inserted at range.location, range.length long */
    TTEditDelete,      /* range removed */
    TTEditAttributes,  /* range's attributes are now attributes */
};

/* What a merge did to the visible text, in order: each one's range is in the
   text as the edits before it left it. An editor applies them one by one to
   its storage, and its selection and scroll position survive. */
@interface TTEdit : NSObject
@property (nonatomic, readonly) TTEditKind kind;
@property (nonatomic, readonly) NSRange range;
@property (nonatomic, readonly, copy, nullable) NSString *string;
@property (nonatomic, readonly, copy) NSDictionary<NSString *, id> *attributes;
- (void)applyToAttributedString:(NSMutableAttributedString *)string;
@end

@interface TopoText : NSObject <NSCopying>

/* Who this copy writes as. Two copies must never write as the same replica at
   once: their ids would collide. A replica per editing session, the default,
   is always safe. */
@property (nonatomic, readonly) TTReplica replica;
@property (nonatomic, readonly) uint64_t clock;

+ (TTReplica)randomReplica;
+ (instancetype)text; /* empty, a random replica */
+ (instancetype)textWithReplica:(TTReplica)replica; /* 0: a random one */
/* The whole state, as -data wrote it. */
+ (nullable instancetype)textWithData:(NSData *)data replica:(TTReplica)replica error:(NSError **)error;
/* A text holding string, inserted as one run whose id comes from the string
   alone: every copy seeded with the same string has the same run, and merges
   with the others as one text. To adopt plain text stored before TopoText. */
+ (instancetype)textSeededWithString:(NSString *)string replica:(TTReplica)replica;
/* The same text and replica: a copy writes as this one does. */
- (id)copyWithZone:(nullable NSZone *)zone;
- (TopoText *)copyWithReplica:(TTReplica)replica;

/* The whole state: canonical, so two copies that have seen the same edits
   write the same bytes, whatever order they heard of them in. */
- (NSData *)data;

#pragma mark Reading

- (NSString *)string;
- (NSUInteger)length;
- (NSAttributedString *)attributedString;
- (NSDictionary<NSString *, id> *)attributesAtIndex:(NSUInteger)index effectiveRange:(nullable NSRangePointer)range;
- (NSArray<NSDictionary *> *)attributeRuns; /* location, length, attributes */

#pragma mark Editing

/* Ranges are UTF-16, as NSString's. */
- (void)insertString:(NSString *)string atIndex:(NSUInteger)index attributes:(nullable NSDictionary<NSString *, id> *)attrs;
- (void)deleteCharactersInRange:(NSRange)range;
- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)string attributes:(nullable NSDictionary<NSString *, id> *)attrs;
/* These keys set (NSNull: removed), the others left as they are. */
- (void)addAttributes:(NSDictionary<NSString *, id> *)attrs range:(NSRange)range;
/* Exactly these, as NSMutableAttributedString's. */
- (void)setAttributes:(nullable NSDictionary<NSString *, id> *)attrs range:(NSRange)range;
- (void)removeAttribute:(NSString *)name range:(NSRange)range;
/* The text made equal to string by one replacement, of what lies between the
   common prefix and suffix; what is inserted takes the attributes before it. */
- (void)setString:(NSString *)string;
/* The same for an attributed string, and its attributes set where they differ. */
- (void)setAttributedString:(NSAttributedString *)string;

#pragma mark Positions

/* The id of the character before a visible index; nil before the first one.
   A cursor kept as an anchor stays put while others edit around it. */
- (nullable TTId *)anchorAtIndex:(NSUInteger)index;
/* Where an anchor is now; a deleted character's anchor is where it was.
   nil: 0. NSNotFound: an id this copy has never seen. */
- (NSUInteger)indexForAnchor:(nullable TTId *)anchor;

#pragma mark Merging

- (TTVersion *)version;
/* What a copy at version lacks, for it to apply. A delta since the empty
   version is the whole state, -data. */
- (NSData *)deltaSinceVersion:(TTVersion *)version;
/* A delta or a whole state, merged in. Applying one twice, or out of turn, is
   harmless; one made for a copy that had seen more than this one is refused,
   TopoTextErrorMissingHistory, and nothing changes. */
- (nullable NSArray<TTEdit *> *)applyData:(NSData *)data error:(NSError **)error;
/* Everything other has, merged in. */
- (NSArray<TTEdit *> *)mergeText:(TopoText *)other;
/* A new copy with both, writing as this one. */
- (TopoText *)mergedWith:(TopoText *)other;

@end

/* Paragraphs. A paragraph is the text up to and including a newline (\n),
   or the text after the last one. Formatting of a paragraph as a whole - a
   heading, a list item, whether a checklist item is checked - is set on
   every character of it, its newline too; and when they disagree (text was
   typed into it while it was changed elsewhere, two paragraphs were
   joined), its newline's stands: the last paragraph's, which has none, its
   first character's. So text typed into a line made a checklist item
   elsewhere ends up in the item, and an item's checked state is one
   register, the last writer's. Which keys are a paragraph's is the
   caller's to say. */
@interface TopoText (Paragraphs)
/* The paragraph holding index (index == length: the last one), its newline
   included. */
- (NSRange)paragraphRangeForIndex:(NSUInteger)index;
/* Every paragraph's range, in order; an empty last one included when the
   text ends with a newline (or is empty). */
- (NSArray<NSValue *> *)paragraphRanges;
/* The paragraph's attributes of these keys: its newline's, or for the last
   paragraph, its first character's. Empty for an empty last paragraph. */
- (NSDictionary<NSString *, id> *)paragraphAttributesAtIndex:(NSUInteger)index keys:(NSSet<NSString *> *)keys;
/* These keys set (NSNull: removed) on every character of each paragraph the
   range touches, newlines included: one edit. */
- (void)addParagraphAttributes:(NSDictionary<NSString *, id> *)attrs range:(NSRange)range;
@end

NS_ASSUME_NONNULL_END


