#import "SNPeers.h"
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
// iphlpapi.h reaches COM's headers (through ras.h), which use the macro
// interface that gnustep-base undefines for Objective-C's @interface:
// defined here as Windows' own headers define it, for them alone.
#define interface struct
#include <iphlpapi.h>
#undef interface
#include <stdlib.h>

/* SNLocalAddress (SNPeers.h) on Windows: its adapters, by their kind, not
   their names (which are the user's). Only an adapter with a gateway: so
   not a virtual switch's (WSL's, Hyper-V's), nor one that leads nowhere. */
NSString *SNLocalAddress(void) {
    ULONG length = 16 * 1024;
    IP_ADAPTER_ADDRESSES *adapters = NULL;
    ULONG result = ERROR_BUFFER_OVERFLOW;
    for (int attempt = 0; attempt < 3 && result == ERROR_BUFFER_OVERFLOW; attempt++) {
        free(adapters);
        adapters = malloc(length);
        if (!adapters) return nil;
        result = GetAdaptersAddresses(AF_INET, GAA_FLAG_INCLUDE_GATEWAYS | GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_SKIP_DNS_SERVER,
                                      NULL, adapters, &length);
    }
    NSString *found = nil, *other = nil;
    for (IP_ADAPTER_ADDRESSES *adapter = result == NO_ERROR ? adapters : NULL; adapter && !found; adapter = adapter->Next) {
        if (adapter->OperStatus != IfOperStatusUp || !adapter->FirstGatewayAddress || !adapter->FirstUnicastAddress) continue;
        BOOL wifi = adapter->IfType == IF_TYPE_IEEE80211;
        if (!wifi && adapter->IfType != IF_TYPE_ETHERNET_CSMACD) continue;
        char text[INET_ADDRSTRLEN];
        struct sockaddr_in *address = (struct sockaddr_in *)adapter->FirstUnicastAddress->Address.lpSockaddr;
        if (!inet_ntop(AF_INET, &address->sin_addr, text, sizeof text)) continue;
        if (wifi) found = @(text);
        else if (!other) other = @(text);
    }
    free(adapters);
    return found ?: other;
}
