#import "SNiOSControllers.h"
#import "SNPeersViewController.h"
#import "SNRichText.h"
#import "SNTextSystem.h"
#import "SNTableGrid.h"
#import "SNUndoTextView.h"
#import "SNMenuAction.h"
#import "SNGalleryViewController.h"
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

/* The folders open in the list, by their ids (synced, so kept across
   launches): a folder with folders in it is closed until opened. */
static NSString * const SNOpenFoldersDefaultsKey = @"SNOpenFolders";

@implementation SNFoldersViewController {
    SNNotes *_notes;
    NSArray<SNFolder *> *_folders;   /* the rows: each folder, then those in it if it is open */
    /* Each folder's depth, and those with folders in it (by object ID). */
    NSDictionary<NSManagedObjectID *, NSNumber *> *_depths;
    NSSet<NSManagedObjectID *> *_parents;
    NSArray<NSString *> *_tags;
    /* The counts, read once a reload (by folder ID, by tag; All Notes'
       and Recently Deleted's under NSNull and @""), not as each cell is
       drawn. */
    NSDictionary *_counts;
    /* The server being signed in to, until it is (then the notes'). */
    ODataSignIn *_signIn;
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
            }] ]],
        /* Every image and file in the notes (Apple Notes' View Attachments). */
        SNMenuAction(@"View Attachments", [UIImage systemImageNamed:@"paperclip"], @selector(viewAttachments:), self) ]];
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
    NSArray<SNFolder *> *tree = _notes.folderTree;
    NSMutableDictionary *depths = [NSMutableDictionary dictionary];
    NSMutableSet *parents = [NSMutableSet set];
    for (SNFolder *f in tree) {
        SNFolder *parent = [_notes parentOfFolder:f];
        depths[f.objectID] = @(parent ? [depths[parent.objectID] integerValue] + 1 : 0);
        if (parent) [parents addObject:parent.objectID];
    }
    _depths = depths;
    _parents = parents;
    /* Shown: each folder whose folders above are all open. */
    NSSet *open = [NSSet setWithArray:[[NSUserDefaults standardUserDefaults] arrayForKey:SNOpenFoldersDefaultsKey] ?: @[]];
    NSMutableArray *shown = [NSMutableArray array];
    NSInteger hiddenBelow = NSIntegerMax;   /* the depth of a closed folder whose folders are being passed */
    for (SNFolder *f in tree) {
        NSInteger depth = [depths[f.objectID] integerValue];
        if (depth > hiddenBelow) continue;
        hiddenBelow = NSIntegerMax;
        [shown addObject:f];
        if ([parents containsObject:f.objectID] && ![open containsObject:f.id ?: @""]) hiddenBelow = depth;
    }
    _folders = shown;
    NSDictionary<NSString *, NSNumber *> *tagCounts = _notes.tagCounts;
    _tags = [tagCounts.allKeys sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
    NSMutableDictionary *counts = [tagCounts mutableCopy];
    for (SNFolder *f in tree) counts[f.objectID] = @([_notes countOfNotesInFolder:f]);
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

/* Signed in as the server asks, then synced with (ODataSignIn). */
- (void)signInToServer:(NSURL *)root {
    [_signIn cancel];
    _signIn = SNSignInTo(root, [[SNSecretStore alloc] init]);
    _signIn.delegate = self;
    [_signIn learn];
}

- (void)useServer:(NSURL *)root signIn:(ODataSignIn *)signIn {
    if (root) [[NSUserDefaults standardUserDefaults] setObject:root.absoluteString forKey:SNServerDefaultsKey];
    else [[NSUserDefaults standardUserDefaults] removeObjectForKey:SNServerDefaultsKey];
    signIn.delegate = nil;
    _notes.configuration = signIn ? signIn.configuration : nil;
    _notes.serviceRoot = root;
    [_notes sync];
}

#pragma mark signing in

- (void)signInDidLearn:(ODataSignIn *)signIn {
    if (signIn.signedIn) {
        [self useServer:signIn.serviceRoot signIn:signIn];
        return;
    }
    if (signIn.kind == ODataSignInPassword) {
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
- (void)signIn:(ODataSignIn *)signIn showCode:(NSString *)code page:(NSURL *)page completePage:(NSURL *)completePage {
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

- (void)signInDidFinish:(ODataSignIn *)signIn {
    if (self.presentedViewController) [self dismissViewControllerAnimated:YES completion:nil];
    [self useServer:signIn.serviceRoot signIn:signIn];
    if (signIn.userName.length) SNTell(self, @"Signed In", [NSString stringWithFormat:@"Signed in as %@.", signIn.userName]);
}

- (void)signIn:(ODataSignIn *)signIn didFail:(NSError *)error {
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
    cell.accessoryView = nil;
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
        depth = f ? [_depths[f.objectID] integerValue] : 0;
        /* Folders in it: a chevron to open or close it (the row opens its
           notes). */
        if (f && [_parents containsObject:f.objectID]) {
            BOOL open = [self isOpen:f];
            UIButton *chevron = [UIButton buttonWithType:UIButtonTypeSystem];
            [chevron setImage:[UIImage systemImageNamed:open ? @"chevron.down" : @"chevron.right"] forState:UIControlStateNormal];
            chevron.frame = CGRectMake(0, 0, 44, 44);
            chevron.tag = ip.row;
            chevron.accessibilityLabel = open ? @"Close" : @"Open";
            [chevron addTarget:self action:@selector(toggleFolder:) forControlEvents:UIControlEventTouchUpInside];
            cell.accessoryView = chevron;
        }
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
    else if (ip.section == SNTagsSection) next = SNNotesControllerFor(_notes, nil, _tags[(NSUInteger)ip.row]);
    else next = SNNotesControllerFor(_notes, ip.section == SNFoldersSection ? _folders[(NSUInteger)ip.row] : nil, nil);
    [self.navigationController pushViewController:next animated:YES];
}

- (IBAction)viewAttachments:(id)sender {
    [self.navigationController pushViewController:[[SNAttachmentsViewController alloc] initWithNotes:_notes] animated:YES];
}

- (BOOL)isOpen:(SNFolder *)folder {
    return [[[NSUserDefaults standardUserDefaults] arrayForKey:SNOpenFoldersDefaultsKey] containsObject:folder.id ?: @""];
}

- (void)setFolder:(SNFolder *)folder open:(BOOL)open {
    if (!folder.id.length) return;
    NSMutableArray *ids = [[[NSUserDefaults standardUserDefaults] arrayForKey:SNOpenFoldersDefaultsKey] mutableCopy] ?: [NSMutableArray array];
    [ids removeObject:folder.id];
    if (open) [ids addObject:folder.id];
    [[NSUserDefaults standardUserDefaults] setObject:ids forKey:SNOpenFoldersDefaultsKey];
    [self reload];
}

- (IBAction)toggleFolder:(UIButton *)sender {
    if (sender.tag < 0 || (NSUInteger)sender.tag >= _folders.count) return;
    SNFolder *f = _folders[(NSUInteger)sender.tag];
    [self setFolder:f open:![self isOpen:f]];
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
        /* Each note a fault, read when its cell is shown. */
        _groups = [_notes groupsInFolder:_tag ? nil : _folder tag:_tag matching:search];
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
    UIAction *gallery = SNMenuAction(@"View as Gallery", [UIImage systemImageNamed:@"square.grid.2x2"], @selector(viewAsGallery:), self);
    if (!_folder || _tag) return [UIMenu menuWithTitle:@"" children:@[ gallery, sortBy, group ]];
    /* The folder's own order, synced with it (Default: the device's). */
    NSNumber *own = [_notes sortOrderOfFolder:_folder];
    UIMenu *folderBy = [UIMenu menuWithTitle:@"Sort Folder By" image:[UIImage systemImageNamed:@"folder"] identifier:nil options:0 children:@[
        [self sortCommand:@"Default" action:@selector(sortFolderByDefault:) on:!own],
        [self sortCommand:@"Date Edited" action:@selector(sortFolderByDateEdited:) on:[own isEqual:@(SNSortByDateEdited)]],
        [self sortCommand:@"Date Created" action:@selector(sortFolderByDateCreated:) on:[own isEqual:@(SNSortByDateCreated)]],
        [self sortCommand:@"Title" action:@selector(sortFolderByTitle:) on:[own isEqual:@(SNSortByTitle)]] ]];
    return [UIMenu menuWithTitle:@"" children:@[ gallery, folderBy, sortBy, group ]];
}

- (IBAction)viewAsGallery:(id)sender {
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:SNGalleryDefaultsKey];
    UINavigationController *nav = self.navigationController;
    NSMutableArray *stack = [nav.viewControllers mutableCopy];
    NSUInteger i = [stack indexOfObject:self];
    if (i == NSNotFound) return;
    stack[i] = SNNotesControllerFor(_notes, _tag ? nil : _folder, _tag);
    [nav setViewControllers:stack animated:NO];
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

/* Searched a moment after the last key, not at each. */
- (void)updateSearchResultsForSearchController:(UISearchController *)c {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reload) object:nil];
    [self performSelector:@selector(reload) withObject:nil afterDelay:0.25];
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
    SNSystemShowChevrons(_textView);
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
    if (@available(iOS 16.0, *)) _textView.findInteractionEnabled = YES;
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
    NSMutableArray *items = [NSMutableArray arrayWithObject:[self noteMenuItem]];
    if (deleted) [items addObject:[[UIBarButtonItem alloc] initWithTitle:@"Recover" style:UIBarButtonItemStylePlain target:self action:@selector(recover:)]];
    self.navigationItem.rightBarButtonItems = items;
}

/* The note's ... menu (Apple Notes' too): Find in Note, Print, Export as
   PDF. */
- (UIBarButtonItem *)noteMenuItem {
    NSMutableArray *actions = [NSMutableArray array];
    if (@available(iOS 16.0, *)) [actions addObject:SNMenuAction(@"Find in Note", [UIImage systemImageNamed:@"magnifyingglass"], @selector(findInNote:), self)];
    [actions addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[
        SNMenuAction(@"Collapse All Sections", [UIImage systemImageNamed:@"chevron.right"], @selector(collapseAllSections:), self),
        SNMenuAction(@"Expand All Sections", [UIImage systemImageNamed:@"chevron.down"], @selector(expandAllSections:), self) ]]];
    [actions addObject:SNMenuAction(@"Print", [UIImage systemImageNamed:@"printer"], @selector(printNote:), self)];
    [actions addObject:SNMenuAction(@"Export as PDF", [UIImage systemImageNamed:@"doc.richtext"], @selector(exportNoteAsPDF:), self)];
    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"]
                                                              menu:[UIMenu menuWithTitle:@"" children:actions]];
    item.accessibilityLabel = @"More";
    return item;
}

#pragma mark printing

/* The note on paper, as a PDF: a text view of the page's width, out of
   sight, the open note's text in it by a binding of its own (read only),
   its tables in grids of their own, in light colours; drawn a page at a
   time, each page ending after the last line that fits on it. A4, or
   Letter where inches are used. */
- (NSData *)pdfOfNote {
    BOOL metric = [[[NSLocale currentLocale] objectForKey:NSLocaleUsesMetricSystem] boolValue];
    CGRect page = metric ? CGRectMake(0, 0, 595, 842) : CGRectMake(0, 0, 612, 792);
    CGFloat margin = 54;
    CGRect content = CGRectInset(page, margin, margin);
    NSTextStorage *storage = [[NSTextStorage alloc] init];
    SNListLayoutManager *lm = [[SNListLayoutManager alloc] init];
    [storage addLayoutManager:lm];
    NSTextContainer *container = [[NSTextContainer alloc] initWithSize:CGSizeMake(content.size.width, CGFLOAT_MAX)];
    [lm addTextContainer:container];
    UITextView *paper = [[UITextView alloc] initWithFrame:CGRectMake(0, 0, content.size.width, 100000) textContainer:container];
    paper.editable = NO;
    paper.scrollEnabled = NO;
    paper.backgroundColor = [UIColor whiteColor];
    paper.textContainerInset = UIEdgeInsetsZero;
    paper.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
    __block SNTextBinding *binding = nil;
    __block SNTableGrids *grids = nil;
    [[UITraitCollection traitCollectionWithUserInterfaceStyle:UIUserInterfaceStyleLight] performAsCurrentTraitCollection:^{
        binding = [[SNTextBinding alloc] initWithTextView:paper editor:self->_editor];
        [binding textWidthMayHaveChanged];
        grids = [[SNTableGrids alloc] initWithBinding:binding notes:self->_notes];
        [grids update];
    }];
    [lm ensureLayoutForTextContainer:container];
    CGFloat height = CGRectGetMaxY([lm usedRectForTextContainer:container]);
    paper.frame = CGRectMake(0, 0, content.size.width, MAX(height, 1));
    [paper layoutIfNeeded];
    /* Where each page begins: at the top of the first line that would not
       fit on the one before. */
    NSMutableArray<NSNumber *> *tops = [NSMutableArray arrayWithObject:@0];
    NSRange glyphs = [lm glyphRangeForTextContainer:container];
    for (NSUInteger g = glyphs.location; g < NSMaxRange(glyphs); ) {
        NSRange line;
        CGRect r = [lm lineFragmentRectForGlyphAtIndex:g effectiveRange:&line];
        if (CGRectGetMaxY(r) - tops.lastObject.doubleValue > content.size.height && r.origin.y > tops.lastObject.doubleValue)
            [tops addObject:@(r.origin.y)];
        g = NSMaxRange(line);
    }
    UIGraphicsPDFRenderer *renderer = [[UIGraphicsPDFRenderer alloc] initWithBounds:page format:[UIGraphicsPDFRendererFormat defaultFormat]];
    NSData *pdf = [renderer PDFDataWithActions:^(UIGraphicsPDFRendererContext *context) {
        for (NSUInteger i = 0; i < tops.count; i++) {
            CGFloat top = tops[i].doubleValue, bottom = i + 1 < tops.count ? tops[i + 1].doubleValue : height;
            [context beginPage];
            CGContextRef c = context.CGContext;
            CGContextSaveGState(c);
            CGContextClipToRect(c, CGRectMake(content.origin.x, content.origin.y, content.size.width, bottom - top));
            CGContextTranslateCTM(c, content.origin.x, content.origin.y - top);
            [paper.layer renderInContext:c];
            CGContextRestoreGState(c);
        }
    }];
    [grids removeAll];
    [binding unbind];
    return pdf;
}

- (NSString *)pdfName {
    NSString *title = [_note.title stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
    return [(title.length ? title : @"Note") stringByAppendingPathExtension:@"pdf"];
}

- (IBAction)collapseAllSections:(id)sender {
    if (!_textView.editable) return;
    NSRange sel = _textView.selectedRange;
    [_binding setAllSectionsCollapsed:YES];
    [self formatted:sel];
}

- (IBAction)expandAllSections:(id)sender {
    if (!_textView.editable) return;
    NSRange sel = _textView.selectedRange;
    [_binding setAllSectionsCollapsed:NO];
    [self formatted:sel];
}

/* The system's print sheet, the note on paper given to it. */
- (IBAction)printNote:(id)sender {
    UIPrintInteractionController *print = [UIPrintInteractionController sharedPrintController];
    UIPrintInfo *info = [UIPrintInfo printInfo];
    info.jobName = _note.title.length ? _note.title : @"Note";
    info.outputType = UIPrintInfoOutputGeneral;
    print.printInfo = info;
    print.printingItem = [self pdfOfNote];
    [print presentAnimated:YES completionHandler:nil];
}

/* The note on paper as a file, offered as any file is (Save to Files,
   AirDrop, Mail...). */
- (IBAction)exportNoteAsPDF:(id)sender {
    NSURL *file = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[self pdfName]]];
    if (![[self pdfOfNote] writeToURL:file atomically:YES]) return;
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[ file ] applicationActivities:nil];
    share.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems.firstObject;
    [self presentViewController:share animated:YES completion:nil];
}

/* The system's find navigator, over the keyboard: Replace too, in a note
   that can be written (what it replaces is an edit of the text, which the
   binding takes as typing); a hardware keyboard's Command-F opens it as
   well. */
- (IBAction)findInNote:(id)sender {
    if (@available(iOS 16.0, *)) [_textView.findInteraction presentFindNavigatorShowingReplace:NO];
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

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!_attachmentToShow) return;
    NSTextStorage *storage = _textView.textStorage;
    for (NSUInteger i = 0; i < storage.length; i++) {
        if ([[storage attribute:SNAttachmentAttributeName atIndex:i effectiveRange:NULL] isEqual:_attachmentToShow]) {
            [_textView scrollRangeToVisible:NSMakeRange(i, 1)];
            break;
        }
    }
    _attachmentToShow = nil;
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

/* A heading's chevron under a tap: its index; NSNotFound: none. */
- (NSUInteger)sectionToggleAt:(UIGestureRecognizer *)g {
    if (!_textView.editable) return NSNotFound;
    CGPoint p = [g locationInView:_textView];
    UIEdgeInsets inset = _textView.textContainerInset;
    SNListLayoutManager *lm = (SNListLayoutManager *)_textView.layoutManager;
    if (![lm isKindOfClass:[SNListLayoutManager class]]) return NSNotFound;
    return [lm sectionToggleAtPoint:CGPointMake(p.x - inset.left, p.y - inset.top)];
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
    return [self checkboxAt:g] != NSNotFound || [self sectionToggleAt:g] != NSNotFound || [self linkAt:g] != nil || [self fileAt:g] != nil;
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
    NSUInteger heading = [self sectionToggleAt:g];
    if (heading != NSNotFound) {
        NSRange sel = _textView.selectedRange;
        [_binding toggleCollapsedAt:heading];
        [self formatted:sel];
        return;
    }
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

/* The format bar's menus: their actions sent to this controller. */
- (void)makeFormatMenus {
    /* A row of four, as Apple Notes' Aa has them. */
    UIMenu *traits = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[
        SNMenuAction(@"Bold", [UIImage systemImageNamed:@"bold"], @selector(bold:), self),
        SNMenuAction(@"Italic", [UIImage systemImageNamed:@"italic"], @selector(italic:), self),
        SNMenuAction(@"Underline", [UIImage systemImageNamed:@"underline"], @selector(underline:), self),
        SNMenuAction(@"Strikethrough", [UIImage systemImageNamed:@"strikethrough"], @selector(strikethrough:), self) ]];
    if (@available(iOS 16.0, *)) traits.preferredElementSize = UIMenuElementSizeSmall;
    _styleItem.menu = [UIMenu menuWithTitle:@"" children:@[
        [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[
            SNMenuAction(@"Title", nil, @selector(title:), self),
            SNMenuAction(@"Heading", nil, @selector(heading:), self),
            SNMenuAction(@"Subheading", nil, @selector(subheading:), self),
            SNMenuAction(@"Body", nil, @selector(body:), self),
            SNMenuAction(@"Monostyled", nil, @selector(mono:), self),
            SNMenuAction(@"Block Quote", [UIImage systemImageNamed:@"text.quote"], @selector(blockQuote:), self) ]],
        traits,
        [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[
            [self colorMenu:@"Highlight" image:@"highlighter" action:@selector(applyHighlightColor:)],
            [self colorMenu:@"Text Color" image:@"paintpalette" action:@selector(applyTextColor:)] ]] ]];
    _attachItem.menu = [UIMenu menuWithTitle:@"" children:@[
        SNMenuAction(@"Choose Photo", [UIImage systemImageNamed:@"photo.on.rectangle"], @selector(attachPhoto:), self),
        SNMenuAction(@"Attach File", [UIImage systemImageNamed:@"doc"], @selector(attachFile:), self),
        SNMenuAction(@"Add Link", [UIImage systemImageNamed:@"link"], @selector(addLink:), self) ]];
    _listItem.menu = [UIMenu menuWithTitle:@"" children:@[
        SNMenuAction(@"Bulleted List", [UIImage systemImageNamed:@"list.bullet"], @selector(bulletList:), self),
        SNMenuAction(@"Dashed List", [UIImage systemImageNamed:@"list.dash"], @selector(dashList:), self),
        SNMenuAction(@"Numbered List", [UIImage systemImageNamed:@"list.number"], @selector(numberList:), self),
        [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[
            SNMenuAction(@"Move Checked to Bottom", [UIImage systemImageNamed:@"arrow.down.to.line"], @selector(moveCheckedToBottom:), self),
            [self keepCheckedAction] ]],
        [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[
            SNMenuAction(@"Increase Indentation", [UIImage systemImageNamed:@"increase.indent"], @selector(indent:), self),
            SNMenuAction(@"Decrease Indentation", [UIImage systemImageNamed:@"decrease.indent"], @selector(outdent:), self) ]] ]];
}

/* None, then the five colours, each a dot of itself. */
- (UIMenu *)colorMenu:(NSString *)title image:(NSString *)image action:(SEL)action {
    NSMutableArray *items = [NSMutableArray arrayWithObject:SNMenuAction(@"None", [UIImage systemImageNamed:@"circle.slash"], action, self)];
    for (NSString *name in SNColorNames()) {
        UIImage *dot = [[UIImage systemImageNamed:@"circle.fill"] imageWithTintColor:SNSystemNamedColor(name)
                                                                        renderingMode:UIImageRenderingModeAlwaysOriginal];
        [items addObject:SNMenuAction(name.capitalizedString, dot, action, self)];
    }
    return [UIMenu menuWithTitle:title image:[UIImage systemImageNamed:image] identifier:nil options:0 children:items];
}

- (UIAction *)keepCheckedAction {
    UIAction *a = SNMenuAction(@"Keep Checked at Bottom", nil, @selector(toggleKeepCheckedAtBottom:), self);
    a.state = _notes.movesCheckedToBottom ? UIMenuElementStateOn : UIMenuElementStateOff;
    return a;
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

/* A colour's name on the selection (a cell's too), or on what is typed
   next; the action's title says which (None: taken off). */
- (void)setCharacterColor:(NSString *)key from:(id)sender {
    SNTextBinding *binding;
    UITextView *tv = [self formattedTextView:&binding];
    if (!tv.editable) return;
    NSString *title = [sender respondsToSelector:@selector(title)] ? [[sender title] lowercaseString] : nil;
    NSString *name = [SNColorNames() containsObject:title] ? title : nil;
    NSRange r = tv.selectedRange;
    [binding setCharacterValue:name forKey:key inRange:r];
    if (r.length) tv.selectedRange = r;
}

- (IBAction)applyHighlightColor:(id)sender { [self setCharacterColor:SNHighlightKey from:sender]; }
- (IBAction)applyTextColor:(id)sender { [self setCharacterColor:SNColorKey from:sender]; }

- (IBAction)blockQuote:(id)sender {
    if (!_textView.editable) return;
    NSRange r = _textView.selectedRange;
    [_binding toggleQuoteForParagraphsInRange:r];
    [self formatted:r];
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
