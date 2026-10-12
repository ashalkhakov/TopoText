// The Share extension (SNShareViewController.h).

#import "SNShareViewController.h"
#import "SNShares.h"
#import "SNShareInbox.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@implementation SNShareViewController {
    NSURL *_link;
    NSMutableArray<NSData *> *_images;
    NSMutableArray<NSString *> *_texts;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"SimpleNotes";
    self.placeholder = @"Add to SimpleNotes";
}

- (BOOL)isContentValid {
    return YES;
}

- (NSArray *)configurationItems {
    return @[];
}

/* What was shared, read (each item provider answers in its own time),
   then written to the inbox, and the sheet closed. */
- (void)didSelectPost {
    _images = [NSMutableArray array];
    _texts = [NSMutableArray array];
    dispatch_group_t reading = dispatch_group_create();
    for (NSExtensionItem *item in self.extensionContext.inputItems) {
        for (NSItemProvider *provider in item.attachments) {
            NSString *type = [provider hasItemConformingToTypeIdentifier:UTTypeURL.identifier] ? UTTypeURL.identifier
                           : [provider hasItemConformingToTypeIdentifier:UTTypeImage.identifier] ? UTTypeImage.identifier
                           : [provider hasItemConformingToTypeIdentifier:UTTypePlainText.identifier] ? UTTypePlainText.identifier : nil;
            if (!type) continue;
            dispatch_group_enter(reading);
            [provider loadItemForTypeIdentifier:type options:nil completionHandler:^(id<NSSecureCoding> value, NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self took:(id)value as:type];
                    dispatch_group_leave(reading);
                });
            }];
        }
    }
    dispatch_group_notify(reading, dispatch_get_main_queue(), ^{
        [self writeShare];
    });
}

/* One thing shared: a link (a file's, an image's data), a picture, text. */
- (void)took:(id)value as:(NSString *)type {
    if ([value isKindOfClass:[NSURL class]] && ![value isFileURL]) {
        if (!_link) _link = value;
    } else if ([value isKindOfClass:[NSURL class]]) {
        NSData *data = [NSData dataWithContentsOfURL:value];
        if (data && [type isEqual:UTTypeImage.identifier]) [_images addObject:data];
    } else if ([value isKindOfClass:[UIImage class]]) {
        NSData *jpeg = UIImageJPEGRepresentation(value, 0.9);
        if (jpeg) [_images addObject:jpeg];
    } else if ([value isKindOfClass:[NSData class]] && [type isEqual:UTTypeImage.identifier]) {
        [_images addObject:value];
    } else if ([value isKindOfClass:[NSString class]]) {
        [_texts addObject:value];
    }
}

- (void)writeShare {
    /* The sheet's text (the page's title, the selection, as the app gave
       it, as the user left it); else the text shared. */
    NSString *text = self.contentText.length ? self.contentText : [_texts componentsJoinedByString:@"\n"];
    NSURL *inbox = SNShareAppGroupInbox();
    NSError *error = nil;
    if (!inbox || !SNWriteShare(inbox, nil, text, _link, _images, &error)) {
        [self.extensionContext cancelRequestWithError:error ?: [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:nil]];
        return;
    }
    [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
}

@end
