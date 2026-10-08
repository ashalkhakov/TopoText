#import "SNRichText.h"
#import "SNNotes.h"
#import "SNModel.h"
#import "SNTextSystem.h"

NSString * const SNBoldKey = @"bold";
NSString * const SNItalicKey = @"italic";
NSString * const SNUnderlineKey = @"underline";
NSString * const SNStrikeKey = @"strike";
NSString * const SNLinkKey = @"link";
NSString * const SNStyleKey = @"style";
NSString * const SNStyleTitle = @"title";
NSString * const SNStyleHeading = @"heading";
NSString * const SNStyleSubheading = @"subheading";
NSString * const SNStyleMono = @"mono";
NSString * const SNListKey = @"list";
NSString * const SNListBullet = @"bullet";
NSString * const SNListDash = @"dash";
NSString * const SNListNumber = @"number";
NSString * const SNListCheck = @"check";
NSString * const SNCheckedKey = @"checked";
NSString * const SNIndentKey = @"indent";
NSString * const SNStyleAttributeName = @"SNStyle";
NSString * const SNListAttributeName = @"SNList";
NSString * const SNCheckedAttributeName = @"SNChecked";
NSString * const SNIndentAttributeName = @"SNIndent";
NSString * const SNLinkAttributeName = @"SNLink";
NSString * const SNAttachmentKey = @"attachment";
NSString * const SNAttachmentAttributeName = @"SNAttachment";
const double SNAttachmentMaxPixels = 1600;
static const unichar SNAttachmentCharacter = 0xFFFC;
/* Bold and italic said beside the font too: a font with no italic face
   (or bold) still says what was meant. */
static NSString * const SNBoldAttributeName = @"SNBold";
static NSString * const SNItalicAttributeName = @"SNItalic";

static const NSInteger SNMaxIndent = 8;

NSSet<NSString *> *SNParagraphKeys(void) {
    static NSSet *keys;
    if (!keys) keys = [NSSet setWithObjects:SNStyleKey, SNListKey, SNCheckedKey, SNIndentKey, nil];
    return keys;
}

static BOOL SNIsStyle(id style) {
    return [style isEqual:SNStyleTitle] || [style isEqual:SNStyleHeading] || [style isEqual:SNStyleSubheading] ||
           [style isEqual:SNStyleMono];
}

/* A title, a heading or a subheading: bold by its style. */
static BOOL SNIsBoldStyle(id style) {
    return SNIsStyle(style) && ![style isEqual:SNStyleMono];
}

static BOOL SNIsList(id list) {
    return [list isEqual:SNListBullet] || [list isEqual:SNListDash] || [list isEqual:SNListNumber] || [list isEqual:SNListCheck];
}

static NSInteger SNIndentOf(id indent) {
    if (![indent isKindOfClass:[NSNumber class]]) return 0;
    return MAX(0, MIN(SNMaxIndent, [indent integerValue]));
}

/* A paragraph's formatting, as one: a list wins over a style (both, after
   a merge of two people's), checked only for a checklist item. */
static NSDictionary *SNParagraphOf(NSDictionary *attrs) {
    NSMutableDictionary *p = [NSMutableDictionary dictionary];
    id list = attrs[SNListKey], style = attrs[SNStyleKey];
    if (SNIsList(list)) {
        p[SNListKey] = list;
        if ([list isEqual:SNListCheck] && [attrs[SNCheckedKey] boolValue]) p[SNCheckedKey] = @YES;
    } else if (SNIsStyle(style)) {
        p[SNStyleKey] = style;
    }
    NSInteger indent = SNIndentOf(attrs[SNIndentKey]);
    if (indent) p[SNIndentKey] = @(indent);
    return p;
}

/* A character's own attributes, its paragraph's taken out. */
static NSMutableDictionary *SNInlineOf(NSDictionary *attrs) {
    NSMutableDictionary *t = [attrs mutableCopy];
    [t removeObjectsForKeys:SNParagraphKeys().allObjects];
    return t;
}

/* The paragraph a new line after one with p begins as: a checklist item
   not ticked, body after a title, as Apple Notes has it. */
static NSDictionary *SNNextParagraph(NSDictionary *p) {
    NSMutableDictionary *n = [SNParagraphOf(p) mutableCopy];
    [n removeObjectForKey:SNCheckedKey];
    if (SNIsBoldStyle(n[SNStyleKey])) [n removeObjectForKey:SNStyleKey];
    return n;
}

#pragma mark paragraphs of a string

/* Paragraphs end at \n only, as TopoText's. */
static NSUInteger SNParagraphStart(NSString *s, NSUInteger i) {
    while (i > 0 && [s characterAtIndex:i - 1] != '\n') i--;
    return i;
}

static NSUInteger SNParagraphEnd(NSString *s, NSUInteger i) {
    NSUInteger n = s.length;
    while (i < n && [s characterAtIndex:i] != '\n') i++;
    return i < n ? i + 1 : n;
}

/* The paragraphs a range touches, whole, their newlines included. */
static NSRange SNParagraphsRange(NSString *s, NSRange r) {
    NSUInteger start = SNParagraphStart(s, MIN(r.location, s.length));
    NSUInteger last = r.length ? NSMaxRange(r) - 1 : r.location;
    NSUInteger end = SNParagraphEnd(s, MIN(MAX(last, start), s.length));
    return NSMakeRange(start, end - start);
}

/* The text ends with an empty paragraph: no character to hold its
   formatting. */
static BOOL SNEndsEmpty(NSString *s) {
    return !s.length || [s characterAtIndex:s.length - 1] == '\n';
}

#pragma mark fonts

SNFont *SNFontFor(NSString *style, BOOL bold, BOOL italic) {
    static NSMutableDictionary *cache;
    if (!cache) cache = [NSMutableDictionary dictionary];
    if (!SNIsStyle(style)) style = nil;
    if (SNIsBoldStyle(style)) bold = YES;
    NSString *key = [NSString stringWithFormat:@"%@/%d/%d", style ?: @"", bold, italic];
    SNFont *font = cache[key];
    if (font) return font;
    CGFloat size = SNSystemFontSize(style);
    font = [style isEqual:SNStyleMono] ? SNSystemMonoFont(size, bold) : SNSystemFont(size, bold);
    if (italic) font = SNSystemFontWithTraits(font, NO, YES);
    cache[key] = font;
    return font;
}

/* The text in from the margin: an indent's, and a list marker's column. */
static NSParagraphStyle *SNParagraphStyle(NSInteger indent, BOOL list) {
    static NSMutableDictionary *cache;
    if (!cache) cache = [NSMutableDictionary dictionary];
    NSNumber *key = @(indent * 2 + (list ? 1 : 0));
    NSParagraphStyle *style = cache[key];
    if (style) return style;
    NSMutableParagraphStyle *m = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
    CGFloat x = (indent + (list ? 1 : 0)) * SNSystemIndentStep();
    m.firstLineHeadIndent = x;
    m.headIndent = x;
    cache[key] = style = [m copy];
    return style;
}

#pragma mark attributes

NSDictionary *SNViewAttributes(NSDictionary *attrs) {
    NSDictionary *p = SNParagraphOf(attrs);
    NSString *style = p[SNStyleKey], *list = p[SNListKey];
    NSMutableDictionary *v = [NSMutableDictionary dictionary];
    BOOL bold = [attrs[SNBoldKey] boolValue] && !SNIsBoldStyle(style), italic = [attrs[SNItalicKey] boolValue];
    v[NSFontAttributeName] = SNFontFor(style, bold, italic);
    if (bold) v[SNBoldAttributeName] = @YES;
    if (italic) v[SNItalicAttributeName] = @YES;
    v[NSForegroundColorAttributeName] = SNSystemTextColor();
    if ([attrs[SNUnderlineKey] boolValue]) v[NSUnderlineStyleAttributeName] = @(NSUnderlineStyleSingle);
    if ([attrs[SNStrikeKey] boolValue]) v[NSStrikethroughStyleAttributeName] = @(NSUnderlineStyleSingle);
    NSString *link = [attrs[SNLinkKey] isKindOfClass:[NSString class]] ? attrs[SNLinkKey] : nil;
    NSURL *url = link ? SNURLOfLink(link) : nil;
    if (url) {
        v[SNLinkAttributeName] = link;
        v[NSLinkAttributeName] = url;
    }
    if ([attrs[SNAttachmentKey] isKindOfClass:[NSString class]]) v[SNAttachmentAttributeName] = attrs[SNAttachmentKey];
    if (style) v[SNStyleAttributeName] = style;
    if (list) v[SNListAttributeName] = list;
    if (p[SNCheckedKey]) v[SNCheckedAttributeName] = @YES;
    if (p[SNIndentKey]) v[SNIndentAttributeName] = p[SNIndentKey];
    v[NSParagraphStyleAttributeName] = SNParagraphStyle(SNIndentOf(p[SNIndentKey]), list != nil);
    return v;
}

NSDictionary *SNTextAttributes(NSDictionary *view) {
    NSMutableDictionary *t = [NSMutableDictionary dictionary];
    t[SNStyleKey] = view[SNStyleAttributeName];
    t[SNListKey] = view[SNListAttributeName];
    t[SNCheckedKey] = view[SNCheckedAttributeName];
    t[SNIndentKey] = view[SNIndentAttributeName];
    t = [SNParagraphOf(t) mutableCopy];
    NSString *style = t[SNStyleKey];
    SNFont *font = view[NSFontAttributeName];
    if (font) {
        BOOL bold = NO, italic = NO;
        SNSystemTraitsOf(font, &bold, &italic);
        if (bold && !SNIsBoldStyle(style)) t[SNBoldKey] = @YES;
        if (italic) t[SNItalicKey] = @YES;
    }
    if ([view[SNBoldAttributeName] boolValue] && !SNIsBoldStyle(style)) t[SNBoldKey] = @YES;
    if ([view[SNItalicAttributeName] boolValue]) t[SNItalicKey] = @YES;
    if ([view[NSUnderlineStyleAttributeName] integerValue]) t[SNUnderlineKey] = @YES;
    if ([view[NSStrikethroughStyleAttributeName] integerValue]) t[SNStrikeKey] = @YES;
    if ([view[SNLinkAttributeName] isKindOfClass:[NSString class]]) t[SNLinkKey] = view[SNLinkAttributeName];
    if ([view[SNAttachmentAttributeName] isKindOfClass:[NSString class]]) t[SNAttachmentKey] = view[SNAttachmentAttributeName];
    return t;
}

/* The view's attributes that are ours, made from TopoText's: others (a
   link, say) are kept as they are. */
static NSArray *SNOwnViewKeys(void) {
    static NSArray *keys;
    if (!keys)
        keys = @[ NSFontAttributeName, NSForegroundColorAttributeName, NSUnderlineStyleAttributeName, NSStrikethroughStyleAttributeName,
                  NSParagraphStyleAttributeName, SNStyleAttributeName, SNListAttributeName, SNCheckedAttributeName,
                  SNIndentAttributeName, SNBoldAttributeName, SNItalicAttributeName, SNLinkAttributeName, NSLinkAttributeName,
                  SNAttachmentAttributeName ];
    return keys;
}

NSAttributedString *SNViewString(TopoText *text) {
    NSMutableAttributedString *s = [[NSMutableAttributedString alloc] init];
    NSString *string = text.string;
    for (NSValue *v in text.paragraphRanges) {
        NSRange para = v.rangeValue;
        if (!para.length) continue;
        NSDictionary *p = [text paragraphAttributesAtIndex:para.location keys:SNParagraphKeys()];
        NSUInteger i = para.location;
        while (i < NSMaxRange(para)) {
            NSRange run;
            NSDictionary *attrs = [text attributesAtIndex:i effectiveRange:&run];
            run = NSIntersectionRange(run, NSMakeRange(i, NSMaxRange(para) - i));
            NSMutableDictionary *a = SNInlineOf(attrs);
            [a addEntriesFromDictionary:p];
            [s appendAttributedString:[[NSAttributedString alloc] initWithString:[string substringWithRange:run]
                                                                      attributes:SNViewAttributes(a)]];
            i = NSMaxRange(run);
        }
    }
    return s;
}

/* The ranges of s's runs of the same attributes in range, in order
   (gnustep-base has no -enumerateAttributesInRange:options:usingBlock:). */
static NSArray<NSValue *> *SNAttributeRuns(NSAttributedString *s, NSRange range) {
    NSMutableArray *runs = [NSMutableArray array];
    NSUInteger i = range.location;
    while (i < NSMaxRange(range)) {
        NSRange run;
        [s attributesAtIndex:i longestEffectiveRange:&run inRange:range];
        run = NSIntersectionRange(run, NSMakeRange(i, NSMaxRange(range) - i));
        if (!run.length) break;
        [runs addObject:[NSValue valueWithRange:run]];
        i = NSMaxRange(run);
    }
    return runs;
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

#pragma mark attachments

static BOOL SNHasPrefix(NSData *data, const char *bytes, NSUInteger n) {
    return data.length >= n && memcmp(data.bytes, bytes, n) == 0;
}

NSData *SNImageDataForAttachment(NSData *data, NSString **type, double *width, double *height) {
    double w = 0, h = 0;
    if (!data.length || !SNSystemImagePixels(data, &w, &h) || w < 1 || h < 1) return nil;
    BOOL png = SNHasPrefix(data, "\x89PNG", 4), jpeg = SNHasPrefix(data, "\xFF\xD8\xFF", 3);
    double scale = MIN(1.0, SNAttachmentMaxPixels / MAX(w, h));
    if (scale >= 1.0 && (png || jpeg)) {
        *type = png ? @"image/png" : @"image/jpeg";
        *width = w;
        *height = h;
        return data;
    }
    NSUInteger tw = (NSUInteger)MAX(1.0, round(w * scale)), th = (NSUInteger)MAX(1.0, round(h * scale));
    NSData *out = SNSystemScaledImage(data, tw, th, png);
    if (!out) return nil;
    *type = png ? @"image/png" : @"image/jpeg";
    *width = tw;
    *height = th;
    return out;
}

static BOOL SNSameSize(SNSize a, SNSize b) {
    return a.width == b.width && a.height == b.height;
}

/* The attachment's view: an image as wide as it is, or as the text is; a
   table's room, its grid over it (a box until its size is known). */
static SNTextAttachment *SNShowAttachment(NSString *attachmentID, SNAttachment *attachment, CGFloat maxWidth, NSValue *room) {
    NSData *data = attachment.data;
    SNTextAttachment *a;
    if ([attachment.kind isEqual:SNAttachmentKindTable]) {
        SNSize size = { 240, 40 };
        if (room) [room getValue:&size];
        a = room ? SNSystemRoomAttachment(size) : SNSystemImageAttachment(nil, nil, size);
        a.loaded = room != nil;
    } else if ([attachment.kind isEqual:SNAttachmentKindFile]) {
        /* A card: its icon, its name, its kind and size. */
        NSString *name = [attachment.entity.attributesByName objectForKey:@"name"] ? attachment.name : nil;
        if (!name.length) name = @"File";
        a = SNSystemFileAttachment(data, name, SNFileDescription(name, data.length), MIN(maxWidth, 360));
        a.loaded = data != nil;
        a.textWidth = maxWidth;
    } else {
        double w = attachment.width.doubleValue, h = attachment.height.doubleValue;
        if (data && (w < 1 || h < 1)) SNSystemImagePixels(data, &w, &h);
        if (w < 1 || h < 1) { w = 160; h = 120; }
        double scale = MIN(MIN(1.0, maxWidth / w), SNSystemPointsPerPixel());
        SNSize size = { MAX(1, w * scale), MAX(1, h * scale) };
        a = SNSystemImageAttachment(data, attachment.type, size);
        a.loaded = data != nil;
        a.textWidth = maxWidth;
    }
    a.attachmentID = attachmentID;
    a.dataHash = data.hash;
    return a;
}

#pragma mark the binding

/* The undo step last registered, by any binding (the note's, a cell's):
   typing goes on in a step only while it is the last one. */
static __weak TTUndoStep *SNLastUndoStep;

@implementation SNTextBinding {
    BOOL _applying;
    /* What was typed since the paragraphs were last made one formatting
       (textDidChange), and where a line began after a newline typed. */
    NSRange _dirty;
    NSMutableIndexSet *_afterNewline;
    /* The empty last paragraph's formatting, when it was given one. */
    NSDictionary *_endParagraph;
    /* Images pasted or dropped, made attachments of the note: each view
       attachment, to have its id once the view's edit is done. */
    NSMapTable<NSTextAttachment *, NSString *> *_pendingAttachments;
    /* Tables' rooms, by attachment id (SNSize values). */
    NSMutableDictionary<NSString *, NSValue *> *_rooms;
    /* The text's width images were last sized to. */
    CGFloat _shownWidth;
    /* Undo: the step typing goes on in, and where it left off; the undo
       manager steps were registered with (to take them back on unbind). */
    TTUndoStep *_typingStep;
    NSUInteger _typingEnd;
    NSUndoManager *_undoManager;
}

- (instancetype)initWithTextView:(id<SNTextViewing>)view editor:(id<SNTextSource>)editor {
    if (!(self = [super init])) return nil;
    _view = view;
    _storage = view.textStorage;
    _editor = editor;
    _dirty = NSMakeRange(NSNotFound, 0);
    _afterNewline = [NSMutableIndexSet indexSet];
    _pendingAttachments = [NSMapTable strongToStrongObjectsMapTable];
    _rooms = [NSMutableDictionary dictionary];
    _applying = YES;
    /* Each attachment's character with its view from the first: a U+FFFC
       without one is taken out of the text by gnustep-gui's attribute
       fixing. */
    NSMutableAttributedString *shown = [SNViewString(editor.text) mutableCopy];
    [self showAttachmentsIn:shown range:NSMakeRange(0, shown.length)];
    [_storage setAttributedString:shown];
    _applying = NO;
    [self showTagsInRange:NSMakeRange(0, _storage.length)];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(storageEdited:)
                                                 name:NSTextStorageDidProcessEditingNotification object:_storage];
    _shownWidth = [self attachmentWidth];
    SNSystemObserveResizing(view, self, @selector(resized:));
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_undoManager removeAllActionsWithTarget:self];
}

- (void)unbind {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self endUndoRecording];
    /* An undo manager keeps its targets unretained. */
    [_undoManager removeAllActionsWithTarget:self];
    _undoManager = nil;
}

#pragma mark undo

/* Before the binding writes what the user did into the text: the edits of
   this event kept as one undo step, registered with the view's undo manager
   as it begins; typing that goes on where it left off (a character typed,
   or deleted, at its end) kept in the typing's step, as a text view keeps
   typing one undo. By the characters' ids (TopoText (Undo)): a sync's
   edits merged in meanwhile do not make it wrong. */
- (void)recordEditOf:(NSRange)r replacing:(NSRange)old characters:(BOOL)characters {
    TopoText *t = _editor.text;
    if (!t.recordingUndoStep) {
        NSUndoManager *last = SNSystemUndoManager(_view);
        BOOL typing = characters && _typingStep && _typingStep == SNLastUndoStep && last.canUndo &&
                      ((!old.length && r.location == _typingEnd) || (!r.length && old.length == 1 && NSMaxRange(old) == _typingEnd));
        if (typing) {
            [t continueUndoStep:_typingStep];
        } else {
            [t beginUndoStep];
            NSUndoManager *um = SNSystemUndoManager(_view);
            if (um) {
                _undoManager = um;
                [um registerUndoWithTarget:self selector:@selector(undoStep:) object:t.recordingUndoStep];
                SNLastUndoStep = t.recordingUndoStep;
            }
        }
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(endUndoRecording) object:nil];
        [self performSelector:@selector(endUndoRecording) withObject:nil afterDelay:0];
    }
    /* A character typed or deleted: typing, which may go on. */
    BOOL typed = characters && ((!old.length && r.length) || (!r.length && old.length == 1)) &&
                 (!old.length ? ![[_storage.string substringWithRange:r] containsString:@"\n"] : YES);
    _typingStep = typed ? t.recordingUndoStep : nil;
    _typingEnd = typed ? (old.length ? old.location : NSMaxRange(r)) : NSNotFound;
}

/* The event's step done with: what comes next is a step of its own. */
- (void)endUndoRecording {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(endUndoRecording) object:nil];
    TopoText *t = _editor.text;
    if (t.recordingUndoStep) [t endUndoStep];
}

/* A step undone (or redone): its edits undone in the text, as edits of this
   copy's; what that did shown, chosen; the step that redoes it registered
   (as a redo, the undo manager being undoing). */
- (void)undoStep:(TTUndoStep *)step {
    [self endUndoRecording];
    _typingStep = nil;
    TopoText *t = _editor.text;
    TTUndoStep *redo = nil;
    NSArray<TTEdit *> *edits = [t undoStep:step redoStep:&redo];
    NSUndoManager *um = SNSystemUndoManager(_view) ?: _undoManager;
    [um registerUndoWithTarget:self selector:@selector(undoStep:) object:redo];
    SNLastUndoStep = nil;
    [self applyEdits:edits];
    /* The last thing it did, chosen: text put back selected; text taken out,
       the insertion point where it was. */
    TTEdit *last = edits.lastObject;
    if (last) {
        NSUInteger len = _storage.length, at = MIN(last.range.location, len);
        _view.selectedRange = last.kind == TTEditDelete ? NSMakeRange(at, 0) : NSMakeRange(at, MIN(last.range.length, len - at));
        [self selectionDidChange];
    }
    [_editor textDidChange];
    SNSystemTextChanged(_view);
}

/* The view's selection; NSNotFound when the view is gone. */
- (NSRange)selection {
    id<SNTextViewing> view = _view;
    return view ? view.selectedRange : NSMakeRange(NSNotFound, 0);
}

/* What is typed next, the view's and the list markers' (the empty last
   line's marker has no character to say it). */
- (void)setTyping:(NSDictionary *)viewAttributes {
    _view.typingAttributes = viewAttributes;
    for (NSLayoutManager *lm in _storage.layoutManagers)
        if ([lm isKindOfClass:[SNListLayoutManager class]]) ((SNListLayoutManager *)lm).extraLineAttributes = viewAttributes;
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
        [self recordEditOf:r replacing:old characters:YES];
        [t deleteCharactersInRange:old];
        NSUInteger at = old.location;
        NSString *string = _storage.string;
        for (NSValue *v in SNAttributeRuns(_storage, r)) {
            NSRange run = v.rangeValue;
            NSDictionary *view = [_storage attributesAtIndex:run.location effectiveRange:NULL];
            NSMutableDictionary *attrs = [SNTextAttributes(view) mutableCopy];
            NSTextAttachment *pasted = view[NSAttachmentAttributeName];
            /* An image pasted or dropped: one of the note's attachments now. */
            if (pasted && !attrs[SNAttachmentKey]) {
                NSString *made = [self attachmentForPasted:pasted];
                if (made) attrs[SNAttachmentKey] = made;
            }
            [t insertString:[string substringWithRange:run] atIndex:at attributes:attrs];
            at += run.length;
        }
        [self noteTyped:r replacing:old in:string];
    } else if (mask & NSTextStorageEditedAttributes) {
        /* Only the keys that changed: the others' registers are left to
           whoever wrote them last. */
        for (NSValue *v in SNAttributeRuns(_storage, r)) {
            NSRange run = v.rangeValue;
            NSDictionary *want = SNTextAttributes([_storage attributesAtIndex:run.location effectiveRange:NULL]);
            NSUInteger i = run.location;
            while (i < NSMaxRange(run)) {
                NSRange have;
                NSDictionary *now = [t attributesAtIndex:i effectiveRange:&have];
                NSRange part = NSMakeRange(i, MIN(NSMaxRange(have), NSMaxRange(run)) - i);
                NSMutableDictionary *diff = [NSMutableDictionary dictionary];
                NSMutableSet *keys = [NSMutableSet setWithArray:want.allKeys];
                [keys addObjectsFromArray:now.allKeys];
                for (NSString *k in keys)
                    if (![want[k] isEqual:now[k]]) diff[k] = want[k] ?: [NSNull null];
                if (diff.count) {
                    [self recordEditOf:part replacing:part characters:NO];
                    [t addAttributes:diff range:part];
                }
                i = NSMaxRange(part);
            }
        }
    } else {
        return;
    }
    /* Never apart: when an edit came grouped in a way not followed, the
       text is made the storage's again. */
    if (![t.string isEqualToString:_storage.string]) {
        NSMutableAttributedString *mapped = [[NSMutableAttributedString alloc] initWithString:_storage.string];
        for (NSValue *v in SNAttributeRuns(_storage, NSMakeRange(0, _storage.length))) {
            NSRange run = v.rangeValue;
            [mapped setAttributes:SNTextAttributes([_storage attributesAtIndex:run.location effectiveRange:NULL]) range:run];
        }
        [self recordEditOf:NSMakeRange(0, _storage.length) replacing:NSMakeRange(0, t.length) characters:NO];
        [t setAttributedString:mapped];
    }
    [_editor textDidChange];
}

/* Remembered for textDidChange: the paragraphs typed in, and the lines a
   typed newline began. */
- (void)noteTyped:(NSRange)r replacing:(NSRange)old in:(NSString *)string {
    _endParagraph = nil;
    NSInteger delta = (NSInteger)r.length - (NSInteger)old.length;
    if (_dirty.location != NSNotFound) {
        if (_dirty.location > old.location) _dirty.location = (NSUInteger)MAX((NSInteger)old.location, (NSInteger)_dirty.location + delta);
        _dirty = NSUnionRange(_dirty, r);
    } else {
        _dirty = r;
    }
    if (old.length) [_afterNewline removeIndexesInRange:NSMakeRange(old.location + 1, old.length)];
    [_afterNewline shiftIndexesStartingAtIndex:NSMaxRange(old) + 1 by:delta];
    for (NSUInteger i = r.location; i < NSMaxRange(r); i++)
        if ([string characterAtIndex:i] == '\n') [_afterNewline addIndex:i + 1];
}

/* What a sync merged into the text, done to the storage. */
- (void)applyEdits:(NSArray<TTEdit *> *)edits {
    NSRange sel = [self selection];
    NSUInteger start = sel.location, end = sel.location == NSNotFound ? NSNotFound : NSMaxRange(sel);
    _applying = YES;
    [_storage beginEditing];
    for (TTEdit *e in edits) {
        switch (e.kind) {
        case TTEditInsert: {
            NSMutableAttributedString *view = [[NSMutableAttributedString alloc] initWithString:e.string attributes:SNViewAttributes(e.attributes)];
            [self showAttachmentsIn:view range:NSMakeRange(0, view.length)];
            [_storage replaceCharactersInRange:NSMakeRange(e.range.location, 0) withAttributedString:view];
            break;
        }
        case TTEditDelete:
            [_storage deleteCharactersInRange:e.range];
            break;
        case TTEditAttributes:
            [_storage setAttributes:SNViewAttributes(e.attributes) range:e.range];
            [self showAttachmentsIn:_storage range:e.range];
            break;
        }
        if (e.kind != TTEditAttributes) _endParagraph = nil;
        if (start != NSNotFound) {
            start = SNMoved(start, e);
            end = SNMoved(end, e);
        }
    }
    /* Each paragraph shown as its newline says. */
    [self showParagraphsAsTheText];
    [_storage endEditing];
    _applying = NO;
    [self showTagsInRange:NSMakeRange(0, _storage.length)];
    [self showAttachmentsInRange:NSMakeRange(0, _storage.length)];
    _dirty = NSMakeRange(NSNotFound, 0);
    [_afterNewline removeAllIndexes];
    if (start != NSNotFound) {
        NSUInteger len = _storage.length;
        start = MIN(start, len);
        _view.selectedRange = NSMakeRange(start, MIN(MAX(end, start), len) - start);
    }
    [self selectionDidChange];
    /* Undo goes on: its steps are kept by ids, which a merge leaves right.
       Only typing's place has moved. */
    _typingStep = nil;
}

- (void)showParagraphsAsTheText {
    TopoText *t = _editor.text;
    if (![t.string isEqualToString:_storage.string]) return;
    for (NSValue *v in t.paragraphRanges) {
        NSRange para = v.rangeValue;
        if (!para.length) continue;
        [self setParagraph:[t paragraphAttributesAtIndex:para.location keys:SNParagraphKeys()] inRange:para];
    }
}

/* What is found in the paragraphs a range touches, shown as Apple Notes
   shows it: tags (#word) in the accent colour, web addresses typed as
   links. The view's only, nothing of the text's: a link given (SNLink)
   stays as it is. */
- (void)showTagsInRange:(NSRange)range {
    NSString *s = _storage.string;
    NSRange para = SNParagraphsRange(s, range);
    if (!para.length) return;
    NSString *text = [s substringWithRange:para];
    BOOL was = _applying;
    _applying = YES;
    [_storage beginEditing];
    [_storage addAttribute:NSForegroundColorAttributeName value:SNSystemTextColor() range:para];
    for (NSValue *v in SNTagRangesInText(text)) {
        NSRange tag = v.rangeValue;
        tag.location += para.location;
        [_storage addAttribute:NSForegroundColorAttributeName value:SNSystemAccentColor() range:tag];
    }
    /* Detected links: off where none is now, on where one is. */
    for (NSValue *v in SNAttributeRuns(_storage, para)) {
        NSRange run = v.rangeValue;
        if (![_storage attribute:SNLinkAttributeName atIndex:run.location effectiveRange:NULL])
            [_storage removeAttribute:NSLinkAttributeName range:run];
    }
    for (NSValue *v in SNLinkRangesInText(text)) {
        NSRange found = v.rangeValue;
        found.location += para.location;
        NSURL *url = SNURLOfLink([s substringWithRange:found]);
        if (!url) continue;
        for (NSValue *r in SNAttributeRuns(_storage, found)) {
            NSRange run = r.rangeValue;
            if (![_storage attribute:SNLinkAttributeName atIndex:run.location effectiveRange:NULL])
                [_storage addAttribute:NSLinkAttributeName value:url range:run];
        }
    }
    [_storage endEditing];
    _applying = was;
}

#pragma mark attachments

/* What the editor has of attachments: a note's; a cell's none. */
- (SNAttachment *)attachmentWithID:(NSString *)attachmentID {
    return [_editor respondsToSelector:@selector(attachmentWithID:)] ? [_editor attachmentWithID:attachmentID] : nil;
}

- (NSString *)addImageData:(NSData *)data type:(NSString *)type width:(double)w height:(double)h {
    return [_editor respondsToSelector:@selector(addImageData:type:width:height:)] ? [_editor addImageData:data type:type width:w height:h] : nil;
}

- (NSString *)addTableWithRows:(NSUInteger)rows columns:(NSUInteger)columns {
    return [_editor respondsToSelector:@selector(addTableWithRows:columns:)] ? [_editor addTableWithRows:rows columns:columns] : nil;
}

- (NSString *)addFileData:(NSData *)data name:(NSString *)name {
    if (!data || data.length > SNAttachmentMaxFileBytes || ![_editor respondsToSelector:@selector(addFileData:name:type:)]) return nil;
    return [_editor addFileData:data name:name type:SNTypeOfFileNamed(name)];
}

/* How wide an image may be shown: the text's width. */
- (CGFloat)attachmentWidth {
    NSLayoutManager *lm = _storage.layoutManagers.firstObject;   /* typed: gnustep-gui's array is not */
    NSTextContainer *c = lm.textContainers.firstObject;
    /* TextKit 2's text view has no layout manager: its own container. */
    id view = _view;
    if (!c && [view respondsToSelector:@selector(textContainer)]) c = [view textContainer];
    CGFloat w = c ? SNSystemContainerWidth(c) - 2 * c.lineFragmentPadding - 4 : 0;
    return w > 40 && w < 4000 ? w : 480;
}

/* The note's attachments in a range of a view's string shown: each U+FFFC
   with an id has its image (a box while it has not come). */
- (void)showAttachmentsIn:(NSMutableAttributedString *)target range:(NSRange)range {
    NSString *s = target.string;
    /* An image is made again when the text is no longer as wide as it was
       sized to: smaller to fit, or as large as it is again. */
    CGFloat width = [self attachmentWidth];
    range = NSIntersectionRange(range, NSMakeRange(0, s.length));
    for (NSUInteger i = range.location; i < NSMaxRange(range); i++) {
        if ([s characterAtIndex:i] != SNAttachmentCharacter) continue;
        NSString *attachmentID = [target attribute:SNAttachmentAttributeName atIndex:i effectiveRange:NULL];
        if (!attachmentID) continue;
        SNTextAttachment *shown = [target attribute:NSAttachmentAttributeName atIndex:i effectiveRange:NULL];
        SNAttachment *attachment = [self attachmentWithID:attachmentID];
        NSValue *room = [attachment.kind isEqual:SNAttachmentKindTable] ? _rooms[attachmentID] : nil;
        if ([shown isKindOfClass:[SNTextAttachment class]] && [shown.attachmentID isEqual:attachmentID]) {
            SNSize size = { 0, 0 };
            if (room) [room getValue:&size];
            if (room ? SNSameSize(shown.room, size) : (shown.loaded && shown.dataHash == attachment.data.hash && shown.room.width == 0 &&
                                                       (shown.textWidth == 0 || shown.textWidth == width)))
                continue;
            if (!room && !attachment.data) continue;
        }
        [target addAttribute:NSAttachmentAttributeName value:SNShowAttachment(attachmentID, attachment, width, room)
                       range:NSMakeRange(i, 1)];
    }
}

- (void)showAttachmentsInRange:(NSRange)range {
    BOOL was = _applying;
    _applying = YES;
    [_storage beginEditing];
    [self showAttachmentsIn:_storage range:range];
    [_storage endEditing];
    _applying = was;
}

- (void)refreshAttachments {
    [self showAttachmentsInRange:NSMakeRange(0, _storage.length)];
}

- (void)textWidthMayHaveChanged {
    CGFloat width = [self attachmentWidth];
    if (width == _shownWidth) return;
    _shownWidth = width;
    [self refreshAttachments];
}

- (void)resized:(NSNotification *)n {
    [self textWidthMayHaveChanged];
}

- (void)setRoomSize:(SNSize)size forAttachmentID:(NSString *)attachmentID {
    NSValue *room = [NSValue valueWithBytes:&size objCType:@encode(SNSize)];
    if ([_rooms[attachmentID] isEqual:room]) return;
    _rooms[attachmentID] = room;
    [self refreshAttachments];
}

/* A pasted image (or file) saved as one of the note's attachments, its id; its view
   attachment is given the id once the view's edit is done (not while the
   storage is still processing it). */
- (NSString *)attachmentForPasted:(NSTextAttachment *)pasted {
    NSString *made = [_pendingAttachments objectForKey:pasted];
    if (made) return made;
    NSString *type = nil;
    double w = 0, h = 0;
    NSData *raw = SNSystemDataOfAttachment(pasted);
    NSData *data = SNImageDataForAttachment(raw, &type, &w, &h);
    if (data) {
        made = [self addImageData:data type:type width:w height:h];
    } else {
        /* Not an image: a file, by its name (a PDF dropped, say). */
        NSString *name = pasted.fileWrapper.preferredFilename ?: pasted.fileWrapper.filename;
        if (raw && name.length) made = [self addFileData:raw name:name];
    }
    if (!made) return nil;
    [_pendingAttachments setObject:made forKey:pasted];
    [self performSelector:@selector(idsForPastedAttachments) withObject:nil afterDelay:0];
    return made;
}

- (void)idsForPastedAttachments {
    if (!_pendingAttachments.count) return;
    NSString *s = _storage.string;
    BOOL was = _applying;
    _applying = YES;
    [_storage beginEditing];
    for (NSUInteger i = 0; i < s.length; i++) {
        if ([s characterAtIndex:i] != SNAttachmentCharacter) continue;
        NSTextAttachment *a = [_storage attribute:NSAttachmentAttributeName atIndex:i effectiveRange:NULL];
        NSString *made = a ? [_pendingAttachments objectForKey:a] : nil;
        if (!made) continue;
        [_storage addAttribute:SNAttachmentAttributeName value:made range:NSMakeRange(i, 1)];
        [_storage addAttribute:NSAttachmentAttributeName value:SNShowAttachment(made, [self attachmentWithID:made], [self attachmentWidth], _rooms[made])
                         range:NSMakeRange(i, 1)];
    }
    [_storage endEditing];
    [_pendingAttachments removeAllObjects];
    _applying = was;
}

- (NSString *)insertTableWithRows:(NSUInteger)rows columns:(NSUInteger)columns inRange:(NSRange)range {
    NSString *made = [self addTableWithRows:rows columns:columns];
    if (!made) return nil;
    [self insertAttachment:made inRange:range];
    return made;
}

- (NSString *)attachmentIDAt:(NSUInteger)index {
    return index < _storage.length ? [_storage attribute:SNAttachmentAttributeName atIndex:index effectiveRange:NULL] : nil;
}

/* The attachment's character in place of the range, shown. */
- (void)insertAttachment:(NSString *)attachmentID inRange:(NSRange)range {
    NSMutableDictionary *t = [SNTextAttributes([self typingAttributesAt:range.location]) mutableCopy];
    t[SNAttachmentKey] = attachmentID;
    NSMutableDictionary *view = [SNViewAttributes(t) mutableCopy];
    view[NSAttachmentAttributeName] = SNShowAttachment(attachmentID, [self attachmentWithID:attachmentID], [self attachmentWidth], _rooms[attachmentID]);
    unichar c = SNAttachmentCharacter;
    [_storage replaceCharactersInRange:range
                  withAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithCharacters:&c length:1] attributes:view]];
}

- (BOOL)insertFileData:(NSData *)data name:(NSString *)name inRange:(NSRange)range {
    NSString *made = [self addFileData:data name:name.length ? name : @"File"];
    if (!made) return NO;
    [self insertAttachment:made inRange:range];
    return YES;
}

- (BOOL)insertImageData:(NSData *)data inRange:(NSRange)range {
    NSString *type = nil;
    double w = 0, h = 0;
    NSData *image = SNImageDataForAttachment(data, &type, &w, &h);
    if (!image) return NO;
    NSString *made = [self addImageData:image type:type width:w height:h];
    if (!made) return NO;
    [self insertAttachment:made inRange:range];
    return YES;
}

#pragma mark formatting

- (NSDictionary *)textAttributesAt:(NSUInteger)index {
    if (!_storage.length) return @{};
    index = MIN(index, _storage.length - 1);
    return SNTextAttributes([_storage attributesAtIndex:index effectiveRange:NULL]);
}

- (NSDictionary *)typing {
    NSDictionary *v = _view.typingAttributes;
    return v ? SNTextAttributes(v) : @{};
}

- (BOOL)range:(NSRange)range has:(NSString *)key {
    if ([SNParagraphKeys() containsObject:key]) return [self paragraphAttributesAt:range.location][key] != nil;
    if (!range.length && _view) return [[self typing][key] boolValue];
    NSUInteger i = range.length ? range.location : (range.location ? range.location - 1 : 0);
    return [[self textAttributesAt:i][key] boolValue];
}

/* These of the text's attributes set on the range (NSNull: removed, as
   TopoText's -addAttributes:range:), where that changes them; the view's
   others (a link, say) kept. */
- (void)setTextAttributes:(NSDictionary *)changes inRange:(NSRange)range {
    [_storage beginEditing];
    for (NSValue *v in SNAttributeRuns(_storage, range)) {
        NSRange run = v.rangeValue;
        NSDictionary *view = [_storage attributesAtIndex:run.location effectiveRange:NULL];
        NSDictionary *was = SNTextAttributes(view);
        NSMutableDictionary *t = [was mutableCopy];
        for (NSString *k in changes) {
            if ([changes[k] isKindOfClass:[NSNull class]]) [t removeObjectForKey:k];
            else t[k] = changes[k];
        }
        if ([t isEqualToDictionary:was]) continue;
        NSMutableDictionary *now = [view mutableCopy];
        [now removeObjectsForKeys:SNOwnViewKeys()];
        [now addEntriesFromDictionary:SNViewAttributes(t)];
        [_storage setAttributes:now range:run];
    }
    [_storage endEditing];
    [self showTagsInRange:range];
}

/* A paragraph's formatting, exactly p; the empty last paragraph's (no
   characters, an empty range at the end) kept for it. */
- (void)setParagraph:(NSDictionary *)p inRange:(NSRange)para {
    p = SNParagraphOf(p);
    if (!para.length) {
        if (para.location == _storage.length) _endParagraph = p;
        return;
    }
    NSMutableDictionary *changes = [NSMutableDictionary dictionary];
    for (NSString *k in SNParagraphKeys()) changes[k] = p[k] ?: [NSNull null];
    [self setTextAttributes:changes inRange:para];
}

- (void)toggle:(NSString *)key inRange:(NSRange)range {
    BOOL on = ![self range:range has:key];
    if (!range.length) {
        NSMutableDictionary *t = [[self typing] mutableCopy];
        if (on) t[key] = @YES; else [t removeObjectForKey:key];
        [self setTyping:SNViewAttributes(t)];
        return;
    }
    [self setTextAttributes:@{ key: on ? @YES : [NSNull null] } inRange:range];
}

- (void)setLink:(NSString *)link inRange:(NSRange)range {
    if (!range.length) return;
    NSString *trimmed = [link stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [self setTextAttributes:@{ SNLinkKey: trimmed.length ? trimmed : [NSNull null] } inRange:range];
}

- (NSString *)linkAt:(NSUInteger)index {
    if (index >= _storage.length) return nil;
    return [_storage attribute:SNLinkAttributeName atIndex:index effectiveRange:NULL];
}

- (NSRange)paragraphsRangeForRange:(NSRange)range {
    return SNParagraphsRange(_storage.string, range);
}

/* The empty last paragraph's formatting: as given, or as the line before
   goes on (a list goes on, a title does not). */
- (NSDictionary *)endParagraph {
    if (_endParagraph) return _endParagraph;
    NSUInteger len = _storage.length;
    return len ? SNNextParagraph([self textAttributesAt:len - 1]) : @{};
}

- (NSDictionary *)paragraphAttributesAt:(NSUInteger)index {
    NSString *s = _storage.string;
    index = MIN(index, s.length);
    if (index == s.length && SNEndsEmpty(s)) return [self endParagraph];
    return SNParagraphOf([self textAttributesAt:SNParagraphStart(s, index)]);
}

/* The paragraphs the range touches, each one's range, its newline
   included; the empty last one, when touched, an empty range at the end. */
- (NSArray<NSValue *> *)paragraphRangesIn:(NSRange)range {
    NSString *s = _storage.string;
    NSMutableArray *all = [NSMutableArray array];
    NSRange whole = SNParagraphsRange(s, range);
    for (NSUInteger i = whole.location; i < NSMaxRange(whole); i = SNParagraphEnd(s, i))
        [all addObject:[NSValue valueWithRange:NSMakeRange(i, SNParagraphEnd(s, i) - i)]];
    if (NSMaxRange(range) >= s.length && SNEndsEmpty(s)) [all addObject:[NSValue valueWithRange:NSMakeRange(s.length, 0)]];
    return all;
}

/* After paragraphs were changed: typing goes on as they are now. */
- (void)paragraphsChanged {
    [self refreshTypingKeepingInline:YES];
}

- (void)setStyle:(NSString *)style forParagraphsInRange:(NSRange)range {
    for (NSValue *v in [self paragraphRangesIn:range]) {
        NSMutableDictionary *p = [[self paragraphAttributesAt:v.rangeValue.location] mutableCopy];
        [p removeObjectsForKeys:@[ SNListKey, SNCheckedKey ]];
        if (SNIsStyle(style)) p[SNStyleKey] = style; else [p removeObjectForKey:SNStyleKey];
        [self setParagraph:p inRange:v.rangeValue];
    }
    [self paragraphsChanged];
}

- (void)toggleList:(NSString *)list forParagraphsInRange:(NSRange)range {
    if (!SNIsList(list)) return;
    NSArray<NSValue *> *paragraphs = [self paragraphRangesIn:range];
    BOOL all = YES;
    for (NSValue *v in paragraphs) all = all && [[self paragraphAttributesAt:v.rangeValue.location][SNListKey] isEqual:list];
    for (NSValue *v in paragraphs) {
        NSMutableDictionary *p = [[self paragraphAttributesAt:v.rangeValue.location] mutableCopy];
        if (all) {
            [p removeObjectsForKeys:@[ SNListKey, SNCheckedKey ]];
        } else {
            if (![p[SNListKey] isEqual:list]) [p removeObjectForKey:SNCheckedKey];
            [p removeObjectForKey:SNStyleKey];
            p[SNListKey] = list;
        }
        [self setParagraph:p inRange:v.rangeValue];
    }
    [self paragraphsChanged];
}

- (BOOL)isCheckItemAt:(NSUInteger)start {
    return [[self paragraphAttributesAt:start][SNListKey] isEqual:SNListCheck] && start < _storage.length;
}

- (NSRange)checklistRangeAt:(NSUInteger)index {
    NSString *s = _storage.string;
    NSUInteger start = SNParagraphStart(s, MIN(index, s.length));
    if (![self isCheckItemAt:start]) return NSMakeRange(NSNotFound, 0);
    while (start > 0 && [self isCheckItemAt:SNParagraphStart(s, start - 1)]) start = SNParagraphStart(s, start - 1);
    NSUInteger end = SNParagraphEnd(s, start);
    while (end < s.length && [self isCheckItemAt:end]) end = SNParagraphEnd(s, end);
    return NSMakeRange(start, end - start);
}

- (BOOL)moveCheckedToBottomOfChecklistAt:(NSUInteger)index {
    NSRange list = [self checklistRangeAt:index];
    if (list.location == NSNotFound) return NO;
    NSString *s = _storage.string;
    NSMutableArray<NSValue *> *items = [NSMutableArray array];
    for (NSUInteger i = list.location; i < NSMaxRange(list); i = SNParagraphEnd(s, i))
        [items addObject:[NSValue valueWithRange:NSMakeRange(i, SNParagraphEnd(s, i) - i)]];
    /* The ticked ones at the bottom already stay; those above an unticked
       one move. */
    NSUInteger tail = items.count;
    while (tail > 0 && [[self paragraphAttributesAt:items[tail - 1].rangeValue.location][SNCheckedKey] boolValue]) tail--;
    NSMutableArray<NSValue *> *moving = [NSMutableArray array];
    for (NSUInteger i = 0; i < tail; i++)
        if ([[self paragraphAttributesAt:items[i].rangeValue.location][SNCheckedKey] boolValue]) [moving addObject:items[i]];
    if (!moving.count) return NO;
    /* Each above the last item ends with its newline. They go above the
       ticked ones at the bottom already, keeping the ticked ones' order; or
       at the end when there are none. */
    NSMutableAttributedString *moved = [[NSMutableAttributedString alloc] init];
    for (NSValue *v in moving) [moved appendAttributedString:[_storage attributedSubstringFromRange:v.rangeValue]];
    NSUInteger at = tail < items.count ? items[tail].rangeValue.location : NSMaxRange(list);
    BOOL endsText = tail == items.count && NSMaxRange(list) == s.length && [s characterAtIndex:s.length - 1] != '\n';
    NSDictionary *lastItem = endsText ? [_storage attributesAtIndex:s.length - 1 effectiveRange:NULL] : nil;
    for (NSValue *v in moving.reverseObjectEnumerator) [_storage deleteCharactersInRange:v.rangeValue];
    for (NSValue *v in moving) at -= v.rangeValue.length;
    if (endsText) {
        /* After a last item with no newline: one before them (the item's
           own: a paragraph is its newline's), none after. */
        [moved deleteCharactersInRange:NSMakeRange(moved.length - 1, 1)];
        [moved insertAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:lastItem] atIndex:0];
    }
    [_storage insertAttributedString:moved atIndex:at];
    /* Moved, not typed: no new items to untick (textDidChange). */
    _dirty = NSMakeRange(NSNotFound, 0);
    [_afterNewline removeAllIndexes];
    [self showTagsInRange:NSMakeRange(list.location, NSMaxRange(list) - list.location)];
    return YES;
}

- (void)toggleCheckedForParagraphsInRange:(NSRange)range {
    NSArray<NSValue *> *paragraphs = [self paragraphRangesIn:range];
    NSNumber *first = nil;
    for (NSValue *v in paragraphs) {
        NSDictionary *p = [self paragraphAttributesAt:v.rangeValue.location];
        if ([p[SNListKey] isEqual:SNListCheck]) {
            first = @([p[SNCheckedKey] boolValue]);
            break;
        }
    }
    if (!first) return;
    for (NSValue *v in paragraphs) {
        NSMutableDictionary *p = [[self paragraphAttributesAt:v.rangeValue.location] mutableCopy];
        if (![p[SNListKey] isEqual:SNListCheck]) continue;
        if (!first.boolValue) p[SNCheckedKey] = @YES; else [p removeObjectForKey:SNCheckedKey];
        [self setParagraph:p inRange:v.rangeValue];
    }
    [self paragraphsChanged];
}

- (void)indentParagraphsInRange:(NSRange)range by:(NSInteger)by {
    for (NSValue *v in [self paragraphRangesIn:range]) {
        NSMutableDictionary *p = [[self paragraphAttributesAt:v.rangeValue.location] mutableCopy];
        NSInteger indent = MAX(0, MIN(SNMaxIndent, SNIndentOf(p[SNIndentKey]) + (by > 0 ? 1 : -1)));
        if (indent) p[SNIndentKey] = @(indent); else [p removeObjectForKey:SNIndentKey];
        [self setParagraph:p inRange:v.rangeValue];
    }
    [self paragraphsChanged];
}

- (NSDictionary *)typingAttributesAt:(NSUInteger)index {
    NSString *s = _storage.string;
    NSUInteger len = s.length;
    index = MIN(index, len);
    /* A character's own, from the one before, as typing goes on; at a
       paragraph's start, from its first. */
    NSUInteger from = NSNotFound;
    if (index > 0 && [s characterAtIndex:index - 1] != '\n') from = index - 1;
    else if (index < len) from = index;
    else if (index > 0) from = index - 1;
    NSMutableDictionary *t = from == NSNotFound ? [NSMutableDictionary dictionary] : SNInlineOf([self textAttributesAt:from]);
    /* A link ends where it ends: what is typed after it is not in it. */
    [t removeObjectForKey:SNLinkKey];
    [t addEntriesFromDictionary:[self paragraphAttributesAt:index]];
    return SNViewAttributes(t);
}

- (void)refreshTypingKeepingInline:(BOOL)keep {
    NSRange sel = [self selection];
    if (sel.location == NSNotFound || sel.length) return;
    NSMutableDictionary *t = [SNTextAttributes([self typingAttributesAt:sel.location]) mutableCopy];
    if (keep) {
        [t removeObjectsForKeys:SNInlineOf(t).allKeys];
        [t addEntriesFromDictionary:SNInlineOf([self typing])];
        [t removeObjectForKey:SNLinkKey];
    }
    [self setTyping:SNViewAttributes(t)];
}

- (void)selectionDidChange {
    /* The insertion point moved away: typing there is another step. */
    NSRange sel = [self selection];
    if (_typingStep && (sel.length || sel.location != _typingEnd)) _typingStep = nil;
    [self refreshTypingKeepingInline:NO];
}

#pragma mark typing in lists

- (BOOL)shouldChangeTextInRange:(NSRange)range replacementString:(NSString *)string {
    if (_applying || !string) return YES;
    NSString *s = _storage.string;
    NSRange sel = [self selection];
    if (!range.length && [string isEqualToString:@"\n"]) {
        /* Return on an empty item: the list ends there (outdented first). */
        NSRange para = SNParagraphsRange(s, NSMakeRange(range.location, 0));
        BOOL empty = !para.length || (para.length == 1 && [s characterAtIndex:para.location] == '\n');
        NSDictionary *p = [self paragraphAttributesAt:range.location];
        if (empty && p[SNListKey]) {
            NSMutableDictionary *q = [p mutableCopy];
            NSInteger indent = SNIndentOf(q[SNIndentKey]);
            if (indent) q[SNIndentKey] = @(indent - 1);
            else [q removeObjectsForKeys:@[ SNListKey, SNCheckedKey ]];
            [self setParagraph:q inRange:para];
            [self paragraphsChanged];
            return NO;
        }
    }
    if (!string.length && range.length == 1 && !sel.length && sel.location == NSMaxRange(range) &&
        [s characterAtIndex:range.location] == '\n') {
        /* Delete at an item's start: its marker goes, then the line joins
           the one before. */
        NSDictionary *p = [self paragraphAttributesAt:sel.location];
        if (p[SNListKey]) {
            NSMutableDictionary *q = [p mutableCopy];
            [q removeObjectsForKeys:@[ SNListKey, SNCheckedKey ]];
            [self setParagraph:q inRange:SNParagraphsRange(s, NSMakeRange(sel.location, 0))];
            [self paragraphsChanged];
            return NO;
        }
    }
    if (!range.length && [string isEqualToString:@"\t"] && [self paragraphAttributesAt:range.location][SNListKey]) {
        [self indentParagraphsInRange:NSMakeRange(range.location, 0) by:1];
        return NO;
    }
    return YES;
}

- (void)textDidChange {
    [self idsForPastedAttachments];
    NSString *s = _storage.string;
    if (_dirty.location != NSNotFound && _dirty.location <= s.length) {
        /* The line after too: a newline typed began it. */
        NSUInteger end = MIN(NSMaxRange(_dirty) + 1, s.length);
        NSRange d = NSMakeRange(_dirty.location, end - _dirty.location);
        [self showTagsInRange:d];
        NSRange whole = SNParagraphsRange(s, d);
        for (NSUInteger i = whole.location; i < NSMaxRange(whole); ) {
            NSUInteger next = SNParagraphEnd(s, i);
            NSRange para = NSMakeRange(i, next - i);
            /* The paragraph is its first character's: typed into, two
               joined, the upper one's stands, as in a text view. */
            NSMutableDictionary *p = [SNParagraphOf([self textAttributesAt:i]) mutableCopy];
            if ([_afterNewline containsIndex:i]) {
                [p removeObjectForKey:SNCheckedKey];
                BOOL empty = para.length == 1 && [s characterAtIndex:i] == '\n';
                if (empty && SNIsBoldStyle(p[SNStyleKey])) [p removeObjectForKey:SNStyleKey];
            }
            [self setParagraph:p inRange:para];
            i = next;
        }
    }
    _dirty = NSMakeRange(NSNotFound, 0);
    [_afterNewline removeAllIndexes];
    [self refreshTypingKeepingInline:NO];
}

@end

#pragma mark list markers

/* A character's first glyph (gnustep-gui's layout manager has no
   -glyphIndexForCharacterAtIndex:). */
static NSUInteger SNGlyphAt(NSLayoutManager *lm, NSUInteger i) {
    return [lm glyphRangeForCharacterRange:NSMakeRange(i, 1) actualCharacterRange:NULL].location;
}

@implementation SNListLayoutManager

- (void)setExtraLineAttributes:(NSDictionary *)attrs {
    if ([attrs isEqual:_extraLineAttributes]) return;
    _extraLineAttributes = [attrs copy];
    NSUInteger len = self.textStorage.length;
    if (len) SNSystemRedisplay(self, NSMakeRange(len - 1, 1));
}

/* After an edit, the whole text drawn again, not only what changed: a
   marker depends on the paragraphs before it (a number counts them, a
   checkbox moves with them). Once the edit is done: not while the storage
   is still processing it. */
- (void)markersMayHaveMoved {
    SNSystemRedisplay(self, NSMakeRange(0, self.textStorage.length));
}

- (void)textEdited {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(markersMayHaveMoved) object:nil];
    [self performSelector:@selector(markersMayHaveMoved) withObject:nil afterDelay:0];
}

/* Each edit: SNTextSystem's -textEdited, each system's own way. */

/* An item's number: one more than the item before at its indent, items
   indented further between them not counted. */
- (NSUInteger)numberAt:(NSUInteger)start indent:(NSInteger)indent {
    NSTextStorage *ts = self.textStorage;
    NSString *s = ts.string;
    NSUInteger n = 1, i = start;
    while (i > 0) {
        NSUInteger prev = SNParagraphStart(s, i - 1);
        NSDictionary *a = [ts attributesAtIndex:prev effectiveRange:NULL];
        NSInteger ind = SNIndentOf(a[SNIndentAttributeName]);
        if (a[SNListAttributeName] && ind > indent) { i = prev; continue; }
        if (![a[SNListAttributeName] isEqual:SNListNumber] || ind != indent) break;
        n++;
        i = prev;
    }
    return n;
}

/* The marker's column of a paragraph whose first line is line, from the
   text container's left edge at left (a line fragment begins at the
   indent on GNUstep, at the edge on Apple's). */
static SNRect SNMarkerColumn(SNRect line, NSInteger indent, CGFloat left) {
    SNRect r = line;
    r.origin.x = left + indent * SNSystemIndentStep();
    r.size.width = SNSystemIndentStep();
    return r;
}

- (void)drawMarker:(NSDictionary *)a start:(NSUInteger)start line:(SNRect)line left:(CGFloat)left baseline:(CGFloat)baseline {
    NSString *list = a[SNListAttributeName];
    NSInteger indent = SNIndentOf(a[SNIndentAttributeName]);
    SNRect col = SNMarkerColumn(line, indent, left);
    SNFont *font = SNFontFor(nil, NO, NO);
    if ([list isEqual:SNListCheck]) {
        CGFloat d = SNSystemCheckboxSize(font);
        CGFloat cx = col.origin.x + col.size.width / 2 - 2, cy = baseline - font.capHeight / 2;
        SNRect box = col;
        box.origin.x = cx - d / 2;
        box.origin.y = cy - d / 2;
        box.size.width = box.size.height = d;
        if ([a[SNCheckedAttributeName] boolValue]) {
            [SNSystemAccentColor() setFill];
            [[SNPath bezierPathWithOvalInRect:box] fill];
            SNPath *tick = [SNPath bezierPath];
            CGFloat x = box.origin.x, y = box.origin.y;
            SNPoint p1 = { x + d * 0.27, y + d * 0.52 }, p2 = { x + d * 0.43, y + d * 0.68 }, p3 = { x + d * 0.74, y + d * 0.34 };
            SNSystemAddLine(tick, p1, p2);
            SNSystemAddLine(tick, p2, p3);
            tick.lineWidth = MAX(1.5, d / 10);
            [[SNColor whiteColor] setStroke];
            [tick stroke];
        } else {
            box.origin.x += 0.6;
            box.origin.y += 0.6;
            box.size.width -= 1.2;
            box.size.height -= 1.2;
            SNPath *ring = [SNPath bezierPathWithOvalInRect:box];
            ring.lineWidth = 1.2;
            [SNSystemMarkerColor() setStroke];
            [ring stroke];
        }
        return;
    }
    NSString *marker = [list isEqual:SNListNumber] ? [NSString stringWithFormat:@"%lu.", (unsigned long)[self numberAt:start indent:indent]]
                     : [list isEqual:SNListDash] ? @"–" : @"•";
    NSDictionary *attrs = @{ NSFontAttributeName: font, NSForegroundColorAttributeName: SNSystemTextColor() };
    CGFloat w = [marker sizeWithAttributes:attrs].width;
    SNPoint at = { [list isEqual:SNListNumber] ? col.origin.x + col.size.width - 5 - w : col.origin.x + (col.size.width - w) / 2 - 2,
                   baseline - font.ascender };
    [marker drawAtPoint:at withAttributes:attrs];
}

- (void)drawGlyphsForGlyphRange:(NSRange)glyphs atPoint:(SNPoint)origin {
    [super drawGlyphsForGlyphRange:glyphs atPoint:origin];
    NSTextStorage *ts = self.textStorage;
    NSString *s = ts.string;
    NSUInteger len = s.length;
    NSRange chars = [self characterRangeForGlyphRange:glyphs actualGlyphRange:NULL];
    NSUInteger i = SNParagraphStart(s, MIN(chars.location, len));
    if (i < chars.location) i = SNParagraphEnd(s, i);
    for (; i < NSMaxRange(chars) && i < len; i = SNParagraphEnd(s, i)) {
        NSDictionary *a = [ts attributesAtIndex:i effectiveRange:NULL];
        if (!a[SNListAttributeName]) continue;
        NSUInteger g = SNGlyphAt(self, i);
        SNRect line = [self lineFragmentRectForGlyphAtIndex:g effectiveRange:NULL];
        line.origin.x += origin.x;
        line.origin.y += origin.y;
        [self drawMarker:a start:i line:line left:origin.x baseline:line.origin.y + [self locationForGlyphAtIndex:g].y];
    }
    /* The empty last line, an item begun there. */
    if (SNEndsEmpty(s) && _extraLineAttributes[SNListAttributeName] && NSMaxRange(glyphs) >= self.numberOfGlyphs) {
        SNRect line = self.extraLineFragmentRect;
        if (line.size.height <= 0) return;
        line.origin.x += origin.x;
        line.origin.y += origin.y;
        SNFont *font = SNFontFor(nil, NO, NO);
        [self drawMarker:_extraLineAttributes start:len line:line left:origin.x baseline:line.origin.y + font.ascender];
    }
}

- (NSUInteger)checkboxAtPoint:(SNPoint)point {
    NSTextStorage *ts = self.textStorage;
    NSString *s = ts.string;
    NSTextContainer *tc = self.textContainers.firstObject;
    if (!s.length || !tc) return NSNotFound;
    NSUInteger g = [self glyphIndexForPoint:point inTextContainer:tc];
    NSUInteger c = MIN([self characterIndexForGlyphAtIndex:g], s.length - 1);
    NSUInteger start = SNParagraphStart(s, c);
    NSDictionary *a = [ts attributesAtIndex:start effectiveRange:NULL];
    if (![a[SNListAttributeName] isEqual:SNListCheck]) return NSNotFound;
    SNRect line = [self lineFragmentRectForGlyphAtIndex:SNGlyphAt(self, start) effectiveRange:NULL];
    SNRect col = SNMarkerColumn(line, SNIndentOf(a[SNIndentAttributeName]), 0);
    BOOL inside = point.x >= col.origin.x - 4 && point.x < col.origin.x + col.size.width &&
                  point.y >= col.origin.y && point.y < col.origin.y + col.size.height;
    return inside ? start : NSNotFound;
}

@end
