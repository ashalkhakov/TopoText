// SimpleNotes on iOS: a folder's notes as cards (View as Gallery, as Apple
// Notes has it), and every image and file in the notes (View Attachments).
// Collection views; their pictures from SNThumbnails, made as they show.

#pragma once
#import <UIKit/UIKit.h>
#import "SNNotes.h"
#import "SNThumbnails.h"

NS_ASSUME_NONNULL_BEGIN

// The notes shown as cards, not a list (user defaults; NO: a list).
FOUNDATION_EXPORT NSString * const SNGalleryDefaultsKey;   // @"SNNotesAsGallery"

// A folder's notes (nil: all of them) or a tag's, as a list or as cards:
// as the user last chose (SNGalleryDefaultsKey).
FOUNDATION_EXPORT UIViewController *SNNotesControllerFor(SNNotes *notes, SNFolder *_Nullable folder, NSString *_Nullable tag);

@interface SNGalleryViewController : UICollectionViewController <SNThumbnailsDelegate, UICollectionViewDelegateFlowLayout>
- (instancetype)initWithNotes:(SNNotes *)notes folder:(nullable SNFolder *)folder;
- (instancetype)initWithNotes:(SNNotes *)notes tag:(NSString *)tag;
// The cards shown, their notes' titles, in order (headings as "## Today").
- (NSArray<NSString *> *)shownRows;
// View as List (its ... menu): the list in its place, and from now on.
- (IBAction)viewAsList:(nullable id)sender;
@end

@interface SNAttachmentsViewController : UICollectionViewController <SNThumbnailsDelegate, UICollectionViewDelegateFlowLayout>
- (instancetype)initWithNotes:(SNNotes *)notes;
// Photos (NO) or Files (YES): the control over it.
@property (nonatomic) BOOL showsFiles;
- (NSArray<SNAttachmentItem *> *)shownItems;
@end

NS_ASSUME_NONNULL_END
