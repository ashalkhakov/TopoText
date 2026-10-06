#import "SNRichText.h"
#import "SNNotes.h"

NSString * const SNBoldKey = @"bold";
NSString * const SNItalicKey = @"italic";
NSString * const SNUnderlineKey = @"underline";
NSString * const SNStrikeKey = @"strike";
NSString * const SNStyleKey = @"style";
NSString * const SNStyleTitle = @"title";
NSString * const SNStyleHeading = @"heading";
NSString * const SNStyleAttributeName = @"SNStyle";
/* Bold and italic said beside the font too: a font with no italic face
   (or bold) still says what was meant. */
static NSString * const SNBoldAttributeName = @"SNBold";
static NSString * const SNItalicAttributeName = @"SNItalic";

#pragma mark fonts

static CGFloat SNSize(NSString *style) {
#if TARGET_OS_IPHONE
    return [style isEqual:SNStyleTitle] ? 28 : [style isEqual:SNStyleHeading] ? 21 : 17;
#else
    return [style isEqual:SNStyleTitle] ? 24 : [style isEqual:SNStyleHeading] ? 18 : 14;
#endif
}

static BOOL SNIsStyle(id style) {
    return [style isEqual:SNStyleTitle] || [style isEqual:SNStyleHeading];
}

SNFont *SNFontFor(NSString *style, BOOL bold, BOOL italic) {
    static NSMutableDictionary *cache;
    if (!cache) cache = [NSMutableDictionary dictionary];
    if (!SNIsStyle(style)) style = nil;
    /* A title or a heading is bold by its style. */
    if (style) bold = YES;
    NSString *key = [NSString stringWithFormat:@"%@/%d/%d", style ?: @"", bold, italic];
    SNFont *font = cache[key];
    if (font) return font;
    CGFloat size = SNSize(style);
    font = bold ? [SNFont boldSystemFontOfSize:size] : [SNFont systemFontOfSize:size];
    if (italic) {
#if TARGET_OS_IPHONE
        UIFontDescriptor *d = [font.fontDescriptor fontDescriptorWithSymbolicTraits:font.fontDescriptor.symbolicTraits | UIFontDescriptorTraitItalic];
        if (d) font = [UIFont fontWithDescriptor:d size:size];
#else
        font = [[NSFontManager sharedFontManager] convertFont:font toHaveTrait:NSItalicFontMask] ?: font;
#endif
    }
    cache[key] = font;
    return font;
}

static void SNTraitsOf(SNFont *font, BOOL *bold, BOOL *italic) {
#if TARGET_OS_IPHONE
    UIFontDescriptorSymbolicTraits t = font.fontDescriptor.symbolicTraits;
    *bold = (t & UIFontDescriptorTraitBold) != 0;
    *italic = (t & UIFontDescriptorTraitItalic) != 0;
#else
    NSFontTraitMask t = [[NSFontManager sharedFontManager] traitsOfFont:font];
    *bold = (t & NSBoldFontMask) != 0;
    *italic = (t & NSItalicFontMask) != 0;
#endif
}

static id SNTextColor(void) {
#if TARGET_OS_IPHONE
    return [UIColor labelColor];
#else
    return [NSColor textColor];
#endif
}

#pragma mark attributes

NSDictionary *SNViewAttributes(NSDictionary *attrs) {
    NSString *style = SNIsStyle(attrs[SNStyleKey]) ? attrs[SNStyleKey] : nil;
    NSMutableDictionary *v = [NSMutableDictionary dictionary];
    BOOL bold = [attrs[SNBoldKey] boolValue] && !style, italic = [attrs[SNItalicKey] boolValue];
    v[NSFontAttributeName] = SNFontFor(style, bold, italic);
    if (bold) v[SNBoldAttributeName] = @YES;
    if (italic) v[SNItalicAttributeName] = @YES;
    v[NSForegroundColorAttributeName] = SNTextColor();
    if ([attrs[SNUnderlineKey] boolValue]) v[NSUnderlineStyleAttributeName] = @(NSUnderlineStyleSingle);
    if ([attrs[SNStrikeKey] boolValue]) v[NSStrikethroughStyleAttributeName] = @(NSUnderlineStyleSingle);
    if (style) v[SNStyleAttributeName] = style;
    return v;
}

NSDictionary *SNTextAttributes(NSDictionary *view) {
    NSMutableDictionary *t = [NSMutableDictionary dictionary];
    NSString *style = SNIsStyle(view[SNStyleAttributeName]) ? view[SNStyleAttributeName] : nil;
    if (style) t[SNStyleKey] = style;
    SNFont *font = view[NSFontAttributeName];
    if (font) {
        BOOL bold = NO, italic = NO;
        SNTraitsOf(font, &bold, &italic);
        if (bold && !style) t[SNBoldKey] = @YES;
        if (italic) t[SNItalicKey] = @YES;
    }
    if ([view[SNBoldAttributeName] boolValue] && !style) t[SNBoldKey] = @YES;
    if ([view[SNItalicAttributeName] boolValue]) t[SNItalicKey] = @YES;
    if ([view[NSUnderlineStyleAttributeName] integerValue]) t[SNUnderlineKey] = @YES;
    if ([view[NSStrikethroughStyleAttributeName] integerValue]) t[SNStrikeKey] = @YES;
    return t;
}

NSAttributedString *SNViewString(TopoText *text) {
    NSMutableAttributedString *s = [[NSMutableAttributedString alloc] init];
    NSString *string = text.string;
    for (NSDictionary *run in text.attributeRuns) {
        NSRange r = NSMakeRange([run[@"location"] unsignedIntegerValue], [run[@"length"] unsignedIntegerValue]);
        [s appendAttributedString:[[NSAttributedString alloc] initWithString:[string substringWithRange:r]
                                                                  attributes:SNViewAttributes(run[@"attributes"])]];
    }
    return s;
}

/* Each run of the same attributes in range (gnustep-base has no
   -enumerateAttributesInRange:options:usingBlock:). */
static void SNEachRun(NSAttributedString *s, NSRange range, void (^block)(NSDictionary *attrs, NSRange run)) {
    NSUInteger i = range.location;
    while (i < NSMaxRange(range)) {
        NSRange run;
        NSDictionary *attrs = [s attributesAtIndex:i longestEffectiveRange:&run inRange:range];
        run = NSIntersectionRange(run, NSMakeRange(i, NSMaxRange(range) - i));
        if (!run.length) break;
        block(attrs ?: @{}, run);
        i = NSMaxRange(run);
    }
}

/* Where a position is after an edit made before it. */
static NSUInteger SNMoved(NSUInteger p, TTEdit *e) {
    NSRange r = e.range;
    switch (e.kind) {
    case TTEditInsert: return r.location < p ? p + r.length : p;
    case TTEditDelete: return p >= NSMaxRange(r) ? p - r.length : (p > r.location ? r.location : p);
    case TTEditAttributes: return p;
    }
    return p;
}

#pragma mark the binding

@implementation SNTextBinding {
    BOOL _applying;
}

- (instancetype)initWithStorage:(NSTextStorage *)storage editor:(SNNoteEditor *)editor {
    if (!(self = [super init])) return nil;
    _storage = storage;
    _editor = editor;
    _applying = YES;
    [_storage setAttributedString:SNViewString(editor.text)];
    _applying = NO;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(storageEdited:)
                                                 name:NSTextStorageDidProcessEditingNotification object:storage];
    __weak SNTextBinding *weak = self;
    editor.didMerge = ^(NSArray<TTEdit *> *edits) {
        [weak applyEdits:edits];
    };
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)unbind {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _editor.didMerge = nil;
}

/* What the user did to the storage, done to the text. */
- (void)storageEdited:(NSNotification *)n {
    if (_applying) return;
    TopoText *t = _editor.text;
    NSUInteger mask = _storage.editedMask;
    NSRange r = _storage.editedRange;
    NSInteger delta = _storage.changeInLength;
    if (r.location == NSNotFound) return;
    if (mask & NSTextStorageEditedCharacters) {
        NSRange old = NSMakeRange(r.location, (NSUInteger)((NSInteger)r.length - delta));
        if (NSMaxRange(old) > t.length) old = NSMakeRange(MIN(r.location, t.length), t.length - MIN(r.location, t.length));
        [t deleteCharactersInRange:old];
        __block NSUInteger at = old.location;
        NSString *string = _storage.string;
        SNEachRun(_storage, r, ^(NSDictionary *attrs, NSRange run) {
            [t insertString:[string substringWithRange:run] atIndex:at attributes:SNTextAttributes(attrs)];
            at += run.length;
        });
    } else if (mask & NSTextStorageEditedAttributes) {
        SNEachRun(_storage, r, ^(NSDictionary *attrs, NSRange run) {
            NSDictionary *want = SNTextAttributes(attrs);
            NSUInteger i = run.location;
            while (i < NSMaxRange(run)) {
                NSRange have;
                NSDictionary *now = [t attributesAtIndex:i effectiveRange:&have];
                NSRange part = NSMakeRange(i, MIN(NSMaxRange(have), NSMaxRange(run)) - i);
                if (![now isEqualToDictionary:want]) [t setAttributes:want range:part];
                i = NSMaxRange(part);
            }
        });
    } else {
        return;
    }
    /* Never apart: when an edit came grouped in a way not followed, the
       text is made the storage's again. */
    if (![t.string isEqualToString:_storage.string]) {
        NSMutableAttributedString *mapped = [[NSMutableAttributedString alloc] initWithString:_storage.string];
        SNEachRun(_storage, NSMakeRange(0, _storage.length), ^(NSDictionary *attrs, NSRange run) {
            [mapped setAttributes:SNTextAttributes(attrs) range:run];
        });
        [t setAttributedString:mapped];
    }
    [_editor textDidChange];
}

/* What a sync merged into the text, done to the storage. */
- (void)applyEdits:(NSArray<TTEdit *> *)edits {
    NSRange sel = _getSelection ? _getSelection() : NSMakeRange(NSNotFound, 0);
    NSUInteger start = sel.location, end = sel.location == NSNotFound ? NSNotFound : NSMaxRange(sel);
    _applying = YES;
    [_storage beginEditing];
    for (TTEdit *e in edits) {
        switch (e.kind) {
        case TTEditInsert:
            [_storage replaceCharactersInRange:NSMakeRange(e.range.location, 0)
                          withAttributedString:[[NSAttributedString alloc] initWithString:e.string attributes:SNViewAttributes(e.attributes)]];
            break;
        case TTEditDelete:
            [_storage deleteCharactersInRange:e.range];
            break;
        case TTEditAttributes:
            [_storage setAttributes:SNViewAttributes(e.attributes) range:e.range];
            break;
        }
        if (start != NSNotFound) {
            start = SNMoved(start, e);
            end = SNMoved(end, e);
        }
    }
    [_storage endEditing];
    _applying = NO;
    if (start != NSNotFound && _setSelection) {
        NSUInteger len = _storage.length;
        start = MIN(start, len);
        _setSelection(NSMakeRange(start, MIN(MAX(end, start), len) - start));
    }
    if (_didApplyRemoteEdits) _didApplyRemoteEdits();
}

#pragma mark formatting

- (NSDictionary *)textAttributesAt:(NSUInteger)index {
    if (!_storage.length) return @{};
    index = MIN(index, _storage.length - 1);
    return SNTextAttributes([_storage attributesAtIndex:index effectiveRange:NULL]);
}

- (BOOL)range:(NSRange)range has:(NSString *)key {
    NSUInteger i = range.length ? range.location : (range.location ? range.location - 1 : 0);
    id v = [self textAttributesAt:i][key];
    return [key isEqual:SNStyleKey] ? v != nil : [v boolValue];
}

/* Each run's attributes changed as change says, its others (a paragraph
   style, say) kept. */
- (void)change:(NSRange)range with:(void (^)(NSMutableDictionary *attrs))change {
    if (!range.length) return;
    [_storage beginEditing];
    SNEachRun(_storage, range, ^(NSDictionary *view, NSRange run) {
        NSMutableDictionary *t = [SNTextAttributes(view) mutableCopy];
        change(t);
        NSMutableDictionary *v = [view mutableCopy];
        for (NSString *k in @[ NSFontAttributeName, NSUnderlineStyleAttributeName, NSStrikethroughStyleAttributeName, SNStyleAttributeName,
                               SNBoldAttributeName, SNItalicAttributeName ])
            [v removeObjectForKey:k];
        [v addEntriesFromDictionary:SNViewAttributes(t)];
        [self->_storage setAttributes:v range:run];
    });
    [_storage endEditing];
}

- (void)toggle:(NSString *)key inRange:(NSRange)range {
    BOOL on = ![self range:range has:key];
    [self change:range with:^(NSMutableDictionary *t) {
        if (on) t[key] = @YES; else [t removeObjectForKey:key];
    }];
}

- (void)setStyle:(NSString *)style forParagraphsInRange:(NSRange)range {
    NSRange p = [_storage.string paragraphRangeForRange:range];
    [self change:p with:^(NSMutableDictionary *t) {
        if (SNIsStyle(style)) {
            t[SNStyleKey] = style;
            [t removeObjectForKey:SNBoldKey];
        } else {
            [t removeObjectForKey:SNStyleKey];
        }
    }];
}

- (NSDictionary *)typingAttributesAt:(NSUInteger)index {
    return SNViewAttributes(index ? [self textAttributesAt:index - 1] : [self textAttributesAt:0]);
}

@end
