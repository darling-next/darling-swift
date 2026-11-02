//
// Darling's `Foundation` overlay -- the one Objective-C class the Foundation field owes that no
// image in this tree defines.
//
// WHY IT IS DEFINED HERE AT ALL.  Xcode 26.3's VoiceBoxClient.framework (reached through
// ContentDeliveryServices -> AppStoreService) binds _OBJC_CLASS_$_NSURLSessionTaskTransactionMetrics
// strongly and eagerly from its Foundation ordinal: chained import[537], lib_ordinal 2
// (Foundation), weak_import 0, bound at __DATA,__objc_classrefs 0x546B8.  The deployed
// Foundation.framework exports no such class and neither does the deployed CFNetwork.framework, so
// the loader aborts on it once Foundation's appendingFormat(_:_:) resolves.  The tree's proper homes
// are src/external/foundation (whose src/external/foundation/reexport_x86_64.exp:127 and :169 list
// the class commented out, because nothing defines it) and src/external/cfnetwork (whose
// src/external/cfnetwork/src/URL/CFNSURLConnection.m:3 defines only the sibling
// NSURLSessionTaskMetrics); both trees are off limits to this wave.  The overlay is the image
// Foundation.framework re-exports as an ordinal (the deployed binary's LC_REEXPORT_DYLIB names
// /usr/lib/swift/libswiftFoundation.dylib), so a class defined here IS reachable under Foundation's
// ordinal -- the same route overlays/Foundation/NSURLErrorConstants.m uses for
// this family. Native task classes are reexported by Foundation from CFNetwork.
//
// THE DECLARATION IS APPLE'S.  Guest SDK, Foundation.framework/Headers/NSURLSession.h:1283
// (`API_AVAILABLE(macosx(10.12), ...) @interface NSURLSessionTaskTransactionMetrics : NSObject`).
// The interface below repeats the class and its superclass and nothing else.
//
// WHY AN EMPTY CLASS IS THE WHOLE ANSWER (measured on the x86_64 slice).  VoiceBoxClient has exactly
// one reference to the class -- the lazy type-metadata accessor at 0x1E010, whose only classref use
// is 0x1E023 (`movq <0x546B8>,%rdi; callq _objc_opt_self; callq _swift_getObjCClassMetadata`).  The
// accessor is called once, at 0x1DC22, and its result is handed straight to
// `Array<NSURLSessionTaskTransactionMetrics>._unconditionallyBridgeFromObjectiveC` (stub 0x3FB8E ->
// GOT 0x4E3A8) applied to the NSArray returned by -[NSURLSessionTaskMetrics transactionMetrics]
// (selector from the selref at 0x54230, objc_msgSend at 0x1DC10).  So the client needs the class
// OBJECT as the element type of an array bridge; it never allocates the class, and no image in the
// load closure binds the metaclass or sends this class a message.  Nothing in this tree can produce
// an instance either: the tree's -[NSURLSessionTaskMetrics transactionMetrics] is the forwarding
// stub in CFNSURLConnection.m, so the bridged array is empty.  An empty class therefore states the
// truth; a property implemented to return an invented snapshot would not, and every operation on a
// real instance fails observably (unrecognized selector) rather than producing a plausible wrong
// value.

#import <Foundation/NSObject.h>

@interface NSURLSessionTaskTransactionMetrics : NSObject
@end

@implementation NSURLSessionTaskTransactionMetrics
@end
