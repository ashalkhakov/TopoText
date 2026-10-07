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

static void SNConfirm(UIViewController *c, NSString *title, NSString *message, NSString *action, void (^done)(void)) {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:action style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) { done(); }]];
    [c presentViewController:a animated:YES completion:nil];
}

static NSString *SNDaysLeftText(SNNote *note) {
    NSInteger left = SNDaysLeft(note);
    return left == 1 ? @"1 day" : [NSString stringWithFormat:@"%ld days", (long)left];
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

/* All Notes; the folders; Recently Deleted, when it has notes. */
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 3; }

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)section {
    if (section == 2) return _notes.countOfDeletedNotes ? 1 : 0;
    return section ? (NSInteger)_folders.count : 1;
}

- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)section {
    return section && _folders.count ? @"Folders" : nil;
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [t dequeueReusableCellWithIdentifier:@"folder"]
        ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"folder"];
    if (ip.section == 2) {
        cell.textLabel.text = @"Recently Deleted";
        cell.imageView.image = [UIImage systemImageNamed:@"trash"];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)_notes.countOfDeletedNotes];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    SNFolder *f = ip.section ? _folders[(NSUInteger)ip.row] : nil;
    cell.textLabel.text = f ? (f.name.length ? f.name : @"Untitled") : @"All Notes";
    cell.imageView.image = [UIImage systemImageNamed:f ? @"folder" : @"tray.full"];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)[_notes countOfNotesInFolder:f]];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == 2) {
        [self.navigationController pushViewController:[[SNNotesViewController alloc] initRecentlyDeletedWithNotes:_notes] animated:YES];
        return;
    }
    SNFolder *f = ip.section ? _folders[(NSUInteger)ip.row] : nil;
    [self.navigationController pushViewController:[[SNNotesViewController alloc] initWithNotes:_notes folder:f] animated:YES];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)t trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section != 1) return nil;
    SNFolder *f = _folders[(NSUInteger)ip.row];
    UIContextualAction *delete = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Delete"
        handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
            SNConfirm(self, [NSString stringWithFormat:@"Delete “%@”?", f.name ?: @""],
                      @"Its notes go to Recently Deleted, where they can be recovered for 30 days.", @"Delete", ^{
                [self->_notes deleteFolder:f];
            });
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
    BOOL _deleted;
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

- (instancetype)initRecentlyDeletedWithNotes:(SNNotes *)notes {
    if ((self = [self initWithNotes:notes folder:nil])) {
        _deleted = YES;
        self.title = @"Recently Deleted";
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = _deleted
        ? [[UIBarButtonItem alloc] initWithTitle:@"Delete All" style:UIBarButtonItemStylePlain target:self action:@selector(deleteAll:)]
        : [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCompose target:self action:@selector(newNote:)];
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
    _list = _deleted ? [_notes deletedNotesMatching:_search.searchBar.text] : [_notes notesInFolder:_folder matching:_search.searchBar.text];
    [self.tableView reloadData];
    SNShowStatus(self, _notes);
    self.navigationItem.rightBarButtonItem.enabled = !_deleted || _list.count;
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

- (void)deleteAll:(id)sender {
    SNConfirm(self, @"Delete every note in Recently Deleted?", @"They are deleted on every device, and cannot be recovered.", @"Delete All", ^{
        [self->_notes emptyRecentlyDeleted];
    });
}

/* A sheet of the folders (and none), for a note to go into. */
- (void)move:(SNNote *)note from:(UIView *)view {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Move to" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"No Folder" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [self->_notes moveNote:note toFolder:nil];
    }]];
    for (SNFolder *f in _notes.folders)
        [sheet addAction:[UIAlertAction actionWithTitle:f.name.length ? f.name : @"Untitled" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            [self->_notes moveNote:note toFolder:f];
        }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = view;
    sheet.popoverPresentationController.sourceRect = view.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
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
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@  %@", note.deletedAt ? SNDaysLeftText(note) : SNDateText(note.updated), note.snippet];
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
    if (_deleted) {
        UIContextualAction *gone = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Delete"
            handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
                SNConfirm(self, [NSString stringWithFormat:@"Delete “%@” immediately?", note.title ?: @"New Note"],
                          @"It is deleted on every device, and cannot be recovered.", @"Delete", ^{
                    [self->_notes deleteNoteImmediately:note];
                });
                done(YES);
            }];
        return [UISwipeActionsConfiguration configurationWithActions:@[ gone ]];
    }
    UIContextualAction *delete = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Delete"
        handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
            [self->_notes deleteNote:note];
            done(YES);
        }];
    UIContextualAction *move = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"Move"
        handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
            [self move:note from:[t cellForRowAtIndexPath:ip] ?: t];
            done(YES);
        }];
    move.backgroundColor = [UIColor systemIndigoColor];
    return [UISwipeActionsConfiguration configurationWithActions:@[ delete, move ]];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)t leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
    SNNote *note = _list[(NSUInteger)ip.row];
    if (_deleted) {
        UIContextualAction *recover = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"Recover"
            handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
                [self->_notes recoverNote:note];
                done(YES);
            }];
        recover.backgroundColor = [UIColor systemBlueColor];
        return [UISwipeActionsConfiguration configurationWithActions:@[ recover ]];
    }
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

/* The XIB's text view, made again on TextKit 1 with a layout manager that
   draws list markers (its own cannot be swapped for one). */
- (void)useListLayoutManager {
    UITextView *old = _textView;
    NSTextStorage *storage = [[NSTextStorage alloc] init];
    SNListLayoutManager *lm = [[SNListLayoutManager alloc] init];
    [storage addLayoutManager:lm];
    NSTextContainer *container = [[NSTextContainer alloc] initWithSize:CGSizeMake(old.bounds.size.width, CGFLOAT_MAX)];
    container.widthTracksTextView = YES;
    [lm addTextContainer:container];
    UITextView *tv = [[UITextView alloc] initWithFrame:old.frame textContainer:container];
    tv.translatesAutoresizingMaskIntoConstraints = NO;
    tv.backgroundColor = old.backgroundColor;
    tv.font = old.font;
    tv.alwaysBounceVertical = old.alwaysBounceVertical;
    tv.allowsEditingTextAttributes = old.allowsEditingTextAttributes;
    tv.autocapitalizationType = old.autocapitalizationType;
    UIView *parent = old.superview;
    [parent insertSubview:tv aboveSubview:old];
    UILayoutGuide *safe = parent.safeAreaLayoutGuide;
    [old removeFromSuperview];
    [NSLayoutConstraint activateConstraints:@[
        [tv.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor], [tv.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [tv.topAnchor constraintEqualToAnchor:safe.topAnchor], [tv.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor] ]];
    _textView = tv;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _editor = [_notes editorForNote:_note];
    [self useListLayoutManager];
    _binding = [[SNTextBinding alloc] initWithStorage:_textView.textStorage editor:_editor];
    UITextView *tv = _textView;
    _binding.getSelection = ^NSRange { return tv.selectedRange; };
    _binding.setSelection = ^(NSRange r) { tv.selectedRange = r; };
    _binding.getTypingAttributes = ^NSDictionary * { return tv.typingAttributes; };
    _binding.setTypingAttributes = ^(NSDictionary *attrs) {
        tv.typingAttributes = attrs;
        ((SNListLayoutManager *)tv.layoutManager).extraLineAttributes = attrs;
    };
    __weak SNEditorViewController *weak = self;
    _editor.didVanish = ^{ [weak.navigationController popViewControllerAnimated:YES]; };
    _textView.delegate = self;
    [_binding selectionDidChange];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)];
    tap.delegate = self;
    [_textView addGestureRecognizer:tap];
    [self makeFormatMenus];
    _textView.textContainerInset = UIEdgeInsetsMake(12, 12, 12, 12);
    _textView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [_formatBar sizeToFit];
    _textView.inputAccessoryView = _formatBar;
    [self followDeletion];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(followDeletion)
                                                 name:SNNotesDidChangeNotification object:_notes];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

/* In Recently Deleted (here, or by a sync), a note is read, not written:
   Recover first. */
- (void)followDeletion {
    BOOL deleted = _note.deletedAt != nil;
    _textView.editable = !deleted;
    self.navigationItem.rightBarButtonItem = deleted
        ? [[UIBarButtonItem alloc] initWithTitle:@"Recover" style:UIBarButtonItemStylePlain target:self action:@selector(recover:)]
        : nil;
}

- (void)recover:(id)sender {
    [_notes recoverNote:_note];
    [self followDeletion];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.toolbarHidden = YES;
    if (!_textView.text.length && !_note.deletedAt) [_textView becomeFirstResponder];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.isMovingFromParentViewController) {
        [_binding unbind];
        [_editor close];
    }
}

- (void)textViewDidChangeSelection:(UITextView *)tv {
    [_binding selectionDidChange];
}

/* Typing in lists, as Apple Notes has it (SNTextBinding). */
- (BOOL)textView:(UITextView *)tv shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text {
    return [_binding shouldChangeTextInRange:range replacementString:text];
}

- (void)textViewDidChange:(UITextView *)tv {
    [_binding textDidChange];
}

#pragma mark checkboxes

- (NSUInteger)checkboxAt:(UIGestureRecognizer *)g {
    if (!_textView.editable) return NSNotFound;
    CGPoint p = [g locationInView:_textView];
    UIEdgeInsets inset = _textView.textContainerInset;
    SNListLayoutManager *lm = (SNListLayoutManager *)_textView.layoutManager;
    if (![lm isKindOfClass:[SNListLayoutManager class]]) return NSNotFound;
    return [lm checkboxAtPoint:CGPointMake(p.x - inset.left, p.y - inset.top)];
}

/* Only a tap on a checkbox: the text view has the others. */
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    return [self checkboxAt:g] != NSNotFound;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return NO;
}

- (void)tapped:(UITapGestureRecognizer *)g {
    NSUInteger at = [self checkboxAt:g];
    if (at != NSNotFound) [self paragraphs:^(SNTextBinding *b, NSRange r) { [b toggleCheckedForParagraphsInRange:r]; } at:NSMakeRange(at, 0)];
}

#pragma mark formatting

- (void)makeFormatMenus {
    __weak SNEditorViewController *weak = self;
    UIAction *(^act)(NSString *, NSString *, SEL) = ^UIAction *(NSString *title, NSString *image, SEL sel) {
        return [UIAction actionWithTitle:title image:image ? [UIImage systemImageNamed:image] : nil identifier:nil
                                 handler:^(UIAction *a) {
                                     SNEditorViewController *me = weak;
                                     if (me) ((void (*)(id, SEL, id))[me methodForSelector:sel])(me, sel, nil);
                                 }];
    };
    _styleItem.menu = [UIMenu menuWithTitle:@"" children:@[
        act(@"Title", nil, @selector(title:)), act(@"Heading", nil, @selector(heading:)),
        act(@"Subheading", nil, @selector(subheading:)), act(@"Body", nil, @selector(body:)),
        act(@"Monostyled", nil, @selector(mono:)) ]];
    _listItem.menu = [UIMenu menuWithTitle:@"" children:@[
        act(@"Bulleted List", @"list.bullet", @selector(bulletList:)), act(@"Dashed List", @"list.dash", @selector(dashList:)),
        act(@"Numbered List", @"list.number", @selector(numberList:)),
        [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[
            act(@"Increase Indentation", @"increase.indent", @selector(indent:)),
            act(@"Decrease Indentation", @"decrease.indent", @selector(outdent:)) ]] ]];
}

/* A change of the paragraphs a range touches; the selection kept. */
- (void)paragraphs:(void (^)(SNTextBinding *binding, NSRange range))change at:(NSRange)r {
    if (!_textView.editable) return;
    NSRange sel = _textView.selectedRange;
    change(_binding, r);
    _textView.selectedRange = sel;
    [_binding selectionDidChange];
    [_textView.layoutManager invalidateDisplayForCharacterRange:NSMakeRange(0, _textView.textStorage.length)];
}

- (void)paragraphs:(void (^)(SNTextBinding *binding, NSRange range))change {
    [self paragraphs:change at:_textView.selectedRange];
}

/* On the selection; with none, on what is typed next. */
- (void)toggle:(NSString *)key {
    NSRange r = _textView.selectedRange;
    [_binding toggle:key inRange:r];
    if (r.length) _textView.selectedRange = r;
}

- (void)style:(NSString *)style {
    [self paragraphs:^(SNTextBinding *b, NSRange r) { [b setStyle:style forParagraphsInRange:r]; }];
}

- (void)list:(NSString *)list {
    [self paragraphs:^(SNTextBinding *b, NSRange r) { [b toggleList:list forParagraphsInRange:r]; }];
}

- (IBAction)bold:(id)sender { [self toggle:SNBoldKey]; }
- (IBAction)italic:(id)sender { [self toggle:SNItalicKey]; }
- (IBAction)underline:(id)sender { [self toggle:SNUnderlineKey]; }
- (IBAction)strikethrough:(id)sender { [self toggle:SNStrikeKey]; }
- (IBAction)title:(id)sender { [self style:SNStyleTitle]; }
- (IBAction)heading:(id)sender { [self style:SNStyleHeading]; }
- (IBAction)subheading:(id)sender { [self style:SNStyleSubheading]; }
- (IBAction)body:(id)sender { [self style:nil]; }
- (IBAction)mono:(id)sender { [self style:SNStyleMono]; }
- (IBAction)bulletList:(id)sender { [self list:SNListBullet]; }
- (IBAction)dashList:(id)sender { [self list:SNListDash]; }
- (IBAction)numberList:(id)sender { [self list:SNListNumber]; }
- (IBAction)checklist:(id)sender { [self list:SNListCheck]; }
- (IBAction)toggleChecked:(id)sender {
    [self paragraphs:^(SNTextBinding *b, NSRange r) { [b toggleCheckedForParagraphsInRange:r]; }];
}
- (IBAction)indent:(id)sender {
    [self paragraphs:^(SNTextBinding *b, NSRange r) { [b indentParagraphsInRange:r by:1]; }];
}
- (IBAction)outdent:(id)sender {
    [self paragraphs:^(SNTextBinding *b, NSRange r) { [b indentParagraphsInRange:r by:-1]; }];
}

@end
