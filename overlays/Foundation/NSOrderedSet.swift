//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

// Darling: NSOrderedSet's conformance to Sequence -- Apple declares it in module Foundation and
// carries it in the release/5.4 overlay file this tree reduced to `Set.swift`, where only the
// Swift.Set bridging survived.
//
// WHY THIS DECLARATION EXISTS (the rung that needed it). Xcode 26.3's
// Contents/SharedFrameworks/DVTFoundation.framework binds, eagerly and strongly,
//
//     _$sSo12NSOrderedSetC10FoundationE12makeIteratorAC017NSFastEnumerationE0VyF
//       == (extension in Foundation): __C.NSOrderedSet.makeIterator() -> Foundation.NSFastEnumerationIterator
//
// against its Foundation ordinal, and the deployed /usr/lib/swift/libswiftFoundation.dylib exported
// no NSOrderedSet Swift symbol at all, so an image in this closure stops with
// `Symbol not found: _...makeIterator...` / `Expected in: .../Foundation.framework/...` once the
// earlier names of the same rung are supplied (measured stop for this rung's first name:
// `_$sSS10FoundationE5bytes8encodingSSSgxh_SSAAE8EncodingVtcSTRzs5UInt8V7ElementRtzlufC`,
// DVTFoundation, 2026-10-12). "Expected in: .../Foundation.framework/..." is the ordinal's blame
// text, not the file that must change: Darling's Foundation.framework is the Objective-C framework,
// it re-exports /usr/lib/swift/libswiftFoundation.dylib, and this module is that dylib.
//
// WHY THE LITERAL CONFORMANCE IS IN THIS FILE TOO (the later rung that needed it). The same class's
// `ExpressibleByArrayLiteral` conformance is demanded, eagerly and strongly (chained-fixups
// imports[1666], lib_ordinal 27 = Foundation, weak_import = 0), by
//
//     _$sSo12NSOrderedSetC10FoundationE12arrayLiteralABypd_tcfC
//       == (extension in Foundation): __C.NSOrderedSet.init(arrayLiteral: Any...)
//
// in Contents/Frameworks/IDEFoundation.framework/Versions/A/IDEFoundation. It is the NSOrderedSet
// sibling of the `NSSet.init(arrayLiteral:)` the NSSet/readToEnd rung added to NSSet.swift, one class
// over in the same in-tree source, and it is added here rather than there because this file is the
// NSOrderedSet file (that rung reported it by name and deliberately left it).
//
// WHAT THE CLIENT DOES WITH IT, MEASURED. At IDEFoundation 0x72e3fd (the one call site: a scan of the
// x86_64 slice for the symbol's stub finds exactly one `callq`), inside
// `IDEFoundation.SigningEditorMainProvisionable.init`, the argument is the literal's `[Any]` buffer
// (`__swiftEmptyArrayStorage` loaded at 0x72e3f3 -- `teams: NSOrderedSet = []`) and the +1 result is
// stored straight into that object's `teams` ivar (0x72e402, `%r15 + offset(teams)`) with no further
// retain. So the initializer must return an owning, empty NSOrderedSet, as Apple's own does.
//
// WHAT THE CLIENT DOES WITH makeIterator() (the earlier rung's name, re-measured here). The one
// symbol the image binds for this API is `makeIterator()` above;
// it binds no specialization. At DVTFoundation 0x2bc4a9 the call is given an NSOrderedSet and the
// returned NSFastEnumerationIterator is driven as a Sequence: the very next symbol loaded is the
// lazy conformance accessor `_$s10Foundation25NSFastEnumerationIteratorVACStAAWl`
// (NSFastEnumerationIterator : IteratorProtocol), which the client also binds, and the iterator's
// `next()` is what the loop calls. The iterator type itself and that conformance are already in this
// module (Foundation/NSFastEnumeration.swift).
//
// WHERE EVERYTHING COMES FROM (nothing here is invented):
//
//   * The DECLARATION is Apple's published API for this module, read out of the guest's own SDK:
//       <Xcode 26.3>/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/
//         Frameworks/Foundation.framework/Modules/Foundation.swiftmodule/x86_64-apple-macos.swiftinterface
//     (line 17917: `extension Foundation.NSOrderedSet : Swift.Sequence { public func makeIterator()
//     -> Foundation.NSFastEnumerationIterator; ... }`; line 17963-17967:
//     `extension Foundation.NSOrderedSet : Swift.ExpressibleByArrayLiteral { required convenience
//     public init(arrayLiteral elements: Any...); public typealias ArrayLiteralElement = Any }`).
//     Both carry `@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)` there, reproduced here.
//
//   * The BODY is Apple's own open source for this exact API, module name and licence:
//     swiftlang/swift release/5.4 stdlib/public/Darwin/Foundation/NSSet.swift:45:
//
//         extension NSOrderedSet : Sequence {
//           /// Return an *iterator* over the elements of this *sequence*.
//           ///
//           /// - Complexity: O(1).
//           public func makeIterator() -> NSFastEnumerationIterator {
//             return NSFastEnumerationIterator(self)
//           }
//         }
//
//     The iterator walks the object through its Objective-C fast enumeration: NSOrderedSet conforms
//     to NSFastEnumeration in Darling's header (src/external/foundation/include/Foundation/
//     NSOrderedSet.h:8) and implements -countByEnumeratingWithState:objects:count:
//     (src/external/corefoundation/NSOrderedSet.m:804), so this is a real implementation and not a
//     stub. The other candidate body, corelibs' `self.objectEnumerator().makeIterator()`, is not
//     used: Apple's Darwin overlay is the source for this module's declarations, and it is the same
//     file that carries NSSet's and NSArray's conformances.
//
//   * The LITERAL conformance's BODY is the same release/5.4 file, NSSet.swift:149:
//
//         extension NSOrderedSet : ExpressibleByArrayLiteral {
//           public required convenience init(arrayLiteral elements: Any...) {
//             self.init(array: elements)
//           }
//         }
//
//     `self.init(array: elements)` is Darling's Objective-C `-[NSOrderedSet initWithArray:]`
//     (declared src/external/foundation/include/Foundation/NSOrderedSet.h:27, implemented at
//     src/external/corefoundation/NSOrderedSet.m and deployed), so the literal is a real ordered set
//     of the elements and the returned object is +1 -- not a stub. The call was type-checked against
//     Darling's SDK before the build (state/foundation-errors-rung/probe-orderedset.swift), the same
//     way the NSSet rung type-checked its own two adaptations.
//
// WHAT IS DELIBERATELY NOT HERE. `init(objects: Any...)` (release/5.4 NSSet.swift:129) is still not
// added: no image in this closure binds it (a grep of the coverage graph's unmet demands for
// `So12NSOrderedSet` finds exactly `makeIterator()` and `arrayLiteral`), and neither does anything
// bind `NSOrderedSet : CustomReflectable`. NSSet's own Sequence and literal conformances live in
// NSSet.swift beside this file, where the NSSet/readToEnd rung put them.

@_exported import Foundation // Clang module

extension NSOrderedSet : Sequence {
  /// Return an *iterator* over the elements of this *sequence*.
  ///
  /// - Complexity: O(1).
  public func makeIterator() -> NSFastEnumerationIterator {
    return NSFastEnumerationIterator(self)
  }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension NSOrderedSet : ExpressibleByArrayLiteral {
  public required convenience init(arrayLiteral elements: Any...) {
    self.init(array: elements)
  }
}
