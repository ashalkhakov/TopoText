// The table grid's cells on UIKit: UITextViews; Tab to the next and, on a
// hardware keyboard, Shift-Tab to the one before; a bar over the keyboard
// with the table's actions and Next Cell, a cell's edit menu with them too.
// The actions are UICommands, sent up the responder chain: the cell typed
// in, then its grid. A link tapped in a cell is followed as one in the note.

#import "SNTableGrid+System.h"

@interface SNTableGrid (UIKit) <UITextViewDelegate, UIGestureRecognizerDelegate>
@end

/* Whoever opens links (the note's editor, SNEditorViewController). */
@protocol SNLinkOpening <NSObject>
- (void)openLink:(NSURL *)url;
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
    /* A link tapped: an editable text view only puts the insertion point
       there. */
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tappedLink:)];
    tap.delegate = self;
    [tv addGestureRecognizer:tap];
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

- (void)previousCell:(id)sender {
    for (NSArray *row in _cells)
        for (UITextView *tv in row)
            if (tv.isFirstResponder) {
                [self moveFrom:tv by:-1];
                return;
            }
}

/* A hardware keyboard's Tab and Shift-Tab, the grid's (up the responder
   chain from the cell), before the system's moving of focus. */
- (NSArray<UIKeyCommand *> *)keyCommands {
    UIKeyCommand *next = [UIKeyCommand keyCommandWithInput:@"\t" modifierFlags:0 action:@selector(nextCell:)];
    UIKeyCommand *back = [UIKeyCommand keyCommandWithInput:@"\t" modifierFlags:UIKeyModifierShift action:@selector(previousCell:)];
    next.wantsPriorityOverSystemBehavior = YES;
    back.wantsPriorityOverSystemBehavior = YES;
    return @[ next, back ];
}

#pragma mark links

/* The link under a point of a cell (nil: none): a given one or one found. */
- (NSURL *)linkInCell:(UITextView *)cell atPoint:(CGPoint)point {
    /* The character under the point: the one before or after the nearest
       insertion point whose box holds it (TextKit 2's -characterRangeAtPoint:
       answers the line's first). */
    UITextPosition *near = [cell closestPositionToPoint:point];
    if (!near) return nil;
    NSInteger at = [cell offsetFromPosition:cell.beginningOfDocument toPosition:near];
    NSUInteger length = cell.textStorage.length;
    for (NSInteger i = at - 1; i <= at; i++) {
        if (i < 0 || (NSUInteger)i >= length) continue;
        UITextPosition *from = [cell positionFromPosition:cell.beginningOfDocument offset:i];
        UITextRange *one = [cell textRangeFromPosition:from toPosition:[cell positionFromPosition:from offset:1]];
        if (!one || !CGRectContainsPoint([cell firstRectForRange:one], point)) continue;
        id link = [cell.textStorage attribute:NSLinkAttributeName atIndex:(NSUInteger)i effectiveRange:NULL];
        return [link isKindOfClass:[NSURL class]] ? link : nil;
    }
    return nil;
}

/* Only a tap on a link: the cell has the others. */
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g {
    if (![g isKindOfClass:[UITapGestureRecognizer class]] || ![g.view isKindOfClass:[UITextView class]]) return YES;
    UITextView *cell = (UITextView *)g.view;
    return [self linkInCell:cell atPoint:[g locationInView:cell]] != nil;
}

- (void)tappedLink:(UITapGestureRecognizer *)g {
    UITextView *cell = (UITextView *)g.view;
    NSURL *url = [self linkInCell:cell atPoint:[g locationInView:cell]];
    if (url) [self followLink:url];
}

/* As one in the note: by whoever opens links up the responder chain (the
   note's editor). */
- (void)followLink:(NSURL *)url {
    for (UIResponder *r = self.nextResponder; r; r = r.nextResponder)
        if ([r respondsToSelector:@selector(openLink:)]) {
            [(id<SNLinkOpening>)r openLink:url];
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
