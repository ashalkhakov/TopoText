// The notes as cards (View > as Gallery: in the list's place, a card
// chosen opens its note as a row does), and every image and file in the
// notes (View > Show Attachments, a window of its own). Collection views
// with a flow layout; their pictures from SNThumbnails, made as they show.

#import <AppKit/AppKit.h>
#import "SNNotes.h"
#import "SNThumbnails.h"

NS_ASSUME_NONNULL_BEGIN

// The notes shown as cards, not a list (user defaults; NO: a list).
FOUNDATION_EXPORT NSString * const SNGalleryDefaultsKey;   // @"SNNotesAsGallery"

@class SNGallery, SNAttachmentsWindow;

@protocol SNGalleryDelegate <NSObject>
// A card chosen: its note to open.
- (void)gallery:(SNGallery *)gallery didChooseNote:(SNNote *)note;
@end

@interface SNGallery : NSObject <NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout, SNThumbnailsDelegate>
- (instancetype)initWithNotes:(SNNotes *)notes NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
// The cards' scroll view, to put where the list is.
@property (nonatomic, readonly) NSScrollView *view;
@property (nonatomic, weak, nullable) id<SNGalleryDelegate> delegate;
// The notes on the cards, in order (setting it shows them).
@property (nonatomic, copy) NSArray<SNNote *> *shownNotes;
// The card of a note shown chosen, or none.
- (void)chooseNote:(nullable SNNote *)note;
// A card's picture, if it has been made (for the self-test).
- (nullable NSImage *)pictureOfNote:(SNNote *)note;
@end

@protocol SNAttachmentsWindowDelegate <NSObject>
// An image or file chosen: its note shown, where it is.
- (void)attachmentsWindow:(SNAttachmentsWindow *)window didChooseAttachment:(SNAttachmentItem *)item;
@end

// AttachmentsWindow.xib: Photos and Files, and their grid.
@interface SNAttachmentsWindow : NSWindowController <NSCollectionViewDataSource, NSCollectionViewDelegate, SNThumbnailsDelegate>
- (instancetype)initWithNotes:(SNNotes *)notes;
@property (nonatomic, strong) IBOutlet NSSegmentedControl *kindControl;
@property (nonatomic, strong) IBOutlet NSScrollView *scrollView;
@property (nonatomic, weak, nullable) id<SNAttachmentsWindowDelegate> delegate;
// Photos (NO) or Files (YES).
@property (nonatomic) BOOL showsFiles;
- (IBAction)kindChosen:(nullable id)sender;
// Read again (the notes changed).
- (void)reload;
- (NSArray<SNAttachmentItem *> *)shownItems;
@end

NS_ASSUME_NONNULL_END
