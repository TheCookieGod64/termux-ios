//
//  terminal_tests.m
//  Host-side tests for the escape sequence parser and screen buffer.
//
//  These compile against GNUstep/libobjc2 on Linux (or Foundation on a Mac) so
//  the terminal logic can be exercised without a device.  See
//  tests/run-tests.sh -- when no Objective-C runtime is available the script
//  falls back to a pure-python re-implementation check.
//

#import <Foundation/Foundation.h>

#import "TXTerminalBuffer.h"
#import "TXTerminalEmulator.h"

static int gFailures = 0;
static int gChecks = 0;

static void Check(BOOL condition, NSString *description) {
    gChecks++;
    if (condition) return;
    gFailures++;
    fprintf(stderr, "FAIL: %s\n", description.UTF8String);
}

static void CheckEqualString(NSString *actual, NSString *expected, NSString *what) {
    gChecks++;
    if ([actual isEqualToString:expected]) return;
    gFailures++;
    fprintf(stderr, "FAIL: %s\n  expected: \"%s\"\n  actual:   \"%s\"\n",
            what.UTF8String, expected.UTF8String, actual.UTF8String);
}

static void CheckEqualInteger(NSInteger actual, NSInteger expected, NSString *what) {
    gChecks++;
    if (actual == expected) return;
    gFailures++;
    fprintf(stderr, "FAIL: %s (expected %ld, got %ld)\n",
            what.UTF8String, (long)expected, (long)actual);
}

static void Feed(TXTerminalEmulator *terminal, NSString *text) {
    [terminal parseData:[text dataUsingEncoding:NSUTF8StringEncoding]];
}

/// Captures whatever the emulator wants to write back to the pty.
@interface TXResponseCollector : NSObject <TXTerminalEmulatorDelegate>
@property (nonatomic, readonly) NSMutableString *response;
@end

@implementation TXResponseCollector

- (instancetype)init {
    self = [super init];
    if (self) _response = [NSMutableString string];
    return self;
}

- (void)terminal:(TXTerminalEmulator *)terminal wantsToWriteData:(NSData *)data {
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (text) [_response appendString:text];
}

@end

#pragma mark - Tests

static void TestPlainText(void) {
    TXTerminalEmulator *terminal = [[TXTerminalEmulator alloc] initWithRows:5 columns:20];
    Feed(terminal, @"hello");
    CheckEqualString([terminal.buffer stringForRow:0], @"hello", @"plain text lands on row 0");
    CheckEqualInteger(terminal.cursorColumn, 5, @"cursor advances");
}

static void TestNewlineAndCarriageReturn(void) {
    TXTerminalEmulator *terminal = [[TXTerminalEmulator alloc] initWithRows:5 columns:20];
    Feed(terminal, @"one\r\ntwo");
    CheckEqualString([terminal.buffer stringForRow:0], @"one", @"first line");
    CheckEqualString([terminal.buffer stringForRow:1], @"two", @"second line");
    CheckEqualInteger(terminal.cursorRow, 1, @"cursor moved down");
}

static void TestCursorPositioning(void) {
    TXTerminalEmulator *terminal = [[TXTerminalEmulator alloc] initWithRows:10 columns:40];
    Feed(terminal, @"\033[5;10H");
    CheckEqualInteger(terminal.cursorRow, 4, @"CUP row is 1-based");
    CheckEqualInteger(terminal.cursorColumn, 9, @"CUP column is 1-based");

    Feed(terminal, @"\033[2A");
    CheckEqualInteger(terminal.cursorRow, 2, @"CUU moves up");
    Feed(terminal, @"\033[3C");
    CheckEqualInteger(terminal.cursorColumn, 12, @"CUF moves right");
    Feed(terminal, @"\033[H");
    CheckEqualInteger(terminal.cursorRow, 0, @"CUP with no args homes");
    CheckEqualInteger(terminal.cursorColumn, 0, @"CUP with no args homes column");
}

static void TestEraseInLine(void) {
    TXTerminalEmulator *terminal = [[TXTerminalEmulator alloc] initWithRows:5 columns:20];
    Feed(terminal, @"abcdefgh");
    Feed(terminal, @"\033[5G");          // column 5 (0-based 4)
    Feed(terminal, @"\033[K");           // erase to end of line
    CheckEqualString([terminal.buffer stringForRow:0], @"abcd", @"EL 0 clears to EOL");
}

static void TestEraseInDisplay(void) {
    TXTerminalEmulator *terminal = [[TXTerminalEmulator alloc] initWithRows:4 columns:10];
    Feed(terminal, @"aaa\r\nbbb\r\nccc");
    Feed(terminal, @"\033[2J");
    CheckEqualString([terminal.buffer stringForRow:0], @"", @"ED 2 clears row 0");
    CheckEqualString([terminal.buffer stringForRow:1], @"", @"ED 2 clears row 1");
}

static void TestScrolling(void) {
    TXTerminalEmulator *terminal = [[TXTerminalEmulator alloc] initWithRows:3 columns:10];
    Feed(terminal, @"1\r\n2\r\n3\r\n4");
    CheckEqualString([terminal.buffer stringForRow:0], @"2", @"screen scrolled up");
    CheckEqualString([terminal.buffer stringForRow:2], @"4", @"newest line at bottom");
    CheckEqualInteger(terminal.buffer.scrollbackLines, 1, @"one line in scrollback");
    CheckEqualString([terminal.buffer stringFromAbsoluteRow:-1 column:0
                                              toAbsoluteRow:-1 column:0],
                     @"1", @"scrollback keeps the first line");
}

static void TestScrollRegion(void) {
    TXTerminalEmulator *terminal = [[TXTerminalEmulator alloc] initWithRows:5 columns:10];
    Feed(terminal, @"1\r\n2\r\n3\r\n4\r\n5");
    Feed(terminal, @"\033[2;4r");        // region rows 2..4
    Feed(terminal, @"\033[4;1H");        // bottom of region
    Feed(terminal, @"\n");               // should scroll only the region
    CheckEqualString([terminal.buffer stringForRow:0], @"1", @"row outside region untouched");
    CheckEqualString([terminal.buffer stringForRow:4], @"5", @"last row untouched");
}

static void TestSGRColors(void) {
    TXTerminalEmulator *terminal = [[TXTerminalEmulator alloc] initWithRows:3 columns:20];
    Feed(terminal, @"\033[31mR\033[0mN");

    TXCell red = [terminal.buffer cellAtRow:0 column:0];
    Check(red.foreground.value == 1 && !red.foreground.isTrueColor, @"SGR 31 sets red");

    TXCell normal = [terminal.buffer cellAtRow:0 column:1];
    Check(normal.foreground.value == TXColorDefaultIndex, @"SGR 0 resets colour");
}

static void TestTrueColor(void) {
    TXTerminalEmulator *terminal = [[TXTerminalEmulator alloc] initWithRows:3 columns:20];
    Feed(terminal, @"\033[38;2;255;128;0mX");
    TXCell cell = [terminal.buffer cellAtRow:0 column:0];
    Check(cell.foreground.isTrueColor, @"38;2 produces truecolour");
    Check(cell.foreground.value == 0xFF8000, @"truecolour RGB is packed correctly");
}

static void TestTrueColorSubParameters(void) {
    TXTerminalEmulator *terminal = [[TXTerminalEmulator alloc] initWithRows:3 columns:20];
    Feed(terminal, @"\033[38:2::10:20:30mX");
    TXCell cell = [terminal.buffer cellAtRow:0 column:0];
    Check(cell.foreground.isTrueColor, @"38:2 colon form produces truecolour");
    Check(cell.foreground.value == ((10 << 16) | (20 << 8) | 30),
          @"colon-form RGB is packed correctly");
}

static void TestSGRAttributes(void) {
    TXTerminalEmulator *terminal = [[TXTerminalEmulator alloc] initWithRows:3 columns:20];
    Feed(terminal, @"\033[1;4mB\033[22mC");
    TXCell bold = [terminal.buffer cellAtRow:0 column:0];
    Check((bold.flags & TXCellFlagBold) != 0, @"SGR 1 sets bold");
    Check((bold.flags & TXCellFlagUnderline) != 0, @"SGR 4 sets underline");

    TXCell after = [terminal.buffer cellAtRow:0 column:1];
    Check((after.flags & TXCellFlagBold) == 0, @"SGR 22 clears bold");
    Check((after.flags & TXCellFlagUnderline) != 0, @"SGR 22 keeps underline");
}

static void TestUTF8(void) {
    TXTerminalEmulator *terminal = [[TXTerminalEmulator alloc] initWithRows:3 columns:20];
    Feed(terminal, @"héllo → ✓");
    CheckEqualString([terminal.buffer stringForRow:0], @"héllo → ✓", @"UTF-8 round trips");
}

static void TestSplitUTF8Sequence(void) {
    TXTerminalEmulator *terminal = [[TXTerminalEmulator alloc] initWithRows:3 columns:20];
    // "é" is C3 A9 -- deliver the bytes in two separate reads.
    uint8_t first[] = {0xC3};
    uint8_t second[] = {0xA9};
    [terminal parseBytes:first length:1];
    [terminal parseBytes:second length:1];
    CheckEqualString([terminal.buffer stringForRow:0], @"é", @"UTF-8 split across reads");
}

static void TestWideCharacters(void) {
    TXTerminalEmulator *terminal = [[TXTerminalEmulator alloc] initWithRows:3 columns:20];
    Feed(terminal, @"日本");
    CheckEqualInteger(terminal.cursorColumn, 4, @"CJK glyphs occupy two columns");
    TXCell trailer = [terminal.buffer cellAtRow:0 column:1];
    Check((trailer.flags & TXCellFlagWideTrailer) != 0, @"wide glyph marks its trailer");
    CheckEqualString([terminal.buffer stringForRow:0], @"日本", @"wide text extracts cleanly");
}

static void TestLineWrap(void) {
    TXTerminalEmulator *terminal = [[TXTerminalEmulator alloc] initWithRows:4 columns:5];
    Feed(terminal, @"abcdefg");
    CheckEqualString([terminal.buffer stringForRow:0], @"abcde", @"first line filled");
    CheckEqualString([terminal.buffer stringForRow:1], @"fg", @"wrapped onto second line");
}

static void TestDeferredWrap(void) {
    TXTerminalEmulator *terminal = [[TXTerminalEmulator alloc] initWithRows:4 columns:5];
    Feed(terminal, @"abcde");
    // The cursor stays on the last column until another glyph arrives.
    CheckEqualInteger(terminal.cursorRow, 0, @"no premature wrap");
    Feed(terminal, @"f");
    CheckEqualInteger(terminal.cursorRow, 1, @"wraps on the next glyph");
}

static void TestInsertDeleteCharacters(void) {
    TXTerminalEmulator *terminal = [[TXTerminalEmulator alloc] initWithRows:3 columns:10];
    Feed(terminal, @"abcdef");
    Feed(terminal, @"\033[3G");          // column 3 -> 0-based 2
    Feed(terminal, @"\033[2@");          // insert two blanks
    CheckEqualString([terminal.buffer stringForRow:0], @"ab  cdef", @"ICH shifts right");

    Feed(terminal, @"\033[2P");          // delete two
    CheckEqualString([terminal.buffer stringForRow:0], @"abcdef", @"DCH shifts back");
}

static void TestInsertDeleteLines(void) {
    TXTerminalEmulator *terminal = [[TXTerminalEmulator alloc] initWithRows:4 columns:10];
    Feed(terminal, @"a\r\nb\r\nc");
    Feed(terminal, @"\033[2;1H\033[L");  // insert a line at row 2
    CheckEqualString([terminal.buffer stringForRow:0], @"a", @"IL keeps row above");
    CheckEqualString([terminal.buffer stringForRow:1], @"", @"IL blanks the new row");
    CheckEqualString([terminal.buffer stringForRow:2], @"b", @"IL pushes rows down");
}

static void TestAlternateScreen(void) {
    TXTerminalEmulator *terminal = [[TXTerminalEmulator alloc] initWithRows:4 columns:10];
    Feed(terminal, @"main");
    Feed(terminal, @"\033[?1049h");
    Check(terminal.usingAlternateScreen, @"1049 switches to the alternate screen");
    CheckEqualString([terminal.buffer stringForRow:0], @"", @"alternate screen starts blank");

    Feed(terminal, @"alt");
    Feed(terminal, @"\033[?1049l");
    Check(!terminal.usingAlternateScreen, @"1049l switches back");
    CheckEqualString([terminal.buffer stringForRow:0], @"main", @"main screen is restored");
}

static void TestSaveRestoreCursor(void) {
    TXTerminalEmulator *terminal = [[TXTerminalEmulator alloc] initWithRows:6 columns:20];
    Feed(terminal, @"\033[3;7H\0337");    // move, DECSC
    Feed(terminal, @"\033[1;1H");
    Feed(terminal, @"\0338");             // DECRC
    CheckEqualInteger(terminal.cursorRow, 2, @"DECRC restores row");
    CheckEqualInteger(terminal.cursorColumn, 6, @"DECRC restores column");
}

static void TestModes(void) {
    TXTerminalEmulator *terminal = [[TXTerminalEmulator alloc] initWithRows:4 columns:10];
    Feed(terminal, @"\033[?1h");
    Check(terminal.applicationCursorKeys, @"DECCKM on");
    Feed(terminal, @"\033[?1l");
    Check(!terminal.applicationCursorKeys, @"DECCKM off");

    Feed(terminal, @"\033[?25l");
    Check(!terminal.cursorVisible, @"DECTCEM hides the cursor");
    Feed(terminal, @"\033[?25h");
    Check(terminal.cursorVisible, @"DECTCEM shows the cursor");

    Feed(terminal, @"\033[?2004h");
    Check(terminal.bracketedPaste, @"bracketed paste on");
}

static void TestMouseModes(void) {
    TXTerminalEmulator *terminal = [[TXTerminalEmulator alloc] initWithRows:4 columns:10];
    Feed(terminal, @"\033[?1000h");
    Check(terminal.mouseMode == TXMouseModeNormal, @"1000 enables normal mouse tracking");
    Feed(terminal, @"\033[?1006h");
    Check(terminal.mouseSGREncoding, @"1006 enables SGR encoding");
    Feed(terminal, @"\033[?1000l");
    Check(terminal.mouseMode == TXMouseModeNone, @"1000l disables tracking");
}

static void TestTabs(void) {
    TXTerminalEmulator *terminal = [[TXTerminalEmulator alloc] initWithRows:3 columns:40];
    Feed(terminal, @"a\tb");
    CheckEqualInteger(terminal.cursorColumn, 9, @"tab stops every 8 columns");
    CheckEqualString([terminal.buffer stringForRow:0], @"a       b", @"tab pads with spaces");
}

static void TestOSCTitle(void) {
    TXTerminalEmulator *terminal = [[TXTerminalEmulator alloc] initWithRows:3 columns:20];
    Feed(terminal, @"\033]0;my title\007");
    CheckEqualString(terminal.title ?: @"", @"my title", @"OSC 0 sets the title");

    Feed(terminal, @"\033]2;other\033\\");   // ST terminated
    CheckEqualString(terminal.title ?: @"", @"other", @"OSC 2 with ST terminator");
}

static void TestDeviceStatusReport(void) {
    TXTerminalEmulator *terminal = [[TXTerminalEmulator alloc] initWithRows:10 columns:40];
    TXResponseCollector *collector = [[TXResponseCollector alloc] init];
    terminal.delegate = collector;

    Feed(terminal, @"\033[4;8H\033[6n");
    CheckEqualString(collector.response, @"\033[4;8R", @"CPR reports the cursor position");

    [collector.response setString:@""];
    Feed(terminal, @"\033[c");
    Check([collector.response hasPrefix:@"\033[?6"], @"DA1 identifies as a VT220+ terminal");
}

static void TestResize(void) {
    TXTerminalEmulator *terminal = [[TXTerminalEmulator alloc] initWithRows:5 columns:20];
    Feed(terminal, @"hello");
    [terminal resizeToRows:10 columns:40];
    CheckEqualInteger(terminal.rows, 10, @"rows updated");
    CheckEqualInteger(terminal.columns, 40, @"columns updated");
    CheckEqualString([terminal.buffer stringForRow:0], @"hello", @"content survives resize");
}

static void TestControlSequenceInterruption(void) {
    TXTerminalEmulator *terminal = [[TXTerminalEmulator alloc] initWithRows:4 columns:20];
    // CAN aborts a partially received sequence.
    Feed(terminal, @"\033[3");
    Feed(terminal, @"\030");
    Feed(terminal, @"X");
    CheckEqualString([terminal.buffer stringForRow:0], @"X", @"CAN aborts the sequence");
}

static void TestUnknownSequencesAreIgnored(void) {
    TXTerminalEmulator *terminal = [[TXTerminalEmulator alloc] initWithRows:4 columns:20];
    Feed(terminal, @"\033[999;999;999zok");
    CheckEqualString([terminal.buffer stringForRow:0], @"ok",
                     @"unknown final byte does not corrupt output");
}

static void TestDECALN(void) {
    TXTerminalEmulator *terminal = [[TXTerminalEmulator alloc] initWithRows:3 columns:5];
    Feed(terminal, @"\033#8");
    CheckEqualString([terminal.buffer stringForRow:1], @"EEEEE", @"DECALN fills with E");
}

static void TestBufferScrollbackLimit(void) {
    TXTerminalBuffer *buffer = [[TXTerminalBuffer alloc] initWithRows:2 columns:10];
    buffer.maxScrollbackLines = 3;
    for (int i = 0; i < 20; i++) {
        [buffer scrollUpFromRow:0 toRow:1 count:1 intoScrollback:YES];
    }
    CheckEqualInteger(buffer.scrollbackLines, 3, @"scrollback respects its limit");
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        TestPlainText();
        TestNewlineAndCarriageReturn();
        TestCursorPositioning();
        TestEraseInLine();
        TestEraseInDisplay();
        TestScrolling();
        TestScrollRegion();
        TestSGRColors();
        TestTrueColor();
        TestTrueColorSubParameters();
        TestSGRAttributes();
        TestUTF8();
        TestSplitUTF8Sequence();
        TestWideCharacters();
        TestLineWrap();
        TestDeferredWrap();
        TestInsertDeleteCharacters();
        TestInsertDeleteLines();
        TestAlternateScreen();
        TestSaveRestoreCursor();
        TestModes();
        TestMouseModes();
        TestTabs();
        TestOSCTitle();
        TestDeviceStatusReport();
        TestResize();
        TestControlSequenceInterruption();
        TestUnknownSequencesAreIgnored();
        TestDECALN();
        TestBufferScrollbackLimit();

        printf("\n%d checks, %d failures\n", gChecks, gFailures);
        return gFailures == 0 ? 0 : 1;
    }
}
