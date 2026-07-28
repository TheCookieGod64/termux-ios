//
//  TXPTYSession.m
//

#import "TXPTYSession.h"

#import <dlfcn.h>
#import <errno.h>
#import <fcntl.h>
#import <signal.h>
#import <spawn.h>
#import <sys/ioctl.h>
#import <sys/stat.h>
#import <sys/wait.h>
#import <termios.h>
#import <unistd.h>
#import <util.h>

extern char **environ;

/// posix_spawn attribute that makes the child the leader of a new session, so
/// the pty becomes its controlling terminal.  Declared here because the iOS
/// SDK headers hide it.
#ifndef POSIX_SPAWN_SETSID
#define POSIX_SPAWN_SETSID 0x0400
#endif

NSString *const TXPTYSessionErrorDomain = @"TXPTYSessionErrorDomain";

/// `posix_spawn_file_actions_addchdir_np` exists in libSystem on iOS but is
/// marked unavailable in the SDK headers, so we bind it at runtime and fall
/// back to a `cd &&` wrapper when it is genuinely missing.
typedef int (*TXAddChdirFunction)(posix_spawn_file_actions_t *, const char *);

static TXAddChdirFunction TXResolveAddChdir(void) {
    static TXAddChdirFunction function;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        function = (TXAddChdirFunction)dlsym(RTLD_DEFAULT,
                                             "posix_spawn_file_actions_addchdir_np");
    });
    return function;
}

@implementation TXPTYSession {
    int _master;
    pid_t _pid;
    dispatch_source_t _readSource;
    dispatch_source_t _processSource;
    dispatch_queue_t _ioQueue;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _master = -1;
    _pid = -1;
    _ioQueue = dispatch_queue_create("dev.termux.ios.pty", DISPATCH_QUEUE_SERIAL);
    _arguments = @[];
    _environment = @{};
    return self;
}

- (void)dealloc {
    [self cleanup];
}

- (int)masterFileDescriptor { return _master; }
- (pid_t)processIdentifier { return _pid; }
- (BOOL)isRunning { return _pid > 0; }

#pragma mark - Environment

- (NSArray<NSString *> *)buildEnvironment {
    NSMutableDictionary<NSString *, NSString *> *env = [NSMutableDictionary dictionary];

    // Sensible defaults; the caller (TXTerminalSession) supplies PREFIX/HOME.
    env[@"TERM"] = @"xterm-256color";
    env[@"COLORTERM"] = @"truecolor";
    env[@"LANG"] = @"en_US.UTF-8";
    env[@"LC_ALL"] = @"en_US.UTF-8";
    env[@"TERM_PROGRAM"] = @"Termux-iOS";

    [env addEntriesFromDictionary:self.environment];

    NSMutableArray<NSString *> *entries = [NSMutableArray array];
    [env enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        [entries addObject:[NSString stringWithFormat:@"%@=%@", key, value]];
    }];
    return entries;
}

#pragma mark - Start

- (BOOL)startWithRows:(NSInteger)rows columns:(NSInteger)columns error:(NSError **)error {
    if (self.isRunning) return YES;

    if (self.executablePath.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:TXPTYSessionErrorDomain code:EINVAL
                                     userInfo:@{NSLocalizedDescriptionKey: @"No executable set"}];
        }
        return NO;
    }

    struct winsize size = {
        .ws_row = (unsigned short)MAX(rows, 1),
        .ws_col = (unsigned short)MAX(columns, 1),
        .ws_xpixel = 0,
        .ws_ypixel = 0,
    };

    struct termios settings;
    memset(&settings, 0, sizeof(settings));
    settings.c_iflag = ICRNL | IXON | IXANY | IMAXBEL | BRKINT | IUTF8;
    settings.c_oflag = OPOST | ONLCR;
    settings.c_cflag = CREAD | CS8 | HUPCL;
    settings.c_lflag = ICANON | ISIG | IEXTEN | ECHO | ECHOE | ECHOK | ECHOKE | ECHOCTL;
    settings.c_cc[VEOF] = 4;        // ^D
    settings.c_cc[VINTR] = 3;       // ^C
    settings.c_cc[VQUIT] = 28;      // ctrl-backslash
    settings.c_cc[VERASE] = 127;    // DEL
    settings.c_cc[VKILL] = 21;      // ^U
    settings.c_cc[VSUSP] = 26;      // ^Z
    settings.c_cc[VSTART] = 17;     // ^Q
    settings.c_cc[VSTOP] = 19;      // ^S
    settings.c_cc[VWERASE] = 23;    // ^W
    settings.c_cc[VREPRINT] = 18;   // ^R
    settings.c_cc[VLNEXT] = 22;     // ^V
    settings.c_cc[VDISCARD] = 15;   // ^O
    settings.c_cc[VMIN] = 1;
    settings.c_cc[VTIME] = 0;
    cfsetispeed(&settings, B38400);
    cfsetospeed(&settings, B38400);

    int master = -1;
    int slave = -1;
    char slaveName[PATH_MAX] = {0};
    if (openpty(&master, &slave, slaveName, &settings, &size) < 0) {
        if (error) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno
                                     userInfo:@{NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:@"openpty failed: %s", strerror(errno)]}];
        }
        return NO;
    }

    fcntl(master, F_SETFD, FD_CLOEXEC);

    // ---- spawn attributes -------------------------------------------------
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, slave, STDIN_FILENO);
    posix_spawn_file_actions_adddup2(&actions, slave, STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, slave, STDERR_FILENO);
    if (slave > STDERR_FILENO) {
        posix_spawn_file_actions_addclose(&actions, slave);
    }
    BOOL chdirHandled = NO;
    if (self.workingDirectory.length > 0) {
        TXAddChdirFunction addChdir = TXResolveAddChdir();
        if (addChdir) {
            addChdir(&actions, self.workingDirectory.fileSystemRepresentation);
            chdirHandled = YES;
        }
    }

    posix_spawnattr_t attributes;
    posix_spawnattr_init(&attributes);
    short flags = POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF;
    posix_spawnattr_setflags(&attributes, flags);

    sigset_t defaultSignals;
    sigfillset(&defaultSignals);
    posix_spawnattr_setsigdefault(&attributes, &defaultSignals);

    // ---- argv / envp ------------------------------------------------------
    NSArray<NSString *> *argumentList = self.arguments.count > 0
        ? self.arguments
        : @[self.executablePath.lastPathComponent];
    NSArray<NSString *> *environmentList = [self buildEnvironment];

    char **argv = calloc(argumentList.count + 1, sizeof(char *));
    for (NSUInteger i = 0; i < argumentList.count; i++) {
        argv[i] = strdup(argumentList[i].UTF8String);
    }
    char **envp = calloc(environmentList.count + 1, sizeof(char *));
    for (NSUInteger i = 0; i < environmentList.count; i++) {
        envp[i] = strdup(environmentList[i].UTF8String);
    }

    // Fallback when the SDK/runtime lacks addchdir_np: the child inherits our
    // working directory, so switch it around the spawn and restore afterwards.
    char previousDirectory[PATH_MAX] = {0};
    BOOL directorySwitched = NO;
    if (!chdirHandled && self.workingDirectory.length > 0) {
        if (getcwd(previousDirectory, sizeof(previousDirectory)) != NULL &&
            chdir(self.workingDirectory.fileSystemRepresentation) == 0) {
            directorySwitched = YES;
        }
    }

    pid_t pid = -1;
    int result = posix_spawn(&pid, self.executablePath.fileSystemRepresentation,
                             &actions, &attributes, argv, envp);

    if (directorySwitched) {
        chdir(previousDirectory);
    }

    for (NSUInteger i = 0; i < argumentList.count; i++) free(argv[i]);
    for (NSUInteger i = 0; i < environmentList.count; i++) free(envp[i]);
    free(argv);
    free(envp);
    posix_spawn_file_actions_destroy(&actions);
    posix_spawnattr_destroy(&attributes);
    close(slave);

    if (result != 0) {
        close(master);
        if (error) {
            NSString *hint = (result == EPERM || result == EACCES)
                ? @" (missing TrollStore entitlements, or the binary is not signed?)"
                : @"";
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:result
                userInfo:@{NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:@"posix_spawn(%@) failed: %s%@",
                        self.executablePath, strerror(result), hint]}];
        }
        return NO;
    }

    _master = master;
    _pid = pid;
    _ttyName = [NSString stringWithUTF8String:slaveName];

    // The pty is the child's controlling terminal; make it the foreground group.
    tcsetpgrp(master, pid);

    [self startReading];
    [self watchProcess];
    return YES;
}

#pragma mark - I/O

- (void)startReading {
    int master = _master;
    int flags = fcntl(master, F_GETFL, 0);
    fcntl(master, F_SETFL, flags | O_NONBLOCK);

    _readSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)master, 0, _ioQueue);

    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_readSource, ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;

        uint8_t buffer[65536];
        while (true) {
            ssize_t count = read(master, buffer, sizeof(buffer));
            if (count > 0) {
                NSData *data = [NSData dataWithBytes:buffer length:(NSUInteger)count];
                dispatch_async(dispatch_get_main_queue(), ^{
                    id<TXPTYSessionDelegate> delegate = strongSelf.delegate;
                    if ([delegate respondsToSelector:@selector(session:didReadData:)]) {
                        [delegate session:strongSelf didReadData:data];
                    }
                });
                if (count < (ssize_t)sizeof(buffer)) break;
                continue;
            }
            if (count == 0) break;
            if (errno == EINTR) continue;
            if (errno == EAGAIN || errno == EWOULDBLOCK) break;
            // EIO means the slave side closed -- the child is gone.
            break;
        }
    });
    dispatch_resume(_readSource);
}

- (void)watchProcess {
    _processSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_PROC, (uintptr_t)_pid,
                                            DISPATCH_PROC_EXIT, _ioQueue);
    __weak typeof(self) weakSelf = self;
    pid_t pid = _pid;
    dispatch_source_set_event_handler(_processSource, ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;

        int status = 0;
        waitpid(pid, &status, WNOHANG);

        NSString *reason;
        int code = 0;
        if (WIFEXITED(status)) {
            code = WEXITSTATUS(status);
            reason = [NSString stringWithFormat:@"exited with status %d", code];
        } else if (WIFSIGNALED(status)) {
            code = 128 + WTERMSIG(status);
            reason = [NSString stringWithFormat:@"killed by signal %d", WTERMSIG(status)];
        } else {
            reason = @"terminated";
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            strongSelf->_pid = -1;
            id<TXPTYSessionDelegate> delegate = strongSelf.delegate;
            if ([delegate respondsToSelector:@selector(session:didTerminateWithStatus:reason:)]) {
                [delegate session:strongSelf didTerminateWithStatus:code reason:reason];
            }
            [strongSelf cleanup];
        });
    });
    dispatch_resume(_processSource);
}

- (void)writeData:(NSData *)data {
    if (_master < 0 || data.length == 0) return;
    int master = _master;
    NSData *payload = [data copy];
    dispatch_async(_ioQueue, ^{
        const uint8_t *bytes = payload.bytes;
        size_t remaining = payload.length;
        while (remaining > 0) {
            ssize_t written = write(master, bytes, remaining);
            if (written > 0) {
                bytes += written;
                remaining -= (size_t)written;
                continue;
            }
            if (written < 0 && errno == EINTR) continue;
            if (written < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
                usleep(1000);
                continue;
            }
            break;
        }
    });
}

- (void)writeString:(NSString *)string {
    [self writeData:[string dataUsingEncoding:NSUTF8StringEncoding]];
}

- (void)resizeToRows:(NSInteger)rows columns:(NSInteger)columns {
    if (_master < 0) return;
    struct winsize size = {
        .ws_row = (unsigned short)MAX(rows, 1),
        .ws_col = (unsigned short)MAX(columns, 1),
        .ws_xpixel = 0,
        .ws_ypixel = 0,
    };
    ioctl(_master, TIOCSWINSZ, &size);
    if (_pid > 0) {
        killpg(_pid, SIGWINCH);
    }
}

- (void)sendSignal:(int)signal {
    if (_pid <= 0) return;
    // Signal the foreground process group so ^C reaches the running command
    // rather than only the shell.
    pid_t group = tcgetpgrp(_master);
    if (group > 0) {
        killpg(group, signal);
    } else {
        killpg(_pid, signal);
    }
}

- (void)terminate {
    if (_pid > 0) {
        killpg(_pid, SIGHUP);
        kill(_pid, SIGKILL);
    }
    [self cleanup];
}

- (void)cleanup {
    if (_readSource) {
        dispatch_source_cancel(_readSource);
        _readSource = nil;
    }
    if (_processSource) {
        dispatch_source_cancel(_processSource);
        _processSource = nil;
    }
    if (_master >= 0) {
        close(_master);
        _master = -1;
    }
    _pid = -1;
}

@end
