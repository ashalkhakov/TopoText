// A note's version history (SNVersionsPanel.h).

#import "SNVersionsPanel.h"
#import "SNTextSystem.h"

@implementation SNVersionsPanel {
    SNNotes *_notes;
    NSDateFormatter *_dates;
}

- (instancetype)initWithNotes:(SNNotes *)notes note:(SNNote *)note {
    if (!(self = [super initWithWindowNibName:@"VersionsPanel"])) return nil;
    _notes = notes;
    _note = note;
    _versions = @[];
    _dates = [[NSDateFormatter alloc] init];
    _dates.dateStyle = NSDateFormatterMediumStyle;
    _dates.timeStyle = NSDateFormatterShortStyle;
    return self;
}

- (void)windowDidLoad {
    [super windowDidLoad];
    self.window.title = [NSString stringWithFormat:@"Version History — %@", _note.title.length ? _note.title : @"New Note"];
    [self reload];
}

- (void)reload {
    [self window];
    NSInteger row = _versionTable.selectedRow;
    _versions = [_notes versionsOfNote:_note];
    [_versionTable reloadData];
    if (_versions.count) [_versionTable selectRowIndexes:[NSIndexSet indexSetWithIndex:row >= 0 && (NSUInteger)row < _versions.count ? (NSUInteger)row : 0]
                                    byExtendingSelection:NO];
    [self showChosen];
}

- (NSManagedObject *)chosen {
    NSInteger row = _versionTable.selectedRow;
    return row >= 0 && (NSUInteger)row < _versions.count ? _versions[(NSUInteger)row] : nil;
}

/* The one chosen beside the note as it is now. */
- (void)showChosen {
    NSManagedObject *version = [self chosen];
    TopoText *then = version ? [_notes textOfVersion:version] : nil;
    if (!then) {
        _statusField.stringValue = _versions.count ? @"" : @"No versions yet. The server keeps one as the note is written, ten minutes at least after the last (none while offline).";
        [_previewView.textStorage setAttributedString:[[NSAttributedString alloc] init]];
        _restoreButton.enabled = NO;
        return;
    }
    NSString *now = _note.text.string ?: @"";
    [_previewView.textStorage setAttributedString:SNVersionPreview(now, then.string)];
    BOOL same = [now isEqualToString:then.string];
    _statusField.stringValue = same ? @"The note is as it was then." : @"Highlighted: what comes back. Struck through: what goes.";
    _restoreButton.enabled = !same && !_note.deletedAt;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)table {
    return (NSInteger)_versions.count;
}

- (id)tableView:(NSTableView *)table objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    NSManagedObject *v = _versions[(NSUInteger)row];
    NSDate *created = [v valueForKey:@"created"];
    return created ? [_dates stringFromDate:created] : @"";
}

- (void)tableViewSelectionDidChange:(NSNotification *)n {
    [self showChosen];
}

- (IBAction)restore:(id)sender {
    NSManagedObject *version = [self chosen];
    if (!version) return;
    [_delegate versionsPanel:self restoreVersion:version];
    [self showChosen];
}

- (IBAction)close:(id)sender {
    [self.window orderOut:nil];
}

@end
