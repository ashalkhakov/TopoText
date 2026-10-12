// A note's version history on iOS (SNVersionsViewController.h).

#import "SNVersionsViewController.h"
#import "SNTextSystem.h"

static NSString *SNVersionDate(NSManagedObject *version) {
    NSDate *created = [version valueForKey:@"created"];
    return created ? [NSDateFormatter localizedStringFromDate:created dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterShortStyle] : @"";
}

@implementation SNVersionsViewController {
    SNNotes *_notes;
    SNNote *_note;
}

- (instancetype)initWithNotes:(SNNotes *)notes note:(SNNote *)note {
    if (!(self = [super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    _notes = notes;
    _note = note;
    _versions = @[];
    self.title = @"Version History";
    return self;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [_notes saveAll];
    _versions = [_notes versionsOfNote:_note];
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_versions.count;
}

- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)section {
    return _versions.count ? @"Kept by the server as the note is written, ten minutes at least apart; for 30 days, fewer the older they are."
                           : @"No versions yet. The server keeps one as the note is written, ten minutes at least after the last (none while offline).";
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [t dequeueReusableCellWithIdentifier:@"version"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"version"];
    UIListContentConfiguration *c = [UIListContentConfiguration valueCellConfiguration];
    c.text = SNVersionDate(_versions[(NSUInteger)ip.row]);
    cell.contentConfiguration = c;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [self.navigationController pushViewController:[[SNVersionViewController alloc] initWithNotes:_notes note:_note version:_versions[(NSUInteger)ip.row]]
                                         animated:YES];
}

@end

@implementation SNVersionViewController {
    SNNotes *_notes;
    SNNote *_note;
    NSManagedObject *_version;
}

- (instancetype)initWithNotes:(SNNotes *)notes note:(SNNote *)note version:(NSManagedObject *)version {
    if (!(self = [super initWithNibName:nil bundle:nil])) return nil;
    _notes = notes;
    _note = note;
    _version = version;
    self.title = SNVersionDate(version);
    return self;
}

- (void)loadView {
    _previewView = [[UITextView alloc] init];
    _previewView.editable = NO;
    _previewView.textContainerInset = UIEdgeInsetsMake(12, 12, 12, 12);
    self.view = _previewView;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    NSString *now = _note.text.string ?: @"", *then = [_notes textOfVersion:_version].string ?: @"";
    _previewView.attributedText = SNVersionPreview(now, then);
    UIBarButtonItem *restore = [[UIBarButtonItem alloc] initWithTitle:@"Restore" style:UIBarButtonItemStyleDone target:self action:@selector(restore:)];
    restore.enabled = ![now isEqualToString:then] && !_note.deletedAt;
    self.navigationItem.rightBarButtonItem = restore;
}

- (IBAction)restore:(id)sender {
    if (![_notes restoreNote:_note toVersion:_version]) return;
    /* Back to the note, as it is now. */
    UINavigationController *nav = self.navigationController;
    NSUInteger i = [nav.viewControllers indexOfObject:self];
    if (i >= 2) [nav popToViewController:nav.viewControllers[i - 2] animated:YES];
}

@end
