// A menu's item as target-action: its action sent to a target, or (nil) to
// the first responder and on up its responder chain.
//
// Not a UICommand: a command finds its target up the chain of the view its
// menu is shown from, and a bar over the keyboard (an input accessory view)
// is in the keyboard's window, whose chain has none of the app's views or
// controllers in it. A command there found its target only when UIKit
// happened to look from the text view instead; otherwise it was left out,
// and the menu did not open.

#pragma once
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT UIAction *SNMenuAction(NSString *title, UIImage * _Nullable image, SEL action, id _Nullable target);

NS_ASSUME_NONNULL_END
