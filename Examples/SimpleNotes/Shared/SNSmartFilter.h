// A smart folder's rules, as Apple Notes' smart folders have them: the
// notes with these tags, edited or made lately, with checklists, with
// attachments, pinned; all of the rules, or any. Kept in the folder's
// filter (Folder.filter, model version 5) as JSON, so it syncs as a
// folder's name does:
//
//   {"match": "all" | "any",
//    "tags": ["work", "family"], "tagsMatch": "any" | "all",
//    "editedWithin": 7, "createdWithin": 30,          (days)
//    "checklists": "any" | "ticked" | "unticked",
//    "attachments": true, "pinned": true}
//
// A rule not there is not asked. No rules: every note. Foundation only.

#pragma once
#import <Foundation/Foundation.h>

@class SNNote;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SNChecklistRule) {
    SNChecklistRuleNone,       // not asked
    SNChecklistRuleAny,        // has a checklist
    SNChecklistRuleTicked,     // has a ticked item
    SNChecklistRuleUnticked,   // has an item not ticked
};

@interface SNSmartFilter : NSObject <NSCopying>
// From a folder's filter; nil: none (not a smart folder), or not one.
+ (nullable instancetype)filterWithString:(nullable NSString *)string;
// As a folder keeps it.
- (NSString *)string;

// Any rule rather than all of them.
@property (nonatomic) BOOL matchesAny;
// Without #, lowercase; any of them rather than all.
@property (nonatomic, copy) NSArray<NSString *> *tags;
@property (nonatomic) BOOL anyTag;
// Edited, made, within so many days (0: not asked).
@property (nonatomic) NSInteger editedWithinDays;
@property (nonatomic) NSInteger createdWithinDays;
@property (nonatomic) SNChecklistRule checklists;
@property (nonatomic) BOOL withAttachments;
@property (nonatomic) BOOL pinnedOnly;

// No rules at all.
@property (nonatomic, readonly, getter=isEmpty) BOOL empty;
// Whether a note (not deleted) is in the folder, at now.
- (BOOL)matchesNote:(SNNote *)note now:(NSDate *)now;

// The rules two devices changed apart, from the ones they last agreed on
// (base): each rule as the side that changed it has it; one both changed,
// the later side's (localLater). Tags merge as a set: one added on either
// side is added, one taken off on either side is off. The same result on
// both devices (tags sorted), so the merge settles.
+ (SNSmartFilter *)filterMergingBase:(SNSmartFilter *)base local:(SNSmartFilter *)local remote:(SNSmartFilter *)remote
                          localLater:(BOOL)localLater;
@end

NS_ASSUME_NONNULL_END
