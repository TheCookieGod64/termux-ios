//
//  TXTerminalEmulator.h
//  A VT100/VT220/xterm-compatible escape sequence interpreter driving a
//  TXTerminalBuffer.  Feed it bytes from the pty; it feeds you back the
//  responses the program expects (DA, CPR, ...) via the delegate.
//

#import <Foundation/Foundation.h>
#import "TXTerminalBuffer.h"

NS_ASSUME_NONNULL_BEGIN

@class TXTerminalEmulator;

/// Mouse reporting modes (DECSET 9/1000/1002/1003).
typedef NS_ENUM(NSInteger, TXMouseMode) {
    TXMouseModeNone = 0,
    TXMouseModeX10,
    TXMouseModeNormal,
    TXMouseModeButtonEvent,
    TXMouseModeAnyEvent,
};

@protocol TXTerminalEmulatorDelegate <NSObject>
@optional
/// The emulator wants to send bytes back to the pty (query replies, etc).
- (void)terminal:(TXTerminalEmulator *)terminal wantsToWriteData:(NSData *)data;
/// OSC 0/2 window title.
- (void)terminal:(TXTerminalEmulator *)terminal didSetTitle:(NSString *)title;
/// BEL.
- (void)terminalDidRing:(TXTerminalEmulator *)terminal;
/// OSC 52 clipboard write.
- (void)terminal:(TXTerminalEmulator *)terminal didSetClipboard:(NSString *)text;
/// Buffer contents changed; the view should schedule a redraw.
- (void)terminalDidUpdateScreen:(TXTerminalEmulator *)terminal;
@end

@interface TXTerminalEmulator : NSObject

@property (nonatomic, weak) id<TXTerminalEmulatorDelegate> delegate;

/// The buffer currently being drawn (normal or alternate screen).
@property (nonatomic, readonly) TXTerminalBuffer *buffer;

@property (nonatomic, readonly) NSInteger rows;
@property (nonatomic, readonly) NSInteger columns;

@property (nonatomic, readonly) NSInteger cursorRow;
@property (nonatomic, readonly) NSInteger cursorColumn;
@property (nonatomic, readonly) BOOL cursorVisible;

/// DECCKM: cursor keys send SS3 instead of CSI.
@property (nonatomic, readonly) BOOL applicationCursorKeys;
/// DECKPAM: keypad sends application sequences.
@property (nonatomic, readonly) BOOL applicationKeypad;
/// Bracketed paste (DECSET 2004).
@property (nonatomic, readonly) BOOL bracketedPaste;
/// True while the alternate screen is active.
@property (nonatomic, readonly) BOOL usingAlternateScreen;

@property (nonatomic, readonly) TXMouseMode mouseMode;
/// SGR (1006) mouse encoding rather than the legacy X10 byte encoding.
@property (nonatomic, readonly) BOOL mouseSGREncoding;

@property (nonatomic, readonly, copy, nullable) NSString *title;

- (instancetype)initWithRows:(NSInteger)rows columns:(NSInteger)columns;

/// Feed output from the pty.  Safe to call with partial UTF-8 sequences.
- (void)parseData:(NSData *)data;
- (void)parseBytes:(const uint8_t *)bytes length:(NSUInteger)length;

- (void)resizeToRows:(NSInteger)rows columns:(NSInteger)columns;

/// Full reset (RIS).
- (void)reset;

@end

NS_ASSUME_NONNULL_END
