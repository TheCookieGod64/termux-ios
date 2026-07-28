//
//  TXTerminalBuffer.h
//  Screen buffer: a grid of cells plus scrollback, with the operations a
//  VT/xterm emulator needs (scrolling regions, insert/delete, erase).
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Text attributes packed into a single word.
typedef NS_OPTIONS(uint16_t, TXCellFlags) {
    TXCellFlagNone          = 0,
    TXCellFlagBold          = 1 << 0,
    TXCellFlagDim           = 1 << 1,
    TXCellFlagItalic        = 1 << 2,
    TXCellFlagUnderline     = 1 << 3,
    TXCellFlagBlink         = 1 << 4,
    TXCellFlagInverse       = 1 << 5,
    TXCellFlagInvisible     = 1 << 6,
    TXCellFlagStrikethrough = 1 << 7,
    /// Right half of a double-width (CJK/emoji) glyph; never drawn itself.
    TXCellFlagWideTrailer   = 1 << 8,
};

/// Colour is either an index into the 256-colour palette or a 24-bit truecolour
/// value.  Index 256 means "default".
typedef struct {
    uint32_t value;   // palette index, or 0xRRGGBB when isTrueColor
    bool isTrueColor;
} TXColor;

static const uint32_t TXColorDefaultIndex = 256;

static inline TXColor TXColorMakeIndexed(uint32_t index) {
    TXColor c;
    c.value = index;
    c.isTrueColor = false;
    return c;
}

static inline TXColor TXColorMakeRGB(uint8_t r, uint8_t g, uint8_t b) {
    TXColor c;
    c.value = ((uint32_t)r << 16) | ((uint32_t)g << 8) | b;
    c.isTrueColor = true;
    return c;
}

static inline TXColor TXColorDefault(void) {
    return TXColorMakeIndexed(TXColorDefaultIndex);
}

static inline bool TXColorEqual(TXColor a, TXColor b) {
    return a.value == b.value && a.isTrueColor == b.isTrueColor;
}

/// One character cell.  `codepoint` is a single Unicode scalar; combining marks
/// are stored out-of-band in the buffer's combining table.
typedef struct {
    uint32_t codepoint;
    TXColor foreground;
    TXColor background;
    TXCellFlags flags;
    /// Index into the combining-mark table (0 == none).
    uint16_t combining;
} TXCell;

TXCell TXCellMakeEmpty(void);

/// Rectangular grid of cells with scrollback, addressed row/column from 0.
@interface TXTerminalBuffer : NSObject

@property (nonatomic, readonly) NSInteger rows;
@property (nonatomic, readonly) NSInteger columns;

/// Number of lines currently retained above the visible screen.
@property (nonatomic, readonly) NSInteger scrollbackLines;
/// Maximum retained scrollback (default 5000).
@property (nonatomic) NSInteger maxScrollbackLines;

/// Monotonically increasing counter bumped on every mutation, so views can
/// cheaply decide whether a redraw is needed.
@property (nonatomic, readonly) uint64_t generation;

- (instancetype)initWithRows:(NSInteger)rows columns:(NSInteger)columns;

#pragma mark - Access

/// Cell at a visible-screen coordinate.  Out-of-range returns an empty cell.
- (TXCell)cellAtRow:(NSInteger)row column:(NSInteger)column;
- (void)setCell:(TXCell)cell atRow:(NSInteger)row column:(NSInteger)column;

/// Cell addressed in "absolute" space where row -scrollbackLines is the oldest
/// scrollback line and row 0 is the top of the visible screen.
- (TXCell)cellAtAbsoluteRow:(NSInteger)row column:(NSInteger)column;

/// Combining marks attached to a cell, or nil.
- (nullable NSString *)combiningMarksForCell:(TXCell)cell;
/// Interns a combining sequence, returning the table index to store in a cell.
- (uint16_t)internCombiningMarks:(NSString *)marks;

/// Whether the row changed since the given generation marker.
- (BOOL)row:(NSInteger)row dirtySinceGeneration:(uint64_t)generation;
- (void)markAllDirty;

#pragma mark - Geometry

- (void)resizeToRows:(NSInteger)rows columns:(NSInteger)columns;

#pragma mark - Mutation

/// Scrolls `count` lines up inside [top, bottom]; lines leaving the top of a
/// full-screen region are pushed into scrollback.
- (void)scrollUpFromRow:(NSInteger)top toRow:(NSInteger)bottom count:(NSInteger)count
       intoScrollback:(BOOL)intoScrollback;
- (void)scrollDownFromRow:(NSInteger)top toRow:(NSInteger)bottom count:(NSInteger)count;

- (void)clearRow:(NSInteger)row fromColumn:(NSInteger)from toColumn:(NSInteger)to
       withTemplate:(TXCell)templateCell;
- (void)insertBlankCharacters:(NSInteger)count atRow:(NSInteger)row column:(NSInteger)column
                 withTemplate:(TXCell)templateCell;
- (void)deleteCharacters:(NSInteger)count atRow:(NSInteger)row column:(NSInteger)column
            withTemplate:(TXCell)templateCell;

- (void)clearScrollback;

#pragma mark - Text extraction

/// Plain text of a visible row with trailing blanks removed.
- (NSString *)stringForRow:(NSInteger)row;
/// Plain text spanning absolute rows, used for copy/select-all.
- (NSString *)stringFromAbsoluteRow:(NSInteger)startRow column:(NSInteger)startColumn
                    toAbsoluteRow:(NSInteger)endRow column:(NSInteger)endColumn;

@end

NS_ASSUME_NONNULL_END
