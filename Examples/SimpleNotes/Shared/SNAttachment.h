// What a note holds besides its text: an image (kind "image"), a table
// (kind "table", its data a TTTable's: cells, rows and columns that merge,
// as a note's text does), or a file (kind "file": a PDF, a document; its
// name, version 5 on, the file's). Its
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
FOUNDATION_EXPORT NSString * const SNAttachmentKindFile;    // @"file": any other (name: its file's)
FOUNDATION_EXPORT NSString * const SNTableType;             // @"application/x-topotext-table"

// A file is kept no larger than this (bytes): it syncs whole, as a note.
FOUNDATION_EXPORT const NSUInteger SNAttachmentMaxFileBytes;   // 25 MB
// A file's type (MIME) by its name's extension; application/octet-stream
// when not known.
FOUNDATION_EXPORT NSString *SNTypeOfFileNamed(NSString *name);
// What a file's card says under its name: its kind and size ("PDF · 1.2 MB").
FOUNDATION_EXPORT NSString *SNFileDescription(NSString *name, NSUInteger bytes);

@interface SNAttachment : NSManagedObject
@end

NS_ASSUME_NONNULL_END

#import "SNAttachment+CoreDataProperties.h"
