//
//  TXTerminalSession.h
//  Ties a pty, an emulator and a title together into one shell session.
//

#import <Foundation/Foundation.h>

#import "TXPTYSession.h"
#import "TXTerminalEmulator.h"

NS_ASSUME_NONNULL_BEGIN

@class TXTerminalSession;

@protocol TXTerminalSessionDelegate <NSObject>
@optional
- (void)sessionDidUpdateScreen:(TXTerminalSession *)session;
- (void)sessionDidChangeTitle:(TXTerminalSession *)session;
- (void)session:(TXTerminalSession *)session didFinishWithReason:(NSString *)reason;
- (void)session:(TXTerminalSession *)session didFailWithError:(NSError *)error;
@end

@interface TXTerminalSession : NSObject

@property (nonatomic, weak) id<TXTerminalSessionDelegate> delegate;

@property (nonatomic, readonly) TXTerminalEmulator *emulator;
@property (nonatomic, readonly) TXPTYSession *pty;

/// Shown in the session switcher; follows the shell's OSC title when set.
@property (nonatomic, readonly, copy) NSString *title;
@property (nonatomic, readonly) BOOL isRunning;

/// Command to run instead of the login shell (optional).
@property (nonatomic, copy, nullable) NSArray<NSString *> *command;

- (instancetype)initWithRows:(NSInteger)rows columns:(NSInteger)columns;

- (BOOL)startWithError:(NSError **)error;
- (void)writeData:(NSData *)data;
- (void)resizeToRows:(NSInteger)rows columns:(NSInteger)columns;
- (void)terminate;

/// Appends text to the screen without sending it to the shell -- used for
/// status messages such as "process exited".
- (void)displayMessage:(NSString *)message;

@end

NS_ASSUME_NONNULL_END
