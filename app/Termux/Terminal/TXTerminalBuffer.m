//
//  TXTerminalBuffer.m
//

#import "TXTerminalBuffer.h"

TXCell TXCellMakeEmpty(void) {
    TXCell cell;
    cell.codepoint = ' ';
    cell.foreground = TXColorDefault();
    cell.background = TXColorDefault();
    cell.flags = TXCellFlagNone;
    cell.combining = 0;
    return cell;
}

/// A single line.  Lines are heap allocated so scrolling is a pointer shuffle
/// rather than a memmove of the whole grid.
typedef struct {
    TXCell *cells;
    NSInteger capacity;
    uint64_t generation;   // last generation at which this line changed
} TXLine;

static TXLine *TXLineCreate(NSInteger columns) {
    TXLine *line = calloc(1, sizeof(TXLine));
    line->cells = calloc((size_t)MAX(columns, 1), sizeof(TXCell));
    line->capacity = MAX(columns, 1);
    for (NSInteger i = 0; i < line->capacity; i++) {
        line->cells[i] = TXCellMakeEmpty();
    }
    return line;
}

static void TXLineFree(TXLine *line) {
    if (!line) return;
    free(line->cells);
    free(line);
}

static void TXLineResize(TXLine *line, NSInteger columns) {
    columns = MAX(columns, 1);
    if (columns == line->capacity) return;
    TXCell *cells = calloc((size_t)columns, sizeof(TXCell));
    NSInteger copy = MIN(columns, line->capacity);
    memcpy(cells, line->cells, (size_t)copy * sizeof(TXCell));
    for (NSInteger i = copy; i < columns; i++) {
        cells[i] = TXCellMakeEmpty();
    }
    free(line->cells);
    line->cells = cells;
    line->capacity = columns;
}

@implementation TXTerminalBuffer {
    TXLine **_lines;              // visible screen, _rows entries
    TXLine **_scrollback;         // ring buffer
    NSInteger _scrollbackCapacity;
    NSInteger _scrollbackHead;    // index of oldest entry
    NSInteger _scrollbackCount;
    NSMutableArray<NSString *> *_combiningTable;
    NSMutableDictionary<NSString *, NSNumber *> *_combiningLookup;
}

- (instancetype)initWithRows:(NSInteger)rows columns:(NSInteger)columns {
    self = [super init];
    if (!self) return nil;

    _rows = MAX(rows, 1);
    _columns = MAX(columns, 1);
    _maxScrollbackLines = 5000;
    _generation = 1;

    _lines = calloc((size_t)_rows, sizeof(TXLine *));
    for (NSInteger i = 0; i < _rows; i++) {
        _lines[i] = TXLineCreate(_columns);
        _lines[i]->generation = _generation;
    }

    _scrollbackCapacity = _maxScrollbackLines;
    _scrollback = calloc((size_t)MAX(_scrollbackCapacity, 1), sizeof(TXLine *));

    _combiningTable = [NSMutableArray arrayWithObject:@""];
    _combiningLookup = [NSMutableDictionary dictionary];

    return self;
}

- (void)dealloc {
    for (NSInteger i = 0; i < _rows; i++) {
        TXLineFree(_lines[i]);
    }
    free(_lines);
    for (NSInteger i = 0; i < _scrollbackCount; i++) {
        TXLineFree(_scrollback[(_scrollbackHead + i) % _scrollbackCapacity]);
    }
    free(_scrollback);
}

#pragma mark - Internals

- (void)touchLine:(TXLine *)line {
    _generation++;
    line->generation = _generation;
}

- (TXLine *)lineAtRow:(NSInteger)row {
    if (row < 0 || row >= _rows) return NULL;
    return _lines[row];
}

- (void)pushLineToScrollback:(TXLine *)line {
    if (_maxScrollbackLines <= 0) {
        TXLineFree(line);
        return;
    }
    if (_scrollbackCapacity != _maxScrollbackLines) {
        [self reallocScrollbackTo:_maxScrollbackLines];
    }
    if (_scrollbackCount == _scrollbackCapacity) {
        TXLineFree(_scrollback[_scrollbackHead]);
        _scrollback[_scrollbackHead] = line;
        _scrollbackHead = (_scrollbackHead + 1) % _scrollbackCapacity;
    } else {
        NSInteger index = (_scrollbackHead + _scrollbackCount) % _scrollbackCapacity;
        _scrollback[index] = line;
        _scrollbackCount++;
    }
}

- (void)reallocScrollbackTo:(NSInteger)capacity {
    capacity = MAX(capacity, 1);
    TXLine **buffer = calloc((size_t)capacity, sizeof(TXLine *));
    NSInteger keep = MIN(_scrollbackCount, capacity);
    NSInteger skip = _scrollbackCount - keep;
    for (NSInteger i = 0; i < skip; i++) {
        TXLineFree(_scrollback[(_scrollbackHead + i) % _scrollbackCapacity]);
    }
    for (NSInteger i = 0; i < keep; i++) {
        buffer[i] = _scrollback[(_scrollbackHead + skip + i) % _scrollbackCapacity];
    }
    free(_scrollback);
    _scrollback = buffer;
    _scrollbackCapacity = capacity;
    _scrollbackHead = 0;
    _scrollbackCount = keep;
}

- (TXLine *)scrollbackLineAtIndex:(NSInteger)index {
    if (index < 0 || index >= _scrollbackCount) return NULL;
    return _scrollback[(_scrollbackHead + index) % _scrollbackCapacity];
}

#pragma mark - Access

- (NSInteger)scrollbackLines {
    return _scrollbackCount;
}

- (TXCell)cellAtRow:(NSInteger)row column:(NSInteger)column {
    TXLine *line = [self lineAtRow:row];
    if (!line || column < 0 || column >= line->capacity) return TXCellMakeEmpty();
    return line->cells[column];
}

- (void)setCell:(TXCell)cell atRow:(NSInteger)row column:(NSInteger)column {
    TXLine *line = [self lineAtRow:row];
    if (!line || column < 0 || column >= line->capacity) return;
    line->cells[column] = cell;
    [self touchLine:line];
}

- (TXCell)cellAtAbsoluteRow:(NSInteger)row column:(NSInteger)column {
    if (row >= 0) return [self cellAtRow:row column:column];
    TXLine *line = [self scrollbackLineAtIndex:_scrollbackCount + row];
    if (!line || column < 0 || column >= line->capacity) return TXCellMakeEmpty();
    return line->cells[column];
}

- (NSString *)combiningMarksForCell:(TXCell)cell {
    if (cell.combining == 0 || cell.combining >= _combiningTable.count) return nil;
    return _combiningTable[cell.combining];
}

- (uint16_t)internCombiningMarks:(NSString *)marks {
    if (marks.length == 0) return 0;
    NSNumber *existing = _combiningLookup[marks];
    if (existing) return (uint16_t)existing.unsignedIntegerValue;
    if (_combiningTable.count >= UINT16_MAX) return 0;
    [_combiningTable addObject:marks];
    uint16_t index = (uint16_t)(_combiningTable.count - 1);
    _combiningLookup[marks] = @(index);
    return index;
}

- (BOOL)row:(NSInteger)row dirtySinceGeneration:(uint64_t)generation {
    TXLine *line = [self lineAtRow:row];
    return line ? line->generation > generation : NO;
}

- (void)markAllDirty {
    _generation++;
    for (NSInteger i = 0; i < _rows; i++) {
        _lines[i]->generation = _generation;
    }
}

#pragma mark - Geometry

- (void)resizeToRows:(NSInteger)rows columns:(NSInteger)columns {
    rows = MAX(rows, 1);
    columns = MAX(columns, 1);
    if (rows == _rows && columns == _columns) return;

    for (NSInteger i = 0; i < _rows; i++) {
        TXLineResize(_lines[i], columns);
    }
    for (NSInteger i = 0; i < _scrollbackCount; i++) {
        TXLineResize([self scrollbackLineAtIndex:i], columns);
    }

    if (rows != _rows) {
        TXLine **lines = calloc((size_t)rows, sizeof(TXLine *));
        if (rows < _rows) {
            // Shrinking: the top lines scroll off into scrollback.
            NSInteger drop = _rows - rows;
            for (NSInteger i = 0; i < drop; i++) {
                [self pushLineToScrollback:_lines[i]];
            }
            memcpy(lines, _lines + drop, (size_t)rows * sizeof(TXLine *));
        } else {
            // Growing: pull lines back out of scrollback when we have them.
            NSInteger extra = rows - _rows;
            NSInteger restore = MIN(extra, _scrollbackCount);
            for (NSInteger i = 0; i < restore; i++) {
                NSInteger index = _scrollbackCount - restore + i;
                lines[i] = [self scrollbackLineAtIndex:index];
            }
            _scrollbackCount -= restore;
            memcpy(lines + restore, _lines, (size_t)_rows * sizeof(TXLine *));
            for (NSInteger i = restore + _rows; i < rows; i++) {
                lines[i] = TXLineCreate(columns);
            }
        }
        free(_lines);
        _lines = lines;
    }

    _rows = rows;
    _columns = columns;
    [self markAllDirty];
}

#pragma mark - Mutation

- (void)scrollUpFromRow:(NSInteger)top toRow:(NSInteger)bottom count:(NSInteger)count
         intoScrollback:(BOOL)intoScrollback {
    top = MAX(top, 0);
    bottom = MIN(bottom, _rows - 1);
    if (top > bottom || count <= 0) return;

    NSInteger height = bottom - top + 1;
    count = MIN(count, height);

    for (NSInteger i = 0; i < count; i++) {
        TXLine *line = _lines[top + i];
        if (intoScrollback) {
            [self pushLineToScrollback:line];
        } else {
            TXLineFree(line);
        }
    }
    memmove(_lines + top, _lines + top + count, (size_t)(height - count) * sizeof(TXLine *));
    for (NSInteger i = 0; i < count; i++) {
        _lines[bottom - count + 1 + i] = TXLineCreate(_columns);
    }
    _generation++;
    for (NSInteger row = top; row <= bottom; row++) {
        _lines[row]->generation = _generation;
    }
}

- (void)scrollDownFromRow:(NSInteger)top toRow:(NSInteger)bottom count:(NSInteger)count {
    top = MAX(top, 0);
    bottom = MIN(bottom, _rows - 1);
    if (top > bottom || count <= 0) return;

    NSInteger height = bottom - top + 1;
    count = MIN(count, height);

    for (NSInteger i = 0; i < count; i++) {
        TXLineFree(_lines[bottom - i]);
    }
    memmove(_lines + top + count, _lines + top, (size_t)(height - count) * sizeof(TXLine *));
    for (NSInteger i = 0; i < count; i++) {
        _lines[top + i] = TXLineCreate(_columns);
    }
    _generation++;
    for (NSInteger row = top; row <= bottom; row++) {
        _lines[row]->generation = _generation;
    }
}

- (void)clearRow:(NSInteger)row fromColumn:(NSInteger)from toColumn:(NSInteger)to
    withTemplate:(TXCell)templateCell {
    TXLine *line = [self lineAtRow:row];
    if (!line) return;
    from = MAX(from, 0);
    to = MIN(to, line->capacity - 1);
    for (NSInteger i = from; i <= to; i++) {
        line->cells[i] = templateCell;
    }
    [self touchLine:line];
}

- (void)insertBlankCharacters:(NSInteger)count atRow:(NSInteger)row column:(NSInteger)column
                 withTemplate:(TXCell)templateCell {
    TXLine *line = [self lineAtRow:row];
    if (!line || count <= 0 || column < 0 || column >= line->capacity) return;
    count = MIN(count, line->capacity - column);
    NSInteger move = line->capacity - column - count;
    if (move > 0) {
        memmove(line->cells + column + count, line->cells + column, (size_t)move * sizeof(TXCell));
    }
    for (NSInteger i = 0; i < count; i++) {
        line->cells[column + i] = templateCell;
    }
    [self touchLine:line];
}

- (void)deleteCharacters:(NSInteger)count atRow:(NSInteger)row column:(NSInteger)column
            withTemplate:(TXCell)templateCell {
    TXLine *line = [self lineAtRow:row];
    if (!line || count <= 0 || column < 0 || column >= line->capacity) return;
    count = MIN(count, line->capacity - column);
    NSInteger move = line->capacity - column - count;
    if (move > 0) {
        memmove(line->cells + column, line->cells + column + count, (size_t)move * sizeof(TXCell));
    }
    for (NSInteger i = 0; i < count; i++) {
        line->cells[line->capacity - count + i] = templateCell;
    }
    [self touchLine:line];
}

- (void)clearScrollback {
    for (NSInteger i = 0; i < _scrollbackCount; i++) {
        TXLineFree([self scrollbackLineAtIndex:i]);
    }
    _scrollbackHead = 0;
    _scrollbackCount = 0;
    _generation++;
}

#pragma mark - Text extraction

- (NSString *)appendLine:(TXLine *)line
              fromColumn:(NSInteger)from
                toColumn:(NSInteger)to
                trimming:(BOOL)trim {
    if (!line) return @"";
    from = MAX(from, 0);
    to = MIN(to, line->capacity - 1);
    if (trim) {
        while (to >= from) {
            TXCell cell = line->cells[to];
            if (cell.codepoint != ' ' && cell.codepoint != 0) break;
            to--;
        }
    }
    NSMutableString *text = [NSMutableString string];
    for (NSInteger i = from; i <= to; i++) {
        TXCell cell = line->cells[i];
        if (cell.flags & TXCellFlagWideTrailer) continue;
        uint32_t cp = cell.codepoint ?: ' ';
        if (cp < 0x10000) {
            [text appendFormat:@"%C", (unichar)cp];
        } else {
            cp -= 0x10000;
            unichar surrogates[2] = {
                (unichar)(0xD800 + (cp >> 10)),
                (unichar)(0xDC00 + (cp & 0x3FF)),
            };
            [text appendString:[NSString stringWithCharacters:surrogates length:2]];
        }
        NSString *marks = [self combiningMarksForCell:cell];
        if (marks) [text appendString:marks];
    }
    return text;
}

- (NSString *)stringForRow:(NSInteger)row {
    return [self appendLine:[self lineAtRow:row] fromColumn:0 toColumn:_columns - 1 trimming:YES];
}

- (NSString *)stringFromAbsoluteRow:(NSInteger)startRow column:(NSInteger)startColumn
                      toAbsoluteRow:(NSInteger)endRow column:(NSInteger)endColumn {
    if (endRow < startRow || (endRow == startRow && endColumn < startColumn)) {
        NSInteger tr = startRow, tc = startColumn;
        startRow = endRow; startColumn = endColumn;
        endRow = tr; endColumn = tc;
    }

    NSMutableArray<NSString *> *pieces = [NSMutableArray array];
    for (NSInteger row = startRow; row <= endRow; row++) {
        TXLine *line = row >= 0 ? [self lineAtRow:row]
                                : [self scrollbackLineAtIndex:_scrollbackCount + row];
        if (!line) continue;
        NSInteger from = (row == startRow) ? startColumn : 0;
        NSInteger to = (row == endRow) ? endColumn : line->capacity - 1;
        BOOL trim = (row != endRow);
        [pieces addObject:[self appendLine:line fromColumn:from toColumn:to trimming:trim]];
    }
    return [pieces componentsJoinedByString:@"\n"];
}

@end
