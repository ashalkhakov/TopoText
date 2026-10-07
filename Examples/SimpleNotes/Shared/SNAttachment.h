// What a note holds besides its text: an image (kind "image"). Its
// properties are generated from the model as the target builds (Codegen:
// Category/Extension) into SNAttachment+CoreDataProperties.h; this is the
// class they extend. The note's text has one character for it (U+FFFC,
// its "attachment" attribute the attachment's id: SNRichText).

#pragma once
#import <CoreData/CoreData.h>

@class SNNote;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const SNAttachmentKindImage;   // @"image"

@interface SNAttachment : NSManagedObject
@end

NS_ASSUME_NONNULL_END

#import "SNAttachment+CoreDataProperties.h"
