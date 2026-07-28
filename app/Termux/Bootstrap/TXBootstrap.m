//
//  TXBootstrap.m
//

#import "TXBootstrap.h"
#import "TXArchive.h"

#import <sys/stat.h>

NSString *const TXBootstrapErrorDomain = @"TXBootstrapErrorDomain";

@implementation TXBootstrap {
    NSString *_documentsPath;
}

+ (TXBootstrap *)sharedBootstrap {
    static TXBootstrap *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[TXBootstrap alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;

    NSArray<NSString *> *paths =
        NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    _documentsPath = paths.firstObject ?: NSTemporaryDirectory();

    _prefixPath = [_documentsPath stringByAppendingPathComponent:@"prefix"];
    _homePath = [_documentsPath stringByAppendingPathComponent:@"home"];
    _temporaryPath = [_prefixPath stringByAppendingPathComponent:@"tmp"];
    _stage = TXBootstrapStageIdle;

    return self;
}

#pragma mark - State

- (BOOL)isInstalled {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *shell in @[@"bin/bash", @"bin/sh", @"bin/dash"]) {
        NSString *path = [self.prefixPath stringByAppendingPathComponent:shell];
        if ([fm isExecutableFileAtPath:path]) return YES;
    }
    return NO;
}

- (NSString *)loginShellPath {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *shell in @[@"bin/bash", @"bin/zsh", @"bin/dash", @"bin/sh"]) {
        NSString *path = [self.prefixPath stringByAppendingPathComponent:shell];
        if ([fm isExecutableFileAtPath:path]) return path;
    }
    // Fallback: the built-in shell we ship inside the app bundle so the
    // terminal is usable before any bootstrap is installed.
    NSString *builtin = [[NSBundle mainBundle] pathForResource:@"xsh" ofType:nil];
    if (builtin && [fm isExecutableFileAtPath:builtin]) return builtin;
    // Last resort: iOS itself has /bin/sh on jailbroken/TrollStore devices.
    return @"/bin/sh";
}

- (NSDictionary<NSString *, NSString *> *)sessionEnvironment {
    NSString *prefix = self.prefixPath;
    NSString *path = [NSString stringWithFormat:
        @"%@/bin:%@/usr/bin:%@/usr/local/bin:%@/sbin:%@/usr/sbin:/usr/bin:/bin:/usr/sbin:/sbin",
        prefix, prefix, prefix, prefix, prefix];

    return @{
        @"PREFIX": prefix,
        @"TERMUX_PREFIX": prefix,
        @"HOME": self.homePath,
        @"PATH": path,
        @"TMPDIR": self.temporaryPath,
        @"TMP": self.temporaryPath,
        @"SHELL": self.loginShellPath,
        @"USER": @"mobile",
        @"LOGNAME": @"mobile",
        @"TERM": @"xterm-256color",
        @"COLORTERM": @"truecolor",
        @"LANG": @"en_US.UTF-8",
        @"TERMINFO": [prefix stringByAppendingPathComponent:@"share/terminfo"],
        @"LD_LIBRARY_PATH": [NSString stringWithFormat:@"%@/lib:%@/usr/lib", prefix, prefix],
        @"DYLD_LIBRARY_PATH": [NSString stringWithFormat:@"%@/lib:%@/usr/lib", prefix, prefix],
        @"PKG_CONFIG_PATH": [prefix stringByAppendingPathComponent:@"lib/pkgconfig"],
        @"TERMUX_IOS": @"1",
    };
}

#pragma mark - Directory skeleton

- (BOOL)prepareDirectoriesWithError:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *directories = @[
        self.prefixPath,
        self.homePath,
        self.temporaryPath,
        [self.prefixPath stringByAppendingPathComponent:@"bin"],
        [self.prefixPath stringByAppendingPathComponent:@"lib"],
        [self.prefixPath stringByAppendingPathComponent:@"etc"],
        [self.prefixPath stringByAppendingPathComponent:@"etc/apt/sources.list.d"],
        [self.prefixPath stringByAppendingPathComponent:@"etc/apt/preferences.d"],
        [self.prefixPath stringByAppendingPathComponent:@"usr/bin"],
        [self.prefixPath stringByAppendingPathComponent:@"usr/lib"],
        [self.prefixPath stringByAppendingPathComponent:@"usr/share"],
        [self.prefixPath stringByAppendingPathComponent:@"var/lib/dpkg"],
        [self.prefixPath stringByAppendingPathComponent:@"var/lib/apt/lists/partial"],
        [self.prefixPath stringByAppendingPathComponent:@"var/cache/apt/archives/partial"],
        [self.prefixPath stringByAppendingPathComponent:@"var/log"],
    ];

    for (NSString *directory in directories) {
        if (![fm createDirectoryAtPath:directory withIntermediateDirectories:YES
                            attributes:nil error:error]) {
            return NO;
        }
    }

    // dpkg refuses to run without these.
    NSString *dpkgDir = [self.prefixPath stringByAppendingPathComponent:@"var/lib/dpkg"];
    for (NSString *file in @[@"status", @"available"]) {
        NSString *path = [dpkgDir stringByAppendingPathComponent:file];
        if (![fm fileExistsAtPath:path]) {
            [@"" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        }
    }
    NSString *updatesDir = [dpkgDir stringByAppendingPathComponent:@"updates"];
    [fm createDirectoryAtPath:updatesDir withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *infoDir = [dpkgDir stringByAppendingPathComponent:@"info"];
    [fm createDirectoryAtPath:infoDir withIntermediateDirectories:YES attributes:nil error:NULL];

    [self writeDefaultProfileIfNeeded];
    return YES;
}

- (void)writeDefaultProfileIfNeeded {
    NSString *profile = [self.homePath stringByAppendingPathComponent:@".profile"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:profile]) return;

    NSString *contents =
        @"# Termux for iOS -- default profile\n"
        @"export PS1='\\[\\e[32m\\]\\u@iphone\\[\\e[0m\\]:\\[\\e[34m\\]\\w\\[\\e[0m\\]\\$ '\n"
        @"alias ls='ls --color=auto 2>/dev/null || ls'\n"
        @"alias ll='ls -la'\n"
        @"umask 022\n"
        @"cd \"$HOME\"\n";
    [contents writeToFile:profile atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

#pragma mark - apt configuration

- (BOOL)writePackageManagerConfigurationWithError:(NSError **)error {
    NSString *prefix = self.prefixPath;

    // Procursus is the de-facto arm64 iOS userland; iphoneos-arm64 is the
    // rootless/TrollStore-friendly flavour.
    NSString *sources =
        @"Types: deb\n"
        @"URIs: https://apt.procurs.us/\n"
        @"Suites: 1800 main\n"
        @"Components: main\n"
        @"Architectures: darwin-arm64 iphoneos-arm64\n";
    NSString *sourcesPath =
        [prefix stringByAppendingPathComponent:@"etc/apt/sources.list.d/procursus.sources"];
    if (![sources writeToFile:sourcesPath atomically:YES
                     encoding:NSUTF8StringEncoding error:error]) {
        return NO;
    }

    // Point every apt/dpkg path inside the prefix -- there is no / to write to.
    NSString *aptConf = [NSString stringWithFormat:
        @"Dir \"%@\";\n"
        @"Dir::State \"%@/var/lib/apt\";\n"
        @"Dir::State::status \"%@/var/lib/dpkg/status\";\n"
        @"Dir::Cache \"%@/var/cache/apt\";\n"
        @"Dir::Etc \"%@/etc/apt\";\n"
        @"Dir::Log \"%@/var/log/apt\";\n"
        @"Dir::Bin::dpkg \"%@/bin/dpkg\";\n"
        @"APT::Architecture \"iphoneos-arm64\";\n"
        @"APT::Architectures { \"iphoneos-arm64\"; };\n"
        @"APT::Get::AllowUnauthenticated \"true\";\n"
        @"Acquire::AllowInsecureRepositories \"true\";\n"
        @"DPkg::Options { \"--force-not-root\"; \"--force-bad-path\"; \"--root=%@\"; \"--admindir=%@/var/lib/dpkg\"; };\n",
        prefix, prefix, prefix, prefix, prefix, prefix, prefix, prefix, prefix];

    NSString *aptConfPath = [prefix stringByAppendingPathComponent:@"etc/apt/apt.conf"];
    if (![aptConf writeToFile:aptConfPath atomically:YES
                     encoding:NSUTF8StringEncoding error:error]) {
        return NO;
    }

    NSString *dpkgConf =
        @"force-not-root\n"
        @"force-bad-path\n"
        @"no-debsig\n";
    NSString *dpkgConfPath = [prefix stringByAppendingPathComponent:@"etc/dpkg/dpkg.cfg"];
    [[NSFileManager defaultManager]
        createDirectoryAtPath:dpkgConfPath.stringByDeletingLastPathComponent
        withIntermediateDirectories:YES attributes:nil error:NULL];
    [dpkgConf writeToFile:dpkgConfPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];

    return YES;
}

#pragma mark - Installation

- (void)reportStage:(TXBootstrapStage)stage
           fraction:(double)fraction
            message:(NSString *)message
           progress:(TXBootstrapProgressHandler)progress {
    _stage = stage;
    if (!progress) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        progress(stage, fraction, message);
    });
}

- (void)finishWithSuccess:(BOOL)success
                    error:(NSError *)error
               completion:(TXBootstrapCompletionHandler)completion {
    _stage = success ? TXBootstrapStageReady : TXBootstrapStageFailed;
    if (!completion) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(success, error);
    });
}

- (void)installBootstrapFromURL:(NSURL *)url
                       progress:(TXBootstrapProgressHandler)progress
                     completion:(TXBootstrapCompletionHandler)completion {
    NSError *error = nil;
    if (![self prepareDirectoriesWithError:&error]) {
        [self finishWithSuccess:NO error:error completion:completion];
        return;
    }

    [self reportStage:TXBootstrapStageDownloading fraction:0
              message:[NSString stringWithFormat:@"Downloading %@", url.lastPathComponent]
             progress:progress];

    NSURLSessionConfiguration *configuration =
        [NSURLSessionConfiguration defaultSessionConfiguration];
    configuration.timeoutIntervalForResource = 3600;

    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
    NSURLSessionDownloadTask *task =
        [session downloadTaskWithURL:url
                   completionHandler:^(NSURL *location, NSURLResponse *response, NSError *taskError) {
        if (taskError || !location) {
            [self finishWithSuccess:NO error:taskError completion:completion];
            return;
        }

        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        if ([http isKindOfClass:[NSHTTPURLResponse class]] && http.statusCode >= 400) {
            NSError *httpError = [NSError errorWithDomain:TXBootstrapErrorDomain
                code:http.statusCode
                userInfo:@{NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:@"Download failed: HTTP %ld", (long)http.statusCode]}];
            [self finishWithSuccess:NO error:httpError completion:completion];
            return;
        }

        NSString *archive = [NSTemporaryDirectory()
            stringByAppendingPathComponent:url.lastPathComponent ?: @"bootstrap.tar"];
        [[NSFileManager defaultManager] removeItemAtPath:archive error:NULL];
        NSError *moveError = nil;
        if (![[NSFileManager defaultManager] moveItemAtURL:location
                                                     toURL:[NSURL fileURLWithPath:archive]
                                                     error:&moveError]) {
            [self finishWithSuccess:NO error:moveError completion:completion];
            return;
        }

        [self installBootstrapFromArchive:archive progress:progress completion:^(BOOL ok, NSError *e) {
            [[NSFileManager defaultManager] removeItemAtPath:archive error:NULL];
            if (completion) completion(ok, e);
        }];
    }];

    [task resume];
}

- (void)installBootstrapFromArchive:(NSString *)archivePath
                           progress:(TXBootstrapProgressHandler)progress
                         completion:(TXBootstrapCompletionHandler)completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        if (![self prepareDirectoriesWithError:&error]) {
            [self finishWithSuccess:NO error:error completion:completion];
            return;
        }

        [self reportStage:TXBootstrapStageExtracting fraction:0.1
                  message:@"Extracting bootstrap..." progress:progress];

        BOOL extracted = [TXArchive extractArchiveAtPath:archivePath
                                             toDirectory:self.prefixPath
                                                progress:^(double fraction, NSString *entry) {
            [self reportStage:TXBootstrapStageExtracting
                     fraction:0.1 + fraction * 0.8
                      message:entry
                     progress:progress];
        }
                                                   error:&error];
        if (!extracted) {
            [self finishWithSuccess:NO error:error completion:completion];
            return;
        }

        [self reportStage:TXBootstrapStageConfiguring fraction:0.95
                  message:@"Configuring package manager..." progress:progress];

        if (![self writePackageManagerConfigurationWithError:&error]) {
            [self finishWithSuccess:NO error:error completion:completion];
            return;
        }

        [self fixExecutablePermissions];
        [self finishWithSuccess:YES error:nil completion:completion];
    });
}

/// Tarballs sometimes lose the executable bit through iOS' file APIs; make sure
/// everything under bin/ and sbin/ can actually run.
- (void)fixExecutablePermissions {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *binDirectories = @[@"bin", @"sbin", @"usr/bin", @"usr/sbin", @"libexec"];

    for (NSString *relative in binDirectories) {
        NSString *directory = [self.prefixPath stringByAppendingPathComponent:relative];
        NSArray<NSString *> *entries = [fm contentsOfDirectoryAtPath:directory error:NULL];
        for (NSString *entry in entries) {
            NSString *path = [directory stringByAppendingPathComponent:entry];
            chmod(path.fileSystemRepresentation, 0755);
        }
    }
}

#pragma mark - Uninstall

- (BOOL)uninstallWithError:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:self.prefixPath] &&
        ![fm removeItemAtPath:self.prefixPath error:error]) {
        return NO;
    }
    _stage = TXBootstrapStageIdle;
    return [self prepareDirectoriesWithError:error];
}

@end
