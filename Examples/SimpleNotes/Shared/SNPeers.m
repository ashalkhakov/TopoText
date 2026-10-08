#import "SNPeers.h"
#import <ifaddrs.h>
#import <arpa/inet.h>
#import <net/if.h>

NSNotificationName const SNPeersDidChangeNotification = @"SNPeersDidChange";
const NSUInteger SNPeersPort = 8642;
NSString * const SNServePeersDefaultsKey = @"SNServePeers";

/* Whom a paired device syncs as here. */
static NSString * const SNPeerSubject = @"peer";

/* A local network's interface, by its name: Ethernet and Wi-Fi as Apple's
   systems and Linux name them, bridges; not cellular (pdp_ip*), a VPN's
   (utun*, tun*, ppp*), nor a container's. */
static BOOL SNIsLocalInterface(const char *name) {
    const char *prefixes[] = { "en", "eth", "wl", "bridge", NULL };
    for (int i = 0; prefixes[i]; i++)
        if (strncmp(name, prefixes[i], strlen(prefixes[i])) == 0) return YES;
    return NO;
}

NSString *SNLocalAddress(void) {
    struct ifaddrs *interfaces = NULL;
    if (getifaddrs(&interfaces) != 0) return nil;
    NSString *found = nil, *other = nil;
    for (struct ifaddrs *at = interfaces; at; at = at->ifa_next) {
        if (!at->ifa_addr || at->ifa_addr->sa_family != AF_INET) continue;
        if (!(at->ifa_flags & IFF_UP) || (at->ifa_flags & IFF_LOOPBACK)) continue;
        char text[INET_ADDRSTRLEN];
        if (!inet_ntop(AF_INET, &((struct sockaddr_in *)at->ifa_addr)->sin_addr, text, sizeof text)) continue;
        NSString *address = @(text);
        if (strcmp(at->ifa_name, "en0") == 0) {
            found = address;
            break;
        }
        if (!other && SNIsLocalInterface(at->ifa_name)) other = address;
    }
    freeifaddrs(interfaces);
    return found ?: other;
}

@interface SNPeers () <ODataSyncPeerBrowserDelegate>
@end

@implementation SNPeers {
    NSURL *_directory;
    NSTimer *_expiry;
    ODataSyncPeerServer *_server;
    ODataSyncPeerAdvertiser *_advertiser;
    ODataSyncPeerBrowser *_browser;
}

- (instancetype)initWithNotes:(SNNotes *)notes directory:(NSURL *)directory error:(NSError **)error {
    if (!(self = [super init])) return nil;
    _notes = notes;
    _directory = [directory copy];
    _deviceName = [NSProcessInfo processInfo].hostName;
    _port = SNPeersPort;
    _status = @"";
    [[NSFileManager defaultManager] createDirectoryAtURL:directory withIntermediateDirectories:YES
                                              attributes:@{ NSFilePosixPermissions: @0700 } error:NULL];
    ODataSyncPeerIdentity *identity = [ODataSyncPeerIdentity identityNamed:notes.engine.replicaID
                                                                 directory:[directory URLByAppendingPathComponent:@"Identity" isDirectory:YES]
                                                                     error:error];
    if (!identity) return nil;
    _trust = [[ODataSyncPeerTrust alloc] initWithIdentity:identity pairingsURL:[self fileNamed:@"Pairings"]];
    NSData *data = [NSData dataWithContentsOfURL:[self fileNamed:@"PeerToken"]];
    NSDictionary *answer = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    if ([answer isKindOfClass:[NSDictionary class]]) [_trust takePeerTokenAnswer:answer error:NULL];
    [self watchExpiry];
    return self;
}

- (void)dealloc {
    [self stop];
}

/* <name>-<replica>.json: another store's are its own. */
- (NSURL *)fileNamed:(NSString *)name {
    return [_directory URLByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@.json", name, _notes.engine.replicaID]];
}

- (void)say:(NSString *)status {
    _status = [status copy];
    [self changed];
}

- (void)changed {
    [[NSNotificationCenter defaultCenter] postNotificationName:SNPeersDidChangeNotification object:self];
}

#pragma mark the token

- (BOOL)hasToken {
    NSDate *expires = _trust.tokenExpires;
    return _trust.token != nil && (!expires || expires.timeIntervalSinceNow > 0);
}

- (NSDate *)tokenExpires {
    return _trust.tokenExpires;
}

/* Told when it runs out. */
- (void)watchExpiry {
    [_expiry invalidate];
    _expiry = nil;
    NSTimeInterval left = self.tokenExpires.timeIntervalSinceNow;
    if (!_trust.token || left <= 0) return;
    _expiry = [NSTimer scheduledTimerWithTimeInterval:left + 1 target:self selector:@selector(tokenExpired:) userInfo:nil repeats:NO];
}

- (void)tokenExpired:(NSTimer *)timer {
    _expiry = nil;
    [self say:@"The peer token ran out: get a new one while the server is reachable."];
}

- (void)fetchToken {
    if (_fetchingToken) return;
    ODataSyncRemote *remote = _notes.serverRemote;
    if (!remote) {
        [self say:@"No server to ask for a peer token: sync with one first (Sync…)."];
        return;
    }
    _fetchingToken = YES;
    [self say:@"Asking the server for a peer token…"];
    ODataSyncEngine *engine = _notes.engine;
    ODataSyncPeerTrust *trust = _trust;
    NSString *thumbprint = trust.identity.thumbprint;
    NSURL *file = [self fileNamed:@"PeerToken"];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        NSError *error = nil;
        NSDictionary *answer = [engine peerTokenFromRemote:remote thumbprint:thumbprint error:&error];
        BOOL ok = answer && [trust takePeerTokenAnswer:answer error:&error];
        if (ok) {
            /* Kept: peers are met without the server until it runs out;
               the user's alone. */
            NSData *data = [NSJSONSerialization dataWithJSONObject:answer options:0 error:NULL];
            if ([[NSFileManager defaultManager] createFileAtPath:file.path contents:nil attributes:@{ NSFilePosixPermissions: @0600 }])
                [data writeToURL:file atomically:NO];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self tokenFetched:ok error:error];
        });
    });
}

- (void)tokenFetched:(BOOL)ok error:(NSError *)error {
    _fetchingToken = NO;
    [self watchExpiry];
    if (!ok) {
        [self say:[NSString stringWithFormat:@"No peer token: %@", error.localizedDescription ?: @"no answer."]];
        return;
    }
    [self say:[NSString stringWithFormat:@"A peer token until %@: your devices nearby sync with this one.",
                                         [NSDateFormatter localizedStringFromDate:self.tokenExpires ?: [NSDate distantFuture]
                                                                        dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle]]];
}

#pragma mark serving

- (BOOL)isServing {
    return _server.running;
}

- (NSURL *)serviceRoot {
    return _server.running ? _server.serviceRoot : nil;
}

- (BOOL)startServing:(NSError **)error {
    if (_server.running) return YES;
    NSString *host = SNLocalAddress();
    if (!host) {
        if (error) *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet
                                            userInfo:@{ NSLocalizedDescriptionKey: @"This device is on no local network." }];
        return NO;
    }
    ODataSyncPeerServer *server = [[ODataSyncPeerServer alloc] initWithEngine:_notes.engine trust:_trust host:host port:_port];
    if (![server start:error]) return NO;
    ODataSyncPeerAdvertiser *advertiser = [[ODataSyncPeerAdvertiser alloc] initWithServer:server name:_deviceName];
    /* The advertiser says it failed by a block only (its API). */
    __weak SNPeers *weak = self;
    advertiser.didFail = ^(NSError *failure) {
        [weak say:[NSString stringWithFormat:@"Not seen nearby: %@", failure.localizedDescription]];
    };
    if (![advertiser start:error]) {
        [server stop];
        return NO;
    }
    _server = server;
    _advertiser = advertiser;
    [self say:@"Your notes are served to your devices nearby."];
    return YES;
}

- (void)stopServing {
    if (!_server) return;
    [_advertiser stop];
    [_server stop];
    _advertiser = nil;
    _server = nil;
    [self say:@"No longer served to devices nearby."];
}

- (NSString *)newPairingOffer {
    if (!_server.running) return nil;
    NSDictionary *offer = [_server pairingOfferForSubject:SNPeerSubject scopes:[NSSet set]];
    NSData *data = [NSJSONSerialization dataWithJSONObject:offer options:0 error:NULL];
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
}

- (void)pairWithOffer:(NSString *)text {
    NSData *data = [[text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *offer = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    if (![offer isKindOfClass:[NSDictionary class]]) {
        [self paired:nil error:[NSError errorWithDomain:NSCocoaErrorDomain code:NSPropertyListReadCorruptError
                                               userInfo:@{ NSLocalizedDescriptionKey: @"That is not a pairing code: the other device shows one under Devices Nearby, Show Pairing Code." }]];
        return;
    }
    _pairing = YES;
    [self say:@"Pairing…"];
    ODataSyncPeerTrust *trust = _trust;
    NSString *replica = _notes.engine.replicaID, *name = _deviceName;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        NSError *error = nil;
        ODataSyncPeerTransport *transport = [ODataSyncPeerTransport transportPairingWithOffer:offer trust:trust replica:replica name:name
                                                                                     subject:SNPeerSubject scopes:[NSSet set] error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self paired:transport error:error];
        });
    });
}

- (void)paired:(ODataSyncPeerTransport *)transport error:(NSError *)error {
    _pairing = NO;
    if (transport) {
        [self say:@"Paired."];
        /* Met at once: the transport knows it already. */
        ODataSyncRemote *remote = [ODataSyncRemote peerWithServiceRoot:transport.serviceRoot];
        remote.transport = transport;
        [_notes syncWithRemote:remote named:@"the device paired"];
    } else {
        [self say:[NSString stringWithFormat:@"Not paired: %@", error.localizedDescription]];
    }
    id<SNPeersDelegate> delegate = _delegate;
    if ([delegate respondsToSelector:@selector(peers:didPairWithError:)]) [delegate peers:self didPairWithError:transport ? nil : error];
}

#pragma mark browsing

- (void)startBrowsing {
    if (_browser) return;
    ODataSyncPeerBrowser *browser = [[ODataSyncPeerBrowser alloc] initWithReplica:_notes.engine.replicaID];
    browser.delegate = self;
    NSError *error = nil;
    if (![browser start:&error]) {
        [self say:[NSString stringWithFormat:@"Not looking for devices nearby: %@", error.localizedDescription]];
        return;
    }
    _browser = browser;
}

- (NSArray *)found {
    return _browser.peers ?: @[];
}

- (void)peerBrowser:(ODataSyncPeerBrowser *)browser didFindPeer:(ODataSyncPeerAnnouncement *)peer {
    [self changed];
}

- (void)peerBrowser:(ODataSyncPeerBrowser *)browser didLosePeer:(ODataSyncPeerAnnouncement *)peer {
    [self changed];
}

- (void)peerBrowser:(ODataSyncPeerBrowser *)browser didFailWithError:(NSError *)error {
    [_browser stop];
    _browser = nil;
    [self say:[NSString stringWithFormat:@"No longer looking for devices nearby: %@", error.localizedDescription]];
}

- (BOOL)syncWithPeer:(ODataSyncPeerAnnouncement *)peer {
    /* Neither would take the other: said so, not a TLS error. */
    if (!self.hasToken && ![self pairingOfPeer:peer]) {
        [self say:[NSString stringWithFormat:@"Not synced with %@: get a peer token, or pair with it, first.", peer.name]];
        return NO;
    }
    ODataSyncRemote *remote = [ODataSyncRemote peerWithServiceRoot:peer.serviceRoot];
    ODataSyncPeerTransport *transport = [[ODataSyncPeerTransport alloc] initWithServiceRoot:peer.serviceRoot trust:_trust];
    /* The certificate it advertised, and no other. */
    transport.expectedThumbprint = peer.thumbprint;
    remote.transport = transport;
    return [_notes syncWithRemote:remote named:peer.name];
}

#pragma mark pairings

- (NSArray *)pairings {
    return _trust.pairings;
}

- (ODataSyncPeerPairing *)pairingOfPeer:(ODataSyncPeerAnnouncement *)peer {
    return [_trust pairingWithThumbprint:peer.thumbprint];
}

- (BOOL)forgetPairing:(ODataSyncPeerPairing *)pairing error:(NSError **)error {
    BOOL ok = [_trust forgetPairingWithThumbprint:pairing.thumbprint error:error];
    [self changed];
    return ok;
}

#pragma mark done

- (void)stop {
    [_expiry invalidate];
    _expiry = nil;
    [_advertiser stop];
    [_server stop];
    [_browser stop];
    _advertiser = nil;
    _server = nil;
    _browser = nil;
}

@end
