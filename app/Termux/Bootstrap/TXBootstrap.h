//
//  TXBootstrap.h
//  Manages the Linux-like userland that lives inside the app container.
//
//  Layout (all inside the app's Documents directory so it survives updates and
//  is reachable from the Files app):
//
//      <container>/Documents/prefix/          $PREFIX      -- the bootstrap
//                                 ├── bin, lib, etc, usr, var
//                                 └── tmp
//      <container>/Documents/home/            $HOME
//
//  The bootstrap itself is a Procursus-style arm64 (iphoneos-arm64) rootfs:
//  a tarball of dpkg + apt + coreutils + bash that we unpack on first launch,
//  after which `apt install ...` works against the configured repositories.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TXBootstrapStage) {
    TXBootstrapStageIdle,
    TXBootstrapStageDownloading,
    TXBootstrapStageExtracting,
    TXBootstrapStageConfiguring,
    TXBootstrapStageReady,
    TXBootstrapStageFailed,
};

typedef void (^TXBootstrapProgressHandler)(TXBootstrapStage stage, double fraction, NSString *message);
typedef void (^TXBootstrapCompletionHandler)(BOOL success, NSError *_Nullable error);

@interface TXBootstrap : NSObject

@property (class, nonatomic, readonly) TXBootstrap *sharedBootstrap;

/// $PREFIX -- root of the userland.
@property (nonatomic, readonly, copy) NSString *prefixPath;
/// $HOME -- the user's home directory.
@property (nonatomic, readonly, copy) NSString *homePath;
/// $TMPDIR inside the prefix.
@property (nonatomic, readonly, copy) NSString *temporaryPath;

/// YES once a usable shell exists in the prefix.
@property (nonatomic, readonly) BOOL isInstalled;

@property (nonatomic, readonly) TXBootstrapStage stage;

/// Login shell to spawn: the bootstrap's bash, or a built-in fallback shell
/// when no bootstrap has been installed yet.
@property (nonatomic, readonly, copy) NSString *loginShellPath;

/// Environment variables handed to every session.
- (NSDictionary<NSString *, NSString *> *)sessionEnvironment;

/// Creates the directory skeleton; cheap, safe to call on every launch.
- (BOOL)prepareDirectoriesWithError:(NSError **)error;

/// Downloads and unpacks the bootstrap rootfs.
- (void)installBootstrapFromURL:(NSURL *)url
                       progress:(nullable TXBootstrapProgressHandler)progress
                     completion:(nullable TXBootstrapCompletionHandler)completion;

/// Unpacks a bootstrap archive already on disk (e.g. shared via the Files app).
- (void)installBootstrapFromArchive:(NSString *)archivePath
                           progress:(nullable TXBootstrapProgressHandler)progress
                         completion:(nullable TXBootstrapCompletionHandler)completion;

/// Writes apt sources/config into the prefix so `apt update` works.
- (BOOL)writePackageManagerConfigurationWithError:(NSError **)error;

/// Removes the whole prefix (keeps $HOME).
- (BOOL)uninstallWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
