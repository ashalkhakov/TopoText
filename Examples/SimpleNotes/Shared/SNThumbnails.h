// Small pictures of the notes' images, for the gallery's cards and the
// attachments browser: made as they are asked for, one a turn of the run
// loop (the last asked for first: what is on screen now), kept a while,
// the image's data let go of once its picture is made.

#pragma once
/* AppKit before Core Data: gnustep-gui's NSPredicateEditorRowTemplate.h
   declares NSAttributeType again when Core Data's came first. */
#import "SNTextSystem.h"
#import "SNNotes.h"

NS_ASSUME_NONNULL_BEGIN

@class SNThumbnails;

@protocol SNThumbnailsDelegate <NSObject>
// One asked for is made: shown where it is wanted.
- (void)thumbnails:(SNThumbnails *)thumbnails didMakeThumbnailForAttachmentID:(NSString *)attachmentID;
@end

@interface SNThumbnails : NSObject
// At most pixels across or down.
- (instancetype)initWithNotes:(SNNotes *)notes pixels:(NSUInteger)pixels NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@property (nonatomic, weak, nullable) id<SNThumbnailsDelegate> delegate;
// The picture, if made; else nil, and it is made (the delegate told). An
// attachment that is not an image, or has not come yet, has none.
- (nullable SNImage *)thumbnailForAttachmentID:(NSString *)attachmentID;
// Those asked for and not made yet, forgotten (the view changed).
- (void)forgetWanted;
@end

NS_ASSUME_NONNULL_END
