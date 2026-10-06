#import "SNiOSControllers.h"
#import "SNRichText.h"

NSString * const SNServerDefaultsKey = @"SNServer";

/* The pull to refresh of a table: a sync, ended when the notes say so. */
static void SNAddRefresh(UITableViewController *c, SEL action) {
    c.refreshControl = [[UIRefreshControl alloc] init];
    [c.refreshControl addTarget:c action:action forControlEvents:UIControlEventValueChanged];
}

/* What the last sync did, under the list. */
static void SNShowStatus(UIViewController *c, SNNotes *notes) {
    UILabel *label = [[UILabel alloc] init];
    label.text = notes.serviceRoot ? notes.status : @"On this device only";
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    label.textColor = [UIColor secondaryLabelColor];
    [label sizeToFit];
    UIBarButtonItem *flex = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    c.toolbarItems = @[ flex, [[UIBarButtonItem alloc] initWithCustomView:label], flex ];
}

static void SNAsk(UIViewController *c, NSString *title, NSString *message, NSString *initial, void (^done)(NSString *text)) {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f) {
        f.text = initial;
        f.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        done(a.textFields.firstObject.text ?: @"");
    }]];
    [c presentViewController:a animated:YES completion:nil];
}

#pragma mark folders

@implementation SNFoldersViewController {
    SNNotes *_notes;
    NSArray<SNFolder *> *_folders;
}

- (instancetype)initWithNotes:(SNNotes *)notes {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _notes = notes;
        self.title = @"Folders";
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(changed:) name:SNNotesDidChangeNotification object:notes];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"folder.badge.plus"]
                                                                              style:UIBarButtonItemStylePlain target:self action:@selector(newFolder:)];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"server.rack"]
                                                                             style:UIBarButtonItemStylePlain target:self action:@selector(server:)];
    SNAddRefresh(self, @selector(refresh:));
    [self reload];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.toolbarHidden = NO;
    [self reload];
}

- (void)reload {
    _folders = _notes.folders;
    [self.tableView reloadData];
    SNShowStatus(self, _notes);
}

- (void)changed:(NSNotification *)n {
    if (!_notes.syncing) [self.refreshControl endRefreshing];
    [self reload];
}

- (void)refresh:(id)sender {
    if (!_notes.serviceRoot) {
        [self.refreshControl endRefreshing];
        [self server:nil];
        return;
    }
    [_notes sync];
}

- (void)newFolder:(id)sender {
    SNAsk(self, @"New Folder", @"Its name:", @"New Folder", ^(NSString *name) {
        if (name.length) [self->_notes addFolderNamed:name];
    });
}

- (void)server:(id)sender {
    SNAsk(self, @"Server", @"The SimpleNotes server's address; empty for this device only.",
          _notes.serviceRoot.absoluteString ?: @"http://", ^(NSString *typed) {
        typed = [typed stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (typed.length && ![typed hasSuffix:@"/"]) typed = [typed stringByAppendingString:@"/"];
        NSURL *root = typed.length > 7 ? [NSURL URLWithString:typed] : nil;
        if (root.host.length) [[NSUserDefaults standardUserDefaults] setObject:root.absoluteString forKey:SNServerDefaultsKey];
        else [[NSUserDefaults standardUserDefaults] removeObjectForKey:SNServerDefaultsKey];
        self->_notes.serviceRoot = root.host.length ? root : nil;
        [self->_notes sync];
    });
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 2; }

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)section {
    return section ? (NSInteger)_folders.count : 1;
}

- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)section {
    return section && _folders.count ? @"Folders" : nil;
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [t dequeueReusableCellWithIdentifier:@"folder"]
        ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"folder"];
    SNFolder *f = ip.section ? _folders[(NSUInteger)ip.row] : nil;
    cell.textLabel.text = f ? (f.name.length ? f.name : @"Untitled") : @"All Notes";
    cell.imageView.image = [UIImage systemImageNamed:f ? @"folder" : @"tray.full"];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)[_notes countOfNotesInFolder:f]];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    SNFolder *f = ip.section ? _folders[(NSUInteger)ip.row] : nil;
    [self.navigationController pushViewController:[[SNNotesViewController alloc] initWithNotes:_notes folder:f] animated:YES];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)t trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
    if (!ip.section) return nil;
    SNFolder *f = _folders[(NSUInteger)ip.row];
    UIContextualAction *delete = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Delete"
        handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
            [self->_notes deleteFolder:f];
            done(YES);
        }];
    UIContextualAction *rename = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"Rename"
        handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
            SNAsk(self, @"Rename Folder", nil, f.name ?: @"", ^(NSString *name) {
                if (name.length) [self->_notes renameFolder:f to:name];
            });
            done(YES);
        }];
    return [UISwipeActionsConfiguration configurationWithActions:@[ delete, rename ]];
}

@end

#pragma mark notes

@implementation SNNotesViewController {
    SNNotes *_notes;
    SNFolder *_folder;
    NSArray<SNNote *> *_list;
    UISearchController *_search;
}

- (instancetype)initWithNotes:(SNNotes *)notes folder:(SNFolder *)folder {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        _notes = notes;
        _folder = folder;
        self.title = folder ? (folder.name.length ? folder.name : @"Untitled") : @"All Notes";
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(changed:) name:SNNotesDidChangeNotification object:notes];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCompose
                                                                                           target:self action:@selector(newNote:)];
    _search = [[UISearchController alloc] initWithSearchResultsController:nil];
    _search.searchResultsUpdater = self;
    _search.obscuresBackgroundDuringPresentation = NO;
    self.navigationItem.searchController = _search;
    self.definesPresentationContext = YES;
    SNAddRefresh(self, @selector(refresh:));
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.toolbarHidden = NO;
    [self reload];
}

- (void)reload {
    _list = [_notes notesInFolder:_folder matching:_search.searchBar.text];
    [self.tableView reloadData];
    SNShowStatus(self, _notes);
}

- (void)changed:(NSNotification *)n {
    if (!_notes.syncing) [self.refreshControl endRefreshing];
    if (_folder && (_folder.isDeleted || !_folder.managedObjectContext)) {
        [self.navigationController popToRootViewControllerAnimated:YES];
        return;
    }
    [self reload];
}

- (void)refresh:(id)sender {
    if (_notes.serviceRoot) [_notes sync];
    else [self.refreshControl endRefreshing];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)c {
    [self reload];
}

- (void)newNote:(id)sender {
    SNNote *note = [_notes addNoteInFolder:_folder];
    [self.navigationController pushViewController:[[SNEditorViewController alloc] initWithNotes:_notes note:note] animated:YES];
}

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_list.count;
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [t dequeueReusableCellWithIdentifier:@"note"]
        ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"note"];
    SNNote *note = _list[(NSUInteger)ip.row];
    cell.textLabel.text = note.title ?: @"New Note";
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@  %@", SNDateText(note.updated), note.snippet];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.imageView.image = note.isPinned ? [UIImage systemImageNamed:@"pin.fill"] : nil;
    return cell;
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    SNNote *note = _list[(NSUInteger)ip.row];
    [self.navigationController pushViewController:[[SNEditorViewController alloc] initWithNotes:_notes note:note] animated:YES];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)t trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
    SNNote *note = _list[(NSUInteger)ip.row];
    UIContextualAction *delete = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Delete"
        handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
            [self->_notes deleteNote:note];
            done(YES);
        }];
    return [UISwipeActionsConfiguration configurationWithActions:@[ delete ]];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)t leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
    SNNote *note = _list[(NSUInteger)ip.row];
    UIContextualAction *pin = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
        title:note.isPinned ? @"Unpin" : @"Pin"
        handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
            [self->_notes setNote:note pinned:!note.isPinned];
            done(YES);
        }];
    pin.backgroundColor = [UIColor systemOrangeColor];
    return [UISwipeActionsConfiguration configurationWithActions:@[ pin ]];
}

@end

#pragma mark the note

@implementation SNEditorViewController {
    SNNotes *_notes;
    SNNote *_note;
    SNNoteEditor *_editor;
    SNTextBinding *_binding;
}

- (instancetype)initWithNotes:(SNNotes *)notes note:(SNNote *)note {
    if ((self = [super initWithNibName:@"SNEditorViewController" bundle:nil])) {
        _notes = notes;
        _note = note;
        self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _editor = [_notes editorForNote:_note];
    _binding = [[SNTextBinding alloc] initWithStorage:_textView.textStorage editor:_editor];
    UITextView *tv = _textView;
    _binding.getSelection = ^NSRange { return tv.selectedRange; };
    _binding.setSelection = ^(NSRange r) { tv.selectedRange = r; };
    __weak SNEditorViewController *weak = self;
    _editor.didVanish = ^{ [weak.navigationController popViewControllerAnimated:YES]; };
    _textView.delegate = self;
    _textView.typingAttributes = [_binding typingAttributesAt:_textView.textStorage.length];
    _textView.textContainerInset = UIEdgeInsetsMake(12, 12, 12, 12);
    _textView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [_formatBar sizeToFit];
    _textView.inputAccessoryView = _formatBar;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.toolbarHidden = YES;
    if (!_textView.text.length) [_textView becomeFirstResponder];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.isMovingFromParentViewController) {
        [_binding unbind];
        [_editor close];
    }
}

- (void)textViewDidChangeSelection:(UITextView *)tv {
    if (!tv.selectedRange.length) tv.typingAttributes = [_binding typingAttributesAt:tv.selectedRange.location];
}

/* On the selection; with none, on what is typed next. */
- (void)toggle:(NSString *)key {
    NSRange r = _textView.selectedRange;
    if (!r.length) {
        NSMutableDictionary *t = [SNTextAttributes(_textView.typingAttributes) mutableCopy];
        if ([t[key] boolValue]) [t removeObjectForKey:key]; else t[key] = @YES;
        _textView.typingAttributes = SNViewAttributes(t);
        return;
    }
    [_binding toggle:key inRange:r];
    _textView.selectedRange = r;
}

- (void)style:(NSString *)style {
    NSRange r = _textView.selectedRange;
    [_binding setStyle:style forParagraphsInRange:r];
    _textView.selectedRange = r;
    _textView.typingAttributes = [_binding typingAttributesAt:NSMaxRange(r)];
}

- (IBAction)bold:(id)sender { [self toggle:SNBoldKey]; }
- (IBAction)italic:(id)sender { [self toggle:SNItalicKey]; }
- (IBAction)underline:(id)sender { [self toggle:SNUnderlineKey]; }
- (IBAction)strikethrough:(id)sender { [self toggle:SNStrikeKey]; }
- (IBAction)title:(id)sender { [self style:SNStyleTitle]; }
- (IBAction)heading:(id)sender { [self style:SNStyleHeading]; }
- (IBAction)body:(id)sender { [self style:nil]; }

@end
