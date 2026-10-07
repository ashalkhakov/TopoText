// What a text binding (SNTextBinding) shows and writes: a TopoText, and
// whoever keeps it. A note's editor (SNNoteEditor), or a table's cell
// (SNTableGrid's). Foundation only: the device's code has it without a
// view system.

#pragma once
#import <Foundation/Foundation.h>
#import <TopoText/TopoText.h>

@class SNAttachment;

NS_ASSUME_NONNULL_BEGIN

@protocol SNTextSource <NSObject>
@property (nonatomic, readonly) TopoText *text;
// The user changed the text (the binding has written it): saved soon.
- (void)textDidChange;
@optional
// What a note has and a cell has not: attachments (images, tables).
- (NSString *)addTableWithRows:(NSUInteger)rows columns:(NSUInteger)columns;
- (NSString *)addImageData:(NSData *)data type:(NSString *)type width:(double)width height:(double)height;
- (NSString *)addFileData:(NSData *)data name:(NSString *)name type:(nullable NSString *)type;
- (nullable SNAttachment *)attachmentWithID:(NSString *)attachmentID;
@end

NS_ASSUME_NONNULL_END
