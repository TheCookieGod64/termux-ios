//
//  TXArchive.m
//

#import "TXArchive.h"

#import <sys/stat.h>
#import <zlib.h>

NSString *const TXArchiveErrorDomain = @"TXArchiveErrorDomain";

#define TX_TAR_BLOCK 512

/// POSIX ustar header.
typedef struct {
    char name[100];
    char mode[8];
    char uid[8];
    char gid[8];
    char size[12];
    char mtime[12];
    char checksum[8];
    char typeflag;
    char linkname[100];
    char magic[6];
    char version[2];
    char uname[32];
    char gname[32];
    char devmajor[8];
    char devminor[8];
    char prefix[155];
    char padding[12];
} TXTarHeader;

static NSError *TXArchiveError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:TXArchiveErrorDomain code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

/// Parses an octal (or GNU base-256) numeric tar field.
static unsigned long long TXParseOctal(const char *field, size_t length) {
    if (length == 0) return 0;

    // GNU base-256 encoding for large values.
    if ((unsigned char)field[0] & 0x80) {
        unsigned long long value = 0;
        for (size_t i = 1; i < length; i++) {
            value = (value << 8) | (unsigned char)field[i];
        }
        return value;
    }

    unsigned long long value = 0;
    for (size_t i = 0; i < length; i++) {
        char c = field[i];
        if (c == ' ' || c == '\0') {
            if (value) break;
            continue;
        }
        if (c < '0' || c > '7') break;
        value = value * 8 + (unsigned long long)(c - '0');
    }
    return value;
}

static NSString *TXStringFromField(const char *field, size_t length) {
    size_t actual = 0;
    while (actual < length && field[actual] != '\0') actual++;
    return [[NSString alloc] initWithBytes:field length:actual encoding:NSUTF8StringEncoding]
        ?: [[NSString alloc] initWithBytes:field length:actual encoding:NSISOLatin1StringEncoding]
        ?: @"";
}

static BOOL TXHeaderIsZero(const uint8_t *block) {
    for (int i = 0; i < TX_TAR_BLOCK; i++) {
        if (block[i] != 0) return NO;
    }
    return YES;
}

@implementation TXArchive

#pragma mark - Decompression

+ (NSData *)gunzipData:(NSData *)data error:(NSError **)error {
    if (data.length == 0) return [NSData data];

    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    stream.next_in = (Bytef *)data.bytes;
    stream.avail_in = (uInt)data.length;

    // 15 + 32 enables automatic gzip/zlib header detection.
    if (inflateInit2(&stream, 15 + 32) != Z_OK) {
        if (error) *error = TXArchiveError(1, @"inflateInit2 failed");
        return nil;
    }

    NSMutableData *output = [NSMutableData dataWithCapacity:data.length * 4];
    uint8_t buffer[262144];
    int status = Z_OK;

    do {
        stream.next_out = buffer;
        stream.avail_out = (uInt)sizeof(buffer);
        status = inflate(&stream, Z_NO_FLUSH);

        if (status != Z_OK && status != Z_STREAM_END && status != Z_BUF_ERROR) {
            inflateEnd(&stream);
            if (error) {
                *error = TXArchiveError(status,
                    [NSString stringWithFormat:@"gzip decompression failed (%d)", status]);
            }
            return nil;
        }

        NSUInteger produced = sizeof(buffer) - stream.avail_out;
        if (produced > 0) [output appendBytes:buffer length:produced];
        if (status == Z_BUF_ERROR && produced == 0) break;
    } while (status != Z_STREAM_END);

    inflateEnd(&stream);
    return output;
}

#pragma mark - Entry point

+ (BOOL)extractArchiveAtPath:(NSString *)archivePath
                 toDirectory:(NSString *)directory
                    progress:(TXArchiveProgressHandler)progress
                       error:(NSError **)error {
    NSData *data = [NSData dataWithContentsOfFile:archivePath
                                          options:NSDataReadingMappedIfSafe
                                            error:error];
    if (!data) return NO;

    NSString *lower = archivePath.lowercaseString;
    NSData *tar = data;

    BOOL gzipped = [lower hasSuffix:@".gz"] || [lower hasSuffix:@".tgz"];
    if (!gzipped && data.length > 2) {
        const uint8_t *bytes = data.bytes;
        gzipped = bytes[0] == 0x1F && bytes[1] == 0x8B;      // gzip magic
    }

    if (gzipped) {
        tar = [self gunzipData:data error:error];
        if (!tar) return NO;
    } else if ([lower hasSuffix:@".zst"] || [lower hasSuffix:@".xz"] ||
               [lower hasSuffix:@".bz2"] || [lower hasSuffix:@".lzma"]) {
        if (error) {
            *error = TXArchiveError(2,
                @"This archive uses xz/zstd/bzip2 compression. "
                @"Please supply a .tar or .tar.gz bootstrap instead.");
        }
        return NO;
    }

    return [self extractTarData:tar toDirectory:directory progress:progress error:error];
}

#pragma mark - Tar

+ (BOOL)extractTarData:(NSData *)data
           toDirectory:(NSString *)directory
              progress:(TXArchiveProgressHandler)progress
                 error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm createDirectoryAtPath:directory withIntermediateDirectories:YES
                        attributes:nil error:error]) {
        return NO;
    }

    NSString *destination = directory.stringByStandardizingPath;
    const uint8_t *bytes = data.bytes;
    NSUInteger length = data.length;
    NSUInteger offset = 0;

    NSString *pendingLongName = nil;
    NSString *pendingLongLink = nil;
    NSMutableDictionary<NSString *, NSString *> *pendingPax = [NSMutableDictionary dictionary];

    // Deferred so that directory mtimes/modes survive writing their contents.
    NSMutableArray<NSDictionary *> *deferredAttributes = [NSMutableArray array];
    NSMutableArray<NSArray *> *deferredLinks = [NSMutableArray array];

    NSUInteger emptyBlocks = 0;

    while (offset + TX_TAR_BLOCK <= length) {
        const uint8_t *block = bytes + offset;

        if (TXHeaderIsZero(block)) {
            offset += TX_TAR_BLOCK;
            if (++emptyBlocks >= 2) break;         // end-of-archive marker
            continue;
        }
        emptyBlocks = 0;

        const TXTarHeader *header = (const TXTarHeader *)block;
        offset += TX_TAR_BLOCK;

        unsigned long long size = TXParseOctal(header->size, sizeof(header->size));
        NSUInteger padded = (NSUInteger)((size + TX_TAR_BLOCK - 1) / TX_TAR_BLOCK) * TX_TAR_BLOCK;
        if (offset + padded > length && size > 0) {
            // Truncated archive: stop cleanly rather than reading past the end.
            break;
        }

        const uint8_t *payload = bytes + offset;
        char type = header->typeflag;

        // ---- metadata-only entries -----------------------------------------
        if (type == 'L') {                              // GNU long name
            pendingLongName = [[NSString alloc] initWithBytes:payload
                                                       length:(NSUInteger)size
                                                     encoding:NSUTF8StringEncoding];
            pendingLongName = [pendingLongName
                stringByTrimmingCharactersInSet:[NSCharacterSet controlCharacterSet]];
            offset += padded;
            continue;
        }
        if (type == 'K') {                              // GNU long link target
            pendingLongLink = [[NSString alloc] initWithBytes:payload
                                                       length:(NSUInteger)size
                                                     encoding:NSUTF8StringEncoding];
            pendingLongLink = [pendingLongLink
                stringByTrimmingCharactersInSet:[NSCharacterSet controlCharacterSet]];
            offset += padded;
            continue;
        }
        if (type == 'x' || type == 'X' || type == 'g') { // PAX headers
            NSString *records = [[NSString alloc] initWithBytes:payload
                                                         length:(NSUInteger)size
                                                       encoding:NSUTF8StringEncoding];
            for (NSString *line in [records componentsSeparatedByString:@"\n"]) {
                NSRange space = [line rangeOfString:@" "];
                if (space.location == NSNotFound) continue;
                NSString *record = [line substringFromIndex:space.location + 1];
                NSRange equals = [record rangeOfString:@"="];
                if (equals.location == NSNotFound) continue;
                pendingPax[[record substringToIndex:equals.location]] =
                    [record substringFromIndex:equals.location + 1];
            }
            offset += padded;
            continue;
        }

        // ---- resolve the entry name ----------------------------------------
        NSString *name = pendingLongName ?: pendingPax[@"path"];
        if (!name) {
            name = TXStringFromField(header->name, sizeof(header->name));
            NSString *prefix = TXStringFromField(header->prefix, sizeof(header->prefix));
            if (prefix.length > 0) {
                name = [prefix stringByAppendingPathComponent:name];
            }
        }
        NSString *linkTarget = pendingLongLink ?: pendingPax[@"linkpath"]
            ?: TXStringFromField(header->linkname, sizeof(header->linkname));

        pendingLongName = nil;
        pendingLongLink = nil;
        [pendingPax removeAllObjects];

        // Procursus tarballs are rooted at ./ or ./var/jb -- strip the noise.
        while ([name hasPrefix:@"./"]) name = [name substringFromIndex:2];
        if ([name isEqualToString:@"."] || name.length == 0) {
            offset += padded;
            continue;
        }

        NSString *path = [destination stringByAppendingPathComponent:name];
        NSString *resolved = path.stringByStandardizingPath;

        // Reject path traversal (../../etc/passwd style entries).
        if (![resolved hasPrefix:destination]) {
            offset += padded;
            continue;
        }

        mode_t mode = (mode_t)TXParseOctal(header->mode, sizeof(header->mode));
        unsigned long long mtime = TXParseOctal(header->mtime, sizeof(header->mtime));

        if (progress) {
            double fraction = length > 0 ? (double)offset / (double)length : 0;
            progress(fraction, name);
        }

        switch (type) {
            case '5': {                                   // directory
                [fm createDirectoryAtPath:resolved withIntermediateDirectories:YES
                               attributes:nil error:NULL];
                [deferredAttributes addObject:@{@"path": resolved,
                                                @"mode": @(mode ?: 0755),
                                                @"mtime": @(mtime)}];
                break;
            }
            case '1':                                     // hard link
            case '2': {                                   // symlink
                if (linkTarget.length > 0) {
                    [deferredLinks addObject:@[resolved, linkTarget, @(type == '2')]];
                }
                break;
            }
            case '0':
            case '\0':
            case '7': {                                   // regular file
                [fm createDirectoryAtPath:resolved.stringByDeletingLastPathComponent
              withIntermediateDirectories:YES attributes:nil error:NULL];
                [fm removeItemAtPath:resolved error:NULL];

                NSData *contents = [NSData dataWithBytes:payload length:(NSUInteger)size];
                if (![contents writeToFile:resolved options:NSDataWritingAtomic error:error]) {
                    return NO;
                }
                chmod(resolved.fileSystemRepresentation, mode ?: 0644);
                break;
            }
            default:
                // Character/block devices and FIFOs cannot exist here; skip.
                break;
        }

        offset += padded;
    }

    // Links last: their targets may appear later in the archive.
    for (NSArray *link in deferredLinks) {
        NSString *path = link[0];
        NSString *target = link[1];
        BOOL symbolic = [(NSNumber *)link[2] boolValue];

        [fm removeItemAtPath:path error:NULL];
        [fm createDirectoryAtPath:path.stringByDeletingLastPathComponent
      withIntermediateDirectories:YES attributes:nil error:NULL];

        if (symbolic) {
            [fm createSymbolicLinkAtPath:path withDestinationPath:target error:NULL];
        } else {
            NSString *absolute = [destination stringByAppendingPathComponent:target];
            [fm linkItemAtPath:absolute toPath:path error:NULL];
        }
    }

    for (NSDictionary *attributes in deferredAttributes) {
        NSString *path = attributes[@"path"];
        chmod(path.fileSystemRepresentation, [attributes[@"mode"] unsignedShortValue]);
    }

    return YES;
}

@end
