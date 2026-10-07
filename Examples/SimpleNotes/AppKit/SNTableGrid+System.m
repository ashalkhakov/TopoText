// The table grid's cells on AppKit (macOS, GNUstep): NSTextViews; Tab and
// Shift-Tab between them, a cell's menu with the table's actions, which
// Format > Table sends up the responder chain (a cell, then its grid).

#import "SNTableGrid+System.h"

@interface SNTableGrid (AppKit) <NSTextViewDelegate>
@end

@implementation SNTableGrid (System)

- (void)systemSetUp {
}

- (BOOL)isFlipped {
    return YES;
}

- (SNGridTextView *)makeCell {
    NSTextView *tv = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, _column ?: 100, 30)];
    tv.richText = YES;
    tv.importsGraphics = NO;
    tv.drawsBackground = NO;
    tv.allowsUndo = YES;
    tv.font = SNFontFor(nil, NO, NO);
    tv.textColor = SNSystemTextColor();
    tv.textContainerInset = NSMakeSize(4, 5);
    tv.horizontallyResizable = NO;
    tv.verticallyResizable = NO;
    tv.textContainer.widthTracksTextView = YES;
    tv.delegate = self;
    return tv;
}

- (CGFloat)heightOfCell:(SNGridTextView *)cell {
    NSLayoutManager *lm = cell.layoutManager;
    NSTextContainer *tc = cell.textContainer;
    [lm glyphRangeForTextContainer:tc];
    CGFloat used = [lm usedRectForTextContainer:tc].size.height;
    CGFloat line = ceil([lm defaultLineHeightForFont:cell.font ?: SNFontFor(nil, NO, NO)]);
    return ceil(MAX(used, line)) + 2 * cell.textContainerInset.height;
}

- (BOOL)cellIsTypedIn:(SNGridTextView *)cell {
    return self.window.firstResponder == cell;
}

- (void)typeInCell:(SNGridTextView *)cell {
    [self.window makeFirstResponder:cell];
}

- (void)redraw {
    [self setNeedsDisplay:YES];
}

#pragma mark the cells' delegate

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    return [self canDo:item.action];
}

/* Tab: the next cell; Shift-Tab: the one before. */
- (BOOL)textView:(NSTextView *)tv doCommandBySelector:(SEL)command {
    if (command == @selector(insertTab:)) {
        [self moveFrom:tv by:1];
        return YES;
    }
    if (command == @selector(insertBacktab:)) {
        [self moveFrom:tv by:-1];
        return YES;
    }
    return NO;
}

/* Typing as in a note's text (SNTextBinding); Tab is the grid's. */
- (BOOL)textView:(NSTextView *)tv shouldChangeTextInRange:(NSRange)range replacementString:(NSString *)string {
    SNTextBinding *b = [self bindingOfCell:tv];
    return b ? [b shouldChangeTextInRange:range replacementString:string] : YES;
}

- (void)textDidChange:(NSNotification *)n {
    [[self bindingOfCell:n.object] textDidChange];
    [self cellChanged:n.object];
}

/* A link in a cell followed as one in the note: its window's controller. */
- (BOOL)textView:(NSTextView *)tv clickedOnLink:(id)link atIndex:(NSUInteger)index {
    id controller = self.window.delegate;
    if ([controller respondsToSelector:@selector(textView:clickedOnLink:atIndex:)])
        return [controller textView:tv clickedOnLink:link atIndex:index];
    return NO;
}

- (void)textDidEndEditing:(NSNotification *)n {
    [self save];
}

- (void)textViewDidChangeSelection:(NSNotification *)n {
    [[self bindingOfCell:n.object] selectionDidChange];
    [self noteCell:n.object];
}

/* A cell's own menu: what it would have, and the table's. */
- (NSMenu *)textView:(NSTextView *)tv menu:(NSMenu *)menu forEvent:(NSEvent *)event atIndex:(NSUInteger)index {
    if (!self.editable) return menu;
    [self noteCell:tv];
    [menu addItem:[NSMenuItem separatorItem]];
    for (NSArray *action in [SNTableGrid tableActions]) {
        if (!action.count) {
            [menu addItem:[NSMenuItem separatorItem]];
            continue;
        }
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:action[0] action:NSSelectorFromString(action[1]) keyEquivalent:@""];
        item.target = self;
        [menu addItem:item];
    }
    return menu;
}

@end
