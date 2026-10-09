#import "SNiOSControllers.h"
#import "SNPeersViewController.h"
#import "SNRichText.h"
#import "SNTableGrid.h"
#import "SNUndoTextView.h"
#import "SNModel.h"
#import "SNTransfer.h"
#import "SNTransferViewController.h"
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

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

/* Said, and OK. */
static void SNTell(UIViewController *c, NSString *title, NSString *message) {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
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
    NSArray<SNFolder *> *_folders;   /* the tree: each folder, then those in it */
    NSArray<NSString *> *_tags;
    /* The counts, read once a reload (by folder ID, by tag; All Notes'
       and Recently Deleted's under NSNull and @""), not as each cell is
       drawn. */
    NSDictionary *_counts;
    /* The server being signed in to, until it is (then the notes'). */
    SNSignIn *_signIn;
    SNPeers *_peers;
    /* Imports waiting for the one going (each with access to its file
       while it goes), and the export's zip, to save once written. */
    NSMutableArray<NSURL *> *_imports;
    NSURL *_importing;
    BOOL _scoped;
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
    /* A folder, or a smart folder (as Apple Notes' New Folder menu). */
    UIMenu *add = [UIMenu menuWithTitle:@"" children:@[
        [UIAction actionWithTitle:@"New Folder" image:[UIImage systemImageNamed:@"folder"] identifier:nil handler:^(UIAction *a) {
            [self newFolder:nil];
        }],
        [UIAction actionWithTitle:@"New Smart Folder" image:[UIImage systemImageNamed:@"gearshape"] identifier:nil handler:^(UIAction *a) {
            [self newSmartFolder:nil];
        }],
        /* Notes in and out as Markdown (SNTransfer.h). */
        [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[
            [UIAction actionWithTitle:@"Import Notes" image:[UIImage systemImageNamed:@"square.and.arrow.down"] identifier:nil handler:^(UIAction *a) {
                [self importNotes:nil];
            }],
            [UIAction actionWithTitle:@"Export All Notes" image:[UIImage systemImageNamed:@"square.and.arrow.up"] identifier:nil handler:^(UIAction *a) {
                [self exportAllNotes:nil];
            }] ]] ]];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"folder.badge.plus"] menu:add];
    self.navigationItem.leftBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"server.rack"] style:UIBarButtonItemStylePlain
                                        target:self action:@selector(server:)],
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"antenna.radiowaves.left.and.right"] style:UIBarButtonItemStylePlain
                                        target:self action:@selector(showDevicesNearby:)] ];
    SNAddRefresh(self, @selector(refresh:));
    [self reload];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.navigationController.toolbarHidden = NO;
    [self reload];
}

- (void)reload {
    _folders = _notes.folderTree;
    NSDictionary<NSString *, NSNumber *> *tagCounts = _notes.tagCounts;
    _tags = [tagCounts.allKeys sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
    NSMutableDictionary *counts = [tagCounts mutableCopy];
    for (SNFolder *f in _folders) counts[f.objectID] = @([_notes countOfNotesInFolder:f]);
    counts[[NSNull null]] = @([_notes countOfNotesInFolder:nil]);
    counts[@""] = @(_notes.countOfDeletedNotes);
    _counts = counts;
    [self.tableView reloadData];
    SNShowStatus(self, _notes);
}

- (void)changed:(NSNotification *)n {
    if (!_notes.syncing) [self.refreshControl endRefreshing];
    /* How far a sync is: the status alone (shown by SNShowStatus). */
    if ([n.userInfo[@"statusOnly"] boolValue]) {
        SNShowStatus(self, _notes);
        return;
    }
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

/* A folder, a zip or Markdown files, from Files. */
- (void)importNotes:(id)sender {
    NSArray *types = @[ UTTypeFolder, UTTypeZIP, UTTypeText, UTTypeHTML ];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:NO];
    picker.allowsMultipleSelection = YES;
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)picker didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (picker.documentPickerMode == UIDocumentPickerModeExportToService) return;
    if (!_imports) _imports = [NSMutableArray array];
    [_imports addObjectsFromArray:urls];
    if (!_importing) [self startNextImport];
}

/* One import at a time, in its sheet; the next when it is closed. */
- (void)startNextImport {
    if (!_imports.count) return;
    _importing = _imports.firstObject;
    [_imports removeObjectAtIndex:0];
    _scoped = [_importing startAccessingSecurityScopedResource];
    [self runTransfer:[SNTransfer importIntoNotes:_notes fromURL:_importing folder:nil]];
}

- (void)runTransfer:(SNTransfer *)transfer {
    SNTransferViewController *sheet = [[SNTransferViewController alloc] initWithTransfer:transfer];
    sheet.delegate = self;
    [self presentViewController:sheet animated:YES completion:nil];
    [transfer start];
}

- (void)transferViewControllerDidClose:(SNTransferViewController *)controller {
    SNTransfer *transfer = controller.transfer;
    [controller dismissViewControllerAnimated:YES completion:^{
        [self reload];
        if (transfer.import) {
            if (self->_scoped) [self->_importing stopAccessingSecurityScopedResource];
            self->_importing = nil;
            self->_scoped = NO;
            [self startNextImport];
        } else if (!transfer.error && !transfer.cancelled) {
            /* Written: saved where the user says, in Files. */
            UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[ transfer.URL ] asCopy:YES];
            picker.delegate = self;
            [self presentViewController:picker animated:YES completion:nil];
        }
    }];
}

/* Every note as Markdown, in a zip saved to Files. */
- (void)exportAllNotes:(id)sender {
    if (_importing) return;
    NSURL *zip = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:@"Notes.zip"];
    [self runTransfer:[SNTransfer exportOfNotes:_notes toURL:zip]];
}

- (void)newFolder:(id)sender {
    SNAsk(self, @"New Folder", @"Its name:", @"New Folder", ^(NSString *name) {
        if (name.length) [self->_notes addFolderNamed:name];
    });
}

- (SNSmartFolderViewController *)smartFolderEditorFor:(SNFolder *)folder {
    SNSmartFilter *filter = folder ? [_notes filterOfFolder:folder] : [[SNSmartFilter alloc] init];
    SNSmartFolderViewController *editor = [[SNSmartFolderViewController alloc] initWithName:folder.name ?: @"Smart Folder"
                                                                                      filter:filter ?: [[SNSmartFilter alloc] init]];
    editor.folder = folder;
    editor.delegate = self;
    return editor;
}

- (void)newSmartFolder:(id)sender {
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[self smartFolderEditorFor:nil]];
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)smartFolderViewControllerDidFinish:(SNSmartFolderViewController *)editor {
    SNFolder *f = editor.folder;
    if (f) {
        [_notes renameFolder:f to:editor.name];
        [_notes setFilter:editor.filter ofFolder:f];
    } else {
        [_notes addSmartFolderNamed:editor.name filter:editor.filter inFolder:nil];
    }
    [self dismissViewControllerAnimated:YES completion:nil];
    [self reload];
}

- (void)smartFolderViewControllerDidCancel:(SNSmartFolderViewController *)editor {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark devices nearby

- (SNPeers *)peers {
    if (_peers || !_peersDirectory) return _peers;
    NSError *error = nil;
    _peers = [[SNPeers alloc] initWithNotes:_notes directory:_peersDirectory error:&error];
    _peers.deviceName = [UIDevice currentDevice].name;
    if (!_peers) SNTell(self, @"Devices nearby cannot be synced with.", error.localizedDescription ?: @"");
    else if (_notes.serverRemote && !_peers.hasToken) [_peers fetchToken];
    return _peers;
}

- (IBAction)showDevicesNearby:(id)sender {
    SNPeers *peers = [self peers];
    if (!peers) return;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[[SNPeersViewController alloc] initWithPeers:peers]];
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)server:(id)sender {
    SNAsk(self, @"Server", @"The SimpleNotes server's address; empty for this device only.",
          _notes.serviceRoot.absoluteString ?: @"http://", ^(NSString *typed) {
        typed = [typed stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (typed.length && ![typed hasSuffix:@"/"]) typed = [typed stringByAppendingString:@"/"];
        NSURL *root = typed.length > 7 ? [NSURL URLWithString:typed] : nil;
        if (!root.host.length) {
            [self useServer:nil signIn:nil];
            return;
        }
        [self signInToServer:root];
    });
}

/* Signed in as the server asks, then synced with (SNSignIn). */
- (void)signInToServer:(NSURL *)root {
    [_signIn cancel];
    _signIn = [[SNSignIn alloc] initWithServiceRoot:root secrets:[[SNSecretStore alloc] init]];
    _signIn.delegate = self;
    [_signIn learn];
}

- (void)useServer:(NSURL *)root signIn:(SNSignIn *)signIn {
    if (root) [[NSUserDefaults standardUserDefaults] setObject:root.absoluteString forKey:SNServerDefaultsKey];
    else [[NSUserDefaults standardUserDefaults] removeObjectForKey:SNServerDefaultsKey];
    signIn.delegate = nil;
    _notes.configuration = signIn ? signIn.configuration : nil;
    _notes.serviceRoot = root;
    [_notes sync];
}

#pragma mark signing in

- (void)signInDidLearn:(SNSignIn *)signIn {
    if (signIn.signedIn) {
        [self useServer:signIn.serviceRoot signIn:signIn];
        return;
    }
    if (signIn.kind == SNSignInPassword) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Sign In" message:signIn.serviceRoot.host
                                                            preferredStyle:UIAlertControllerStyleAlert];
        [a addTextFieldWithConfigurationHandler:^(UITextField *f) {
            f.placeholder = @"User name";
            f.autocapitalizationType = UITextAutocapitalizationTypeNone;
        }];
        [a addTextFieldWithConfigurationHandler:^(UITextField *f) {
            f.placeholder = @"Password";
            f.secureTextEntry = YES;
        }];
        [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [a addAction:[UIAlertAction actionWithTitle:@"Sign In" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            [signIn signInWithUser:a.textFields[0].text ?: @"" password:a.textFields[1].text ?: @""];
        }]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }
    [signIn begin];
}

/* The code, and the provider's page to enter it on (opened in Safari). */
- (void)signIn:(SNSignIn *)signIn showCode:(NSString *)code page:(NSURL *)page completePage:(NSURL *)completePage {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Sign In"
        message:[NSString stringWithFormat:@"Open %@ and enter the code\n\n%@", page.host ?: page.absoluteString, code]
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *x) {
        [signIn cancel];
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Open Page" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [[UIApplication sharedApplication] openURL:completePage ?: page options:@{} completionHandler:nil];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)signInDidFinish:(SNSignIn *)signIn {
    if (self.presentedViewController) [self dismissViewControllerAnimated:YES completion:nil];
    [self useServer:signIn.serviceRoot signIn:signIn];
    if (signIn.userName.length) SNTell(self, @"Signed In", [NSString stringWithFormat:@"Signed in as %@.", signIn.userName]);
}

- (void)signIn:(SNSignIn *)signIn didFail:(NSError *)error {
    if (self.presentedViewController) [self dismissViewControllerAnimated:YES completion:nil];
    SNTell(self, @"Not Signed In", error.localizedDescription ?: @"");
}

/* All Notes; the folders, those in a folder under it; Recently Deleted,
   when it has notes; the tags. */
enum { SNAllSection, SNFoldersSection, SNDeletedSection, SNTagsSection };

- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 4; }

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)section {
    switch (section) {
    case SNAllSection: return 1;
    case SNFoldersSection: return (NSInteger)_folders.count;
    case SNDeletedSection: return _notes.countOfDeletedNotes ? 1 : 0;
    default: return (NSInteger)_tags.count;
    }
}

- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)section {
    if (section == SNFoldersSection && _folders.count) return @"Folders";
    if (section == SNTagsSection && _tags.count) return @"Tags";
    return nil;
}

/* A row: its name, its icon and how many notes, indented as deep as it is
   (the icon too). */
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [t dequeueReusableCellWithIdentifier:@"folder"]
        ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"folder"];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    UIListContentConfiguration *c = [UIListContentConfiguration valueCellConfiguration];
    NSUInteger count;
    NSInteger depth = 0;
    if (ip.section == SNDeletedSection) {
        c.text = @"Recently Deleted";
        c.image = [UIImage systemImageNamed:@"trash"];
        count = [_counts[@""] unsignedIntegerValue];
    } else if (ip.section == SNTagsSection) {
        NSString *tag = _tags[(NSUInteger)ip.row];
        c.text = [@"#" stringByAppendingString:tag];
        c.image = [UIImage systemImageNamed:@"number"];
        count = [_counts[tag] unsignedIntegerValue];
    } else {
        SNFolder *f = ip.section == SNFoldersSection ? _folders[(NSUInteger)ip.row] : nil;
        c.text = f ? (f.name.length ? f.name : @"Untitled") : @"All Notes";
        c.image = [UIImage systemImageNamed:!f ? @"tray.full" : [_notes isSmartFolder:f] ? @"gearshape" : @"folder"];
        count = [_counts[f ? (id)f.objectID : (id)[NSNull null]] unsignedIntegerValue];
        depth = f ? (NSInteger)[_notes depthOfFolder:f] : 0;
    }
    c.secondaryText = [NSString stringWithFormat:@"%lu", (unsigned long)count];
    cell.contentConfiguration = c;
    cell.indentationWidth = 20;
    cell.indentationLevel = depth;
    return cell;
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    UIViewController *next;
    if (ip.section == SNDeletedSection) next = [[SNNotesViewController alloc] initRecentlyDeletedWithNotes:_notes];
    else if (ip.section == SNTagsSection) next = [[SNNotesViewController alloc] initWithNotes:_notes tag:_tags[(NSUInteger)ip.row]];
    else next = [[SNNotesViewController alloc] initWithNotes:_notes folder:ip.section == SNFoldersSection ? _folders[(NSUInteger)ip.row] : nil];
    [self.navigationController pushViewController:next animated:YES];
}

/* A sheet of where a folder can go: the top, or a folder not in it. */
- (void)move:(SNFolder *)folder from:(UIView *)view {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Move “%@” to", folder.name ?: @""]
                                                                   message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Top Level" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [self->_notes moveFolder:folder toFolder:nil];
    }]];
    for (SNFolder *f in _notes.folderTree) {
        if (f == folder || [_notes folder:f isInFolder:folder] || [_notes isSmartFolder:f]) continue;
        NSString *indent = [@"" stringByPaddingToLength:[_notes depthOfFolder:f] * 3 withString:@" " startingAtIndex:0];
        [sheet addAction:[UIAlertAction actionWithTitle:[indent stringByAppendingString:f.name.length ? f.name : @"Untitled"]
                                                  style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            [self->_notes moveFolder:folder toFolder:f];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = view;
    sheet.popoverPresentationController.sourceRect = view.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)t trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section != SNFoldersSection) return nil;
    SNFolder *f = _folders[(NSUInteger)ip.row];
    UIContextualAction *delete = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"Delete"
        handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
            NSString *what = [self->_notes isSmartFolder:f] ? @"Its notes stay where they are." : [self->_notes foldersInFolder:f].count
                ? @"The folders in it are deleted too. Their notes go to Recently Deleted, where they can be recovered for 30 days."
                : @"Its notes go to Recently Deleted, where they can be recovered for 30 days.";
            SNConfirm(self, [NSString stringWithFormat:@"Delete “%@”?", f.name ?: @""], what, @"Delete", ^{
                [self->_notes deleteFolder:f];
            });
            done(YES);
        }];
    BOOL smart = [_notes isSmartFolder:f];
    UIContextualAction *rename = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:smart ? @"Edit" : @"Rename"
        handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
            if (smart) {
                UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[self smartFolderEditorFor:f]];
                [self presentViewController:nav animated:YES completion:nil];
            } else {
                SNAsk(self, @"Rename Folder", nil, f.name ?: @"", ^(NSString *name) {
                    if (name.length) [self->_notes renameFolder:f to:name];
                });
            }
            done(YES);
        }];
    UIContextualAction *move = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"Move"
        handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
            [self move:f from:[t cellForRowAtIndexPath:ip] ?: t];
            done(YES);
        }];
    move.backgroundColor = [UIColor systemIndigoColor];
    return [UISwipeActionsConfiguration configurationWithActions:@[ delete, rename, move ]];
}

@end

#pragma mark notes

@implementation SNNotesViewController {
    SNNotes *_notes;
    SNFolder *_folder;
    NSString *_tag;
    BOOL _deleted;
    NSArray<SNNoteGroup *> *_groups;
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

- (instancetype)initWithNotes:(SNNotes *)notes tag:(NSString *)tag {
    if ((self = [self initWithNotes:notes folder:nil])) {
        _tag = [tag copy];
        self.title = [@"#" stringByAppendingString:tag];
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
    if (_deleted) {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Delete All" style:UIBarButtonItemStylePlain
                                                                                 target:self action:@selector(deleteAll:)];
    } else {
        UIBarButtonItem *view = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] menu:nil];
        self.navigationItem.rightBarButtonItems = @[ [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCompose
                                                                                                  target:self action:@selector(newNote:)], view ];
    }
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
    NSString *search = _search.searchBar.text;
    if (_deleted) {
        NSArray *deleted = [_notes deletedNotesMatching:search];
        _groups = deleted.count ? @[ [[SNNoteGroup alloc] initWithTitle:nil notes:deleted] ] : @[];
        self.navigationItem.rightBarButtonItem.enabled = deleted.count > 0;
    } else {
        _groups = [_notes groupsOfNotes:_tag ? [_notes notesTagged:_tag matching:search] : [_notes notesInFolder:_folder matching:search]
                               sortedBy:[_notes sortOrderForFolder:_tag ? nil : _folder]];
        self.navigationItem.rightBarButtonItems.lastObject.menu = [self viewMenu];
    }
    [self.tableView reloadData];
    SNShowStatus(self, _notes);
}

/* Sort By and Group By Date: commands up the responder chain, to here. */
- (UIMenu *)viewMenu {
    SNSortOrder order = _notes.sortOrder;
    UICommand *group = [UICommand commandWithTitle:@"Group By Date" image:nil action:@selector(toggleGroupByDate:) propertyList:nil];
    group.state = _notes.groupsByDate ? UIMenuElementStateOn : UIMenuElementStateOff;
    if (order == SNSortByTitle) group.attributes = UIMenuElementAttributesDisabled;
    UIMenu *sortBy = [UIMenu menuWithTitle:@"Sort By" image:[UIImage systemImageNamed:@"arrow.up.arrow.down"] identifier:nil options:0 children:@[
        [self sortCommand:@"Date Edited" action:@selector(sortByDateEdited:) on:order == SNSortByDateEdited],
        [self sortCommand:@"Date Created" action:@selector(sortByDateCreated:) on:order == SNSortByDateCreated],
        [self sortCommand:@"Title" action:@selector(sortByTitle:) on:order == SNSortByTitle] ]];
    if (!_folder || _tag) return [UIMenu menuWithTitle:@"" children:@[ sortBy, group ]];
    /* The folder's own order, synced with it (Default: the device's). */
    NSNumber *own = [_notes sortOrderOfFolder:_folder];
    UIMenu *folderBy = [UIMenu menuWithTitle:@"Sort Folder By" image:[UIImage systemImageNamed:@"folder"] identifier:nil options:0 children:@[
        [self sortCommand:@"Default" action:@selector(sortFolderByDefault:) on:!own],
        [self sortCommand:@"Date Edited" action:@selector(sortFolderByDateEdited:) on:[own isEqual:@(SNSortByDateEdited)]],
        [self sortCommand:@"Date Created" action:@selector(sortFolderByDateCreated:) on:[own isEqual:@(SNSortByDateCreated)]],
        [self sortCommand:@"Title" action:@selector(sortFolderByTitle:) on:[own isEqual:@(SNSortByTitle)]] ]];
    return [UIMenu menuWithTitle:@"" children:@[ folderBy, sortBy, group ]];
}

- (UICommand *)sortCommand:(NSString *)title action:(SEL)action on:(BOOL)on {
    UICommand *c = [UICommand commandWithTitle:title image:nil action:action propertyList:nil];
    c.state = on ? UIMenuElementStateOn : UIMenuElementStateOff;
    return c;
}

- (NSArray<NSString *> *)shownRows {
    NSMutableArray *rows = [NSMutableArray array];
    for (SNNoteGroup *g in _groups) {
        if (g.title) [rows addObject:[@"## " stringByAppendingString:g.title]];
        for (SNNote *n in g.notes) [rows addObject:n.title ?: @""];
    }
    return rows;
}

- (IBAction)sortByDateEdited:(id)sender { _notes.sortOrder = SNSortByDateEdited; }
- (IBAction)sortByDateCreated:(id)sender { _notes.sortOrder = SNSortByDateCreated; }
- (IBAction)sortByTitle:(id)sender { _notes.sortOrder = SNSortByTitle; }
- (IBAction)toggleGroupByDate:(id)sender { _notes.groupsByDate = !_notes.groupsByDate; }
- (IBAction)sortFolderByDefault:(id)sender { if (_folder) [_notes setSortOrder:nil ofFolder:_folder]; }
- (IBAction)sortFolderByDateEdited:(id)sender { if (_folder) [_notes setSortOrder:@(SNSortByDateEdited) ofFolder:_folder]; }
- (IBAction)sortFolderByDateCreated:(id)sender { if (_folder) [_notes setSortOrder:@(SNSortByDateCreated) ofFolder:_folder]; }
- (IBAction)sortFolderByTitle:(id)sender { if (_folder) [_notes setSortOrder:@(SNSortByTitle) ofFolder:_folder]; }

- (SNNote *)noteAt:(NSIndexPath *)ip {
    return _groups[(NSUInteger)ip.section].notes[(NSUInteger)ip.row];
}

- (void)changed:(NSNotification *)n {
    if (!_notes.syncing) [self.refreshControl endRefreshing];
    /* How far a sync is: the status alone (shown by SNShowStatus). */
    if ([n.userInfo[@"statusOnly"] boolValue]) {
        SNShowStatus(self, _notes);
        return;
    }
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
    for (SNFolder *f in _notes.folderTree) {
        if ([_notes isSmartFolder:f]) continue;
        NSString *indent = [@"" stringByPaddingToLength:[_notes depthOfFolder:f] * 3 withString:@" " startingAtIndex:0];
        [sheet addAction:[UIAlertAction actionWithTitle:[indent stringByAppendingString:f.name.length ? f.name : @"Untitled"]
                                                  style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            [self->_notes moveNote:note toFolder:f];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = view;
    sheet.popoverPresentationController.sourceRect = view.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)newNote:(id)sender {
    SNNote *note = [_notes addNoteInFolder:_folder];
    [self.navigationController pushViewController:[[SNEditorViewController alloc] initWithNotes:_notes note:note] animated:YES];
}

/* A section a group: Pinned, Today, ... */
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t {
    return (NSInteger)_groups.count;
}

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_groups[(NSUInteger)section].notes.count;
}

- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)section {
    return _groups[(NSUInteger)section].title;
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [t dequeueReusableCellWithIdentifier:@"note"]
        ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"note"];
    SNNote *note = [self noteAt:ip];
    cell.textLabel.text = note.title ?: @"New Note";
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@  %@", note.deletedAt ? SNDaysLeftText(note) : SNDateText(note.edited), note.snippet];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.imageView.image = note.isPinned ? [UIImage systemImageNamed:@"pin.fill"] : nil;
    return cell;
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    SNNote *note = [self noteAt:ip];
    [self.navigationController pushViewController:[[SNEditorViewController alloc] initWithNotes:_notes note:note] animated:YES];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)t trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
    SNNote *note = [self noteAt:ip];
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

/* A note pressed and held: its link (simplenotes://note/<id>), to paste
   into another note as a link that opens it. */
- (UIContextMenuConfiguration *)tableView:(UITableView *)t contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)ip point:(CGPoint)point {
    SNNote *note = [self noteAt:ip];
    if (!note.id || note.deletedAt) return nil;
    NSString *link = SNLinkToNote(note.id).absoluteString;
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu *(NSArray *suggested) {
        return [UIMenu menuWithTitle:@"" children:@[ [UIAction actionWithTitle:@"Copy Link" image:[UIImage systemImageNamed:@"link"]
                                                                  identifier:nil handler:^(UIAction *a) {
            [UIPasteboard generalPasteboard].string = link;
        }] ]];
    }];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)t leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
    SNNote *note = [self noteAt:ip];
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
    /* The note's tables, each over its place in the text. */
    SNTableGrids *_grids;
    /* The file Quick Look shows. */
    NSURL *_previewed;
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
    /* Undo the binding's, by ids: it survives a sync's merge (SNUndoTextView). */
    UITextView *tv = [[SNUndoTextView alloc] initWithFrame:old.frame textContainer:container];
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
    _editor.delegate = self;
    _binding = [[SNTextBinding alloc] initWithTextView:_textView editor:_editor];
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
    _grids = [[SNTableGrids alloc] initWithBinding:_binding notes:_notes];
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
    /* An attachment can come after the text that has it. */
    [_binding refreshAttachments];
    BOOL deleted = _note.deletedAt != nil;
    _textView.editable = !deleted;
    /* A table's cells can have been typed into elsewhere. */
    [_grids reload];
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

/* Wider or narrower (turned, a split view, first laid out): images sized
   to it again, the tables laid out again. */
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [_binding textWidthMayHaveChanged];
    [_grids update];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.isMovingFromParentViewController) {
        [_grids removeAll];
        [_binding unbind];
        [_editor close];
    }
}

- (void)textViewDidChangeSelection:(UITextView *)tv {
    [_binding selectionDidChange];
}

/* From a table's cell into the note: the keyboard keeps the cell's bar
   unless told, once the change of first responder is done with, that the
   note's text view has one of its own. */
- (void)textViewDidBeginEditing:(UITextView *)tv {
    [self performSelector:@selector(showFormatBar) withObject:nil afterDelay:0];
}

- (void)showFormatBar {
    if (!_textView.isFirstResponder) return;
    _textView.inputAccessoryView = nil;
    [_textView reloadInputViews];
    _textView.inputAccessoryView = _formatBar;
    [_textView reloadInputViews];
}

/* What is selected linked, from the menu over it, as in Apple Notes. */
- (UIMenu *)textView:(UITextView *)tv editMenuForTextInRange:(NSRange)range suggestedActions:(NSArray<UIMenuElement *> *)suggested
    API_AVAILABLE(ios(16.0)) {
    if (!range.length || !tv.editable) return [UIMenu menuWithChildren:suggested];
    UICommand *link = [UICommand commandWithTitle:@"Add Link" image:[UIImage systemImageNamed:@"link"] action:@selector(addLink:) propertyList:nil];
    return [UIMenu menuWithChildren:[suggested arrayByAddingObject:link]];
}

- (IBAction)hideKeyboard:(id)sender {
    [self.view endEditing:YES];
}

/* Typing in lists, as Apple Notes has it (SNTextBinding). */
- (BOOL)textView:(UITextView *)tv shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text {
    return [_binding shouldChangeTextInRange:range replacementString:text];
}

- (void)textViewDidChange:(UITextView *)tv {
    [_binding textDidChange];
    /* The tables after what changed moved with it. */
    [_grids update];
}

#pragma mark the editor's delegate

/* What a sync brought into the note, into the text view. */
- (void)noteEditor:(SNNoteEditor *)editor didMergeEdits:(NSArray<TTEdit *> *)edits {
    [_binding applyEdits:edits];
    [_grids update];
}

- (void)noteEditorDidVanish:(SNNoteEditor *)editor {
    [self.navigationController popViewControllerAnimated:YES];
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
/* The link under a tap: a given one or one detected; nil for none. */
- (NSURL *)linkAt:(UIGestureRecognizer *)g {
    NSTextStorage *ts = _textView.textStorage;
    if (!ts.length) return nil;
    CGPoint p = [g locationInView:_textView];
    UIEdgeInsets inset = _textView.textContainerInset;
    p = CGPointMake(p.x - inset.left, p.y - inset.top);
    NSLayoutManager *lm = _textView.layoutManager;
    NSUInteger glyph = [lm glyphIndexForPoint:p inTextContainer:_textView.textContainer];
    CGRect box = [lm boundingRectForGlyphRange:NSMakeRange(glyph, 1) inTextContainer:_textView.textContainer];
    if (!CGRectContainsPoint(box, p)) return nil;
    NSUInteger at = [lm characterIndexForGlyphAtIndex:glyph];
    id link = at < ts.length ? [ts attribute:NSLinkAttributeName atIndex:at effectiveRange:NULL] : nil;
    return [link isKindOfClass:[NSURL class]] ? link : nil;
}

/* The file's card under a tap: its attachment's id; nil for none. */
- (NSString *)fileAt:(UIGestureRecognizer *)g {
    NSTextStorage *ts = _textView.textStorage;
    if (!ts.length) return nil;
    CGPoint p = [g locationInView:_textView];
    UIEdgeInsets inset = _textView.textContainerInset;
    p = CGPointMake(p.x - inset.left, p.y - inset.top);
    NSLayoutManager *lm = _textView.layoutManager;
    NSUInteger glyph = [lm glyphIndexForPoint:p inTextContainer:_textView.textContainer];
    CGRect box = [lm boundingRectForGlyphRange:NSMakeRange(glyph, 1) inTextContainer:_textView.textContainer];
    if (!CGRectContainsPoint(box, p)) return nil;
    NSString *attachmentID = [_binding attachmentIDAt:[lm characterIndexForGlyphAtIndex:glyph]];
    return [[_notes attachmentWithID:attachmentID].kind isEqual:SNAttachmentKindFile] ? attachmentID : nil;
}

/* Only a tap on a checkbox, a link or a file: the text view has the others. */
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    return [self checkboxAt:g] != NSNotFound || [self linkAt:g] != nil || [self fileAt:g] != nil;
}

/* A link to a note opens its editor; any other, in its own application. */
- (void)openLink:(NSURL *)url {
    NSString *noteID = SNNoteIDInLink(url);
    if (!noteID) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        return;
    }
    SNNote *note = [_notes noteWithID:noteID];
    if (note) [self.navigationController pushViewController:[[SNEditorViewController alloc] initWithNotes:_notes note:note] animated:YES];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return NO;
}

- (void)tapped:(UITapGestureRecognizer *)g {
    NSString *file = [self checkboxAt:g] == NSNotFound ? [self fileAt:g] : nil;
    if (file) {
        [self previewFileOfAttachment:file];
        return;
    }
    NSURL *link = [self checkboxAt:g] == NSNotFound ? [self linkAt:g] : nil;
    if (link) {
        [self openLink:link];
        return;
    }
    NSUInteger at = [self checkboxAt:g];
    if (at == NSNotFound || !_textView.editable) return;
    NSRange sel = _textView.selectedRange;
    [_binding toggleCheckedForParagraphsInRange:NSMakeRange(at, 0)];
    if (_notes.movesCheckedToBottom) [_binding moveCheckedToBottomOfChecklistAt:at];
    [self formatted:sel];
}

#pragma mark formatting

/* The format bar's menus: commands sent up the responder chain, to this
   controller (the text view is first responder). */
- (void)makeFormatMenus {
    /* A row of four, as Apple Notes' Aa has them. */
    UIMenu *traits = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[
        [UICommand commandWithTitle:@"Bold" image:[UIImage systemImageNamed:@"bold"] action:@selector(bold:) propertyList:nil],
        [UICommand commandWithTitle:@"Italic" image:[UIImage systemImageNamed:@"italic"] action:@selector(italic:) propertyList:nil],
        [UICommand commandWithTitle:@"Underline" image:[UIImage systemImageNamed:@"underline"] action:@selector(underline:) propertyList:nil],
        [UICommand commandWithTitle:@"Strikethrough" image:[UIImage systemImageNamed:@"strikethrough"] action:@selector(strikethrough:) propertyList:nil] ]];
    if (@available(iOS 16.0, *)) traits.preferredElementSize = UIMenuElementSizeSmall;
    _styleItem.menu = [UIMenu menuWithTitle:@"" children:@[
        [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[
            [UICommand commandWithTitle:@"Title" image:nil action:@selector(title:) propertyList:nil],
            [UICommand commandWithTitle:@"Heading" image:nil action:@selector(heading:) propertyList:nil],
            [UICommand commandWithTitle:@"Subheading" image:nil action:@selector(subheading:) propertyList:nil],
            [UICommand commandWithTitle:@"Body" image:nil action:@selector(body:) propertyList:nil],
            [UICommand commandWithTitle:@"Monostyled" image:nil action:@selector(mono:) propertyList:nil] ]],
        traits ]];
    _attachItem.menu = [UIMenu menuWithTitle:@"" children:@[
        [UICommand commandWithTitle:@"Choose Photo" image:[UIImage systemImageNamed:@"photo.on.rectangle"] action:@selector(attachPhoto:) propertyList:nil],
        [UICommand commandWithTitle:@"Attach File" image:[UIImage systemImageNamed:@"doc"] action:@selector(attachFile:) propertyList:nil],
        [UICommand commandWithTitle:@"Add Link" image:[UIImage systemImageNamed:@"link"] action:@selector(addLink:) propertyList:nil] ]];
    _listItem.menu = [UIMenu menuWithTitle:@"" children:@[
        [UICommand commandWithTitle:@"Bulleted List" image:[UIImage systemImageNamed:@"list.bullet"] action:@selector(bulletList:) propertyList:nil],
        [UICommand commandWithTitle:@"Dashed List" image:[UIImage systemImageNamed:@"list.dash"] action:@selector(dashList:) propertyList:nil],
        [UICommand commandWithTitle:@"Numbered List" image:[UIImage systemImageNamed:@"list.number"] action:@selector(numberList:) propertyList:nil],
        [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[
            [UICommand commandWithTitle:@"Move Checked to Bottom" image:[UIImage systemImageNamed:@"arrow.down.to.line"]
                                 action:@selector(moveCheckedToBottom:) propertyList:nil],
            [self keepCheckedCommand] ]],
        [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[
            [UICommand commandWithTitle:@"Increase Indentation" image:[UIImage systemImageNamed:@"increase.indent"] action:@selector(indent:) propertyList:nil],
            [UICommand commandWithTitle:@"Decrease Indentation" image:[UIImage systemImageNamed:@"decrease.indent"] action:@selector(outdent:) propertyList:nil] ]] ]];
}

- (UICommand *)keepCheckedCommand {
    UICommand *c = [UICommand commandWithTitle:@"Keep Checked at Bottom" image:nil action:@selector(toggleKeepCheckedAtBottom:) propertyList:nil];
    c.state = _notes.movesCheckedToBottom ? UIMenuElementStateOn : UIMenuElementStateOff;
    return c;
}

/* After the binding changed paragraphs: the selection as it was, typing
   as the text there, the markers drawn again. */
- (void)formatted:(NSRange)selection {
    _textView.selectedRange = selection;
    [_binding selectionDidChange];
    [_textView.layoutManager invalidateDisplayForCharacterRange:NSMakeRange(0, _textView.textStorage.length)];
    [_grids update];
}

/* What character formatting and links go on: a table's cell typed in, or
   else the note's text; and its binding. */
- (UITextView *)formattedTextView:(SNTextBinding **)binding {
    UITextView *cell = [_grids cellTypedIn];
    SNTextBinding *b = cell ? [_grids bindingOfCell:cell] : nil;
    *binding = b ?: _binding;
    return b ? cell : _textView;
}

/* On the selection; with none, on what is typed next. */
- (void)toggle:(NSString *)key {
    SNTextBinding *binding;
    UITextView *tv = [self formattedTextView:&binding];
    if (!tv.editable) return;
    NSRange r = tv.selectedRange;
    [binding toggle:key inRange:r];
    if (r.length) tv.selectedRange = r;
}

- (void)style:(NSString *)style {
    if (!_textView.editable) return;
    NSRange r = _textView.selectedRange;
    [_binding setStyle:style forParagraphsInRange:r];
    [self formatted:r];
}

- (void)list:(NSString *)list {
    if (!_textView.editable) return;
    NSRange r = _textView.selectedRange;
    [_binding toggleList:list forParagraphsInRange:r];
    [self formatted:r];
}

- (void)indentBy:(NSInteger)by {
    if (!_textView.editable) return;
    NSRange r = _textView.selectedRange;
    [_binding indentParagraphsInRange:r by:by];
    [self formatted:r];
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
- (NSString *)insertTableWithRows:(NSUInteger)rows columns:(NSUInteger)columns {
    if (!_textView.editable) return nil;
    NSRange r = _textView.selectedRange;
    NSString *made = [_binding insertTableWithRows:rows columns:columns inRange:r];
    _textView.selectedRange = NSMakeRange(r.location + 1, 0);
    [_binding selectionDidChange];
    [_grids update];
    return made;
}

/* Two rows, two columns, as Apple Notes' are, its first cell typed in. */
- (IBAction)addTable:(id)sender {
    NSString *made = [self insertTableWithRows:2 columns:2];
    [[_grids gridForAttachmentID:made] beginEditing];
}

- (SNTableGrid *)gridForAttachmentID:(NSString *)attachmentID {
    return [_grids gridForAttachmentID:attachmentID];
}

/* Photos into the note, at the insertion point (one pasted is one too). */
- (IBAction)attachPhoto:(id)sender {
    if (!_textView.editable) return;
    PHPickerConfiguration *config = [[PHPickerConfiguration alloc] init];
    config.filter = [PHPickerFilter imagesFilter];
    config.selectionLimit = 0;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    for (PHPickerResult *result in results)
        [result.itemProvider loadDataRepresentationForTypeIdentifier:@"public.image" completionHandler:^(NSData *data, NSError *error) {
            if (!data) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self insertImageData:data];
            });
        }];
}

- (IBAction)attachFile:(id)sender {
    if (!_textView.editable) return;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[ UTTypeItem ] asCopy:YES];
    picker.allowsMultipleSelection = YES;
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)picker didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    for (NSURL *url in urls) {
        NSData *data = [NSData dataWithContentsOfURL:url];
        NSRange r = _textView.selectedRange;
        if (data && [_binding insertImageData:data inRange:r]) {
            _textView.selectedRange = NSMakeRange(r.location + 1, 0);
            [_binding selectionDidChange];
            [_grids update];
            continue;
        }
        if (![self insertFileData:data name:url.lastPathComponent])
            SNTell(self, data.length > SNAttachmentMaxFileBytes ? @"Larger than 25 MB" : @"Not read",
                   [NSString stringWithFormat:@"“%@” was not attached.", url.lastPathComponent]);
    }
}

- (BOOL)insertFileData:(NSData *)data name:(NSString *)name {
    if (!data || !_textView.editable) return NO;
    NSRange r = _textView.selectedRange;
    if (![_binding insertFileData:data name:name inRange:r]) return NO;
    _textView.selectedRange = NSMakeRange(r.location + 1, 0);
    [_binding selectionDidChange];
    [_grids update];
    return YES;
}

- (BOOL)previewFileOfAttachment:(NSString *)attachmentID {
    SNAttachment *a = attachmentID ? [_notes attachmentWithID:attachmentID] : nil;
    _previewed = a ? [_notes fileURLOfAttachment:a] : nil;
    if (!_previewed) return NO;
    QLPreviewController *preview = [[QLPreviewController alloc] init];
    preview.dataSource = self;
    [self presentViewController:preview animated:YES completion:nil];
    return YES;
}

- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller {
    return _previewed ? 1 : 0;
}

- (id<QLPreviewItem>)previewController:(QLPreviewController *)controller previewItemAtIndex:(NSInteger)index {
    return _previewed;
}

- (void)insertImageData:(NSData *)data {
    NSRange r = _textView.selectedRange;
    if (![_binding insertImageData:data inRange:r]) return;
    _textView.selectedRange = NSMakeRange(r.location + 1, 0);
    [_binding selectionDidChange];
    [_grids update];
}

/* On the selection; with none, on the link the insertion point is in. */
- (IBAction)addLink:(id)sender {
    SNTextBinding *binding;
    UITextView *tv = [self formattedTextView:&binding];
    if (!tv.editable) return;
    NSRange range = tv.selectedRange;
    NSString *current = [binding linkAt:range.length ? range.location : (range.location ? range.location - 1 : 0)];
    if (!range.length && current && range.location)
        [tv.textStorage attribute:SNLinkAttributeName atIndex:range.location - 1 longestEffectiveRange:&range
                          inRange:NSMakeRange(0, tv.textStorage.length)];
    if (!range.length) return;
    NSRange chosen = range;
    SNAsk(self, @"Add Link", @"A web address, or a link to a note; empty: none.", current ?: @"https://", ^(NSString *link) {
        [binding setLink:[link isEqualToString:@"https://"] ? nil : link inRange:chosen];
        if (tv == self->_textView) [self formatted:chosen];
        else tv.selectedRange = chosen;
    });
}

- (IBAction)toggleChecked:(id)sender {
    if (!_textView.editable) return;
    NSRange r = _textView.selectedRange;
    [_binding toggleCheckedForParagraphsInRange:r];
    if (_notes.movesCheckedToBottom) [_binding moveCheckedToBottomOfChecklistAt:r.location];
    [self formatted:r];
}

- (IBAction)moveCheckedToBottom:(id)sender {
    if (!_textView.editable) return;
    NSRange r = _textView.selectedRange;
    [_binding moveCheckedToBottomOfChecklistAt:r.location];
    [self formatted:r];
}

- (IBAction)toggleKeepCheckedAtBottom:(id)sender {
    _notes.movesCheckedToBottom = !_notes.movesCheckedToBottom;
    [self makeFormatMenus];
    if (_notes.movesCheckedToBottom) [self moveCheckedToBottom:nil];
}
- (IBAction)indent:(id)sender { [self indentBy:1]; }
- (IBAction)outdent:(id)sender { [self indentBy:-1]; }

@end
