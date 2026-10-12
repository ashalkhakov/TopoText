// The gallery and the attachments browser (SNGalleryViewController.h).

#import "SNGalleryViewController.h"
#import "SNiOSControllers.h"
#import "SNMenuAction.h"

NSString * const SNGalleryDefaultsKey = @"SNNotesAsGallery";

UIViewController *SNNotesControllerFor(SNNotes *notes, SNFolder *folder, NSString *tag) {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:SNGalleryDefaultsKey])
        return tag ? [[SNGalleryViewController alloc] initWithNotes:notes tag:tag] : [[SNGalleryViewController alloc] initWithNotes:notes folder:folder];
    return tag ? [[SNNotesViewController alloc] initWithNotes:notes tag:tag] : [[SNNotesViewController alloc] initWithNotes:notes folder:folder];
}

static NSString * const SNCardID = @"card", * const SNHeadingID = @"heading", * const SNFileID = @"file";

/* A note's card: its first picture, or its text; its title and date. Also
   an image's square, and a file's row (its icon, its name, its note). */
@interface SNCardCell : UICollectionViewCell
@property (nonatomic, readonly) UIImageView *picture;
@property (nonatomic, readonly) UILabel *preview, *titleLabel, *detailLabel;
@end

@implementation SNCardCell

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    UIView *box = [[UIView alloc] init];
    box.backgroundColor = [UIColor secondarySystemBackgroundColor];
    box.layer.cornerRadius = 10;
    box.clipsToBounds = YES;
    box.translatesAutoresizingMaskIntoConstraints = NO;
    _picture = [[UIImageView alloc] init];
    _picture.contentMode = UIViewContentModeScaleAspectFill;
    _picture.translatesAutoresizingMaskIntoConstraints = NO;
    _preview = [[UILabel alloc] init];
    _preview.numberOfLines = 0;
    _preview.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    _preview.textColor = [UIColor secondaryLabelColor];
    _preview.translatesAutoresizingMaskIntoConstraints = NO;
    [box addSubview:_preview];
    [box addSubview:_picture];
    _titleLabel = [[UILabel alloc] init];
    _titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _detailLabel = [[UILabel alloc] init];
    _detailLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    _detailLabel.textColor = [UIColor secondaryLabelColor];
    _detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:box];
    [self.contentView addSubview:_titleLabel];
    [self.contentView addSubview:_detailLabel];
    UIView *c = self.contentView;
    [NSLayoutConstraint activateConstraints:@[
        [box.topAnchor constraintEqualToAnchor:c.topAnchor], [box.leadingAnchor constraintEqualToAnchor:c.leadingAnchor],
        [box.trailingAnchor constraintEqualToAnchor:c.trailingAnchor],
        [_picture.topAnchor constraintEqualToAnchor:box.topAnchor], [_picture.bottomAnchor constraintEqualToAnchor:box.bottomAnchor],
        [_picture.leadingAnchor constraintEqualToAnchor:box.leadingAnchor], [_picture.trailingAnchor constraintEqualToAnchor:box.trailingAnchor],
        [_preview.topAnchor constraintEqualToAnchor:box.topAnchor constant:8], [_preview.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:8],
        [_preview.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-8],
        [_preview.bottomAnchor constraintLessThanOrEqualToAnchor:box.bottomAnchor constant:-8],
        [_titleLabel.topAnchor constraintEqualToAnchor:box.bottomAnchor constant:6],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:c.leadingAnchor], [_titleLabel.trailingAnchor constraintEqualToAnchor:c.trailingAnchor],
        [_detailLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:1],
        [_detailLabel.leadingAnchor constraintEqualToAnchor:c.leadingAnchor], [_detailLabel.trailingAnchor constraintEqualToAnchor:c.trailingAnchor],
        [_detailLabel.bottomAnchor constraintEqualToAnchor:c.bottomAnchor] ]];
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    _picture.image = nil;
    _preview.text = nil;
}

@end

/* A group's heading over its cards (Pinned, Today...). */
@interface SNHeadingView : UICollectionReusableView
@property (nonatomic, readonly) UILabel *label;
@end

@implementation SNHeadingView
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _label = [[UILabel alloc] init];
    _label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle3];
    _label.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_label];
    [NSLayoutConstraint activateConstraints:@[ [_label.leadingAnchor constraintEqualToAnchor:self.layoutMarginsGuide.leadingAnchor],
                                               [_label.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-4] ]];
    return self;
}
@end

/* A note's text but its title: the card's preview when it has no picture. */
static NSString *SNPreviewOf(SNNote *note) {
    NSString *body = note.body ?: @"";
    NSRange line = [body rangeOfString:@"\n"];
    NSString *rest = line.location == NSNotFound ? @"" : [body substringFromIndex:NSMaxRange(line)];
    rest = [rest stringByReplacingOccurrencesOfString:@"￼" withString:@""];
    return rest.length > 300 ? [rest substringToIndex:300] : rest;
}

static NSString *SNShortDate(NSDate *date) {
    if (!date) return @"";
    return [NSDateFormatter localizedStringFromDate:date dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterNoStyle];
}

/* How many cards across: as many as are at least min wide. */
static CGSize SNCardSize(UICollectionView *view, CGFloat min, CGFloat aspect, CGFloat below) {
    CGFloat inset = 16, gap = 12;
    CGFloat width = view.bounds.size.width - 2 * inset;
    NSUInteger across = MAX(2, (NSUInteger)((width + gap) / (min + gap)));
    CGFloat w = floor((width - gap * (across - 1)) / across);
    return CGSizeMake(w, w * aspect + below);
}

#pragma mark - the gallery

@implementation SNGalleryViewController {
    SNNotes *_notes;
    SNFolder *_folder;
    NSString *_tag;
    NSArray<SNNoteGroup *> *_groups;
    SNThumbnails *_thumbnails;
    /* Each note's first image's id (NSNull: none), found once. */
    NSMutableDictionary<NSManagedObjectID *, id> *_pictures;
}

- (instancetype)initWithNotes:(SNNotes *)notes folder:(SNFolder *)folder {
    UICollectionViewFlowLayout *flow = [[UICollectionViewFlowLayout alloc] init];
    flow.sectionInset = UIEdgeInsetsMake(8, 16, 16, 16);
    flow.minimumInteritemSpacing = 12;
    flow.minimumLineSpacing = 18;
    if (!(self = [super initWithCollectionViewLayout:flow])) return nil;
    _notes = notes;
    _folder = folder;
    _pictures = [NSMutableDictionary dictionary];
    _thumbnails = [[SNThumbnails alloc] initWithNotes:notes pixels:360];
    _thumbnails.delegate = self;
    self.title = folder.name ?: @"All Notes";
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(notesChanged:) name:SNNotesDidChangeNotification object:notes];
    return self;
}

- (instancetype)initWithNotes:(SNNotes *)notes tag:(NSString *)tag {
    if ((self = [self initWithNotes:notes folder:nil])) {
        _tag = [tag copy];
        self.title = [@"#" stringByAppendingString:tag];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.collectionView.backgroundColor = [UIColor systemBackgroundColor];
    self.collectionView.alwaysBounceVertical = YES;
    [self.collectionView registerClass:[SNCardCell class] forCellWithReuseIdentifier:SNCardID];
    [self.collectionView registerClass:[SNHeadingView class] forSupplementaryViewOfKind:UICollectionElementKindSectionHeader withReuseIdentifier:SNHeadingID];
    UIBarButtonItem *more = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] menu:
        [UIMenu menuWithTitle:@"" children:@[ SNMenuAction(@"View as List", [UIImage systemImageNamed:@"list.bullet"], @selector(viewAsList:), self) ]]];
    more.accessibilityLabel = @"More";
    self.navigationItem.rightBarButtonItems = @[ [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCompose
                                                                                              target:self action:@selector(newNote:)], more ];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.toolbarHidden = YES;
    [self reload];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [self.collectionViewLayout invalidateLayout];
}

- (void)reload {
    _groups = [_notes groupsInFolder:_tag ? nil : _folder tag:_tag matching:nil];
    [_pictures removeAllObjects];
    [_thumbnails forgetWanted];
    [self.collectionView reloadData];
}

- (void)notesChanged:(NSNotification *)n {
    if (self.viewIfLoaded.window) [self reload];
}

- (NSArray<NSString *> *)shownRows {
    NSMutableArray *rows = [NSMutableArray array];
    for (SNNoteGroup *g in _groups) {
        if (g.title) [rows addObject:[@"## " stringByAppendingString:g.title]];
        for (SNNote *n in g.notes) [rows addObject:n.title ?: @""];
    }
    return rows;
}

- (IBAction)viewAsList:(id)sender {
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:SNGalleryDefaultsKey];
    [self putInPlace:SNNotesControllerFor(_notes, _folder, _tag)];
}

/* Another view of the same notes, in this one's place. */
- (void)putInPlace:(UIViewController *)other {
    UINavigationController *nav = self.navigationController;
    NSMutableArray *stack = [nav.viewControllers mutableCopy];
    NSUInteger i = [stack indexOfObject:self];
    if (i == NSNotFound) return;
    stack[i] = other;
    [nav setViewControllers:stack animated:NO];
}

- (IBAction)newNote:(id)sender {
    SNNote *note = [_notes addNoteInFolder:[_notes isSmartFolder:_folder] ? nil : _folder];
    [self.navigationController pushViewController:[[SNEditorViewController alloc] initWithNotes:_notes note:note] animated:YES];
}

- (SNNote *)noteAt:(NSIndexPath *)ip {
    return _groups[(NSUInteger)ip.section].notes[(NSUInteger)ip.item];
}

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)cv {
    return (NSInteger)_groups.count;
}

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)section {
    return (NSInteger)_groups[(NSUInteger)section].notes.count;
}

- (CGSize)collectionView:(UICollectionView *)cv layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)ip {
    return SNCardSize(cv, 150, 1.0, 44);
}

- (CGSize)collectionView:(UICollectionView *)cv layout:(UICollectionViewLayout *)layout referenceSizeForHeaderInSection:(NSInteger)section {
    return _groups[(NSUInteger)section].title ? CGSizeMake(cv.bounds.size.width, 36) : CGSizeZero;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)cv viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)ip {
    SNHeadingView *h = [cv dequeueReusableSupplementaryViewOfKind:kind withReuseIdentifier:SNHeadingID forIndexPath:ip];
    h.label.text = _groups[(NSUInteger)ip.section].title;
    return h;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    SNCardCell *cell = [cv dequeueReusableCellWithReuseIdentifier:SNCardID forIndexPath:ip];
    SNNote *note = [self noteAt:ip];
    cell.titleLabel.text = note.title.length ? note.title : @"New Note";
    cell.detailLabel.text = SNShortDate(note.edited);
    id picture = _pictures[note.objectID];
    if (!picture) _pictures[note.objectID] = picture = [_notes firstImageIDOfNote:note] ?: (id)[NSNull null];
    cell.picture.image = [picture isKindOfClass:[NSString class]] ? [_thumbnails thumbnailForAttachmentID:picture] : nil;
    cell.preview.text = cell.picture.image ? nil : SNPreviewOf(note);
    return cell;
}

- (void)thumbnails:(SNThumbnails *)thumbnails didMakeThumbnailForAttachmentID:(NSString *)attachmentID {
    for (NSIndexPath *ip in self.collectionView.indexPathsForVisibleItems)
        if ([_pictures[[self noteAt:ip].objectID] isEqual:attachmentID]) [self.collectionView reloadItemsAtIndexPaths:@[ ip ]];
}

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    [self.navigationController pushViewController:[[SNEditorViewController alloc] initWithNotes:_notes note:[self noteAt:ip]] animated:YES];
}

@end

#pragma mark - the attachments browser

@implementation SNAttachmentsViewController {
    SNNotes *_notes;
    NSArray<SNAttachmentItem *> *_items;
    SNThumbnails *_thumbnails;
    UISegmentedControl *_kinds;
}

- (instancetype)initWithNotes:(SNNotes *)notes {
    UICollectionViewFlowLayout *flow = [[UICollectionViewFlowLayout alloc] init];
    flow.sectionInset = UIEdgeInsetsMake(12, 16, 16, 16);
    flow.minimumInteritemSpacing = 4;
    flow.minimumLineSpacing = 4;
    if (!(self = [super initWithCollectionViewLayout:flow])) return nil;
    _notes = notes;
    _thumbnails = [[SNThumbnails alloc] initWithNotes:notes pixels:300];
    _thumbnails.delegate = self;
    self.title = @"Attachments";
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.collectionView.backgroundColor = [UIColor systemBackgroundColor];
    self.collectionView.alwaysBounceVertical = YES;
    [self.collectionView registerClass:[SNCardCell class] forCellWithReuseIdentifier:SNCardID];
    [self.collectionView registerClass:[UICollectionViewListCell class] forCellWithReuseIdentifier:SNFileID];
    _kinds = [[UISegmentedControl alloc] initWithItems:@[ @"Photos", @"Files" ]];
    _kinds.selectedSegmentIndex = 0;
    [_kinds addTarget:self action:@selector(kindChosen:) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = _kinds;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.toolbarHidden = YES;
    [self reload];
}

- (void)kindChosen:(UISegmentedControl *)sender {
    self.showsFiles = sender.selectedSegmentIndex == 1;
}

- (void)setShowsFiles:(BOOL)files {
    _showsFiles = files;
    _kinds.selectedSegmentIndex = files ? 1 : 0;
    [self reload];
}

- (void)reload {
    _items = [_notes attachmentsOfKind:_showsFiles ? SNAttachmentKindFile : SNAttachmentKindImage];
    [_thumbnails forgetWanted];
    [self.collectionView reloadData];
}

- (NSArray<SNAttachmentItem *> *)shownItems {
    return _items;
}

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)section {
    return (NSInteger)_items.count;
}

- (CGSize)collectionView:(UICollectionView *)cv layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)ip {
    if (_showsFiles) return CGSizeMake(cv.bounds.size.width - 32, 56);
    CGSize card = SNCardSize(cv, 100, 1.0, 0);
    return CGSizeMake(card.width, card.width);
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    SNAttachmentItem *item = _items[(NSUInteger)ip.item];
    SNNote *note = (SNNote *)[_notes noteForObjectID:item.noteID];
    if (_showsFiles) {
        UICollectionViewListCell *cell = [cv dequeueReusableCellWithReuseIdentifier:SNFileID forIndexPath:ip];
        UIListContentConfiguration *c = [UIListContentConfiguration subtitleCellConfiguration];
        c.text = item.name.length ? item.name : @"File";
        c.secondaryText = [NSString stringWithFormat:@"%@ · %@", note.title.length ? note.title : @"New Note", SNShortDate(item.created)];
        c.image = [UIImage systemImageNamed:@"doc"];
        cell.contentConfiguration = c;
        return cell;
    }
    SNCardCell *cell = [cv dequeueReusableCellWithReuseIdentifier:SNCardID forIndexPath:ip];
    cell.titleLabel.text = nil;
    cell.detailLabel.text = nil;
    cell.picture.image = [_thumbnails thumbnailForAttachmentID:item.attachmentID];
    cell.accessibilityLabel = note.title;
    return cell;
}

- (void)thumbnails:(SNThumbnails *)thumbnails didMakeThumbnailForAttachmentID:(NSString *)attachmentID {
    if (_showsFiles) return;
    for (NSIndexPath *ip in self.collectionView.indexPathsForVisibleItems)
        if ([_items[(NSUInteger)ip.item].attachmentID isEqual:attachmentID]) [self.collectionView reloadItemsAtIndexPaths:@[ ip ]];
}

/* Its note, opened where it is. */
- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    SNAttachmentItem *item = _items[(NSUInteger)ip.item];
    SNNote *note = (SNNote *)[_notes noteForObjectID:item.noteID];
    if (!note) return;
    SNEditorViewController *editor = [[SNEditorViewController alloc] initWithNotes:_notes note:note];
    editor.attachmentToShow = item.attachmentID;
    [self.navigationController pushViewController:editor animated:YES];
}

@end
