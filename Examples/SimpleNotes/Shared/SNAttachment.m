#import "SNAttachment.h"

NSString * const SNAttachmentKindImage = @"image";
NSString * const SNAttachmentKindTable = @"table";
NSString * const SNAttachmentKindFile = @"file";
NSString * const SNTableType = @"application/x-topotext-table";

const NSUInteger SNAttachmentMaxFileBytes = 25 * 1024 * 1024;

NSString *SNTypeOfFileNamed(NSString *name) {
    static NSDictionary *types;
    if (!types)
        types = @{ @"pdf": @"application/pdf", @"txt": @"text/plain", @"md": @"text/markdown", @"csv": @"text/csv",
                   @"html": @"text/html", @"htm": @"text/html", @"rtf": @"application/rtf", @"json": @"application/json",
                   @"xml": @"application/xml", @"zip": @"application/zip", @"gz": @"application/gzip",
                   @"doc": @"application/msword",
                   @"docx": @"application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                   @"xls": @"application/vnd.ms-excel",
                   @"xlsx": @"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                   @"ppt": @"application/vnd.ms-powerpoint",
                   @"pptx": @"application/vnd.openxmlformats-officedocument.presentationml.presentation",
                   @"odt": @"application/vnd.oasis.opendocument.text", @"ods": @"application/vnd.oasis.opendocument.spreadsheet",
                   @"pages": @"application/vnd.apple.pages", @"numbers": @"application/vnd.apple.numbers",
                   @"key": @"application/vnd.apple.keynote", @"mp3": @"audio/mpeg", @"m4a": @"audio/mp4",
                   @"wav": @"audio/wav", @"mp4": @"video/mp4", @"mov": @"video/quicktime", @"png": @"image/png",
                   @"jpg": @"image/jpeg", @"jpeg": @"image/jpeg", @"gif": @"image/gif", @"heic": @"image/heic",
                   @"svg": @"image/svg+xml" };
    return types[name.pathExtension.lowercaseString] ?: @"application/octet-stream";
}

NSString *SNFileDescription(NSString *name, NSUInteger bytes) {
    NSString *ext = name.pathExtension.uppercaseString;
    NSString *size;
    if (bytes < 1024) size = [NSString stringWithFormat:@"%lu bytes", (unsigned long)bytes];
    else if (bytes < 1024 * 1024) size = [NSString stringWithFormat:@"%.0f KB", bytes / 1024.0];
    else size = [NSString stringWithFormat:@"%.1f MB", bytes / (1024.0 * 1024.0)];
    return ext.length ? [NSString stringWithFormat:@"%@ · %@", ext, size] : size;
}

@implementation SNAttachment
@end
