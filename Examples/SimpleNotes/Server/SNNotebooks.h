// A notebook per user, at the server: every folder, note and attachment
// has an owner (Folder.owner, ...; model version 6), the signed-in user's
// subject (the principal's, HSPrincipal), kept at the server and never
// sent (OData.served NO). Each user reads and writes their own rows only:
// fetched, by key, through navigation, in a delta (a deletion is told to
// its owner only: the owner is kept in its tombstone). A row a write makes
// is the writer's.
//
// Who the user is, is the sign-in's: a proxy that signs users in
// (TrustedUserHeader), or an identity provider's access token (JWTIssuer:
// Keycloak, Authentik, ...). An anonymous request (AllowAnonymous) has the
// rows no one owns.

#pragma once
#import <ODataSync/ODataSyncService.h>

NS_ASSUME_NONNULL_BEGIN

// A set's handler that keeps each user to their own rows.
@interface SNNotebookHandler : ODataSyncSetHandler
@end

// Each set of an entity with an owner served so; before ODataSyncService
// is made (it keeps a handler that is already an ODataSyncSetHandler).
FOUNDATION_EXPORT void SNServeNotebookPerUser(ODataService *service);
// The rows no one owns (made before notebooks were per user), given to
// owner; how many.
FOUNDATION_EXPORT NSUInteger SNGiveUnownedRows(NSPersistentStoreCoordinator *coordinator, NSString *owner, NSError **error);

// Peer tokens (ODataKit's docs/peer-sync.md): a signed-in device asks for
// one (PeerToken), and the user's devices nearby sync with each other by
// them while offline. The signing key, a JWK in file (made, 0600, the first
// time; kept: a new key makes every token issued before worthless).
FOUNDATION_EXPORT NSDictionary *_Nullable SNPeerSigningKeyAt(NSURL *file, NSError **error);
// Issued by histories (the PeerToken action), named for the service root.
FOUNDATION_EXPORT void SNIssuePeerTokens(ODataSyncService *histories, NSDictionary *signingKey);

NS_ASSUME_NONNULL_END
