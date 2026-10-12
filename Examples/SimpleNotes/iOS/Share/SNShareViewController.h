// SimpleNotes' Share extension: what another app shares (its text, a web
// page's link and title, pictures) written into the inbox the app and the
// extension share (SNShares.h), which the app makes notes of as it opens
// or comes back. The system's compose sheet: the text can be changed
// first.

#import <UIKit/UIKit.h>
#import <Social/Social.h>

@interface SNShareViewController : SLComposeServiceViewController
@end
