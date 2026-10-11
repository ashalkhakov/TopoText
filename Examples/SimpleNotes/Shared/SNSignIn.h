// Signing in to a SimpleNotes server: ODataSync's ODataSignIn (as the
// server's $metadata says: nothing, a user and password, or OpenID Connect
// by the device flow), as SimpleNotes's identity provider client
// ("simplenotes"), its tokens kept where SimpleNotes has always kept them
// (SNSecretStore: the Keychain's "SimpleNotes sign-in", on GNUstep
// Application Support/SimpleNotes/SignIn.plist), so that nobody is signed
// out by the update that moved the sign-in to ODataSync.

#pragma once
#import <Foundation/Foundation.h>
#import <ODataSync/ODataSync.h>

NS_ASSUME_NONNULL_BEGIN

// Each system's (AppKit/, iOS/SNSecretStore.m).
@interface SNSecretStore : NSObject <ODataSecretStoring>
@end

// The identity provider's client SimpleNotes signs in as: a public client
// with the device flow on (Keycloak: OAuth 2.0 Device Authorization Grant).
FOUNDATION_EXPORT NSString * const SNSignInClientID;   // @"simplenotes"

// A sign-in to the server at serviceRoot, as SimpleNotes's client, its
// tokens in secrets.
FOUNDATION_EXPORT ODataSignIn *SNSignInTo(NSURL *serviceRoot, id<ODataSecretStoring> secrets);

NS_ASSUME_NONNULL_END
