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

- (SNGridTextView *)makeCell:(NSString *)string {
    NSTextView *tv = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, _column ?: 100, 30)];
    tv.richText = NO;
    tv.importsGraphics = NO;
    tv.drawsBackground = NO;
    tv.allowsUndo = YES;
    tv.font = SNFontFor(nil, NO, NO);
    tv.textColor = SNSystemTextColor();
    tv.textContainerInset = NSMakeSize(4, 5);
    tv.horizontallyResizable = NO;
    tv.verticallyResizable = NO;
    tv.textContainer.widthTracksTextView = YES;
    tv.string = string;
    tv.delegate = self;
    return tv;
}

- (NSString *)stringOfCell:(SNGridTextView *)cell {
    return cell.string ?: @"";
}

- (void)setString:(NSString *)string ofCell:(SNGridTextView *)cell {
    NSRange sel = cell.selectedRange;
    cell.string = string;
    NSUInteger at = MIN(sel.location, string.length);
    cell.selectedRange = NSMakeRange(at, MIN(sel.length, string.length - at));
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

- (void)textDidChange:(NSNotification *)n {
    [self cellChanged:n.object];
}

- (void)textDidEndEditing:(NSNotification *)n {
    [self save];
}

- (void)textViewDidChangeSelection:(NSNotification *)n {
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
