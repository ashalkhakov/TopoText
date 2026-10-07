#import "SNSmartFolderViewController.h"

enum { SNNameSection, SNMatchSection, SNTagsSection, SNWhenSection, SNOtherSection, SNSectionCount };

/* The choices of the pop-up rows: titles and their values. */
static NSArray<NSArray *> *SNDayChoices(void) {
    return @[ @[ @"Any Time", @0 ], @[ @"Today", @1 ], @[ @"Last 7 Days", @7 ], @[ @"Last 30 Days", @30 ], @[ @"Last 90 Days", @90 ],
              @[ @"Last Year", @365 ] ];
}

static NSArray<NSArray *> *SNChecklistChoices(void) {
    return @[ @[ @"Not Asked", @(SNChecklistRuleNone) ], @[ @"Any Checklist", @(SNChecklistRuleAny) ],
              @[ @"Ticked Items", @(SNChecklistRuleTicked) ], @[ @"Items Not Ticked", @(SNChecklistRuleUnticked) ] ];
}

@implementation SNSmartFolderViewController {
    UITextField *_nameField, *_tagsField;
    UISegmentedControl *_match, *_tagsMatch;
    UISwitch *_attachments, *_pinned;
}

- (instancetype)initWithName:(NSString *)name filter:(SNSmartFilter *)filter {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _name = [name copy];
        _filter = [filter copy];
        self.title = @"Smart Folder";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                          target:self action:@selector(cancel:)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                                           target:self action:@selector(done:)];
    _nameField = [self fieldWithText:_name placeholder:@"Name"];
    NSMutableArray *tags = [NSMutableArray array];
    for (NSString *t in _filter.tags) [tags addObject:[@"#" stringByAppendingString:t]];
    _tagsField = [self fieldWithText:[tags componentsJoinedByString:@" "] placeholder:@"#work #family"];
    _tagsField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _match = [[UISegmentedControl alloc] initWithItems:@[ @"All Rules", @"Any Rule" ]];
    _match.selectedSegmentIndex = _filter.matchesAny ? 1 : 0;
    _tagsMatch = [[UISegmentedControl alloc] initWithItems:@[ @"All Tags", @"Any Tag" ]];
    _tagsMatch.selectedSegmentIndex = _filter.anyTag ? 1 : 0;
    _attachments = [[UISwitch alloc] init];
    _attachments.on = _filter.withAttachments;
    _pinned = [[UISwitch alloc] init];
    _pinned.on = _filter.pinnedOnly;
}

- (UITextField *)fieldWithText:(NSString *)text placeholder:(NSString *)placeholder {
    UITextField *f = [[UITextField alloc] init];
    f.text = text;
    f.placeholder = placeholder;
    f.clearButtonMode = UITextFieldViewModeWhileEditing;
    f.returnKeyType = UIReturnKeyDone;
    f.delegate = self;
    f.translatesAutoresizingMaskIntoConstraints = NO;
    return f;
}

- (BOOL)textFieldShouldReturn:(UITextField *)f {
    [f resignFirstResponder];
    return YES;
}

#pragma mark the form

- (NSInteger)numberOfSectionsInTableView:(UITableView *)t {
    return SNSectionCount;
}

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)section {
    switch (section) {
    case SNTagsSection: return 2;
    case SNWhenSection: return 3;
    case SNOtherSection: return 2;
    default: return 1;
    }
}

- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)section {
    switch (section) {
    case SNMatchSection: return @"Include notes matching";
    case SNTagsSection: return @"Tags";
    case SNWhenSection: return @"Dates and checklists";
    default: return nil;
    }
}

/* A view filling a cell's content, inset as its text would be. */
static void SNFill(UITableViewCell *cell, UIView *v) {
    [cell.contentView addSubview:v];
    v.translatesAutoresizingMaskIntoConstraints = NO;
    UILayoutGuide *m = cell.contentView.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [v.leadingAnchor constraintEqualToAnchor:m.leadingAnchor], [v.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
        [v.topAnchor constraintEqualToAnchor:m.topAnchor], [v.bottomAnchor constraintEqualToAnchor:m.bottomAnchor] ]];
}

/* A row whose value is chosen from a menu (its value shown at the right). */
- (UITableViewCell *)choiceCell:(NSString *)title choices:(NSArray<NSArray *> *)choices value:(NSInteger)value action:(SEL)action {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    UIListContentConfiguration *c = [UIListContentConfiguration valueCellConfiguration];
    c.text = title;
    cell.contentConfiguration = c;
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    NSMutableArray *items = [NSMutableArray array];
    for (NSArray *choice in choices) {
        UICommand *command = [UICommand commandWithTitle:choice[0] image:nil action:action propertyList:choice[1]];
        command.state = [choice[1] integerValue] == value ? UIMenuElementStateOn : UIMenuElementStateOff;
        [items addObject:command];
        if ([choice[1] integerValue] == value) [b setTitle:choice[0] forState:UIControlStateNormal];
    }
    b.menu = [UIMenu menuWithTitle:@"" children:items];
    b.showsMenuAsPrimaryAction = YES;
    [b sizeToFit];
    cell.accessoryView = b;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (UITableViewCell *)switchCell:(NSString *)title control:(UISwitch *)control {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    UIListContentConfiguration *c = [UIListContentConfiguration cellConfiguration];
    c.text = title;
    cell.contentConfiguration = c;
    cell.accessoryView = control;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    switch (ip.section) {
    case SNNameSection: SNFill(cell, _nameField); return cell;
    case SNMatchSection: SNFill(cell, _match); return cell;
    case SNTagsSection: SNFill(cell, ip.row == 0 ? _tagsField : _tagsMatch); return cell;
    case SNWhenSection:
        if (ip.row == 0) return [self choiceCell:@"Edited" choices:SNDayChoices() value:_filter.editedWithinDays action:@selector(chooseEdited:)];
        if (ip.row == 1) return [self choiceCell:@"Created" choices:SNDayChoices() value:_filter.createdWithinDays action:@selector(chooseCreated:)];
        return [self choiceCell:@"Checklists" choices:SNChecklistChoices() value:_filter.checklists action:@selector(chooseChecklists:)];
    default:
        return ip.row == 0 ? [self switchCell:@"With Attachments" control:_attachments] : [self switchCell:@"Pinned" control:_pinned];
    }
}

/* The menus' commands: their property lists the values chosen. */
- (void)chooseEdited:(UICommand *)sender {
    [self read];
    _filter.editedWithinDays = [sender.propertyList integerValue];
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:SNWhenSection] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)chooseCreated:(UICommand *)sender {
    [self read];
    _filter.createdWithinDays = [sender.propertyList integerValue];
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:SNWhenSection] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)chooseChecklists:(UICommand *)sender {
    [self read];
    _filter.checklists = (SNChecklistRule)[sender.propertyList integerValue];
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:SNWhenSection] withRowAnimation:UITableViewRowAnimationNone];
}

#pragma mark done

/* Tags typed with or without #, by spaces or commas. */
static NSArray<NSString *> *SNTagsTyped(NSString *typed) {
    NSMutableArray *tags = [NSMutableArray array];
    NSCharacterSet *between = [NSCharacterSet characterSetWithCharactersInString:@" ,\t"];
    for (NSString *part in [typed componentsSeparatedByCharactersInSet:between]) {
        NSString *t = [part stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"#"]].lowercaseString;
        if (t.length && ![tags containsObject:t]) [tags addObject:t];
    }
    return tags;
}

/* The form, read into name and filter (the pop-up rows' values are kept as
   they are chosen). */
- (void)read {
    if (!_nameField) return;
    NSString *name = [_nameField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    _name = name.length ? name : @"Smart Folder";
    SNSmartFilter *f = [_filter copy];
    f.matchesAny = _match.selectedSegmentIndex == 1;
    f.tags = SNTagsTyped(_tagsField.text ?: @"");
    f.anyTag = _tagsMatch.selectedSegmentIndex == 1;
    f.withAttachments = _attachments.on;
    f.pinnedOnly = _pinned.on;
    _filter = f;
}

- (IBAction)done:(id)sender {
    [self.view endEditing:YES];
    [self read];
    [_delegate smartFolderViewControllerDidFinish:self];
}

- (IBAction)cancel:(id)sender {
    [_delegate smartFolderViewControllerDidCancel:self];
}

@end
