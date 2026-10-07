// The table grid's cells on UIKit: UITextViews; Tab (a hardware keyboard's)
// to the next, a bar over the keyboard with the table's actions and Next
// Cell, a cell's edit menu with them too. The actions are UICommands, sent
// up the responder chain: the cell typed in, then its grid.

#import "SNTableGrid+System.h"

@interface SNTableGrid (UIKit) <UITextViewDelegate>
@end

@implementation SNTableGrid (System)

- (UIMenu *)tableMenu {
    NSMutableArray *groups = [NSMutableArray array], *group = [NSMutableArray array];
    for (NSArray *action in [SNTableGrid tableActions]) {
        if (!action.count) {
            [groups addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:group]];
            group = [NSMutableArray array];
            continue;
        }
        [group addObject:[UICommand commandWithTitle:action[0] image:nil action:NSSelectorFromString(action[1]) propertyList:nil]];
    }
    [groups addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:group]];
    return [UIMenu menuWithTitle:@"Table" children:groups];
}

- (void)systemSetUp {
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.contentMode = UIViewContentModeRedraw;
    UIToolbar *bar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
    UIBarButtonItem *table = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"tablecells"] menu:[self tableMenu]];
    table.accessibilityLabel = @"Table";
    UIBarButtonItem *space = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *next = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.right.to.line"]
                                                             style:UIBarButtonItemStylePlain target:self action:@selector(nextCell:)];
    next.accessibilityLabel = @"Next Cell";
    UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(endTyping:)];
    bar.items = @[ table, space, next, done ];
    [bar sizeToFit];
    _systemState = bar;
}

- (SNGridTextView *)makeCell:(NSString *)string {
    UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(0, 0, _column ?: 100, 30)];
    tv.scrollEnabled = NO;
    tv.backgroundColor = [UIColor clearColor];
    tv.font = SNFontFor(nil, NO, NO);
    tv.textColor = SNSystemTextColor();
    tv.textContainerInset = UIEdgeInsetsMake(6, 4, 6, 4);
    tv.text = string;
    tv.inputAccessoryView = _systemState;
    tv.delegate = self;
    return tv;
}

- (NSString *)stringOfCell:(SNGridTextView *)cell {
    return cell.text ?: @"";
}

- (void)setString:(NSString *)string ofCell:(SNGridTextView *)cell {
    NSRange sel = cell.selectedRange;
    cell.text = string;
    NSUInteger at = MIN(sel.location, string.length);
    cell.selectedRange = NSMakeRange(at, MIN(sel.length, string.length - at));
}

- (CGFloat)heightOfCell:(SNGridTextView *)cell {
    return ceil([cell sizeThatFits:CGSizeMake(cell.frame.size.width, CGFLOAT_MAX)].height);
}

- (BOOL)cellIsTypedIn:(SNGridTextView *)cell {
    return cell.isFirstResponder;
}

- (void)typeInCell:(SNGridTextView *)cell {
    [cell becomeFirstResponder];
}

- (void)redraw {
    [self setNeedsDisplay];
}

#pragma mark actions

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    for (NSArray *a in [SNTableGrid tableActions])
        if (a.count && NSSelectorFromString(a[1]) == action) return [self canDo:action];
    return [super canPerformAction:action withSender:sender];
}

- (void)nextCell:(id)sender {
    for (NSArray *row in _cells)
        for (UITextView *tv in row)
            if (tv.isFirstResponder) {
                [self moveFrom:tv by:1];
                return;
            }
}

- (void)endTyping:(id)sender {
    [self endEditing:YES];
    [self save];
}

#pragma mark the cells' delegate

- (void)textViewDidBeginEditing:(UITextView *)tv {
    [self noteCell:tv];
}

/* Tab: the next cell. */
- (BOOL)textView:(UITextView *)tv shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text {
    if ([text isEqualToString:@"\t"]) {
        [self moveFrom:tv by:1];
        return NO;
    }
    return YES;
}

- (void)textViewDidChange:(UITextView *)tv {
    [self cellChanged:tv];
}

- (void)textViewDidEndEditing:(UITextView *)tv {
    [self save];
}

/* A cell's own menu: what it would have, and the table's. */
- (UIMenu *)textView:(UITextView *)tv editMenuForTextInRange:(NSRange)range suggestedActions:(NSArray<UIMenuElement *> *)suggested
    API_AVAILABLE(ios(16.0)) {
    if (!self.editable) return [UIMenu menuWithChildren:suggested];
    return [UIMenu menuWithChildren:[suggested arrayByAddingObject:[self tableMenu]]];
}

@end
