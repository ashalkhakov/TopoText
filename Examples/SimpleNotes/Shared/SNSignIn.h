// Signing in to a SimpleNotes server, as its $metadata says to
// (Authorization vocabulary): with nothing (a server for one household),
// a user and password (a proxy that asks for them), or OpenID Connect
// (Keycloak, Authentik, ...), by the OAuth device flow (RFC 8628): the app
// shows a short code and a page, the user signs in there in any browser,
// on any device, and the app is given tokens. The same on macOS, GNUstep
// and iOS, with no browser of its own. Tokens are kept in an SNSecretStore
// (the Keychain; on GNUstep a file only the user can read), the access
// token refreshed when it runs out.
//
// The identity provider's client: clientID ("simplenotes" by default), a
// public client with the device flow on (Keycloak: OAuth 2.0 Device
// Authorization Grant).

#pragma once
#import <Foundation/Foundation.h>
#import <ODataIncrementalStore/ODataConfiguration.h>

@class SNSignIn;

NS_ASSUME_NONNULL_BEGIN

// Where a sign-in's tokens are kept: by account (the server's address).
@protocol SNSecretStoring <NSObject>
- (nullable NSDictionary<NSString *, id> *)secretsForAccount:(NSString *)account;
- (BOOL)setSecrets:(nullable NSDictionary<NSString *, id> *)secrets forAccount:(NSString *)account;
@end

// Each system's (AppKit/, iOS/SNSecretStore.m).
@interface SNSecretStore : NSObject <SNSecretStoring>
@end

typedef NS_ENUM(NSInteger, SNSignInKind) {
    SNSignInUnknown,     // not asked yet
    SNSignInNone,        // the server asks for no one
    SNSignInPassword,    // a user and password (Http basic)
    SNSignInOpenID,      // OpenID Connect: the device flow
};

@protocol SNSignInDelegate <NSObject>
@optional
// What the server asks for, learnt (-learn).
- (void)signInDidLearn:(SNSignIn *)signIn;
// The user to open page (page with the code in it: completePage) and enter
// code. Until -signInDidFinish:, -signIn:didFail:, or -cancel.
- (void)signIn:(SNSignIn *)signIn showCode:(NSString *)code page:(NSURL *)page completePage:(nullable NSURL *)completePage;
- (void)signInDidFinish:(SNSignIn *)signIn;
- (void)signIn:(SNSignIn *)signIn didFail:(NSError *)error;
@end

@interface SNSignIn : NSObject <ODataCredentialProviding>
- (instancetype)initWithServiceRoot:(NSURL *)serviceRoot secrets:(id<SNSecretStoring>)secrets NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@property (nonatomic, readonly, copy) NSURL *serviceRoot;
@property (nonatomic, copy) NSString *clientID;
@property (nonatomic, weak, nullable) id<SNSignInDelegate> delegate;

// What the server asks for, from its $metadata; the delegate told.
- (void)learn;
@property (nonatomic, readonly) SNSignInKind kind;
@property (nonatomic, readonly, copy, nullable) NSURL *issuer;

// OpenID Connect: the device flow begun; a user and password: kept.
- (void)begin;
- (void)signInWithUser:(NSString *)user password:(NSString *)password;
- (void)cancel;
// The tokens (or password) forgotten.
- (void)signOut;
@property (nonatomic, readonly, getter=isSignedIn) BOOL signedIn;
// Who: preferred_username (or the subject), from the tokens.
@property (nonatomic, readonly, copy, nullable) NSString *userName;

// The configuration a sync uses: its credentials this sign-in's.
- (ODataConfiguration *)configuration;

// How it asks: overridden by tests, to answer as a server would. On any
// thread; done once.
- (void)send:(NSURLRequest *)request done:(void (^)(NSData *_Nullable data, NSHTTPURLResponse *_Nullable response, NSError *_Nullable error))done;
@end

FOUNDATION_EXPORT NSString * const SNSignInErrorDomain;

// PKCE's S256 challenge of a verifier (RFC 7636): sent with the device
// flow, which some providers ask for (Keycloak, with PKCE set on the client).
FOUNDATION_EXPORT NSString *SNChallengeOfVerifier(NSString *verifier);

NS_ASSUME_NONNULL_END
