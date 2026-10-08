// Zip archives, as export writes them and import reads them (another app's
// export: Trilium's, Obsidian's folder zipped): entries stored or deflated
// (zlib), names in UTF-8. Not Zip64, not encrypted: an archive larger than
// 4 GB, or an entry so made, is not read.

#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SNZipReader : NSObject
// nil: not a zip archive (or not one read here).
- (nullable instancetype)initWithData:(NSData *)data;
// The files' paths, in the archive's order ("a/b.md"; folders not listed).
@property (nonatomic, readonly, copy) NSArray<NSString *> *paths;
// A file's contents; nil: none so named, or not read (a method not known,
// a CRC that does not match).
- (nullable NSData *)dataAtPath:(NSString *)path;
// When it was last modified, as the archive says.
- (nullable NSDate *)dateAtPath:(NSString *)path;
@end

@interface SNZipWriter : NSObject
// A file, deflated (or stored, when that is no smaller).
- (void)addData:(NSData *)data atPath:(NSString *)path date:(nullable NSDate *)date;
// The archive written so far.
- (NSData *)data;
@end

NS_ASSUME_NONNULL_END
