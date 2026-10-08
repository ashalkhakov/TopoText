#import "SNSmartFolderPanel.h"

@implementation SNSmartFolderPanel

- (instancetype)initWithName:(NSString *)name filter:(SNSmartFilter *)filter {
    if ((self = [super initWithWindowNibName:@"SmartFolderPanel"])) {
        _name = [name copy];
        _filter = [filter copy];
    }
    return self;
}

/* A pop-up's item of tag, chosen (its first when none has it). */
static void SNChooseTag(NSPopUpButton *popUp, NSInteger tag) {
    if (![popUp selectItemWithTag:tag]) [popUp selectItemAtIndex:0];
}

- (void)show {
    _nameField.stringValue = _name;
    SNChooseTag(_matchPopUp, _filter.matchesAny ? 1 : 0);
    NSMutableArray *tags = [NSMutableArray array];
    for (NSString *t in _filter.tags) [tags addObject:[@"#" stringByAppendingString:t]];
    _tagsField.stringValue = [tags componentsJoinedByString:@" "];
    SNChooseTag(_tagsMatchPopUp, _filter.anyTag ? 1 : 0);
    SNChooseTag(_editedPopUp, _filter.editedWithinDays);
    SNChooseTag(_createdPopUp, _filter.createdWithinDays);
    SNChooseTag(_checklistsPopUp, _filter.checklists);
    _attachmentsBox.state = _filter.withAttachments ? NSControlStateValueOn : NSControlStateValueOff;
    _pinnedBox.state = _filter.pinnedOnly ? NSControlStateValueOn : NSControlStateValueOff;
}

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

- (void)read {
    NSString *name = [_nameField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    _name = name.length ? name : @"Smart Folder";
    SNSmartFilter *f = [[SNSmartFilter alloc] init];
    f.matchesAny = _matchPopUp.selectedTag == 1;
    f.tags = SNTagsTyped(_tagsField.stringValue);
    f.anyTag = _tagsMatchPopUp.selectedTag == 1;
    f.editedWithinDays = _editedPopUp.selectedTag;
    f.createdWithinDays = _createdPopUp.selectedTag;
    f.checklists = (SNChecklistRule)_checklistsPopUp.selectedTag;
    f.withAttachments = _attachmentsBox.state == NSControlStateValueOn;
    f.pinnedOnly = _pinnedBox.state == NSControlStateValueOn;
    _filter = f;
}

- (BOOL)runModal {
    NSWindow *window = self.window;
    [self show];
    [window center];
    [window makeFirstResponder:_nameField];
    NSModalResponse r = [NSApp runModalForWindow:window];
    [window orderOut:nil];
    if (r != NSModalResponseStop) return NO;
    [self read];
    return YES;
}

- (IBAction)ok:(id)sender {
    [NSApp stopModal];
}

- (IBAction)cancel:(id)sender {
    [NSApp abortModal];
}

@end
