#import "SNPeers.h"
#import <ifaddrs.h>
#import <arpa/inet.h>
#import <net/if.h>

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
