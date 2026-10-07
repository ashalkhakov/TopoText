// A note. Its properties are generated from the model as the target builds
// (Codegen: Category/Extension), by Xcode's momc or FreeCoreData's, into
// SNNote+CoreDataProperties.h; this is the class they extend.

#pragma once
#import <CoreData/CoreData.h>
#import <TopoText/TopoText.h>

@class SNFolder, SNAttachment;

NS_ASSUME_NONNULL_BEGIN

@interface SNNote : NSManagedObject
// The body as a TopoText: a copy of its own, written as a new replica
// (an editing session's).
- (TopoText *)text;
// The text stored: its state, its plain text, its title.
- (void)setText:(TopoText *)text;
- (BOOL)isPinned;
// When it was last edited: edited, on a store of an older version of the
// model updated (read as stored: key-value coding's "updated" is
// NSManagedObject's -isUpdated on Apple's Core Data).
@property (nonatomic, nullable) NSDate *lastEdited;
// What a list shows under the title.
@property (nonatomic, readonly) NSString *snippet;
@end

NS_ASSUME_NONNULL_END

#import "SNNote+CoreDataProperties.h"
