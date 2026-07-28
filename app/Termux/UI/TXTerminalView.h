//
//  TXTerminalView.h
//  Draws a TXTerminalEmulator's buffer and turns touches/keystrokes into
//  bytes for the pty.
//

#import <UIKit/UIKit.h>

#import "TXColorScheme.h"
#import "TXTerminalEmulator.h"

NS_ASSUME_NONNULL_BEGIN

@class TXTerminalView;

@protocol TXTerminalViewDelegate <NSObject>
@optional
/// User input that should reach the pty.
- (void)terminalView:(TXTerminalView *)view didProduceInput:(NSData *)data;
/// The view's size changed, so the pty needs a new winsize.
- (void)terminalView:(TXTerminalView *)view didResizeToRows:(NSInteger)rows
             columns:(NSInteger)columns;
@end

/// Supplies the sticky modifier state held by the extra-key row, so that
/// tapping CTRL there and then a letter on the software keyboard produces a
/// control character.
@protocol TXTerminalViewModifierSource <NSObject>
- (BOOL)terminalViewControlModifierActive:(TXTerminalView *)view;
- (BOOL)terminalViewAltModifierActive:(TXTerminalView *)view;
/// Called after a key consumed the modifiers, so one-shot state can clear.
- (void)terminalViewDidConsumeModifiers:(TXTerminalView *)view;
@end

@interface TXTerminalView : UIView <UIKeyInput, UITextInputTraits>

@property (nonatomic, weak) id<TXTerminalViewDelegate> delegate;
/// Optional source of sticky CTRL/ALT state from the extra-key row.
@property (nonatomic, weak) id<TXTerminalViewModifierSource> modifierSource;
@property (nonatomic, strong) TXTerminalEmulator *emulator;
@property (nonatomic, strong) TXColorScheme *colorScheme;

@property (nonatomic, strong) UIFont *font;
/// Extra spacing between rows, as a multiple of the font's line height.
@property (nonatomic) CGFloat lineSpacing;

/// How many lines the user has scrolled back (0 == live view).
@property (nonatomic, readonly) NSInteger scrollOffset;

/// Grid geometry derived from the current font and bounds.
@property (nonatomic, readonly) NSInteger rows;
@property (nonatomic, readonly) NSInteger columns;
@property (nonatomic, readonly) CGSize cellSize;

/// Text currently selected by the user, or nil.
@property (nonatomic, readonly, copy, nullable) NSString *selectedText;

/// Schedules a redraw, coalesced to the display refresh rate.
- (void)setNeedsScreenUpdate;

/// Recomputes rows/columns and notifies the delegate.
- (void)updateGeometry;

- (void)scrollToBottom;
- (void)scrollByLines:(NSInteger)lines;

- (void)clearSelection;
- (void)selectAll;

/// Sends a key that has no character representation (arrows, F-keys, ...).
- (void)sendSpecialKey:(NSString *)keyName;
/// Sends text with the modifier state applied (ctrl/alt).
- (void)sendText:(NSString *)text control:(BOOL)control alt:(BOOL)alt;
/// Pastes text, honouring bracketed-paste mode.
- (void)pasteText:(NSString *)text;

@end

NS_ASSUME_NONNULL_END
