// Devices nearby, synced with directly (ODataKit's docs/peer-sync.md): this
// device's identity (a certificate named for its replica) and whom it
// trusts; a peer token from the server, which the user's other devices take
// while offline; the notes served to them over TLS and advertised
// (Bonjour, Avahi); the devices found; pairing, for devices with no server
// in common. A port of ODataKit's DVPeers (Examples/Device) over SNNotes.

#pragma once
#import <Foundation/Foundation.h>
#import <ODataSync/ODataSync.h>
#import "SNNotes.h"

NS_ASSUME_NONNULL_BEGIN

@class SNPeers;

// Posted on the main thread when something of the peers changed: a token,
// serving, a device found or lost, a pairing, the status.
FOUNDATION_EXPORT NSNotificationName const SNPeersDidChangeNotification;

// Where peers reach this device.
FOUNDATION_EXPORT const NSUInteger SNPeersPort;

// Whether the notes are served to devices nearby (kept: served again at the
// next launch).
FOUNDATION_EXPORT NSString * const SNServePeersDefaultsKey;   // @"SNServePeers"

@protocol SNPeersDelegate <NSObject>
@optional
// A pairing done (error nil: paired, a sync with it begun) or refused.
- (void)peers:(SNPeers *)peers didPairWithError:(nullable NSError *)error;
@end

// All on the main thread.
@interface SNPeers : NSObject
// Its identity, made the first time (the keychain on Apple's systems, a
// file in directory elsewhere); its pairings and token in directory.
- (nullable instancetype)initWithNotes:(SNNotes *)notes directory:(NSURL *)directory error:(NSError **)error NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@property (nonatomic, readonly) SNNotes *notes;
@property (nonatomic, readonly) ODataSyncPeerTrust *trust;
@property (nonatomic, weak, nullable) id<SNPeersDelegate> delegate;
// What peers are told it is called, and the port it serves them on. Set
// before serving.
@property (nonatomic, copy) NSString *deviceName;
@property (nonatomic) NSUInteger port;
// What happened last, in words.
@property (nonatomic, readonly, copy) NSString *status;

// The token the server issued, and until when; kept across launches.
@property (nonatomic, readonly) BOOL hasToken;
@property (nonatomic, readonly, nullable) NSDate *tokenExpires;
// Asked of the server (signed in), on a thread of its own.
- (void)fetchToken;
@property (nonatomic, readonly, getter=isFetchingToken) BOOL fetchingToken;

// The notes served at https://<address>:<port>/sync/<replica>/ and
// advertised; NO and why not.
- (BOOL)startServing:(NSError **)error;
- (void)stopServing;
@property (nonatomic, readonly, getter=isServing) BOOL serving;
@property (nonatomic, readonly, nullable) NSURL *serviceRoot;
// A pairing offer, as text (JSON) for the other device; nil when not
// serving. Good for two minutes, once; a new one replaces the last.
- (nullable NSString *)newPairingOffer;
// Paired with the device whose offer that is, then synced with it; the
// delegate told.
- (void)pairWithOffer:(NSString *)text;
@property (nonatomic, readonly, getter=isPairing) BOOL pairing;

// Looking for devices nearby.
- (void)startBrowsing;
@property (nonatomic, readonly, copy) NSArray<ODataSyncPeerAnnouncement *> *found;
// A sync with a device found. NO when it would not take this one (no
// token, no pairing), or while a sync runs.
- (BOOL)syncWithPeer:(ODataSyncPeerAnnouncement *)peer;

@property (nonatomic, readonly, copy) NSArray<ODataSyncPeerPairing *> *pairings;
- (nullable ODataSyncPeerPairing *)pairingOfPeer:(ODataSyncPeerAnnouncement *)peer;
- (BOOL)forgetPairing:(ODataSyncPeerPairing *)pairing error:(NSError **)error;

// Not serving, not browsing.
- (void)stop;
@end

// The device's address on the local network (Wi-Fi's, else Ethernet's;
// never cellular or a VPN's), nil when it has none.
FOUNDATION_EXPORT NSString *_Nullable SNLocalAddress(void);

NS_ASSUME_NONNULL_END
