#import "SNTransferViewController.h"

@implementation SNTransferViewController {
    UILabel *_status;
    UIProgressView *_bar;
    UILabel *_detail;
    UIButton *_button;
}

- (instancetype)initWithTransfer:(SNTransfer *)transfer {
    if (!(self = [super initWithNibName:nil bundle:nil])) return nil;
    _transfer = transfer;
    transfer.delegate = self;
    self.modalInPresentation = YES;
    if (@available(iOS 15.0, *)) self.sheetPresentationController.detents = @[ UISheetPresentationControllerDetent.mediumDetent ];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    UILabel *title = [[UILabel alloc] init];
    title.text = _transfer.import ? @"Import" : @"Export";
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    _status = [[UILabel alloc] init];
    _status.text = _transfer.status;
    _bar = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    _detail = [[UILabel alloc] init];
    _detail.numberOfLines = 0;
    _detail.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    _detail.textColor = UIColor.secondaryLabelColor;
    _detail.text = _transfer.URL.lastPathComponent;
    _button = [UIButton buttonWithType:UIButtonTypeSystem];
    [_button setTitle:@"Stop" forState:UIControlStateNormal];
    [_button addTarget:self action:@selector(stopOrDone:) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[ title, _status, _bar, _detail, _button ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 14;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    UILayoutGuide *g = self.view.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:g.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:g.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:24],
    ]];
}

- (void)transferDidProgress:(SNTransfer *)transfer {
    _status.text = transfer.status;
    if (transfer.total) _bar.progress = (float)transfer.done / (float)transfer.total;
}

- (void)transferDidFinish:(SNTransfer *)transfer {
    _status.text = transfer.error || transfer.cancelled ? @"Stopped." : @"Done.";
    if (!transfer.error && !transfer.cancelled) _bar.progress = 1;
    NSMutableArray *lines = [NSMutableArray arrayWithObject:transfer.summary];
    NSArray *skipped = transfer.skipped;
    for (NSUInteger i = 0; i < MIN(skipped.count, 5u); i++) [lines addObject:skipped[i]];
    if (skipped.count > 5) [lines addObject:[NSString stringWithFormat:@"and %lu more.", (unsigned long)(skipped.count - 5)]];
    _detail.text = [lines componentsJoinedByString:@"\n"];
    [_button setTitle:@"Done" forState:UIControlStateNormal];
    _button.enabled = YES;
}

- (void)stopOrDone:(id)sender {
    if (!_transfer.finished) {
        [_transfer cancel];
        _button.enabled = NO;
        _status.text = @"Stopping…";
        return;
    }
    id<SNTransferViewControllerDelegate> delegate = _delegate;
    [delegate transferViewControllerDidClose:self];
}

@end
