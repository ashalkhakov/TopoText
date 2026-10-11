#import "SNSignIn.h"

NSString * const SNSignInClientID = @"simplenotes";

ODataSignIn *SNSignInTo(NSURL *serviceRoot, id<ODataSecretStoring> secrets) {
    ODataSignIn *signIn = [[ODataSignIn alloc] initWithServiceRoot:serviceRoot secrets:secrets];
    signIn.clientID = SNSignInClientID;
    return signIn;
}
