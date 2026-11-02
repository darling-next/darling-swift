//
// Darling's `Foundation` overlay -- Foundation-framework C globals the tree does not define.
//
// WHY AN OBJECTIVE-C FILE IS HERE AT ALL.  Xcode 26.3's
// Contents/SharedFrameworks/ContentDelivery.framework binds _NSURLErrorBackgroundTaskCancelledReasonKey
// from its Foundation ordinal and does not merely call it: the x86_64 slice loads the symbol's slot
// and dereferences the pointer it holds (0x4088f `movq <got>, %rax`; 0x40896 `movq (%rax), %rdx`;
// 0x408a0 `-[NSDictionary objectForKeyedSubscript:]`), so the symbol has to be an `NSString * const`
// whose content is a valid object the moment the image is bound.  A Swift declaration cannot be that:
// a Swift global of class type is initialized lazily, and a client that reads the storage directly
// instead of through the accessor would read NULL.
//
// WHY IT IS NOT IN THE TREE'S OWN Foundation.  That is where it belongs, and where its five siblings
// are: src/external/foundation/src/NSURLError.m defines NSURLErrorDomain,
// NSURLErrorFailingURLErrorKey, NSURLErrorFailingURLStringErrorKey, NSErrorFailingURLStringKey and
// NSURLErrorFailingURLPeerTrustErrorKey as `NSString *const X = @"X";`, declared in
// src/external/foundation/include/Foundation/NSURLError.h.  This key was never added there, and that
// tree is off limits to this wave.  The overlay is the image Foundation.framework re-exports as an
// ordinal (src/external/foundation/CMakeLists.txt appends -reexport_library for
// libswiftFoundation.dylib), so a symbol defined here IS reachable under Foundation's ordinal, which
// is exactly how this client binds it.
//
// THE VALUE is Apple's own, from open source this tree already carries:
// swift-corelibs-foundation/Sources/Foundation/NSURLError.swift:37,
// `public let NSURLErrorBackgroundTaskCancelledReasonKey: String = "NSURLErrorBackgroundTaskCancelledReasonKey"`.
// The symbol's spelling and kind come from the guest SDK's own export list (Foundation.tbd) and its
// declaration, Foundation/Versions/C/Headers/NSURLError.h:62
// (`FOUNDATION_EXPORT NSString * const NSURLErrorBackgroundTaskCancelledReasonKey`).

#import <Foundation/NSString.h>
#import <Foundation/NSObjCRuntime.h>

// Stated here because the tree's NSURLError.h carries the other five keys and not this one; the
// declaration and the definition are the same object.
FOUNDATION_EXPORT NSString * const NSURLErrorBackgroundTaskCancelledReasonKey;

NSString * const NSURLErrorBackgroundTaskCancelledReasonKey = @"NSURLErrorBackgroundTaskCancelledReasonKey";
