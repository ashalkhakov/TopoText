// SNSecretStore on iOS: the Keychain, this device only.

#import "SNSignIn.h"
#import <Security/Security.h>

@implementation SNSecretStore

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
    item[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
    return SecItemAdd((__bridge CFDictionaryRef)item, NULL) == errSecSuccess;
}

@end
