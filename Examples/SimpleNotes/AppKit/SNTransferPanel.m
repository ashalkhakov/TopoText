#import "SNTransferPanel.h"

@implementation SNTransferPanel

- (instancetype)initWithTransfer:(SNTransfer *)transfer {
    if (!(self = [super initWithWindowNibName:@"TransferPanel"])) return nil;
    _transfer = transfer;
    transfer.delegate = self;
    return self;
}

- (void)windowDidLoad {
    [super windowDidLoad];
    self.window.title = _transfer.import ? @"Import" : @"Export";
    _detailField.stringValue = _transfer.URL.lastPathComponent ?: @"";
    [_progressBar startAnimation:nil];
}

- (void)transferDidProgress:(SNTransfer *)transfer {
    _statusField.stringValue = transfer.status;
    if (transfer.total) {
        if ([_progressBar isIndeterminate]) {
            [_progressBar stopAnimation:nil];
            [_progressBar setIndeterminate:NO];
            _progressBar.maxValue = transfer.total;
        }
        _progressBar.doubleValue = transfer.done;
    }
}

- (void)transferDidFinish:(SNTransfer *)transfer {
    [_progressBar stopAnimation:nil];
    [_progressBar setIndeterminate:NO];
    _progressBar.maxValue = MAX(transfer.total, 1);
    _progressBar.doubleValue = transfer.error || transfer.cancelled ? transfer.done : _progressBar.maxValue;
    _statusField.stringValue = transfer.error ? @"Stopped." : transfer.cancelled ? @"Stopped." : @"Done.";
    /* What happened; the first of what was left out (all of it in the log). */
    NSMutableArray *lines = [NSMutableArray arrayWithObject:transfer.summary];
    NSArray *skipped = transfer.skipped;
    for (NSUInteger i = 0; i < MIN(skipped.count, 3u); i++) [lines addObject:skipped[i]];
    if (skipped.count > 3) [lines addObject:[NSString stringWithFormat:@"and %lu more (in the log).", (unsigned long)(skipped.count - 3)]];
    for (NSString *s in skipped) NSLog(@"SimpleNotes: left out: %@", s);
    _detailField.stringValue = [lines componentsJoinedByString:@"\n"];
    _button.title = @"Close";
    _button.keyEquivalent = @"\r";
}

- (IBAction)stopOrClose:(id)sender {
    if (!_transfer.finished) {
        [_transfer cancel];
        _button.enabled = NO;
        _statusField.stringValue = @"Stopping…";
        return;
    }
    [self close];
    id<SNTransferPanelDelegate> delegate = _delegate;
    [delegate transferPanelDidClose:self];
}

@end
