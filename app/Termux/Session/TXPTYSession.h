//
//  TXPTYSession.h
//  Owns a pseudo-terminal and the child process attached to it.
//
//  On iOS a normal sandboxed app cannot spawn processes.  With TrollStore we
//  ship the app with `platform-application` + `com.apple.private.security.no-sandbox`
//  (see Resources/entitlements.plist) which makes posix_spawn work like it does
//  on macOS.  `fork()` is unreliable on iOS, so we always spawn.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Errors raised by this class itself (spawn failures use NSPOSIXErrorDomain).
extern NSString *const TXPTYSessionErrorDomain;

@class TXPTYSession;

@protocol TXPTYSessionDelegate <NSObject>
@optional
/// Bytes read from the pty master.  Delivered on the main queue.
- (void)session:(TXPTYSession *)session didReadData:(NSData *)data;
/// The child exited; `reason` is a human readable summary.
- (void)session:(TXPTYSession *)session didTerminateWithStatus:(int)status reason:(NSString *)reason;
@end

@interface TXPTYSession : NSObject

@property (nonatomic, weak) id<TXPTYSessionDelegate> delegate;

/// Executable to run, e.g. <bootstrap>/bin/login or /bin/sh.
@property (nonatomic, copy) NSString *executablePath;
/// argv (argv[0] included).  Prefix argv[0] with '-' for a login shell.
@property (nonatomic, copy) NSArray<NSString *> *arguments;
/// Additional environment entries; merged over the computed defaults.
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *environment;
/// Working directory for the child.
@property (nonatomic, copy, nullable) NSString *workingDirectory;

@property (nonatomic, readonly) pid_t processIdentifier;
@property (nonatomic, readonly) BOOL isRunning;
/// File descriptor of the pty master (-1 when not running).
@property (nonatomic, readonly) int masterFileDescriptor;
/// Name of the slave device, e.g. /dev/ttys003.
@property (nonatomic, readonly, copy, nullable) NSString *ttyName;

- (BOOL)startWithRows:(NSInteger)rows columns:(NSInteger)columns error:(NSError **)error;

- (void)writeData:(NSData *)data;
- (void)writeString:(NSString *)string;

- (void)resizeToRows:(NSInteger)rows columns:(NSInteger)columns;

/// Sends a signal to the child's process group (e.g. SIGINT from Ctrl-C key).
- (void)sendSignal:(int)signal;

- (void)terminate;

@end

NS_ASSUME_NONNULL_END
