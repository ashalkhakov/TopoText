// Small pictures of the notes' images (SNThumbnails.h).

#import "SNThumbnails.h"

/* An image's data as a picture at most pixels across or down; nil: not an
   image. */
static SNImage *SNThumbnailOf(NSData *data, NSUInteger pixels) {
    double w = 0, h = 0;
    if (!data || !SNSystemImagePixels(data, &w, &h) || w < 1 || h < 1) return nil;
    double scale = MIN(1.0, pixels / MAX(w, h));
    NSData *small = scale < 1 ? SNSystemScaledImage(data, MAX(1, (NSUInteger)(w * scale)), MAX(1, (NSUInteger)(h * scale)), NO) : data;
    return small ? [[SNImage alloc] initWithData:small] : nil;
}

@implementation SNThumbnails {
    SNNotes *_notes;
    NSUInteger _pixels;
    NSCache *_made;              /* attachment id: its picture, or NSNull (none) */
    NSMutableArray *_wanted;     /* attachment ids, the last asked for last */
    BOOL _making;
}

- (instancetype)initWithNotes:(SNNotes *)notes pixels:(NSUInteger)pixels {
    if (!(self = [super init])) return nil;
    _notes = notes;
    _pixels = pixels;
    _made = [[NSCache alloc] init];
    _made.countLimit = 400;
    _wanted = [NSMutableArray array];
    return self;
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

- (SNImage *)thumbnailForAttachmentID:(NSString *)attachmentID {
    id made = [_made objectForKey:attachmentID];
    if (made) return [made isKindOfClass:[SNImage class]] ? made : nil;
    [_wanted removeObject:attachmentID];
    [_wanted addObject:attachmentID];
    if (!_making) {
        _making = YES;
        [self performSelector:@selector(makeNext) withObject:nil afterDelay:0];
    }
    return nil;
}

- (void)forgetWanted {
    [_wanted removeAllObjects];
}

/* The last asked for, made; then the next, a turn of the run loop later. */
- (void)makeNext {
    _making = NO;
    NSString *attachmentID = _wanted.lastObject;
    if (!attachmentID) return;
    [_wanted removeLastObject];
    SNAttachment *a = [_notes attachmentWithID:attachmentID];
    SNImage *picture = [a.kind isEqual:SNAttachmentKindImage] ? SNThumbnailOf(a.data, _pixels) : nil;
    [_notes letGoOfAttachment:a];
    /* One not come yet is asked for again next time; none, never. */
    if (picture || a.data) [_made setObject:picture ?: (id)[NSNull null] forKey:attachmentID];
    if (picture) [_delegate thumbnails:self didMakeThumbnailForAttachmentID:attachmentID];
    if (_wanted.count) {
        _making = YES;
        [self performSelector:@selector(makeNext) withObject:nil afterDelay:0];
    }
}

@end
