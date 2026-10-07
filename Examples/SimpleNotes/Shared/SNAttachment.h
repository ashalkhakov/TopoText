// What a note holds besides its text: an image (kind "image"), or a table
// (kind "table", its data a TTTable's: cells, rows and columns that merge,
// as a note's text does). Its
// properties are generated from the model as the target builds (Codegen:
// Category/Extension) into SNAttachment+CoreDataProperties.h; this is the
// class they extend. The note's text has one character for it (U+FFFC,
// its "attachment" attribute the attachment's id: SNRichText).

#pragma once
#import <CoreData/CoreData.h>

@class SNNote;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const SNAttachmentKindImage;   // @"image"
FOUNDATION_EXPORT NSString * const SNAttachmentKindTable;   // @"table"
FOUNDATION_EXPORT NSString * const SNTableType;             // @"application/x-topotext-table"

@interface SNAttachment : NSManagedObject
@end

NS_ASSUME_NONNULL_END

#import "SNAttachment+CoreDataProperties.h"
