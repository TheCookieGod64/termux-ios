//
//  TXKeyboardAccessoryView.h
//  The extra key row above the software keyboard: ESC, CTRL, ALT, TAB, arrows,
//  and the punctuation an iOS keyboard buries three taps deep.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class TXKeyboardAccessoryView;

@protocol TXKeyboardAccessoryViewDelegate <NSObject>
/// A named special key was tapped ("escape", "up", "f5", ...).
- (void)accessoryView:(TXKeyboardAccessoryView *)view didTapSpecialKey:(NSString *)keyName;
/// A literal character was tapped, with the sticky modifiers applied.
- (void)accessoryView:(TXKeyboardAccessoryView *)view
          didTapText:(NSString *)text
             control:(BOOL)control
                 alt:(BOOL)alt;
/// Sticky modifier state changed, so the terminal can reflect it.
- (void)accessoryViewDidChangeModifiers:(TXKeyboardAccessoryView *)view;
@end

@interface TXKeyboardAccessoryView : UIView

@property (nonatomic, weak) id<TXKeyboardAccessoryViewDelegate> delegate;

/// Sticky modifiers: tapped once they apply to the next key, tapped twice they
/// lock until tapped again.
@property (nonatomic, readonly) BOOL controlActive;
@property (nonatomic, readonly) BOOL altActive;

/// Clears one-shot modifiers after a key has consumed them.
- (void)consumeModifiers;

@end

NS_ASSUME_NONNULL_END
