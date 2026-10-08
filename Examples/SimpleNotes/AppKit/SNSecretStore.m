// SNSecretStore on AppKit: the Keychain on macOS; on GNUstep, which has
// none, a property list only the user can read (0600), in the app's
// Application Support.

#import "SNSignIn.h"
#ifndef GNUSTEP
#import <Security/Security.h>
#endif

@implementation SNSecretStore

#ifdef GNUSTEP

- (NSString *)path {
    NSString *support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    NSString *dir = [support stringByAppendingPathComponent:@"SimpleNotes"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES
                                               attributes:@{ NSFilePosixPermissions: @0700 } error:NULL];
    return [dir stringByAppendingPathComponent:@"SignIn.plist"];
}

/* Read by NSPropertyListSerialization, not +dictionaryWithContentsOfFile:,
   which on GNUstep takes a binary property list for text and gives nil:
   the tokens were written, and never read back. */
- (NSDictionary *)all {
    NSData *data = [NSData dataWithContentsOfFile:[self path]];
    id all = data.length ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL] : nil;
    return [all isKindOfClass:[NSDictionary class]] ? all : @{};
}

- (NSDictionary *)secretsForAccount:(NSString *)account {
    id mine = [self all][account];
    return [mine isKindOfClass:[NSDictionary class]] ? mine : nil;
}

- (BOOL)setSecrets:(NSDictionary *)secrets forAccount:(NSString *)account {
    NSString *path = [self path];
    NSMutableDictionary *all = [[self all] mutableCopy];
    if (secrets) all[account] = secrets;
    else [all removeObjectForKey:account];
    /* Made unreadable to others before anything is written into it. */
    if (![[NSFileManager defaultManager] fileExistsAtPath:path])
        [[NSFileManager defaultManager] createFileAtPath:path contents:[NSData data] attributes:@{ NSFilePosixPermissions: @0600 }];
    [[NSFileManager defaultManager] setAttributes:@{ NSFilePosixPermissions: @0600 } ofItemAtPath:path error:NULL];
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:all format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL];
    return data && [data writeToFile:path options:0 error:NULL];
}

#else

static NSDictionary *SNKeychainQuery(NSString *account) {
    return @{ (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword, (__bridge id)kSecAttrService: @"SimpleNotes sign-in",
              (__bridge id)kSecAttrAccount: account };
}

- (NSDictionary *)secretsForAccount:(NSString *)account {
    NSMutableDictionary *q = [SNKeychainQuery(account) mutableCopy];
    q[(__bridge id)kSecReturnData] = @YES;
    q[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef found = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)q, &found) != errSecSuccess || !found) return nil;
    NSData *data = (__bridge_transfer NSData *)found;
    id plist = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL];
    return [plist isKindOfClass:[NSDictionary class]] ? plist : nil;
}

- (BOOL)setSecrets:(NSDictionary *)secrets forAccount:(NSString *)account {
    NSDictionary *q = SNKeychainQuery(account);
    SecItemDelete((__bridge CFDictionaryRef)q);
    if (!secrets) return YES;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:secrets format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
    NSMutableDictionary *item = [q mutableCopy];
    item[(__bridge id)kSecValueData] = data;
    return SecItemAdd((__bridge CFDictionaryRef)item, NULL) == errSecSuccess;
}

#endif

@end
