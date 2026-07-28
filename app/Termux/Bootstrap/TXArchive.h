//
//  TXArchive.h
//  Streaming tar reader with gzip/xz-free plumbing.
//
//  iOS has no libarchive and no tar binary we can rely on before the bootstrap
//  exists, so we unpack the rootfs ourselves.  Supported inputs:
//
//      .tar        raw ustar / GNU tar
//      .tar.gz     via zlib (in libSystem)
//      .tar.zst    via the bundled zstd decoder when present
//
//  Handles regular files, directories, symlinks, hardlinks, GNU long names and
//  PAX extended headers -- everything a Procursus bootstrap contains.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^TXArchiveProgressHandler)(double fraction, NSString *entryName);

@interface TXArchive : NSObject

/// Extracts `archivePath` into `directory`, creating intermediate paths.
/// Entries that would escape the destination are rejected.
+ (BOOL)extractArchiveAtPath:(NSString *)archivePath
                 toDirectory:(NSString *)directory
                    progress:(nullable TXArchiveProgressHandler)progress
                       error:(NSError **)error;

/// Extracts an in-memory tar (already decompressed).
+ (BOOL)extractTarData:(NSData *)data
           toDirectory:(NSString *)directory
              progress:(nullable TXArchiveProgressHandler)progress
                 error:(NSError **)error;

/// Gunzips a buffer using zlib from libSystem.
+ (nullable NSData *)gunzipData:(NSData *)data error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
