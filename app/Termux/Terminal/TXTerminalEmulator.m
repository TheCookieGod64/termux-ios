//
//  TXTerminalEmulator.m
//

#import "TXTerminalEmulator.h"

#pragma mark - Character width

/// Compact wcwidth: zero for combining marks, two for the wide CJK/emoji
/// ranges, one otherwise.  Good enough for terminal layout without pulling in
/// the full Unicode tables.
static int TXCharacterWidth(uint32_t cp) {
    if (cp == 0) return 0;
    if (cp < 32 || (cp >= 0x7F && cp < 0xA0)) return 0;

    // Combining marks and other zero-width classes.
    static const uint32_t zero[][2] = {
        {0x0300, 0x036F}, {0x0483, 0x0489}, {0x0591, 0x05BD}, {0x05BF, 0x05BF},
        {0x05C1, 0x05C2}, {0x05C4, 0x05C5}, {0x0610, 0x061A}, {0x064B, 0x065F},
        {0x0670, 0x0670}, {0x06D6, 0x06DC}, {0x06DF, 0x06E4}, {0x06E7, 0x06E8},
        {0x06EA, 0x06ED}, {0x0711, 0x0711}, {0x0730, 0x074A}, {0x07A6, 0x07B0},
        {0x07EB, 0x07F3}, {0x0816, 0x0819}, {0x081B, 0x0823}, {0x0825, 0x0827},
        {0x0829, 0x082D}, {0x0859, 0x085B}, {0x08E3, 0x0903}, {0x093A, 0x093C},
        {0x0941, 0x0948}, {0x094D, 0x094D}, {0x0951, 0x0957}, {0x0962, 0x0963},
        {0x0981, 0x0981}, {0x09BC, 0x09BC}, {0x09C1, 0x09C4}, {0x09CD, 0x09CD},
        {0x0A01, 0x0A02}, {0x0A3C, 0x0A3C}, {0x0A41, 0x0A42}, {0x0A47, 0x0A48},
        {0x0A4B, 0x0A4D}, {0x0A70, 0x0A71}, {0x0A81, 0x0A82}, {0x0ABC, 0x0ABC},
        {0x0AC1, 0x0AC5}, {0x0AC7, 0x0AC8}, {0x0ACD, 0x0ACD}, {0x0B01, 0x0B01},
        {0x0B3C, 0x0B3C}, {0x0B3F, 0x0B3F}, {0x0B41, 0x0B44}, {0x0B4D, 0x0B4D},
        {0x0BC0, 0x0BC0}, {0x0BCD, 0x0BCD}, {0x0C00, 0x0C00}, {0x0C3E, 0x0C40},
        {0x0C46, 0x0C48}, {0x0C4A, 0x0C4D}, {0x0CBC, 0x0CBC}, {0x0CCC, 0x0CCD},
        {0x0D41, 0x0D44}, {0x0D4D, 0x0D4D}, {0x0DCA, 0x0DCA}, {0x0E31, 0x0E31},
        {0x0E34, 0x0E3A}, {0x0E47, 0x0E4E}, {0x0EB1, 0x0EB1}, {0x0EB4, 0x0EBC},
        {0x0EC8, 0x0ECD}, {0x0F18, 0x0F19}, {0x0F35, 0x0F35}, {0x0F37, 0x0F37},
        {0x0F71, 0x0F7E}, {0x0F80, 0x0F84}, {0x0F86, 0x0F87}, {0x102D, 0x1030},
        {0x1032, 0x1037}, {0x1039, 0x103A}, {0x1058, 0x1059}, {0x135D, 0x135F},
        {0x1712, 0x1714}, {0x1752, 0x1753}, {0x1772, 0x1773}, {0x17B4, 0x17B5},
        {0x17B7, 0x17BD}, {0x17C6, 0x17C6}, {0x17C9, 0x17D3}, {0x180B, 0x180D},
        {0x18A9, 0x18A9}, {0x1A17, 0x1A18}, {0x1AB0, 0x1AFF}, {0x1B00, 0x1B03},
        {0x1B34, 0x1B34}, {0x1B6B, 0x1B73}, {0x1DC0, 0x1DFF}, {0x20D0, 0x20F0},
        {0x2CEF, 0x2CF1}, {0x302A, 0x302D}, {0x3099, 0x309A}, {0xA66F, 0xA672},
        {0xA806, 0xA806}, {0xA8C4, 0xA8C4}, {0xA8E0, 0xA8F1}, {0xFB1E, 0xFB1E},
        {0xFE00, 0xFE0F}, {0xFE20, 0xFE2F}, {0x101FD, 0x101FD}, {0x1D167, 0x1D169},
        {0x1D17B, 0x1D182}, {0x1D185, 0x1D18B}, {0x1D1AA, 0x1D1AD}, {0xE0100, 0xE01EF},
    };
    for (size_t i = 0; i < sizeof(zero) / sizeof(zero[0]); i++) {
        if (cp >= zero[i][0] && cp <= zero[i][1]) return 0;
    }

    static const uint32_t wide[][2] = {
        {0x1100, 0x115F}, {0x2329, 0x232A}, {0x2E80, 0x303E}, {0x3041, 0x33FF},
        {0x3400, 0x4DBF}, {0x4E00, 0x9FFF}, {0xA000, 0xA4CF}, {0xA960, 0xA97F},
        {0xAC00, 0xD7A3}, {0xF900, 0xFAFF}, {0xFE10, 0xFE19}, {0xFE30, 0xFE6F},
        {0xFF00, 0xFF60}, {0xFFE0, 0xFFE6}, {0x16FE0, 0x16FE4}, {0x17000, 0x18AFF},
        {0x1B000, 0x1B2FF}, {0x1F004, 0x1F004}, {0x1F0CF, 0x1F0CF}, {0x1F18E, 0x1F18E},
        {0x1F191, 0x1F19A}, {0x1F200, 0x1F320}, {0x1F32D, 0x1F335}, {0x1F337, 0x1F37C},
        {0x1F37E, 0x1F393}, {0x1F3A0, 0x1F3CA}, {0x1F3CF, 0x1F3D3}, {0x1F3E0, 0x1F3F0},
        {0x1F3F4, 0x1F3F4}, {0x1F3F8, 0x1F43E}, {0x1F440, 0x1F440}, {0x1F442, 0x1F4FC},
        {0x1F4FF, 0x1F53D}, {0x1F54B, 0x1F54E}, {0x1F550, 0x1F567}, {0x1F57A, 0x1F57A},
        {0x1F595, 0x1F596}, {0x1F5A4, 0x1F5A4}, {0x1F5FB, 0x1F64F}, {0x1F680, 0x1F6C5},
        {0x1F6CC, 0x1F6CC}, {0x1F6D0, 0x1F6D2}, {0x1F6EB, 0x1F6EC}, {0x1F6F4, 0x1F6FC},
        {0x1F7E0, 0x1F7EB}, {0x1F90D, 0x1F971}, {0x1F973, 0x1F976}, {0x1F97A, 0x1F9A2},
        {0x1F9A5, 0x1F9AA}, {0x1F9AE, 0x1F9CA}, {0x1F9CD, 0x1F9FF}, {0x1FA70, 0x1FAFF},
        {0x20000, 0x2FFFD}, {0x30000, 0x3FFFD},
    };
    for (size_t i = 0; i < sizeof(wide) / sizeof(wide[0]); i++) {
        if (cp >= wide[i][0] && cp <= wide[i][1]) return 2;
    }
    return 1;
}

#pragma mark - Parser state

typedef NS_ENUM(NSInteger, TXParserState) {
    TXParserStateGround = 0,
    TXParserStateEscape,
    TXParserStateEscapeIntermediate,
    TXParserStateCSIEntry,
    TXParserStateCSIParam,
    TXParserStateCSIIntermediate,
    TXParserStateCSIIgnore,
    TXParserStateOSCString,
    TXParserStateDCSEntry,
    TXParserStateDCSParam,
    TXParserStateDCSPassthrough,
    TXParserStateSOSPMAPCString,
};

#define TX_MAX_PARAMS 32

/// Saved cursor state for DECSC/DECRC and alt-screen switches.
typedef struct {
    NSInteger row;
    NSInteger column;
    TXColor foreground;
    TXColor background;
    TXCellFlags flags;
    BOOL originMode;
    BOOL wraparound;
    int charset;
} TXCursorState;

@implementation TXTerminalEmulator {
    TXTerminalBuffer *_normalBuffer;
    TXTerminalBuffer *_alternateBuffer;

    NSInteger _rows;
    NSInteger _columns;

    NSInteger _cursorRow;
    NSInteger _cursorColumn;
    /// Deferred wrap: we are logically past the last column.
    BOOL _wrapPending;

    NSInteger _scrollTop;
    NSInteger _scrollBottom;

    TXColor _foreground;
    TXColor _background;
    TXCellFlags _flags;

    BOOL _originMode;        // DECOM
    BOOL _wraparound;        // DECAWM
    BOOL _reverseWraparound;
    BOOL _insertMode;        // IRM
    BOOL _newlineMode;       // LNM

    TXCursorState _savedCursor;
    TXCursorState _savedCursorAlt;

    NSMutableIndexSet *_tabStops;

    // Parser
    TXParserState _state;
    int _params[TX_MAX_PARAMS];
    BOOL _paramSet[TX_MAX_PARAMS];
    NSInteger _paramCount;
    /// Sub-parameters introduced by ':' (SGR truecolour, underline styles).
    int _subParams[TX_MAX_PARAMS][8];
    NSInteger _subParamCount[TX_MAX_PARAMS];
    uint8_t _intermediates[4];
    NSInteger _intermediateCount;
    uint8_t _privateMarker;
    NSMutableData *_stringBuffer;

    // UTF-8 decoding
    uint32_t _utf8Codepoint;
    int _utf8Remaining;
    uint32_t _utf8Minimum;

    // Character sets: G0..G3, and the currently mapped GL.
    char _charsets[4];
    int _activeCharset;
    int _singleShift;

    BOOL _needsScreenUpdate;
}

- (instancetype)initWithRows:(NSInteger)rows columns:(NSInteger)columns {
    self = [super init];
    if (!self) return nil;

    _rows = MAX(rows, 1);
    _columns = MAX(columns, 1);

    _normalBuffer = [[TXTerminalBuffer alloc] initWithRows:_rows columns:_columns];
    _alternateBuffer = [[TXTerminalBuffer alloc] initWithRows:_rows columns:_columns];
    _alternateBuffer.maxScrollbackLines = 0;

    _stringBuffer = [NSMutableData data];
    _tabStops = [NSMutableIndexSet indexSet];

    [self resetInternal];
    return self;
}

#pragma mark - Accessors

- (TXTerminalBuffer *)buffer {
    return _usingAlternateScreen ? _alternateBuffer : _normalBuffer;
}

- (NSInteger)rows { return _rows; }
- (NSInteger)columns { return _columns; }
- (NSInteger)cursorRow { return _cursorRow; }
- (NSInteger)cursorColumn { return MIN(_cursorColumn, _columns - 1); }

#pragma mark - Reset

- (void)reset {
    [self resetInternal];
    [_normalBuffer clearScrollback];
    TXCell blank = [self blankCell];
    for (NSInteger row = 0; row < _rows; row++) {
        [_normalBuffer clearRow:row fromColumn:0 toColumn:_columns - 1 withTemplate:blank];
        [_alternateBuffer clearRow:row fromColumn:0 toColumn:_columns - 1 withTemplate:blank];
    }
    [self notifyScreenUpdate];
}

- (void)resetInternal {
    _cursorRow = 0;
    _cursorColumn = 0;
    _wrapPending = NO;
    _scrollTop = 0;
    _scrollBottom = _rows - 1;
    _foreground = TXColorDefault();
    _background = TXColorDefault();
    _flags = TXCellFlagNone;
    _originMode = NO;
    _wraparound = YES;
    _reverseWraparound = NO;
    _insertMode = NO;
    _newlineMode = NO;
    _cursorVisible = YES;
    _applicationCursorKeys = NO;
    _applicationKeypad = NO;
    _bracketedPaste = NO;
    _usingAlternateScreen = NO;
    _mouseMode = TXMouseModeNone;
    _mouseSGREncoding = NO;
    _state = TXParserStateGround;
    _utf8Remaining = 0;
    _activeCharset = 0;
    _singleShift = -1;
    for (int i = 0; i < 4; i++) _charsets[i] = 'B';
    [self resetTabStops];
    [self saveCursor];
}

- (void)resetTabStops {
    [_tabStops removeAllIndexes];
    for (NSInteger column = 8; column < _columns; column += 8) {
        [_tabStops addIndex:(NSUInteger)column];
    }
}

- (TXCell)blankCell {
    TXCell cell = TXCellMakeEmpty();
    // Only the background colour "sticks" to erased cells (ANSI behaviour).
    cell.background = _background;
    return cell;
}

#pragma mark - Geometry

- (void)resizeToRows:(NSInteger)rows columns:(NSInteger)columns {
    rows = MAX(rows, 1);
    columns = MAX(columns, 1);
    if (rows == _rows && columns == _columns) return;

    NSInteger oldRows = _rows;
    [_normalBuffer resizeToRows:rows columns:columns];
    [_alternateBuffer resizeToRows:rows columns:columns];

    _rows = rows;
    _columns = columns;

    // Keep the cursor attached to its line when the screen shrank and lines
    // scrolled off the top.
    if (rows < oldRows) {
        _cursorRow -= (oldRows - rows);
    }
    _cursorRow = MAX(0, MIN(_cursorRow, _rows - 1));
    _cursorColumn = MAX(0, MIN(_cursorColumn, _columns - 1));

    _scrollTop = 0;
    _scrollBottom = _rows - 1;
    _wrapPending = NO;
    [self resetTabStops];
    [self notifyScreenUpdate];
}

#pragma mark - Delegate helpers

- (void)notifyScreenUpdate {
    _needsScreenUpdate = YES;
}

- (void)flushScreenUpdate {
    if (!_needsScreenUpdate) return;
    _needsScreenUpdate = NO;
    if ([self.delegate respondsToSelector:@selector(terminalDidUpdateScreen:)]) {
        [self.delegate terminalDidUpdateScreen:self];
    }
}

- (void)respond:(NSString *)string {
    if (![self.delegate respondsToSelector:@selector(terminal:wantsToWriteData:)]) return;
    [self.delegate terminal:self wantsToWriteData:[string dataUsingEncoding:NSUTF8StringEncoding]];
}

#pragma mark - Feeding data

- (void)parseData:(NSData *)data {
    [self parseBytes:data.bytes length:data.length];
}

- (void)parseBytes:(const uint8_t *)bytes length:(NSUInteger)length {
    for (NSUInteger i = 0; i < length; i++) {
        [self consumeByte:bytes[i]];
    }
    [self flushScreenUpdate];
}

#pragma mark - Parser core

- (void)consumeByte:(uint8_t)byte {
    // C0 controls are handled from (almost) any state, per the DEC parser.
    if (byte < 0x20) {
        switch (_state) {
            case TXParserStateOSCString:
                if (byte == 0x07) {                      // BEL terminates OSC
                    [self dispatchOSC];
                    _state = TXParserStateGround;
                    return;
                }
                if (byte == 0x1B) {                      // maybe ST
                    _state = TXParserStateEscape;
                    return;
                }
                if (byte == 0x18 || byte == 0x1A) {
                    _state = TXParserStateGround;
                    return;
                }
                return;                                   // ignore other C0
            case TXParserStateDCSPassthrough:
            case TXParserStateSOSPMAPCString:
                if (byte == 0x1B) { _state = TXParserStateEscape; return; }
                if (byte == 0x18 || byte == 0x1A) { _state = TXParserStateGround; return; }
                return;
            default:
                break;
        }

        if (byte == 0x1B) {
            [self clearParserState];
            _state = TXParserStateEscape;
            return;
        }
        if (byte == 0x18 || byte == 0x1A) {   // CAN, SUB
            _state = TXParserStateGround;
            return;
        }
        [self executeControl:byte];
        return;
    }

    switch (_state) {
        case TXParserStateGround:
            [self groundByte:byte];
            break;
        case TXParserStateEscape:
            [self escapeByte:byte];
            break;
        case TXParserStateEscapeIntermediate:
            if (byte >= 0x20 && byte <= 0x2F) {
                [self collectIntermediate:byte];
            } else {
                [self dispatchEscape:byte];
                _state = TXParserStateGround;
            }
            break;
        case TXParserStateCSIEntry:
        case TXParserStateCSIParam:
        case TXParserStateCSIIntermediate:
        case TXParserStateCSIIgnore:
            [self csiByte:byte];
            break;
        case TXParserStateOSCString:
            [_stringBuffer appendBytes:&byte length:1];
            break;
        case TXParserStateDCSEntry:
        case TXParserStateDCSParam:
            if (byte >= 0x30 && byte <= 0x3B) {
                [self collectParameter:byte];
                _state = TXParserStateDCSParam;
            } else if (byte >= 0x20 && byte <= 0x2F) {
                [self collectIntermediate:byte];
            } else {
                _state = TXParserStateDCSPassthrough;
            }
            break;
        case TXParserStateDCSPassthrough:
        case TXParserStateSOSPMAPCString:
            [_stringBuffer appendBytes:&byte length:1];
            break;
    }
}

- (void)clearParserState {
    _paramCount = 0;
    memset(_params, 0, sizeof(_params));
    memset(_paramSet, 0, sizeof(_paramSet));
    memset(_subParamCount, 0, sizeof(_subParamCount));
    _intermediateCount = 0;
    _privateMarker = 0;
    [_stringBuffer setLength:0];
}

- (void)collectIntermediate:(uint8_t)byte {
    if (_intermediateCount < (NSInteger)sizeof(_intermediates)) {
        _intermediates[_intermediateCount++] = byte;
    }
}

- (void)collectParameter:(uint8_t)byte {
    if (_paramCount == 0) _paramCount = 1;
    NSInteger index = _paramCount - 1;

    if (byte == ';') {
        if (_paramCount < TX_MAX_PARAMS) _paramCount++;
        return;
    }
    if (byte == ':') {
        if (_subParamCount[index] < 8) _subParamCount[index]++;
        return;
    }
    if (index >= TX_MAX_PARAMS) return;

    int digit = byte - '0';
    NSInteger sub = _subParamCount[index];
    if (sub > 0) {
        int *slot = &_subParams[index][sub - 1];
        *slot = MIN(*slot * 10 + digit, 65535);
    } else {
        _paramSet[index] = YES;
        _params[index] = MIN(_params[index] * 10 + digit, 65535);
    }
}

/// Per ECMA-48 an omitted *or* zero parameter selects the sequence's default.
- (int)param:(NSInteger)index defaultValue:(int)fallback {
    if (index >= _paramCount || index >= TX_MAX_PARAMS) return fallback;
    if (!_paramSet[index]) return fallback;
    int value = _params[index];
    return value == 0 ? fallback : value;
}

- (int)rawParam:(NSInteger)index {
    if (index >= _paramCount || index >= TX_MAX_PARAMS) return 0;
    return _params[index];
}

#pragma mark - Ground state (printable text)

- (void)groundByte:(uint8_t)byte {
    if (byte < 0x80) {
        [self putCodepoint:[self mapCharset:byte]];
        return;
    }

    // UTF-8 continuation
    if (_utf8Remaining > 0) {
        if ((byte & 0xC0) != 0x80) {              // malformed
            _utf8Remaining = 0;
            [self putCodepoint:0xFFFD];
            [self groundByte:byte];
            return;
        }
        _utf8Codepoint = (_utf8Codepoint << 6) | (byte & 0x3F);
        if (--_utf8Remaining == 0) {
            uint32_t cp = _utf8Codepoint;
            if (cp < _utf8Minimum || (cp >= 0xD800 && cp <= 0xDFFF) || cp > 0x10FFFF) {
                cp = 0xFFFD;
            }
            [self putCodepoint:cp];
        }
        return;
    }

    if ((byte & 0xE0) == 0xC0) {
        _utf8Codepoint = byte & 0x1F; _utf8Remaining = 1; _utf8Minimum = 0x80;
    } else if ((byte & 0xF0) == 0xE0) {
        _utf8Codepoint = byte & 0x0F; _utf8Remaining = 2; _utf8Minimum = 0x800;
    } else if ((byte & 0xF8) == 0xF0) {
        _utf8Codepoint = byte & 0x07; _utf8Remaining = 3; _utf8Minimum = 0x10000;
    } else {
        [self putCodepoint:0xFFFD];
    }
}

/// Applies the DEC special graphics character set (line drawing) when selected.
- (uint32_t)mapCharset:(uint8_t)byte {
    int slot = _singleShift >= 0 ? _singleShift : _activeCharset;
    _singleShift = -1;
    if (_charsets[slot] != '0' || byte < 0x5F || byte > 0x7E) return byte;

    static const uint16_t dec[] = {
        0x00A0, 0x25C6, 0x2592, 0x2409, 0x240C, 0x240D, 0x240A, 0x00B0,
        0x00B1, 0x2424, 0x240B, 0x2518, 0x2510, 0x250C, 0x2514, 0x253C,
        0x23BA, 0x23BB, 0x2500, 0x23BC, 0x23BD, 0x251C, 0x2524, 0x2534,
        0x252C, 0x2502, 0x2264, 0x2265, 0x03C0, 0x2260, 0x00A3, 0x00B7,
    };
    return dec[byte - 0x5F];
}

- (void)putCodepoint:(uint32_t)cp {
    int width = TXCharacterWidth(cp);

    // Combining marks attach to the previous cell.
    if (width == 0) {
        NSInteger row = _cursorRow;
        NSInteger column = _cursorColumn - 1;
        while (column >= 0 &&
               ([self.buffer cellAtRow:row column:column].flags & TXCellFlagWideTrailer)) {
            column--;
        }
        if (column < 0) return;
        TXCell cell = [self.buffer cellAtRow:row column:column];
        NSString *existing = [self.buffer combiningMarksForCell:cell] ?: @"";
        NSString *combined = [existing stringByAppendingString:
                              [[NSString alloc] initWithBytes:&cp length:4
                                                     encoding:NSUTF32LittleEndianStringEncoding] ?: @""];
        cell.combining = [self.buffer internCombiningMarks:combined];
        [self.buffer setCell:cell atRow:row column:column];
        [self notifyScreenUpdate];
        return;
    }

    if (_wrapPending && _wraparound) {
        [self carriageReturn];
        [self lineFeedScrolling:YES];
        _wrapPending = NO;
    }

    // A double-width glyph never straddles the right margin.
    if (width == 2 && _cursorColumn == _columns - 1) {
        [self.buffer setCell:[self blankCell] atRow:_cursorRow column:_cursorColumn];
        if (_wraparound) {
            [self carriageReturn];
            [self lineFeedScrolling:YES];
        } else {
            return;
        }
    }

    if (_insertMode) {
        [self.buffer insertBlankCharacters:width atRow:_cursorRow column:_cursorColumn
                              withTemplate:[self blankCell]];
    }

    TXCell cell = TXCellMakeEmpty();
    cell.codepoint = cp;
    cell.foreground = _foreground;
    cell.background = _background;
    cell.flags = _flags;
    [self.buffer setCell:cell atRow:_cursorRow column:_cursorColumn];

    if (width == 2 && _cursorColumn + 1 < _columns) {
        TXCell trailer = cell;
        trailer.codepoint = ' ';
        trailer.flags |= TXCellFlagWideTrailer;
        [self.buffer setCell:trailer atRow:_cursorRow column:_cursorColumn + 1];
    }

    _cursorColumn += width;
    if (_cursorColumn >= _columns) {
        _cursorColumn = _columns - 1;
        _wrapPending = YES;
    }
    [self notifyScreenUpdate];
}

#pragma mark - C0 controls

- (void)executeControl:(uint8_t)byte {
    switch (byte) {
        case 0x07:  // BEL
            if ([self.delegate respondsToSelector:@selector(terminalDidRing:)]) {
                [self.delegate terminalDidRing:self];
            }
            break;
        case 0x08:  // BS
            [self backspace];
            break;
        case 0x09:  // HT
            [self horizontalTab:1];
            break;
        case 0x0A:  // LF
        case 0x0B:  // VT
        case 0x0C:  // FF
            [self lineFeedScrolling:YES];
            if (_newlineMode) [self carriageReturn];
            break;
        case 0x0D:  // CR
            [self carriageReturn];
            break;
        case 0x0E:  // SO -> G1
            _activeCharset = 1;
            break;
        case 0x0F:  // SI -> G0
            _activeCharset = 0;
            break;
        default:
            break;
    }
}

- (void)backspace {
    if (_wrapPending) {
        _wrapPending = NO;
        return;
    }
    if (_cursorColumn > 0) {
        _cursorColumn--;
    } else if (_reverseWraparound && _cursorRow > _scrollTop) {
        _cursorRow--;
        _cursorColumn = _columns - 1;
    }
    [self notifyScreenUpdate];
}

- (void)carriageReturn {
    _cursorColumn = 0;
    _wrapPending = NO;
    [self notifyScreenUpdate];
}

- (void)lineFeedScrolling:(BOOL)allowScroll {
    _wrapPending = NO;
    if (_cursorRow == _scrollBottom) {
        if (allowScroll) {
            BOOL toScrollback = !_usingAlternateScreen && _scrollTop == 0 && _scrollBottom == _rows - 1;
            [self.buffer scrollUpFromRow:_scrollTop toRow:_scrollBottom count:1
                          intoScrollback:toScrollback];
        }
    } else if (_cursorRow < _rows - 1) {
        _cursorRow++;
    }
    [self notifyScreenUpdate];
}

- (void)reverseIndex {
    _wrapPending = NO;
    if (_cursorRow == _scrollTop) {
        [self.buffer scrollDownFromRow:_scrollTop toRow:_scrollBottom count:1];
    } else if (_cursorRow > 0) {
        _cursorRow--;
    }
    [self notifyScreenUpdate];
}

- (void)horizontalTab:(NSInteger)count {
    for (NSInteger i = 0; i < count; i++) {
        NSInteger next = _columns - 1;
        for (NSInteger column = _cursorColumn + 1; column < _columns; column++) {
            if ([_tabStops containsIndex:(NSUInteger)column]) { next = column; break; }
        }
        _cursorColumn = next;
    }
    _wrapPending = NO;
    [self notifyScreenUpdate];
}

- (void)backTab:(NSInteger)count {
    for (NSInteger i = 0; i < count; i++) {
        NSInteger prev = 0;
        for (NSInteger column = _cursorColumn - 1; column >= 0; column--) {
            if ([_tabStops containsIndex:(NSUInteger)column]) { prev = column; break; }
        }
        _cursorColumn = prev;
    }
    [self notifyScreenUpdate];
}

#pragma mark - Escape sequences

- (void)escapeByte:(uint8_t)byte {
    if (byte >= 0x20 && byte <= 0x2F) {
        [self collectIntermediate:byte];
        _state = TXParserStateEscapeIntermediate;
        return;
    }

    switch (byte) {
        case '[':
            [self clearParserState];
            _state = TXParserStateCSIEntry;
            return;
        case ']':
            [self clearParserState];
            _state = TXParserStateOSCString;
            return;
        case 'P':
            [self clearParserState];
            _state = TXParserStateDCSEntry;
            return;
        case 'X': case '^': case '_':
            [self clearParserState];
            _state = TXParserStateSOSPMAPCString;
            return;
        case '\\':                     // ST -- terminates OSC/DCS
            if (_stringBuffer.length > 0) [self dispatchOSC];
            _state = TXParserStateGround;
            return;
        default:
            break;
    }

    [self dispatchEscape:byte];
    _state = TXParserStateGround;
}

- (void)dispatchEscape:(uint8_t)final {
    if (_intermediateCount > 0) {
        uint8_t intermediate = _intermediates[0];
        // Character set designation: ESC ( B, ESC ) 0, ...
        if (intermediate == '(' || intermediate == ')' ||
            intermediate == '*' || intermediate == '+') {
            int slot = intermediate == '(' ? 0 : intermediate == ')' ? 1 : intermediate == '*' ? 2 : 3;
            _charsets[slot] = (char)final;
            return;
        }
        if (intermediate == '#' && final == '8') {   // DECALN
            TXCell cell = TXCellMakeEmpty();
            cell.codepoint = 'E';
            for (NSInteger row = 0; row < _rows; row++) {
                for (NSInteger column = 0; column < _columns; column++) {
                    [self.buffer setCell:cell atRow:row column:column];
                }
            }
            [self notifyScreenUpdate];
            return;
        }
        return;
    }

    switch (final) {
        case '7': [self saveCursor]; break;               // DECSC
        case '8': [self restoreCursor]; break;            // DECRC
        case '=': _applicationKeypad = YES; break;        // DECKPAM
        case '>': _applicationKeypad = NO; break;         // DECKPNM
        case 'D': [self lineFeedScrolling:YES]; break;    // IND
        case 'E':                                         // NEL
            [self carriageReturn];
            [self lineFeedScrolling:YES];
            break;
        case 'H':                                         // HTS
            [_tabStops addIndex:(NSUInteger)_cursorColumn];
            break;
        case 'M': [self reverseIndex]; break;             // RI
        case 'N': _singleShift = 2; break;                // SS2
        case 'O': _singleShift = 3; break;                // SS3
        case 'c': [self reset]; break;                    // RIS
        default: break;
    }
}

- (void)saveCursor {
    TXCursorState state = {
        .row = _cursorRow, .column = _cursorColumn,
        .foreground = _foreground, .background = _background,
        .flags = _flags, .originMode = _originMode,
        .wraparound = _wraparound, .charset = _activeCharset,
    };
    if (_usingAlternateScreen) _savedCursorAlt = state; else _savedCursor = state;
}

- (void)restoreCursor {
    TXCursorState state = _usingAlternateScreen ? _savedCursorAlt : _savedCursor;
    _cursorRow = MAX(0, MIN(state.row, _rows - 1));
    _cursorColumn = MAX(0, MIN(state.column, _columns - 1));
    _foreground = state.foreground;
    _background = state.background;
    _flags = state.flags;
    _originMode = state.originMode;
    _wraparound = state.wraparound;
    _activeCharset = state.charset;
    _wrapPending = NO;
    [self notifyScreenUpdate];
}

#pragma mark - CSI

- (void)csiByte:(uint8_t)byte {
    if (_state == TXParserStateCSIIgnore) {
        if (byte >= 0x40 && byte <= 0x7E) _state = TXParserStateGround;
        return;
    }

    if (byte >= 0x30 && byte <= 0x39) {          // digits
        [self collectParameter:byte];
        _state = TXParserStateCSIParam;
        return;
    }
    if (byte == ';' || byte == ':') {
        [self collectParameter:byte];
        _state = TXParserStateCSIParam;
        return;
    }
    if (byte >= 0x3C && byte <= 0x3F) {          // < = > ?
        if (_state == TXParserStateCSIEntry) {
            _privateMarker = byte;
            _state = TXParserStateCSIParam;
        } else {
            _state = TXParserStateCSIIgnore;
        }
        return;
    }
    if (byte >= 0x20 && byte <= 0x2F) {
        [self collectIntermediate:byte];
        _state = TXParserStateCSIIntermediate;
        return;
    }
    if (byte >= 0x40 && byte <= 0x7E) {
        [self dispatchCSI:byte];
        _state = TXParserStateGround;
        return;
    }
    _state = TXParserStateCSIIgnore;
}

- (NSInteger)clampRow:(NSInteger)row {
    if (_originMode) {
        return MAX(_scrollTop, MIN(row, _scrollBottom));
    }
    return MAX(0, MIN(row, _rows - 1));
}

- (void)dispatchCSI:(uint8_t)final {
    int p0 = [self param:0 defaultValue:1];
    TXCell blank = [self blankCell];

    if (_privateMarker == '?') {
        switch (final) {
            case 'h': [self setPrivateModes:YES]; return;
            case 'l': [self setPrivateModes:NO]; return;
            case 'K': {                                   // DECSEL (treat as EL)
                [self eraseInLine:[self param:0 defaultValue:0]];
                return;
            }
            case 'J': {                                   // DECSED
                [self eraseInDisplay:[self param:0 defaultValue:0]];
                return;
            }
            default: return;
        }
    }

    if (_intermediateCount > 0) {
        uint8_t intermediate = _intermediates[0];
        if (intermediate == ' ' && final == 'q') return;         // DECSCUSR (cursor style)
        if (intermediate == '!' && final == 'p') { [self reset]; return; }  // DECSTR
        if (intermediate == '$') return;                          // DECRQM etc.
        return;
    }

    switch (final) {
        case '@':                                     // ICH
            [self.buffer insertBlankCharacters:p0 atRow:_cursorRow column:_cursorColumn
                                  withTemplate:blank];
            break;
        case 'A':                                     // CUU
            _cursorRow = MAX(_cursorRow - p0, _originMode ? _scrollTop : 0);
            _wrapPending = NO;
            break;
        case 'B':                                     // CUD
            _cursorRow = MIN(_cursorRow + p0, _originMode ? _scrollBottom : _rows - 1);
            _wrapPending = NO;
            break;
        case 'C':                                     // CUF
            _cursorColumn = MIN(_cursorColumn + p0, _columns - 1);
            _wrapPending = NO;
            break;
        case 'D':                                     // CUB
            _cursorColumn = MAX(_cursorColumn - p0, 0);
            _wrapPending = NO;
            break;
        case 'E':                                     // CNL
            _cursorRow = MIN(_cursorRow + p0, _rows - 1);
            _cursorColumn = 0;
            _wrapPending = NO;
            break;
        case 'F':                                     // CPL
            _cursorRow = MAX(_cursorRow - p0, 0);
            _cursorColumn = 0;
            _wrapPending = NO;
            break;
        case 'G':                                     // CHA
        case '`':                                     // HPA
            _cursorColumn = MAX(0, MIN(p0 - 1, _columns - 1));
            _wrapPending = NO;
            break;
        case 'H':                                     // CUP
        case 'f': {                                   // HVP
            NSInteger row = [self param:0 defaultValue:1] - 1;
            NSInteger column = [self param:1 defaultValue:1] - 1;
            if (_originMode) row += _scrollTop;
            _cursorRow = [self clampRow:row];
            _cursorColumn = MAX(0, MIN(column, _columns - 1));
            _wrapPending = NO;
            break;
        }
        case 'I':                                     // CHT
            [self horizontalTab:p0];
            break;
        case 'J':                                     // ED
            [self eraseInDisplay:[self param:0 defaultValue:0]];
            break;
        case 'K':                                     // EL
            [self eraseInLine:[self param:0 defaultValue:0]];
            break;
        case 'L':                                     // IL
            if (_cursorRow >= _scrollTop && _cursorRow <= _scrollBottom) {
                [self.buffer scrollDownFromRow:_cursorRow toRow:_scrollBottom count:p0];
            }
            break;
        case 'M':                                     // DL
            if (_cursorRow >= _scrollTop && _cursorRow <= _scrollBottom) {
                [self.buffer scrollUpFromRow:_cursorRow toRow:_scrollBottom count:p0
                              intoScrollback:NO];
            }
            break;
        case 'P':                                     // DCH
            [self.buffer deleteCharacters:p0 atRow:_cursorRow column:_cursorColumn
                             withTemplate:blank];
            break;
        case 'S':                                     // SU
            [self.buffer scrollUpFromRow:_scrollTop toRow:_scrollBottom count:p0
                          intoScrollback:NO];
            break;
        case 'T':                                     // SD
            [self.buffer scrollDownFromRow:_scrollTop toRow:_scrollBottom count:p0];
            break;
        case 'X': {                                   // ECH
            NSInteger to = MIN(_cursorColumn + p0 - 1, _columns - 1);
            [self.buffer clearRow:_cursorRow fromColumn:_cursorColumn toColumn:to
                     withTemplate:blank];
            break;
        }
        case 'Z':                                     // CBT
            [self backTab:p0];
            break;
        case 'b': {                                   // REP
            TXCell previous = [self.buffer cellAtRow:_cursorRow
                                              column:MAX(_cursorColumn - 1, 0)];
            for (int i = 0; i < p0; i++) [self putCodepoint:previous.codepoint];
            break;
        }
        case 'c':                                     // DA1
            [self respond:@"\033[?62;1;6;9;15;22c"];
            break;
        case 'd':                                     // VPA
            _cursorRow = [self clampRow:_originMode ? _scrollTop + p0 - 1 : p0 - 1];
            _wrapPending = NO;
            break;
        case 'g':                                     // TBC
            if ([self param:0 defaultValue:0] == 3) {
                [_tabStops removeAllIndexes];
            } else {
                [_tabStops removeIndex:(NSUInteger)_cursorColumn];
            }
            break;
        case 'h': [self setAnsiModes:YES]; break;     // SM
        case 'l': [self setAnsiModes:NO]; break;      // RM
        case 'm': [self selectGraphicRendition]; break;
        case 'n':                                     // DSR
            if ([self param:0 defaultValue:0] == 6) {
                NSInteger row = _originMode ? _cursorRow - _scrollTop : _cursorRow;
                [self respond:[NSString stringWithFormat:@"\033[%ld;%ldR",
                               (long)(row + 1), (long)(_cursorColumn + 1)]];
            } else if ([self param:0 defaultValue:0] == 5) {
                [self respond:@"\033[0n"];
            }
            break;
        case 'r': {                                   // DECSTBM
            NSInteger top = [self param:0 defaultValue:1] - 1;
            NSInteger bottom = _paramCount > 1 && _paramSet[1] ? _params[1] - 1 : _rows - 1;
            if (top < bottom && bottom < _rows) {
                _scrollTop = MAX(top, 0);
                _scrollBottom = bottom;
            } else if (top == 0 && bottom >= _rows - 1) {
                _scrollTop = 0;
                _scrollBottom = _rows - 1;
            }
            _cursorRow = _originMode ? _scrollTop : 0;
            _cursorColumn = 0;
            _wrapPending = NO;
            break;
        }
        case 's': [self saveCursor]; break;
        case 'u': [self restoreCursor]; break;
        case 't':                                     // window ops
            if ([self param:0 defaultValue:0] == 18) {
                [self respond:[NSString stringWithFormat:@"\033[8;%ld;%ldt",
                               (long)_rows, (long)_columns]];
            }
            break;
        default:
            break;
    }
    [self notifyScreenUpdate];
}

- (void)eraseInDisplay:(int)mode {
    TXCell blank = [self blankCell];
    switch (mode) {
        case 0:
            [self.buffer clearRow:_cursorRow fromColumn:_cursorColumn toColumn:_columns - 1
                     withTemplate:blank];
            for (NSInteger row = _cursorRow + 1; row < _rows; row++) {
                [self.buffer clearRow:row fromColumn:0 toColumn:_columns - 1 withTemplate:blank];
            }
            break;
        case 1:
            for (NSInteger row = 0; row < _cursorRow; row++) {
                [self.buffer clearRow:row fromColumn:0 toColumn:_columns - 1 withTemplate:blank];
            }
            [self.buffer clearRow:_cursorRow fromColumn:0 toColumn:_cursorColumn
                     withTemplate:blank];
            break;
        case 2:
        case 3:
            for (NSInteger row = 0; row < _rows; row++) {
                [self.buffer clearRow:row fromColumn:0 toColumn:_columns - 1 withTemplate:blank];
            }
            if (mode == 3) [self.buffer clearScrollback];
            break;
        default:
            break;
    }
    _wrapPending = NO;
}

- (void)eraseInLine:(int)mode {
    TXCell blank = [self blankCell];
    switch (mode) {
        case 0:
            [self.buffer clearRow:_cursorRow fromColumn:_cursorColumn toColumn:_columns - 1
                     withTemplate:blank];
            break;
        case 1:
            [self.buffer clearRow:_cursorRow fromColumn:0 toColumn:_cursorColumn
                     withTemplate:blank];
            break;
        case 2:
            [self.buffer clearRow:_cursorRow fromColumn:0 toColumn:_columns - 1
                     withTemplate:blank];
            break;
        default:
            break;
    }
    _wrapPending = NO;
}

#pragma mark - Modes

- (void)setAnsiModes:(BOOL)enabled {
    for (NSInteger i = 0; i < MAX(_paramCount, 1); i++) {
        switch ([self rawParam:i]) {
            case 4:  _insertMode = enabled; break;      // IRM
            case 20: _newlineMode = enabled; break;     // LNM
            default: break;
        }
    }
}

- (void)setPrivateModes:(BOOL)enabled {
    for (NSInteger i = 0; i < MAX(_paramCount, 1); i++) {
        int mode = [self rawParam:i];
        switch (mode) {
            case 1:    _applicationCursorKeys = enabled; break;      // DECCKM
            case 3:                                                   // DECCOLM
                [self eraseInDisplay:2];
                _cursorRow = 0; _cursorColumn = 0;
                break;
            case 6:                                                   // DECOM
                _originMode = enabled;
                _cursorRow = enabled ? _scrollTop : 0;
                _cursorColumn = 0;
                break;
            case 7:    _wraparound = enabled; break;                  // DECAWM
            case 12:   break;                                         // cursor blink
            case 25:   _cursorVisible = enabled; break;               // DECTCEM
            case 45:   _reverseWraparound = enabled; break;
            case 9:    _mouseMode = enabled ? TXMouseModeX10 : TXMouseModeNone; break;
            case 1000: _mouseMode = enabled ? TXMouseModeNormal : TXMouseModeNone; break;
            case 1002: _mouseMode = enabled ? TXMouseModeButtonEvent : TXMouseModeNone; break;
            case 1003: _mouseMode = enabled ? TXMouseModeAnyEvent : TXMouseModeNone; break;
            case 1005: break;                                         // UTF-8 mouse
            case 1006: _mouseSGREncoding = enabled; break;
            case 1015: break;
            case 47:
            case 1047:
            case 1049:
                [self setAlternateScreen:enabled saveCursor:(mode == 1049)];
                break;
            case 1048:
                if (enabled) [self saveCursor]; else [self restoreCursor];
                break;
            case 2004: _bracketedPaste = enabled; break;
            default: break;
        }
    }
    [self notifyScreenUpdate];
}

- (void)setAlternateScreen:(BOOL)enabled saveCursor:(BOOL)withCursor {
    if (enabled == _usingAlternateScreen) return;

    if (enabled) {
        if (withCursor) [self saveCursor];
        _usingAlternateScreen = YES;
        TXCell blank = [self blankCell];
        for (NSInteger row = 0; row < _rows; row++) {
            [_alternateBuffer clearRow:row fromColumn:0 toColumn:_columns - 1
                          withTemplate:blank];
        }
        if (withCursor) { _cursorRow = 0; _cursorColumn = 0; }
    } else {
        _usingAlternateScreen = NO;
        if (withCursor) [self restoreCursor];
    }
    _wrapPending = NO;
    [self.buffer markAllDirty];
    [self notifyScreenUpdate];
}

#pragma mark - SGR

- (void)selectGraphicRendition {
    if (_paramCount == 0) {
        _flags = TXCellFlagNone;
        _foreground = TXColorDefault();
        _background = TXColorDefault();
        return;
    }

    for (NSInteger i = 0; i < _paramCount; i++) {
        int code = [self rawParam:i];

        // Truecolour with colon sub-parameters: 38:2::R:G:B or 38:5:N
        if ((code == 38 || code == 48 || code == 58) && _subParamCount[i] > 0) {
            int kind = _subParams[i][0];
            TXColor color = TXColorDefault();
            if (kind == 2 && _subParamCount[i] >= 4) {
                NSInteger base = _subParamCount[i] >= 5 ? 2 : 1;
                color = TXColorMakeRGB((uint8_t)_subParams[i][base],
                                       (uint8_t)_subParams[i][base + 1],
                                       (uint8_t)_subParams[i][base + 2]);
            } else if (kind == 5 && _subParamCount[i] >= 2) {
                color = TXColorMakeIndexed((uint32_t)_subParams[i][1]);
            }
            if (code == 38) _foreground = color;
            else if (code == 48) _background = color;
            continue;
        }

        // Truecolour with semicolon parameters: 38;2;R;G;B or 38;5;N
        if ((code == 38 || code == 48) && i + 1 < _paramCount) {
            int kind = [self rawParam:i + 1];
            TXColor color = TXColorDefault();
            if (kind == 2 && i + 4 < _paramCount) {
                color = TXColorMakeRGB((uint8_t)[self rawParam:i + 2],
                                       (uint8_t)[self rawParam:i + 3],
                                       (uint8_t)[self rawParam:i + 4]);
                i += 4;
            } else if (kind == 5 && i + 2 < _paramCount) {
                color = TXColorMakeIndexed((uint32_t)[self rawParam:i + 2]);
                i += 2;
            } else {
                i += 1;
            }
            if (code == 38) _foreground = color; else _background = color;
            continue;
        }

        switch (code) {
            case 0:
                _flags = TXCellFlagNone;
                _foreground = TXColorDefault();
                _background = TXColorDefault();
                break;
            case 1:  _flags |= TXCellFlagBold; break;
            case 2:  _flags |= TXCellFlagDim; break;
            case 3:  _flags |= TXCellFlagItalic; break;
            case 4:  _flags |= TXCellFlagUnderline; break;
            case 5:
            case 6:  _flags |= TXCellFlagBlink; break;
            case 7:  _flags |= TXCellFlagInverse; break;
            case 8:  _flags |= TXCellFlagInvisible; break;
            case 9:  _flags |= TXCellFlagStrikethrough; break;
            case 21:
            case 22: _flags &= ~(TXCellFlagBold | TXCellFlagDim); break;
            case 23: _flags &= ~TXCellFlagItalic; break;
            case 24: _flags &= ~TXCellFlagUnderline; break;
            case 25: _flags &= ~TXCellFlagBlink; break;
            case 27: _flags &= ~TXCellFlagInverse; break;
            case 28: _flags &= ~TXCellFlagInvisible; break;
            case 29: _flags &= ~TXCellFlagStrikethrough; break;
            case 39: _foreground = TXColorDefault(); break;
            case 49: _background = TXColorDefault(); break;
            default:
                if (code >= 30 && code <= 37) {
                    _foreground = TXColorMakeIndexed((uint32_t)(code - 30));
                } else if (code >= 40 && code <= 47) {
                    _background = TXColorMakeIndexed((uint32_t)(code - 40));
                } else if (code >= 90 && code <= 97) {
                    _foreground = TXColorMakeIndexed((uint32_t)(code - 90 + 8));
                } else if (code >= 100 && code <= 107) {
                    _background = TXColorMakeIndexed((uint32_t)(code - 100 + 8));
                }
                break;
        }
    }
}

#pragma mark - OSC

- (void)dispatchOSC {
    NSString *string = [[NSString alloc] initWithData:_stringBuffer encoding:NSUTF8StringEncoding];
    [_stringBuffer setLength:0];
    if (string.length == 0) return;

    NSRange separator = [string rangeOfString:@";"];
    NSString *command = separator.location == NSNotFound ? string
                                                         : [string substringToIndex:separator.location];
    NSString *value = separator.location == NSNotFound ? @""
                                                       : [string substringFromIndex:separator.location + 1];

    NSInteger code = command.integerValue;
    switch (code) {
        case 0:
        case 1:
        case 2:
            _title = value;
            if ([self.delegate respondsToSelector:@selector(terminal:didSetTitle:)]) {
                [self.delegate terminal:self didSetTitle:value];
            }
            break;
        case 52: {                                     // clipboard
            NSRange sep = [value rangeOfString:@";"];
            if (sep.location == NSNotFound) break;
            NSString *encoded = [value substringFromIndex:sep.location + 1];
            NSData *decoded = [[NSData alloc] initWithBase64EncodedString:encoded options:0];
            NSString *text = decoded ? [[NSString alloc] initWithData:decoded
                                                             encoding:NSUTF8StringEncoding] : nil;
            if (text && [self.delegate respondsToSelector:@selector(terminal:didSetClipboard:)]) {
                [self.delegate terminal:self didSetClipboard:text];
            }
            break;
        }
        default:
            break;
    }
}

@end
