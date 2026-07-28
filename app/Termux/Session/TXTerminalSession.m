//
//  TXTerminalSession.m
//

#import "TXTerminalSession.h"

#import "TXBootstrap.h"

#import <UIKit/UIKit.h>

@interface TXTerminalSession () <TXPTYSessionDelegate, TXTerminalEmulatorDelegate>
@end

@implementation TXTerminalSession

- (instancetype)initWithRows:(NSInteger)rows columns:(NSInteger)columns {
    self = [super init];
    if (!self) return nil;

    _emulator = [[TXTerminalEmulator alloc] initWithRows:rows columns:columns];
    _emulator.delegate = self;

    _pty = [[TXPTYSession alloc] init];
    _pty.delegate = self;

    _title = @"shell";
    return self;
}

- (BOOL)isRunning {
    return self.pty.isRunning;
}

#pragma mark - Start

- (BOOL)startWithError:(NSError **)error {
    TXBootstrap *bootstrap = [TXBootstrap sharedBootstrap];
    if (![bootstrap prepareDirectoriesWithError:error]) return NO;

    NSString *shell = bootstrap.loginShellPath;

    if (self.command.count > 0) {
        self.pty.executablePath = self.command.firstObject;
        self.pty.arguments = self.command;
    } else {
        self.pty.executablePath = shell;
        // Leading '-' marks it as a login shell so profiles get sourced.
        self.pty.arguments = @[[@"-" stringByAppendingString:shell.lastPathComponent]];
    }

    self.pty.environment = bootstrap.sessionEnvironment;
    self.pty.workingDirectory = bootstrap.homePath;

    NSError *startError = nil;
    BOOL started = [self.pty startWithRows:self.emulator.rows
                                   columns:self.emulator.columns
                                     error:&startError];
    if (!started) {
        [self displayFailureBanner:startError];
        if (error) *error = startError;
        return NO;
    }

    if (!bootstrap.isInstalled) {
        [self displayWelcomeBanner];
    }
    return YES;
}

- (void)displayWelcomeBanner {
    NSString *banner =
        @"\r\n"
        @"\033[1;32m  Termux for iOS\033[0m\r\n"
        @"  \033[2mNo bootstrap installed yet -- running the built-in shell.\033[0m\r\n"
        @"  \033[2mTap the menu and choose \"Install bootstrap\" to get apt,\033[0m\r\n"
        @"  \033[2mbash, coreutils and the rest of the userland.\033[0m\r\n"
        @"\r\n";
    [self.emulator parseData:[banner dataUsingEncoding:NSUTF8StringEncoding]];
}

- (void)displayFailureBanner:(NSError *)error {
    NSString *banner = [NSString stringWithFormat:
        @"\r\n\033[1;31m  Could not start a shell\033[0m\r\n"
        @"  %@\r\n\r\n"
        @"  \033[2mThis usually means the app was installed without\033[0m\r\n"
        @"  \033[2mTrollStore, so the required entitlements are missing.\033[0m\r\n\r\n",
        error.localizedDescription ?: @"unknown error"];
    [self.emulator parseData:[banner dataUsingEncoding:NSUTF8StringEncoding]];
    if ([self.delegate respondsToSelector:@selector(sessionDidUpdateScreen:)]) {
        [self.delegate sessionDidUpdateScreen:self];
    }
}

#pragma mark - I/O

- (void)writeData:(NSData *)data {
    [self.pty writeData:data];
}

- (void)resizeToRows:(NSInteger)rows columns:(NSInteger)columns {
    if (rows == self.emulator.rows && columns == self.emulator.columns) return;
    [self.emulator resizeToRows:rows columns:columns];
    [self.pty resizeToRows:rows columns:columns];
}

- (void)terminate {
    [self.pty terminate];
}

- (void)displayMessage:(NSString *)message {
    [self.emulator parseData:[message dataUsingEncoding:NSUTF8StringEncoding]];
    if ([self.delegate respondsToSelector:@selector(sessionDidUpdateScreen:)]) {
        [self.delegate sessionDidUpdateScreen:self];
    }
}

#pragma mark - TXPTYSessionDelegate

- (void)session:(TXPTYSession *)session didReadData:(NSData *)data {
    [self.emulator parseData:data];
}

- (void)session:(TXPTYSession *)session didTerminateWithStatus:(int)status reason:(NSString *)reason {
    NSString *message = [NSString stringWithFormat:
        @"\r\n\033[2m[process %@]\033[0m\r\n", reason];
    [self.emulator parseData:[message dataUsingEncoding:NSUTF8StringEncoding]];

    if ([self.delegate respondsToSelector:@selector(session:didFinishWithReason:)]) {
        [self.delegate session:self didFinishWithReason:reason];
    }
}

#pragma mark - TXTerminalEmulatorDelegate

- (void)terminal:(TXTerminalEmulator *)terminal wantsToWriteData:(NSData *)data {
    [self.pty writeData:data];
}

- (void)terminalDidUpdateScreen:(TXTerminalEmulator *)terminal {
    if ([self.delegate respondsToSelector:@selector(sessionDidUpdateScreen:)]) {
        [self.delegate sessionDidUpdateScreen:self];
    }
}

- (void)terminal:(TXTerminalEmulator *)terminal didSetTitle:(NSString *)title {
    _title = title.length > 0 ? title : @"shell";
    if ([self.delegate respondsToSelector:@selector(sessionDidChangeTitle:)]) {
        [self.delegate sessionDidChangeTitle:self];
    }
}

- (void)terminalDidRing:(TXTerminalEmulator *)terminal {
    // A short haptic tap is far less annoying than a sound on a phone.
    UIImpactFeedbackGenerator *generator =
        [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [generator impactOccurred];
}

- (void)terminal:(TXTerminalEmulator *)terminal didSetClipboard:(NSString *)text {
    [UIPasteboard generalPasteboard].string = text;
}

@end
