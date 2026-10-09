#import "SNZip.h"
#import <zlib.h>

static uint16_t SNRead16(const uint8_t *p) {
    return (uint16_t)(p[0] | p[1] << 8);
}

static uint32_t SNRead32(const uint8_t *p) {
    return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}

static void SNWrite16(NSMutableData *d, uint16_t v) {
    uint8_t b[2] = { (uint8_t)v, (uint8_t)(v >> 8) };
    [d appendBytes:b length:2];
}

static void SNWrite32(NSMutableData *d, uint32_t v) {
    uint8_t b[4] = { (uint8_t)v, (uint8_t)(v >> 8), (uint8_t)(v >> 16), (uint8_t)(v >> 24) };
    [d appendBytes:b length:4];
}

/* MS-DOS's date and time, as zip keeps them (local time, 2 s steps). */
static NSDate *SNDateOfDOS(uint16_t date, uint16_t time) {
    NSDateComponents *c = [[NSDateComponents alloc] init];
    c.year = 1980 + (date >> 9);
    c.month = (date >> 5) & 0xF;
    c.day = date & 0x1F;
    c.hour = time >> 11;
    c.minute = (time >> 5) & 0x3F;
    c.second = (time & 0x1F) * 2;
    if (c.month < 1 || c.day < 1) return nil;
    return [[NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian] dateFromComponents:c];
}

static void SNDOSOfDate(NSDate *date, uint16_t *dosDate, uint16_t *dosTime) {
    NSDateComponents *c = [[NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian]
        components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond
          fromDate:date ?: [NSDate date]];
    NSInteger year = MAX(0, MIN(127, c.year - 1980));
    *dosDate = (uint16_t)(year << 9 | c.month << 5 | c.day);
    *dosTime = (uint16_t)(c.hour << 11 | c.minute << 5 | c.second / 2);
}

/* An entry as the central directory has it. */
@interface SNZipEntry : NSObject
@property (nonatomic) uint16_t method, dosDate, dosTime;
@property (nonatomic) uint32_t crc, compressedSize, size, offset;
@end

@implementation SNZipEntry
@end

@implementation SNZipReader {
    NSData *_data;
    NSMutableDictionary<NSString *, SNZipEntry *> *_entries;
    NSMutableArray<NSString *> *_paths;
}

- (instancetype)initWithData:(NSData *)data {
    self = [super init];
    if (!self) return nil;
    _data = data;
    _entries = [NSMutableDictionary dictionary];
    _paths = [NSMutableArray array];
    const uint8_t *b = data.bytes;
    NSUInteger n = data.length;
    if (n < 22) return nil;
    /* The end of the central directory: last, after a comment of at most 64 KB. */
    NSInteger end = -1;
    for (NSInteger i = (NSInteger)n - 22; i >= 0 && i >= (NSInteger)n - 22 - 65535; i--) {
        if (SNRead32(b + i) == 0x06054b50) {
            end = i;
            break;
        }
    }
    if (end < 0) return nil;
    NSUInteger count = SNRead16(b + end + 10);
    NSUInteger at = SNRead32(b + end + 16);
    for (NSUInteger k = 0; k < count; k++) {
        if (at + 46 > n || SNRead32(b + at) != 0x02014b50) return nil;
        uint16_t flags = SNRead16(b + at + 8);
        SNZipEntry *e = [[SNZipEntry alloc] init];
        e.method = SNRead16(b + at + 10);
        e.dosTime = SNRead16(b + at + 12);
        e.dosDate = SNRead16(b + at + 14);
        e.crc = SNRead32(b + at + 16);
        e.compressedSize = SNRead32(b + at + 20);
        e.size = SNRead32(b + at + 24);
        NSUInteger nameLength = SNRead16(b + at + 28), extra = SNRead16(b + at + 30), comment = SNRead16(b + at + 32);
        e.offset = SNRead32(b + at + 42);
        if (at + 46 + nameLength > n) return nil;
        NSData *raw = [data subdataWithRange:NSMakeRange(at + 46, nameLength)];
        /* UTF-8 when it says so, and when it is (many write it without saying). */
        NSString *name = [[NSString alloc] initWithData:raw encoding:NSUTF8StringEncoding];
        if (!name && !(flags & 0x800)) name = [[NSString alloc] initWithData:raw encoding:NSISOLatin1StringEncoding];
        name = [name stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
        at += 46 + nameLength + extra + comment;
        if (!name.length || [name hasSuffix:@"/"] || (flags & 1)) continue;
        if (!_entries[name]) [_paths addObject:name];
        _entries[name] = e;
    }
    return self;
}

- (NSArray<NSString *> *)paths {
    return [_paths copy];
}

- (NSDate *)dateAtPath:(NSString *)path {
    SNZipEntry *e = _entries[path];
    return e ? SNDateOfDOS(e.dosDate, e.dosTime) : nil;
}

- (NSData *)dataAtPath:(NSString *)path {
    SNZipEntry *e = _entries[path];
    if (!e) return nil;
    const uint8_t *b = _data.bytes;
    NSUInteger n = _data.length;
    if ((NSUInteger)e.offset + 30 > n || SNRead32(b + e.offset) != 0x04034b50) return nil;
    NSUInteger start = e.offset + 30 + SNRead16(b + e.offset + 26) + SNRead16(b + e.offset + 28);
    if (start + e.compressedSize > n) return nil;
    NSData *out;
    if (e.method == 0) {
        out = [_data subdataWithRange:NSMakeRange(start, e.compressedSize)];
    } else if (e.method == 8) {
        NSMutableData *inflated = [NSMutableData dataWithLength:e.size];
        z_stream z;
        memset(&z, 0, sizeof z);
        if (inflateInit2(&z, -MAX_WBITS) != Z_OK) return nil;
        z.next_in = (Bytef *)(b + start);
        z.avail_in = e.compressedSize;
        z.next_out = inflated.mutableBytes;
        z.avail_out = e.size;
        int r = inflate(&z, Z_FINISH);
        inflateEnd(&z);
        if (r != Z_STREAM_END || z.total_out != e.size) return nil;
        out = inflated;
    } else {
        return nil;
    }
    if (crc32(0, out.bytes, (uInt)out.length) != e.crc) return nil;
    return out;
}

@end

@implementation SNZipWriter {
    NSMutableData *_data;        /* in memory */
    NSFileHandle *_file;         /* or into a file */
    NSURL *_url;
    uint64_t _offset;
    NSMutableData *_directory;
    uint16_t _count;
    BOOL _failed;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _data = [NSMutableData data];
    _directory = [NSMutableData data];
    return self;
}

- (instancetype)initWithURL:(NSURL *)url error:(NSError **)error {
    self = [super init];
    if (!self) return nil;
    if (![[NSFileManager defaultManager] createFileAtPath:url.path contents:nil attributes:nil] ||
        !(_file = [NSFileHandle fileHandleForWritingAtPath:url.path])) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError
                                            userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"“%@” could not be written.", url.lastPathComponent] }];
        return nil;
    }
    _url = url;
    _directory = [NSMutableData data];
    return self;
}

/* Written out: into memory, or the file. */
- (BOOL)put:(NSData *)bytes {
    if (_failed) return NO;
    if (_data) {
        [_data appendData:bytes];
    } else {
        @try {
            [_file writeData:bytes];
        } @catch (NSException *e) {
            _failed = YES;
            return NO;
        }
    }
    _offset += bytes.length;
    return YES;
}

- (BOOL)addData:(NSData *)data atPath:(NSString *)path date:(NSDate *)date {
    NSData *name = [path dataUsingEncoding:NSUTF8StringEncoding];
    uint32_t crc = (uint32_t)crc32(0, data.bytes, (uInt)data.length);
    uint16_t method = 0;
    NSData *body = data;
    if (data.length > 64) {
        uLong bound = compressBound((uLong)data.length) + 16;
        NSMutableData *deflated = [NSMutableData dataWithLength:bound];
        z_stream z;
        memset(&z, 0, sizeof z);
        if (deflateInit2(&z, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -MAX_WBITS, 8, Z_DEFAULT_STRATEGY) == Z_OK) {
            z.next_in = (Bytef *)data.bytes;
            z.avail_in = (uInt)data.length;
            z.next_out = deflated.mutableBytes;
            z.avail_out = (uInt)bound;
            if (deflate(&z, Z_FINISH) == Z_STREAM_END && z.total_out < data.length) {
                deflated.length = z.total_out;
                body = deflated;
                method = 8;
            }
            deflateEnd(&z);
        }
    }
    uint16_t dosDate, dosTime;
    SNDOSOfDate(date, &dosDate, &dosTime);
    uint32_t offset = (uint32_t)_offset;
    /* The local header, then the file. */
    NSMutableData *header = [NSMutableData data];
    SNWrite32(header, 0x04034b50);
    SNWrite16(header, 20);
    SNWrite16(header, 0x800);
    SNWrite16(header, method);
    SNWrite16(header, dosTime);
    SNWrite16(header, dosDate);
    SNWrite32(header, crc);
    SNWrite32(header, (uint32_t)body.length);
    SNWrite32(header, (uint32_t)data.length);
    SNWrite16(header, (uint16_t)name.length);
    SNWrite16(header, 0);
    [header appendData:name];
    if (![self put:header] || ![self put:body]) return NO;
    /* Its entry in the central directory. */
    SNWrite32(_directory, 0x02014b50);
    SNWrite16(_directory, 20);
    SNWrite16(_directory, 20);
    SNWrite16(_directory, 0x800);
    SNWrite16(_directory, method);
    SNWrite16(_directory, dosTime);
    SNWrite16(_directory, dosDate);
    SNWrite32(_directory, crc);
    SNWrite32(_directory, (uint32_t)body.length);
    SNWrite32(_directory, (uint32_t)data.length);
    SNWrite16(_directory, (uint16_t)name.length);
    SNWrite16(_directory, 0);
    SNWrite16(_directory, 0);
    SNWrite16(_directory, 0);
    SNWrite16(_directory, 0);
    SNWrite32(_directory, 0);
    SNWrite32(_directory, offset);
    [_directory appendData:name];
    _count++;
    return YES;
}

/* The central directory and its end. */
- (NSData *)end {
    NSMutableData *out = [_directory mutableCopy];
    SNWrite32(out, 0x06054b50);
    SNWrite16(out, 0);
    SNWrite16(out, 0);
    SNWrite16(out, _count);
    SNWrite16(out, _count);
    SNWrite32(out, (uint32_t)_directory.length);
    SNWrite32(out, (uint32_t)_offset);
    SNWrite16(out, 0);
    return out;
}

- (NSData *)data {
    NSMutableData *out = [_data mutableCopy] ?: [NSMutableData data];
    [out appendData:[self end]];
    return out;
}

- (BOOL)finish:(NSError **)error {
    BOOL ok = _file && [self put:[self end]];
    @try {
        [_file closeFile];
    } @catch (NSException *e) {
        ok = NO;
    }
    _file = nil;
    if (!ok && error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteOutOfSpaceError
                                               userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"“%@” could not be written.", _url.lastPathComponent] }];
    return ok;
}

@end
