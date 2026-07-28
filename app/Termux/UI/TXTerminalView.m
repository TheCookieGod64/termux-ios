//
//  TXTerminalView.m
//

#import "TXTerminalView.h"

#import <CoreText/CoreText.h>

@interface TXTerminalView () <UIGestureRecognizerDelegate>
@end

@implementation TXTerminalView {
    CADisplayLink *_displayLink;
    BOOL _needsRedraw;

    CGFloat _cellWidth;
    CGFloat _cellHeight;
    CGFloat _baselineOffset;

    CTFontRef _regularFont;
    CTFontRef _boldFont;
    CTFontRef _italicFont;
    CTFontRef _boldItalicFont;

    // Selection, in absolute buffer coordinates.
    BOOL _hasSelection;
    NSInteger _selectionStartRow, _selectionStartColumn;
    NSInteger _selectionEndRow, _selectionEndColumn;

    BOOL _cursorBlinkOn;
    NSTimeInterval _lastBlinkToggle;

    /// Leftover pan distance smaller than one row, per view instance.
    CGFloat _panAccumulator;
}

#pragma mark - Lifecycle

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    _colorScheme = [TXColorScheme defaultScheme];
    _lineSpacing = 0.0;
    _cursorBlinkOn = YES;
    self.opaque = YES;
    self.backgroundColor = _colorScheme.defaultBackground;
    self.contentMode = UIViewContentModeRedraw;
    self.clearsContextBeforeDrawing = NO;

    self.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];

    [self installGestureRecognizers];
    [self startDisplayLink];

    return self;
}

- (void)dealloc {
    [_displayLink invalidate];
    [self releaseFonts];
}

- (void)releaseFonts {
    if (_regularFont) { CFRelease(_regularFont); _regularFont = NULL; }
    if (_boldFont) { CFRelease(_boldFont); _boldFont = NULL; }
    if (_italicFont) { CFRelease(_italicFont); _italicFont = NULL; }
    if (_boldItalicFont) { CFRelease(_boldItalicFont); _boldItalicFont = NULL; }
}

#pragma mark - Font & metrics

- (void)setFont:(UIFont *)font {
    _font = font;
    [self releaseFonts];

    _regularFont = CTFontCreateWithName((__bridge CFStringRef)font.fontName, font.pointSize, NULL);

    UIFontDescriptor *descriptor = font.fontDescriptor;
    UIFontDescriptor *bold =
        [descriptor fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitBold |
                                                      UIFontDescriptorTraitMonoSpace];
    UIFontDescriptor *italic =
        [descriptor fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitItalic |
                                                      UIFontDescriptorTraitMonoSpace];
    UIFontDescriptor *boldItalic =
        [descriptor fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitBold |
                                                      UIFontDescriptorTraitItalic |
                                                      UIFontDescriptorTraitMonoSpace];

    _boldFont = bold ? CTFontCreateWithFontDescriptor((__bridge CTFontDescriptorRef)bold,
                                                      font.pointSize, NULL)
                     : (CTFontRef)CFRetain(_regularFont);
    _italicFont = italic ? CTFontCreateWithFontDescriptor((__bridge CTFontDescriptorRef)italic,
                                                          font.pointSize, NULL)
                         : (CTFontRef)CFRetain(_regularFont);
    _boldItalicFont = boldItalic
        ? CTFontCreateWithFontDescriptor((__bridge CTFontDescriptorRef)boldItalic,
                                         font.pointSize, NULL)
        : (CTFontRef)CFRetain(_boldFont);

    [self recomputeCellMetrics];
    [self updateGeometry];
    [self setNeedsScreenUpdate];
}

- (void)recomputeCellMetrics {
    // Measure a representative glyph rather than trusting the font's advance,
    // which is wrong for some fallback fonts.
    UniChar character = 'M';
    CGGlyph glyph = 0;
    CGSize advance = CGSizeZero;
    if (CTFontGetGlyphsForCharacters(_regularFont, &character, &glyph, 1)) {
        CTFontGetAdvancesForGlyphs(_regularFont, kCTFontOrientationHorizontal,
                                   &glyph, &advance, 1);
    }

    _cellWidth = advance.width > 0 ? ceil(advance.width * 100) / 100 : self.font.pointSize * 0.6;

    CGFloat ascent = CTFontGetAscent(_regularFont);
    CGFloat descent = CTFontGetDescent(_regularFont);
    CGFloat leading = CTFontGetLeading(_regularFont);
    _cellHeight = ceil(ascent + descent + leading) * (1.0 + _lineSpacing);
    _baselineOffset = descent + leading / 2 + (_cellHeight - (ascent + descent + leading)) / 2;
}

- (void)setLineSpacing:(CGFloat)lineSpacing {
    _lineSpacing = lineSpacing;
    [self recomputeCellMetrics];
    [self updateGeometry];
    [self setNeedsScreenUpdate];
}

- (CGSize)cellSize {
    return CGSizeMake(_cellWidth, _cellHeight);
}

- (NSInteger)rows {
    if (_cellHeight <= 0) return 24;
    return MAX((NSInteger)floor(self.bounds.size.height / _cellHeight), 1);
}

- (NSInteger)columns {
    if (_cellWidth <= 0) return 80;
    return MAX((NSInteger)floor(self.bounds.size.width / _cellWidth), 1);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self updateGeometry];
}

- (void)updateGeometry {
    NSInteger rows = self.rows;
    NSInteger columns = self.columns;
    if (rows <= 0 || columns <= 0) return;

    if (self.emulator && (self.emulator.rows != rows || self.emulator.columns != columns)) {
        [self.emulator resizeToRows:rows columns:columns];
    }
    if ([self.delegate respondsToSelector:@selector(terminalView:didResizeToRows:columns:)]) {
        [self.delegate terminalView:self didResizeToRows:rows columns:columns];
    }
    [self setNeedsScreenUpdate];
}

- (void)setColorScheme:(TXColorScheme *)colorScheme {
    _colorScheme = colorScheme;
    self.backgroundColor = colorScheme.defaultBackground;
    [self setNeedsScreenUpdate];
}

#pragma mark - Redraw scheduling

- (void)startDisplayLink {
    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(displayLinkFired:)];
    if (@available(iOS 15.0, *)) {
        _displayLink.preferredFrameRateRange = CAFrameRateRangeMake(10, 60, 60);
    }
    [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)displayLinkFired:(CADisplayLink *)link {
    // Blink the cursor at the traditional ~1.6 Hz.
    NSTimeInterval now = CACurrentMediaTime();
    if (now - _lastBlinkToggle > 0.6) {
        _lastBlinkToggle = now;
        _cursorBlinkOn = !_cursorBlinkOn;
        if (self.emulator.cursorVisible && _scrollOffset == 0) _needsRedraw = YES;
    }

    if (_needsRedraw) {
        _needsRedraw = NO;
        [self setNeedsDisplay];
    }
}

- (void)setNeedsScreenUpdate {
    _needsRedraw = YES;
}

#pragma mark - Scrolling

- (void)scrollToBottom {
    if (_scrollOffset == 0) return;
    _scrollOffset = 0;
    [self setNeedsScreenUpdate];
}

- (void)scrollByLines:(NSInteger)lines {
    NSInteger maximum = self.emulator.buffer.scrollbackLines;
    NSInteger offset = MAX(0, MIN(_scrollOffset + lines, maximum));
    if (offset == _scrollOffset) return;
    _scrollOffset = offset;
    [self setNeedsScreenUpdate];
}

#pragma mark - Drawing

- (void)drawRect:(CGRect)rect {
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (!context || !self.emulator) return;

    TXTerminalBuffer *buffer = self.emulator.buffer;
    TXColorScheme *scheme = self.colorScheme;

    CGContextSetFillColorWithColor(context, scheme.defaultBackground.CGColor);
    CGContextFillRect(context, rect);

    CGContextSetTextMatrix(context, CGAffineTransformIdentity);
    // Flip so that row 0 is at the top and CoreText still draws upright.
    CGContextTranslateCTM(context, 0, self.bounds.size.height);
    CGContextScaleCTM(context, 1.0, -1.0);

    NSInteger rows = MIN(self.rows, self.emulator.rows);
    NSInteger columns = MIN(self.columns, self.emulator.columns);

    for (NSInteger screenRow = 0; screenRow < rows; screenRow++) {
        NSInteger bufferRow = screenRow - _scrollOffset;
        CGFloat y = self.bounds.size.height - (CGFloat)(screenRow + 1) * _cellHeight;

        [self drawRow:bufferRow atY:y columns:columns buffer:buffer scheme:scheme context:context];
    }

    if (_scrollOffset == 0) {
        [self drawCursorInContext:context scheme:scheme];
    }
}

- (void)drawRow:(NSInteger)bufferRow
            atY:(CGFloat)y
        columns:(NSInteger)columns
         buffer:(TXTerminalBuffer *)buffer
         scheme:(TXColorScheme *)scheme
        context:(CGContextRef)context {
    // ---- pass 1: background runs -------------------------------------------
    NSInteger column = 0;
    while (column < columns) {
        TXCell cell = [buffer cellAtAbsoluteRow:bufferRow column:column];
        BOOL inverse = (cell.flags & TXCellFlagInverse) != 0;
        BOOL selected = [self isCellSelectedAtRow:bufferRow column:column];

        TXColor backgroundColor = inverse ? cell.foreground : cell.background;
        UIColor *background = [scheme colorForTerminalColor:backgroundColor
                                               isForeground:inverse
                                                       bold:NO];

        NSInteger run = column + 1;
        while (run < columns) {
            TXCell next = [buffer cellAtAbsoluteRow:bufferRow column:run];
            BOOL nextInverse = (next.flags & TXCellFlagInverse) != 0;
            if (nextInverse != inverse) break;
            if ([self isCellSelectedAtRow:bufferRow column:run] != selected) break;
            TXColor nextBackground = nextInverse ? next.foreground : next.background;
            if (!TXColorEqual(nextBackground, backgroundColor)) break;
            run++;
        }

        BOOL isDefault = !inverse && TXColorEqual(cell.background, TXColorDefault());
        if (!isDefault || selected) {
            CGRect fill = CGRectMake((CGFloat)column * _cellWidth, y,
                                     (CGFloat)(run - column) * _cellWidth, _cellHeight);
            if (selected) {
                CGContextSetFillColorWithColor(context, scheme.selectionColor.CGColor);
            } else {
                CGContextSetFillColorWithColor(context, background.CGColor);
            }
            CGContextFillRect(context, fill);
        }
        column = run;
    }

    // ---- pass 2: glyphs -----------------------------------------------------
    column = 0;
    while (column < columns) {
        TXCell cell = [buffer cellAtAbsoluteRow:bufferRow column:column];

        if (cell.flags & TXCellFlagWideTrailer) { column++; continue; }
        if (cell.flags & TXCellFlagInvisible) { column++; continue; }
        if (cell.codepoint == ' ' || cell.codepoint == 0) {
            if (!(cell.flags & (TXCellFlagUnderline | TXCellFlagStrikethrough))) {
                column++;
                continue;
            }
        }

        BOOL bold = (cell.flags & TXCellFlagBold) != 0;
        BOOL italic = (cell.flags & TXCellFlagItalic) != 0;
        BOOL inverse = (cell.flags & TXCellFlagInverse) != 0;

        TXColor foregroundColor = inverse ? cell.background : cell.foreground;
        UIColor *foreground = [scheme colorForTerminalColor:foregroundColor
                                               isForeground:!inverse
                                                       bold:bold];
        if (cell.flags & TXCellFlagDim) {
            foreground = [foreground colorWithAlphaComponent:0.6];
        }

        // Coalesce a run of cells sharing the same style into one CTLine.
        NSMutableString *text = [NSMutableString string];
        NSInteger run = column;
        while (run < columns) {
            TXCell next = [buffer cellAtAbsoluteRow:bufferRow column:run];
            if (next.flags != cell.flags) break;
            if (!TXColorEqual(next.foreground, cell.foreground)) break;
            if (!TXColorEqual(next.background, cell.background)) break;
            if ([self isCellSelectedAtRow:bufferRow column:run] !=
                [self isCellSelectedAtRow:bufferRow column:column]) break;

            [text appendString:[self stringForCell:next buffer:buffer]];
            run++;
            // A double-width glyph owns the trailer cell that follows it.
            if (run < columns) {
                TXCell trailer = [buffer cellAtAbsoluteRow:bufferRow column:run];
                if (trailer.flags & TXCellFlagWideTrailer) run++;
            }
        }
        if (text.length == 0) { column = MAX(run, column + 1); continue; }

        CTFontRef font = bold ? (italic ? _boldItalicFont : _boldFont)
                              : (italic ? _italicFont : _regularFont);

        NSDictionary *attributes = @{
            (__bridge NSString *)kCTFontAttributeName: (__bridge id)font,
            (__bridge NSString *)kCTForegroundColorAttributeName: (__bridge id)foreground.CGColor,
        };
        NSAttributedString *attributed =
            [[NSAttributedString alloc] initWithString:text attributes:attributes];
        CTLineRef line = CTLineCreateWithAttributedString(
            (__bridge CFAttributedStringRef)attributed);

        CGContextSetTextPosition(context, (CGFloat)column * _cellWidth, y + _baselineOffset);
        CTLineDraw(line, context);
        CFRelease(line);

        CGFloat runWidth = (CGFloat)(run - column) * _cellWidth;
        if (cell.flags & TXCellFlagUnderline) {
            CGContextSetFillColorWithColor(context, foreground.CGColor);
            CGContextFillRect(context,
                CGRectMake((CGFloat)column * _cellWidth, y + _baselineOffset - 2,
                           runWidth, 1));
        }
        if (cell.flags & TXCellFlagStrikethrough) {
            CGContextSetFillColorWithColor(context, foreground.CGColor);
            CGContextFillRect(context,
                CGRectMake((CGFloat)column * _cellWidth, y + _cellHeight * 0.45,
                           runWidth, 1));
        }

        column = MAX(run, column + 1);
    }
}

- (NSString *)stringForCell:(TXCell)cell buffer:(TXTerminalBuffer *)buffer {
    uint32_t codepoint = cell.codepoint ?: ' ';
    NSString *base;
    if (codepoint < 0x10000) {
        unichar unit = (unichar)codepoint;
        base = [NSString stringWithCharacters:&unit length:1];
    } else {
        uint32_t value = codepoint - 0x10000;
        unichar surrogates[2] = {
            (unichar)(0xD800 + (value >> 10)),
            (unichar)(0xDC00 + (value & 0x3FF)),
        };
        base = [NSString stringWithCharacters:surrogates length:2];
    }
    NSString *marks = [buffer combiningMarksForCell:cell];
    return marks ? [base stringByAppendingString:marks] : base;
}

- (void)drawCursorInContext:(CGContextRef)context scheme:(TXColorScheme *)scheme {
    if (!self.emulator.cursorVisible) return;
    if (!_cursorBlinkOn && self.isFirstResponder) return;

    NSInteger row = self.emulator.cursorRow;
    NSInteger column = self.emulator.cursorColumn;
    if (row < 0 || row >= self.rows) return;

    CGFloat y = self.bounds.size.height - (CGFloat)(row + 1) * _cellHeight;
    CGRect cursor = CGRectMake((CGFloat)column * _cellWidth, y, _cellWidth, _cellHeight);

    CGContextSetFillColorWithColor(context, scheme.cursorColor.CGColor);

    if (self.isFirstResponder) {
        CGContextFillRect(context, cursor);
        // Redraw the glyph underneath in the background colour so it stays legible.
        TXCell cell = [self.emulator.buffer cellAtRow:row column:column];
        if (cell.codepoint && cell.codepoint != ' ') {
            NSDictionary *attributes = @{
                (__bridge NSString *)kCTFontAttributeName: (__bridge id)_regularFont,
                (__bridge NSString *)kCTForegroundColorAttributeName:
                    (__bridge id)scheme.defaultBackground.CGColor,
            };
            NSAttributedString *attributed = [[NSAttributedString alloc]
                initWithString:[self stringForCell:cell buffer:self.emulator.buffer]
                    attributes:attributes];
            CTLineRef line = CTLineCreateWithAttributedString(
                (__bridge CFAttributedStringRef)attributed);
            CGContextSetTextPosition(context, (CGFloat)column * _cellWidth, y + _baselineOffset);
            CTLineDraw(line, context);
            CFRelease(line);
        }
    } else {
        CGContextSetStrokeColorWithColor(context, scheme.cursorColor.CGColor);
        CGContextSetLineWidth(context, 1.0);
        CGContextStrokeRect(context, CGRectInset(cursor, 0.5, 0.5));
    }
}

#pragma mark - Selection

- (BOOL)isCellSelectedAtRow:(NSInteger)row column:(NSInteger)column {
    if (!_hasSelection) return NO;

    NSInteger startRow = _selectionStartRow, startColumn = _selectionStartColumn;
    NSInteger endRow = _selectionEndRow, endColumn = _selectionEndColumn;
    if (endRow < startRow || (endRow == startRow && endColumn < startColumn)) {
        NSInteger tr = startRow, tc = startColumn;
        startRow = endRow; startColumn = endColumn;
        endRow = tr; endColumn = tc;
    }

    if (row < startRow || row > endRow) return NO;
    if (row == startRow && column < startColumn) return NO;
    if (row == endRow && column > endColumn) return NO;
    return YES;
}

- (NSString *)selectedText {
    if (!_hasSelection) return nil;
    return [self.emulator.buffer stringFromAbsoluteRow:_selectionStartRow
                                                column:_selectionStartColumn
                                         toAbsoluteRow:_selectionEndRow
                                                column:_selectionEndColumn];
}

- (void)clearSelection {
    if (!_hasSelection) return;
    _hasSelection = NO;
    [self setNeedsScreenUpdate];
}

- (void)selectAll {
    _hasSelection = YES;
    _selectionStartRow = -self.emulator.buffer.scrollbackLines;
    _selectionStartColumn = 0;
    _selectionEndRow = self.emulator.rows - 1;
    _selectionEndColumn = self.emulator.columns - 1;
    [self setNeedsScreenUpdate];
}

#pragma mark - Gestures

- (void)installGestureRecognizers {
    UITapGestureRecognizer *tap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    tap.delegate = self;
    [self addGestureRecognizer:tap];

    UILongPressGestureRecognizer *longPress =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                      action:@selector(handleLongPress:)];
    longPress.delegate = self;
    [self addGestureRecognizer:longPress];

    UIPanGestureRecognizer *pan =
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    pan.delegate = self;
    pan.maximumNumberOfTouches = 1;
    [self addGestureRecognizer:pan];

    UIPinchGestureRecognizer *pinch =
        [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinch:)];
    pinch.delegate = self;
    [self addGestureRecognizer:pinch];
}

- (void)handleTap:(UITapGestureRecognizer *)recognizer {
    if (_hasSelection) {
        [self clearSelection];
        return;
    }
    if (!self.isFirstResponder) [self becomeFirstResponder];

    // Report the tap to programs that asked for mouse events.
    if (self.emulator.mouseMode != TXMouseModeNone) {
        CGPoint point = [recognizer locationInView:self];
        [self sendMouseEventAtPoint:point button:0 pressed:YES];
        [self sendMouseEventAtPoint:point button:0 pressed:NO];
    }
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)recognizer {
    CGPoint point = [recognizer locationInView:self];
    NSInteger row = [self bufferRowAtPoint:point];
    NSInteger column = [self columnAtPoint:point];

    switch (recognizer.state) {
        case UIGestureRecognizerStateBegan:
            _hasSelection = YES;
            _selectionStartRow = _selectionEndRow = row;
            _selectionStartColumn = _selectionEndColumn = column;
            [self setNeedsScreenUpdate];
            break;
        case UIGestureRecognizerStateChanged:
            _selectionEndRow = row;
            _selectionEndColumn = column;
            [self setNeedsScreenUpdate];
            break;
        case UIGestureRecognizerStateEnded:
            if (self.selectedText.length > 0) {
                [UIPasteboard generalPasteboard].string = self.selectedText;
            }
            break;
        default:
            break;
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateBegan) _panAccumulator = 0;

    CGPoint translation = [recognizer translationInView:self];
    [recognizer setTranslation:CGPointZero inView:self];
    _panAccumulator += translation.y;

    if (_cellHeight <= 0) return;
    NSInteger lines = (NSInteger)(_panAccumulator / _cellHeight);
    if (lines == 0) return;
    _panAccumulator -= (CGFloat)lines * _cellHeight;

    if (self.emulator.usingAlternateScreen) {
        // In the alternate screen (vim, less) send arrow keys instead so the
        // application scrolls its own view.
        NSString *key = lines > 0 ? @"up" : @"down";
        for (NSInteger i = 0; i < ABS(lines); i++) [self sendSpecialKey:key];
    } else {
        [self scrollByLines:lines];
    }
}

- (void)handlePinch:(UIPinchGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateChanged) return;
    if (fabs(recognizer.scale - 1.0) < 0.02) return;

    CGFloat size = self.font.pointSize * recognizer.scale;
    size = MAX(8, MIN(size, 32));
    recognizer.scale = 1.0;

    if (fabs(size - self.font.pointSize) < 0.5) return;
    self.font = [UIFont monospacedSystemFontOfSize:round(size) weight:UIFontWeightRegular];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer
shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}

- (NSInteger)columnAtPoint:(CGPoint)point {
    if (_cellWidth <= 0) return 0;
    return MAX(0, MIN((NSInteger)(point.x / _cellWidth), self.emulator.columns - 1));
}

- (NSInteger)bufferRowAtPoint:(CGPoint)point {
    if (_cellHeight <= 0) return 0;
    NSInteger screenRow = (NSInteger)(point.y / _cellHeight);
    return screenRow - _scrollOffset;
}

#pragma mark - Mouse reporting

- (void)sendMouseEventAtPoint:(CGPoint)point button:(int)button pressed:(BOOL)pressed {
    NSInteger column = [self columnAtPoint:point] + 1;
    NSInteger row = [self bufferRowAtPoint:point] + 1;
    if (row < 1) return;

    NSString *sequence;
    if (self.emulator.mouseSGREncoding) {
        sequence = [NSString stringWithFormat:@"\033[<%d;%ld;%ld%@",
                    button, (long)column, (long)row, pressed ? @"M" : @"m"];
    } else {
        int code = pressed ? button : 3;
        sequence = [NSString stringWithFormat:@"\033[M%c%c%c",
                    (char)(32 + code), (char)(32 + column), (char)(32 + row)];
    }
    [self sendData:[sequence dataUsingEncoding:NSUTF8StringEncoding]];
}

#pragma mark - Input plumbing

- (void)sendData:(NSData *)data {
    if (data.length == 0) return;
    [self scrollToBottom];
    if ([self.delegate respondsToSelector:@selector(terminalView:didProduceInput:)]) {
        [self.delegate terminalView:self didProduceInput:data];
    }
}

- (void)sendString:(NSString *)string {
    [self sendData:[string dataUsingEncoding:NSUTF8StringEncoding]];
}

- (void)sendText:(NSString *)text control:(BOOL)control alt:(BOOL)alt {
    if (text.length == 0) return;

    NSMutableData *payload = [NSMutableData data];

    if (control) {
        unichar character = [text.uppercaseString characterAtIndex:0];
        uint8_t byte;
        if (character >= 'A' && character <= 'Z') {
            byte = (uint8_t)(character - 'A' + 1);
        } else if (character == ' ' || character == '@') {
            byte = 0;
        } else if (character == '[') {
            byte = 27;
        } else if (character == '\\') {
            byte = 28;
        } else if (character == ']') {
            byte = 29;
        } else if (character == '^') {
            byte = 30;
        } else if (character == '_' || character == '?') {
            byte = 31;
        } else {
            byte = (uint8_t)character;
        }
        if (alt) {
            uint8_t escape = 0x1B;
            [payload appendBytes:&escape length:1];
        }
        [payload appendBytes:&byte length:1];
    } else {
        if (alt) {
            uint8_t escape = 0x1B;
            [payload appendBytes:&escape length:1];
        }
        [payload appendData:[text dataUsingEncoding:NSUTF8StringEncoding]];
    }

    [self sendData:payload];
}

- (void)sendSpecialKey:(NSString *)keyName {
    BOOL application = self.emulator.applicationCursorKeys;
    NSString *csi = application ? @"\033O" : @"\033[";

    static NSDictionary<NSString *, NSString *> *simple;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        simple = @{
            @"escape": @"\033",
            @"tab": @"\t",
            @"backtab": @"\033[Z",
            @"return": @"\r",
            @"enter": @"\r",
            @"backspace": @"\x7f",
            @"delete": @"\033[3~",
            @"insert": @"\033[2~",
            @"pageup": @"\033[5~",
            @"pagedown": @"\033[6~",
            @"f1": @"\033OP", @"f2": @"\033OQ", @"f3": @"\033OR", @"f4": @"\033OS",
            @"f5": @"\033[15~", @"f6": @"\033[17~", @"f7": @"\033[18~", @"f8": @"\033[19~",
            @"f9": @"\033[20~", @"f10": @"\033[21~", @"f11": @"\033[23~", @"f12": @"\033[24~",
        };
    });

    NSString *key = keyName.lowercaseString;
    NSString *sequence = simple[key];
    if (!sequence) {
        if ([key isEqualToString:@"up"]) sequence = [csi stringByAppendingString:@"A"];
        else if ([key isEqualToString:@"down"]) sequence = [csi stringByAppendingString:@"B"];
        else if ([key isEqualToString:@"right"]) sequence = [csi stringByAppendingString:@"C"];
        else if ([key isEqualToString:@"left"]) sequence = [csi stringByAppendingString:@"D"];
        else if ([key isEqualToString:@"home"]) sequence = [csi stringByAppendingString:@"H"];
        else if ([key isEqualToString:@"end"]) sequence = [csi stringByAppendingString:@"F"];
    }
    if (sequence) [self sendString:sequence];
}

- (void)pasteText:(NSString *)text {
    if (text.length == 0) return;
    if (self.emulator.bracketedPaste) {
        [self sendString:[NSString stringWithFormat:@"\033[200~%@\033[201~", text]];
    } else {
        [self sendString:text];
    }
}

#pragma mark - UIKeyInput

- (BOOL)canBecomeFirstResponder { return YES; }

- (BOOL)hasText { return YES; }

- (void)insertText:(NSString *)text {
    if ([text isEqualToString:@"\n"]) {
        [self sendString:@"\r"];
        return;
    }

    // Honour CTRL/ALT held down on the extra-key row.
    id<TXTerminalViewModifierSource> source = self.modifierSource;
    if (source) {
        BOOL control = [source terminalViewControlModifierActive:self];
        BOOL alt = [source terminalViewAltModifierActive:self];
        if (control || alt) {
            [self sendText:text control:control alt:alt];
            [source terminalViewDidConsumeModifiers:self];
            return;
        }
    }

    [self sendString:text];
}

- (void)deleteBackward {
    [self sendString:@"\x7f"];
}

- (UIKeyboardType)keyboardType { return UIKeyboardTypeASCIICapable; }
- (UITextAutocorrectionType)autocorrectionType { return UITextAutocorrectionTypeNo; }
- (UITextAutocapitalizationType)autocapitalizationType { return UITextAutocapitalizationTypeNone; }
- (UITextSpellCheckingType)spellCheckingType { return UITextSpellCheckingTypeNo; }
- (UIKeyboardAppearance)keyboardAppearance { return UIKeyboardAppearanceDark; }
- (UIReturnKeyType)returnKeyType { return UIReturnKeyDefault; }
- (BOOL)enablesReturnKeyAutomatically { return NO; }
- (BOOL)isSecureTextEntry { return NO; }
- (UITextSmartQuotesType)smartQuotesType { return UITextSmartQuotesTypeNo; }
- (UITextSmartDashesType)smartDashesType { return UITextSmartDashesTypeNo; }
- (UITextSmartInsertDeleteType)smartInsertDeleteType { return UITextSmartInsertDeleteTypeNo; }

#pragma mark - Hardware keyboard

- (NSArray<UIKeyCommand *> *)keyCommands {
    static NSArray<UIKeyCommand *> *commands;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray<UIKeyCommand *> *list = [NSMutableArray array];

        NSDictionary<NSString *, NSString *> *specials = @{
            UIKeyInputUpArrow: @"up",
            UIKeyInputDownArrow: @"down",
            UIKeyInputLeftArrow: @"left",
            UIKeyInputRightArrow: @"right",
            UIKeyInputEscape: @"escape",
            UIKeyInputPageUp: @"pageup",
            UIKeyInputPageDown: @"pagedown",
            UIKeyInputHome: @"home",
            UIKeyInputEnd: @"end",
        };
        for (NSString *input in specials) {
            [list addObject:[UIKeyCommand keyCommandWithInput:input
                                                modifierFlags:0
                                                       action:@selector(handleKeyCommand:)]];
        }

        // Ctrl-<letter> and Alt-<letter>.
        NSString *letters = @"abcdefghijklmnopqrstuvwxyz";
        for (NSUInteger i = 0; i < letters.length; i++) {
            NSString *letter = [letters substringWithRange:NSMakeRange(i, 1)];
            [list addObject:[UIKeyCommand keyCommandWithInput:letter
                                                modifierFlags:UIKeyModifierControl
                                                       action:@selector(handleKeyCommand:)]];
            [list addObject:[UIKeyCommand keyCommandWithInput:letter
                                                modifierFlags:UIKeyModifierAlternate
                                                       action:@selector(handleKeyCommand:)]];
        }
        for (NSString *input in @[@"[", @"]", @"\\", @"_", @" ", @"-", @"/"]) {
            [list addObject:[UIKeyCommand keyCommandWithInput:input
                                                modifierFlags:UIKeyModifierControl
                                                       action:@selector(handleKeyCommand:)]];
        }
        [list addObject:[UIKeyCommand keyCommandWithInput:@"\t"
                                            modifierFlags:UIKeyModifierShift
                                                   action:@selector(handleKeyCommand:)]];

        commands = list;
    });
    return commands;
}

- (void)handleKeyCommand:(UIKeyCommand *)command {
    NSString *input = command.input ?: @"";
    UIKeyModifierFlags flags = command.modifierFlags;

    static NSDictionary<NSString *, NSString *> *specials;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        specials = @{
            UIKeyInputUpArrow: @"up",
            UIKeyInputDownArrow: @"down",
            UIKeyInputLeftArrow: @"left",
            UIKeyInputRightArrow: @"right",
            UIKeyInputEscape: @"escape",
            UIKeyInputPageUp: @"pageup",
            UIKeyInputPageDown: @"pagedown",
            UIKeyInputHome: @"home",
            UIKeyInputEnd: @"end",
        };
    });

    NSString *special = specials[input];
    if (special) {
        [self sendSpecialKey:special];
        return;
    }
    if ([input isEqualToString:@"\t"] && (flags & UIKeyModifierShift)) {
        [self sendSpecialKey:@"backtab"];
        return;
    }

    [self sendText:input
           control:(flags & UIKeyModifierControl) != 0
               alt:(flags & UIKeyModifierAlternate) != 0];
}

#pragma mark - Editing menu

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    if (action == @selector(paste:)) {
        return [UIPasteboard generalPasteboard].hasStrings;
    }
    if (action == @selector(copy:)) {
        return self.selectedText.length > 0;
    }
    if (action == @selector(selectAll:)) return YES;
    return [super canPerformAction:action withSender:sender];
}

- (void)copy:(id)sender {
    NSString *text = self.selectedText;
    if (text.length > 0) [UIPasteboard generalPasteboard].string = text;
    [self clearSelection];
}

- (void)paste:(id)sender {
    NSString *text = [UIPasteboard generalPasteboard].string;
    if (text) [self pasteText:text];
}

- (void)selectAll:(id)sender {
    [self selectAll];
}

@end
