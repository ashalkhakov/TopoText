// The gallery and the attachments window, on AppKit (SNGallery.h).

#import "SNGallery.h"

NSString * const SNGalleryDefaultsKey = @"SNNotesAsGallery";

static NSString * const SNCardID = @"card";

/* What a card has under its box: its title and date. */
static const CGFloat SNCardLines = 36;

/* A card's view: a rounded box behind its picture (or its note's text),
   its title and date under it (lines); outlined when chosen. */
@interface SNCardView : NSView
@property (nonatomic) BOOL chosen;
@property (nonatomic) BOOL lines;
@end

@implementation SNCardView

- (BOOL)isFlipped {
    return YES;
}

- (void)setChosen:(BOOL)chosen {
    _chosen = chosen;
    [self setNeedsDisplay:YES];
}

- (NSRect)boxRect {
    NSRect r = self.bounds;
    if (_lines) r.size.height = MAX(0, r.size.height - SNCardLines);
    return r;
}

- (void)drawRect:(NSRect)rect {
    NSBezierPath *box = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect([self boxRect], 0.5, 0.5) xRadius:8 yRadius:8];
    [[[NSColor grayColor] colorWithAlphaComponent:0.12] setFill];
    [box fill];
    if (_chosen) {
        [[NSColor selectedControlColor] setStroke];
        box.lineWidth = 3;
        [box stroke];
    }
}

@end

/* A card: a note's (its first picture, else its text; its title, its
   date), an image's (its picture), or a file's (its icon, its name, its
   note). */
@interface SNCardItem : NSCollectionViewItem
@property (nonatomic, strong) NSImageView *picture;
@property (nonatomic, strong) NSTextField *preview, *titleField, *detailField;
@property (nonatomic, copy, nullable) NSString *attachmentID;
@end

static NSTextField *SNLabel(NSFont *font, NSColor *color, BOOL wraps) {
    NSTextField *f = [[NSTextField alloc] initWithFrame:NSZeroRect];
    f.editable = NO;
    f.selectable = NO;
    f.bordered = NO;
    f.bezeled = NO;
    f.drawsBackground = NO;
    f.font = font;
    f.textColor = color;
    [f.cell setLineBreakMode:wraps ? NSLineBreakByWordWrapping : NSLineBreakByTruncatingTail];
    [f.cell setWraps:wraps];
    return f;
}

@implementation SNCardItem

- (void)loadView {
    SNCardView *v = [[SNCardView alloc] initWithFrame:NSMakeRect(0, 0, 150, 190)];
    _picture = [[NSImageView alloc] initWithFrame:NSZeroRect];
    _picture.imageScaling = NSImageScaleProportionallyUpOrDown;
    _preview = SNLabel([NSFont systemFontOfSize:10], [NSColor grayColor], YES);
    _titleField = SNLabel([NSFont boldSystemFontOfSize:12], [NSColor controlTextColor], NO);
    _detailField = SNLabel([NSFont systemFontOfSize:10], [NSColor grayColor], NO);
    for (NSView *sub in @[ _preview, _picture, _titleField, _detailField ]) [v addSubview:sub];
    self.view = v;
}

/* Laid out at a size, its parts following it as it changes (the layout
   sizes the card): the box, and under it the title and the date (none:
   the box the whole card). */
- (void)layOutAtSize:(NSSize)size lines:(BOOL)lines {
    SNCardView *v = (SNCardView *)self.view;
    [v setFrameSize:size];
    v.lines = lines;
    NSRect box = [v boxRect];
    _picture.frame = NSInsetRect(box, 4, 4);
    _picture.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _preview.frame = NSInsetRect(box, 8, 8);
    _preview.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _titleField.frame = NSMakeRect(0, size.height - SNCardLines + 3, size.width, 16);
    _detailField.frame = NSMakeRect(0, size.height - SNCardLines + 19, size.width, 14);
    _titleField.autoresizingMask = _detailField.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    _titleField.hidden = _detailField.hidden = !lines;
    [v setNeedsDisplay:YES];
}

- (void)setSelected:(BOOL)selected {
    [super setSelected:selected];
    ((SNCardView *)self.view).chosen = selected;
}

@end

static NSString *SNPreviewOf(SNNote *note) {
    NSString *body = note.body ?: @"";
    NSRange line = [body rangeOfString:@"\n"];
    NSString *rest = line.location == NSNotFound ? @"" : [body substringFromIndex:NSMaxRange(line)];
    rest = [rest stringByReplacingOccurrencesOfString:@"￼" withString:@""];
    return rest.length > 300 ? [rest substringToIndex:300] : rest;
}

static NSString *SNShortDate(NSDate *date) {
    if (!date) return @"";
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.dateStyle = NSDateFormatterShortStyle;
    f.timeStyle = NSDateFormatterNoStyle;
    return [f stringFromDate:date];
}

/* A note's card: as many across as are at least 130 wide, filling the
   row (AppKit's flow spreads what a row has left between its cards); its
   box square, its lines under it. */
static NSSize SNCardSize(NSCollectionView *cv) {
    CGFloat inset = 12, gap = 12;
    NSScrollView *scroll = cv.enclosingScrollView;
    CGFloat width = (scroll ? scroll.contentSize.width : cv.frame.size.width) - 2 * inset - 1;
    NSUInteger across = MAX(1, (NSUInteger)((width + gap) / (130 + gap)));
    CGFloat w = floor((width - gap * (across - 1)) / across);
    return NSMakeSize(w, w + SNCardLines);
}

/* A collection view in a scroll view, its cards size by flow. */
static NSCollectionView *SNGrid(NSScrollView *scroll, NSSize item, id owner) {
    NSCollectionViewFlowLayout *flow = [[NSCollectionViewFlowLayout alloc] init];
    flow.itemSize = item;
    flow.minimumInteritemSpacing = 12;
    flow.minimumLineSpacing = 14;
    flow.sectionInset = NSEdgeInsetsMake(12, 12, 12, 12);
    NSCollectionView *grid = [[NSCollectionView alloc] initWithFrame:NSMakeRect(0, 0, scroll.contentSize.width, scroll.contentSize.height)];
    grid.autoresizingMask = NSViewWidthSizable;
    grid.collectionViewLayout = flow;
    grid.selectable = YES;
    grid.backgroundColors = @[ [NSColor controlBackgroundColor] ];
    [grid registerClass:[SNCardItem class] forItemWithIdentifier:SNCardID];
    grid.delegate = owner;
    grid.dataSource = owner;
    scroll.documentView = grid;
    scroll.hasVerticalScroller = YES;
    return grid;
}

#pragma mark - the gallery

@implementation SNGallery {
    SNNotes *_notes;
    NSCollectionView *_grid;
    SNThumbnails *_thumbnails;
    /* Each note's first image's id (NSNull: none), found once. */
    NSMutableDictionary<NSManagedObjectID *, id> *_pictures;
    BOOL _choosing;
}

- (instancetype)initWithNotes:(SNNotes *)notes {
    if (!(self = [super init])) return nil;
    _notes = notes;
    _shownNotes = @[];
    _pictures = [NSMutableDictionary dictionary];
    _thumbnails = [[SNThumbnails alloc] initWithNotes:notes pixels:300];
    _thumbnails.delegate = self;
    _view = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 300, 400)];
    _view.borderType = NSNoBorder;
    _grid = SNGrid(_view, NSMakeSize(140, 176), self);
    return self;
}

- (void)setShownNotes:(NSArray<SNNote *> *)notes {
    _shownNotes = [notes copy];
    [_pictures removeAllObjects];
    [_thumbnails forgetWanted];
    [_grid reloadData];
}

- (void)chooseNote:(SNNote *)note {
    NSUInteger i = note ? [_shownNotes indexOfObject:note] : NSNotFound;
    _choosing = YES;
    _grid.selectionIndexPaths = i == NSNotFound ? [NSSet set] : [NSSet setWithObject:[NSIndexPath indexPathForItem:(NSInteger)i inSection:0]];
    _choosing = NO;
}

- (NSImage *)pictureOfNote:(SNNote *)note {
    id picture = _pictures[note.objectID];
    return [picture isKindOfClass:[NSString class]] ? [_thumbnails thumbnailForAttachmentID:picture] : nil;
}

- (NSInteger)collectionView:(NSCollectionView *)cv numberOfItemsInSection:(NSInteger)section {
    return (NSInteger)_shownNotes.count;
}

- (NSCollectionViewItem *)collectionView:(NSCollectionView *)cv itemForRepresentedObjectAtIndexPath:(NSIndexPath *)ip {
    SNCardItem *card = (SNCardItem *)[cv makeItemWithIdentifier:SNCardID forIndexPath:ip];
    SNNote *note = _shownNotes[(NSUInteger)ip.item];
    [card layOutAtSize:SNCardSize(cv) lines:YES];
    card.titleField.stringValue = note.title.length ? note.title : @"New Note";
    card.detailField.stringValue = SNShortDate(note.edited);
    id picture = _pictures[note.objectID];
    if (!picture) _pictures[note.objectID] = picture = [_notes firstImageIDOfNote:note] ?: (id)[NSNull null];
    card.attachmentID = [picture isKindOfClass:[NSString class]] ? picture : nil;
    card.picture.image = card.attachmentID ? [_thumbnails thumbnailForAttachmentID:card.attachmentID] : nil;
    card.preview.stringValue = card.picture.image ? @"" : SNPreviewOf(note);
    return card;
}

- (NSSize)collectionView:(NSCollectionView *)cv layout:(NSCollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)ip {
    return SNCardSize(cv);
}

- (void)thumbnails:(SNThumbnails *)thumbnails didMakeThumbnailForAttachmentID:(NSString *)attachmentID {
    for (SNCardItem *card in _grid.visibleItems) {
        if (![card.attachmentID isEqual:attachmentID]) continue;
        card.picture.image = [thumbnails thumbnailForAttachmentID:attachmentID];
        card.preview.stringValue = @"";
    }
}

- (void)collectionView:(NSCollectionView *)cv didSelectItemsAtIndexPaths:(NSSet<NSIndexPath *> *)paths {
    if (_choosing) return;
    NSIndexPath *ip = paths.anyObject;
    if (ip && (NSUInteger)ip.item < _shownNotes.count) [_delegate gallery:self didChooseNote:_shownNotes[(NSUInteger)ip.item]];
}

@end

#pragma mark - the attachments window

@implementation SNAttachmentsWindow {
    SNNotes *_notes;
    NSCollectionView *_grid;
    NSArray<SNAttachmentItem *> *_items;
    SNThumbnails *_thumbnails;
}

- (instancetype)initWithNotes:(SNNotes *)notes {
    if (!(self = [super initWithWindowNibName:@"AttachmentsWindow"])) return nil;
    _notes = notes;
    _items = @[];
    _thumbnails = [[SNThumbnails alloc] initWithNotes:notes pixels:240];
    _thumbnails.delegate = self;
    return self;
}

- (void)windowDidLoad {
    [super windowDidLoad];
    _grid = SNGrid(_scrollView, NSMakeSize(120, 120), self);
    [self reload];
}

- (IBAction)kindChosen:(id)sender {
    self.showsFiles = _kindControl.selectedSegment == 1;
}

- (void)setShowsFiles:(BOOL)files {
    _showsFiles = files;
    [self window];
    _kindControl.selectedSegment = files ? 1 : 0;
    ((NSCollectionViewFlowLayout *)_grid.collectionViewLayout).itemSize = files ? NSMakeSize(260, 44) : NSMakeSize(120, 120);
    [self reload];
}

- (void)reload {
    [self window];
    _items = [_notes attachmentsOfKind:_showsFiles ? SNAttachmentKindFile : SNAttachmentKindImage];
    [_thumbnails forgetWanted];
    [_grid reloadData];
}

- (NSArray<SNAttachmentItem *> *)shownItems {
    return _items;
}

- (NSInteger)collectionView:(NSCollectionView *)cv numberOfItemsInSection:(NSInteger)section {
    return (NSInteger)_items.count;
}

- (NSCollectionViewItem *)collectionView:(NSCollectionView *)cv itemForRepresentedObjectAtIndexPath:(NSIndexPath *)ip {
    SNCardItem *card = (SNCardItem *)[cv makeItemWithIdentifier:SNCardID forIndexPath:ip];
    SNAttachmentItem *item = _items[(NSUInteger)ip.item];
    SNNote *note = [_notes noteForObjectID:item.noteID];
    card.attachmentID = item.attachmentID;
    card.preview.stringValue = @"";
    if (_showsFiles) {
        /* A row: the file's icon, its name, its note. */
        [card layOutAtSize:NSMakeSize(260, 44) lines:NO];
        card.picture.frame = NSMakeRect(6, 6, 32, 32);
        card.picture.autoresizingMask = NSViewNotSizable;
        card.picture.image = [[NSWorkspace sharedWorkspace] iconForFileType:item.name.pathExtension.length ? item.name.pathExtension : @"txt"];
        card.titleField.frame = NSMakeRect(46, 6, 208, 16);
        card.detailField.frame = NSMakeRect(46, 23, 208, 14);
        card.titleField.hidden = card.detailField.hidden = NO;
        card.titleField.stringValue = item.name.length ? item.name : @"File";
        card.detailField.stringValue = [NSString stringWithFormat:@"%@ · %@", note.title.length ? note.title : @"New Note", SNShortDate(item.created)];
    } else {
        [card layOutAtSize:NSMakeSize(120, 120) lines:NO];
        card.picture.image = [_thumbnails thumbnailForAttachmentID:item.attachmentID];
        card.view.toolTip = note.title;
    }
    return card;
}

- (void)thumbnails:(SNThumbnails *)thumbnails didMakeThumbnailForAttachmentID:(NSString *)attachmentID {
    if (_showsFiles) return;
    for (SNCardItem *card in _grid.visibleItems)
        if ([card.attachmentID isEqual:attachmentID]) card.picture.image = [thumbnails thumbnailForAttachmentID:attachmentID];
}

- (void)collectionView:(NSCollectionView *)cv didSelectItemsAtIndexPaths:(NSSet<NSIndexPath *> *)paths {
    NSIndexPath *ip = paths.anyObject;
    if (ip && (NSUInteger)ip.item < _items.count) [_delegate attachmentsWindow:self didChooseAttachment:_items[(NSUInteger)ip.item]];
}

@end
