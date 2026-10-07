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
}

/* Each cell a bar of its own: one bar shared by cells, its cell taken away
   while typed in (a row deleted), stays over the keyboard whoever types
   next, the note's text too. */
- (UIToolbar *)makeBar {
    UIToolbar *bar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
    UIBarButtonItem *table = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"tablecells"] menu:[self tableMenu]];
    table.accessibilityLabel = @"Table";
    /* A cell's characters formatted: the editor's actions, which format the
       text typed in, a cell's too. */
    UIMenu *format = [UIMenu menuWithTitle:@"" children:@[
        [UICommand commandWithTitle:@"Bold" image:[UIImage systemImageNamed:@"bold"] action:@selector(bold:) propertyList:nil],
        [UICommand commandWithTitle:@"Italic" image:[UIImage systemImageNamed:@"italic"] action:@selector(italic:) propertyList:nil],
        [UICommand commandWithTitle:@"Underline" image:[UIImage systemImageNamed:@"underline"] action:@selector(underline:) propertyList:nil],
        [UICommand commandWithTitle:@"Strikethrough" image:[UIImage systemImageNamed:@"strikethrough"] action:@selector(strikethrough:) propertyList:nil],
        [UICommand commandWithTitle:@"Add Link" image:[UIImage systemImageNamed:@"link"] action:@selector(addLink:) propertyList:nil] ]];
    UIBarButtonItem *formatItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"textformat"] menu:format];
    formatItem.accessibilityLabel = @"Format";
    UIBarButtonItem *space = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *next = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.right.to.line"]
                                                             style:UIBarButtonItemStylePlain target:self action:@selector(nextCell:)];
    next.accessibilityLabel = @"Next Cell";
    UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(endTyping:)];
    bar.items = @[ formatItem, table, space, next, done ];
    [bar sizeToFit];
    return bar;
}

- (SNGridTextView *)makeCell {
    UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(0, 0, _column ?: 100, 30)];
    tv.scrollEnabled = NO;
    tv.backgroundColor = [UIColor clearColor];
    tv.font = SNFontFor(nil, NO, NO);
    tv.textColor = SNSystemTextColor();
    tv.textContainerInset = UIEdgeInsetsMake(6, 4, 6, 4);
    tv.inputAccessoryView = [self makeBar];
    tv.delegate = self;
    return tv;
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
    /* From the note's text: the keyboard to show this cell's bar, not the
       note's. */
    [tv performSelector:@selector(reloadInputViews) withObject:nil afterDelay:0];
    [self noteCell:tv];
}

/* Tab: the next cell. */
- (BOOL)textView:(UITextView *)tv shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text {
    if ([text isEqualToString:@"\t"]) {
        [self moveFrom:tv by:1];
        return NO;
    }
    SNTextBinding *b = [self bindingOfCell:tv];
    return b ? [b shouldChangeTextInRange:range replacementString:text] : YES;
}

- (void)textViewDidChange:(UITextView *)tv {
    [[self bindingOfCell:tv] textDidChange];
    [self cellChanged:tv];
}

- (void)textViewDidChangeSelection:(UITextView *)tv {
    [[self bindingOfCell:tv] selectionDidChange];
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
