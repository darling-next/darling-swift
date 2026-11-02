//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

// Darling: NSSet's Swift conformance surface -- the part Apple declares in module Foundation and
// carries in the release/5.4 overlay file this tree reduced to `Set.swift`, where only the
// Swift.Set bridging survived. This file is the NSSet sibling of `NSOrderedSet.swift` (which holds
// NSOrderedSet's Sequence conformance) and of `NSDictionary+Literal.swift` (which holds
// NSDictionary's literal and Sequence conformances).
//
// WHY THIS FILE EXISTS (the rung that needed it). Xcode 26.3's
// Contents/SharedFrameworks/XCTHarness.framework/Versions/A/XCTHarness binds, eagerly and strongly
// (chained-fixups imports[539], [540], [541] with lib_ordinal 12 = Foundation, weak_import = 0),
//
//     _$sSo5NSSetC10FoundationE12arrayLiteralABypd_tcfC
//       == (extension in Foundation): __C.NSSet.init(arrayLiteral: Any...)
//     _$sSo5NSSetC10FoundationE12makeIteratorAC017NSFastEnumerationD0VyF
//       == (extension in Foundation): __C.NSSet.makeIterator() -> Foundation.NSFastEnumerationIterator
//     _$sSo5NSSetC10FoundationE3setA2Bh_tcfC
//       == (extension in Foundation): __C.NSSet.init(set: __shared NSSet)
//
// against its Foundation ordinal, and the deployed /usr/lib/swift/libswiftFoundation.dylib exported
// no NSSet Swift symbol at all (measured: the coverage graph classifies all three of these names,
// and FileHandle's readToEnd, as `missing` -- absent from the field image, its re-exports and every
// image the process loads), so dyld has nothing to bind them to -- `Symbol not found: <name>` /
// `Expected in: /System/Library/Frameworks/Foundation.framework/...` is the shape of that failure, and
// the coverage graph lists all three of these names plus FileHandle's readToEnd as THIS image's unmet
// Foundation demands, so the loader's stop reaches one of them (never all at once: dyld reports the
// first name it cannot bind). "Expected in: .../Foundation.framework/..." is the ordinal's blame text,
// not the file that must change: Darling's Foundation.framework is the Objective-C framework, it
// re-exports /usr/lib/swift/libswiftFoundation.dylib, and this module is that dylib -- the same
// mechanism the Morphology, NSOrderedSet and NSFileHandle rungs used.
//
// The same two Swift names are also demanded by other images of this closure (the graph's own unmet
// list): DVTSourceControl and IDEFoundation both bind `arrayLiteral`, IDEFoundation also binds
// `makeIterator`, AppThinning binds NSFileHandle's `readToEnd` (that one is in NSFileHandle.swift).
//
// WHAT THE CLIENTS DO WITH THEM (measured from the demanding images' own bind tables and their
// disassembly, not assumed):
//
//   * `makeIterator()` is called at XCTHarness 0xc40ab, 0xc433c, 0xc4431 and 0xc45f5 -- inside the
//     stdlib Sequence algorithms the client's own binary SPECIALIZED for NSSet
//     (`Sequence.compactMap`, `Sequence.forEach`, `Sequence.contains(where:)`,
//     `Sequence.first(where:)`, mangled `_$sSTsE...So5NSSetC_Tg5...`). The returned
//     NSFastEnumerationIterator is then driven by `Sequence.next()`
//     (`_$sSt4next7ElementQzSgyFTj`, XCTHarness 0xc4110) through the lazy conformance accessor the
//     client also binds (`_$s10Foundation25NSFastEnumerationIteratorVStAAMc`, which the deployed
//     dylib already exports), and the loop ends where `next()` answers an empty Optional
//     (XCTHarness 0xc4115 tests the returned `Any?`'s tag word). A fabricated iterator therefore
//     silently changes what those loops visit, so this conformance must really walk the set.
//   * `init(arrayLiteral:)` is called at XCTHarness 0xc6c95 and 0x15e29b (both inside
//     `XCTHGenericRunDestinationPool.init(runDestination:)`) with rdi = the `_ContiguousArrayStorage<Any>`
//     the client allocated for the literal (XCTHarness 0xc6c52, `__swift_instantiateConcreteTypeFromMangledNameV2`
//     of `_$ss23_ContiguousArrayStorageCyypGMd` at 0xc6c44) -- i.e. the `Any...` variadic argument
//     arrives as a Swift `[Any]` buffer. The returned set is passed straight on as an Objective-C
//     message argument (objc_msgSend at 0xc6caa) and then released (0xc6cb5), so the initializer has
//     to hand back a +1 object, as Apple's own does.
//   * `init(set:)` is called at XCTHarness 0xc4c50 in
//     `XCTHGenericRunDestinationPool.init(runDestinations:)`, rdi = the NSSet the client retained
//     for the call (XCTHarness 0xc4c44, `-objc_retain`), and the result is stored straight into that
//     object's `availableRunDestinations` ivar (0xc4c55/0xc4c5c) without a further retain: the
//     initializer returns an owning reference to a copy of the argument.
//
// WHERE EVERYTHING COMES FROM (nothing here is invented):
//
//   * The DECLARATIONS -- spelling, argument labels, `required`/`@nonobjc`, genericity (the
//     `Any...` variadics) and availability -- are Apple's published API for this module, read out of
//     the guest's own SDK:
//       <Xcode 26.3>/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/
//         Frameworks/Foundation.framework/Modules/Foundation.swiftmodule/x86_64-apple-macos.swiftinterface
//     (line 17906: `extension Foundation.NSSet : Swift.Sequence { public func makeIterator()
//     -> Foundation.NSFastEnumerationIterator; public typealias Element = Any; public typealias
//     Iterator = Foundation.NSFastEnumerationIterator }`; line 17957-17962:
//     `extension Foundation.NSSet : Swift.ExpressibleByArrayLiteral { required convenience public
//     init(arrayLiteral elements: Any...); public typealias ArrayLiteralElement = Any }`; line
//     17969-17971: `extension Foundation.NSSet { @nonobjc convenience public init(set anSet:
//     __shared Foundation.NSSet) }`). Both conformances carry
//     `@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)` there, which is reproduced here.
//
//   * The BODIES are Apple's own open source for these exact APIs, and the file is IN THIS TREE:
//     src/external/corefoundation/submodules/swift-corelibs-foundation/Darwin/Foundation-swiftoverlay/
//     NSSet.swift (Apache-2.0 with Runtime Library Exception) --
//       line 37-43: `extension NSSet : Sequence { public func makeIterator() ->
//                    NSFastEnumerationIterator { return NSFastEnumerationIterator(self) } }`
//       line 135-141: `extension NSSet : ExpressibleByArrayLiteral { public required convenience
//                    init(arrayLiteral elements: Any...) { self.init(array: elements) } }`
//       line 143-179: `extension NSSet { @nonobjc public convenience init(set anSet: __shared NSSet)
//                    { ...CFSetGetValues(anSet, valueBuffer)... self.init(objects: valueBufferForInit,
//                    count: numElems) } }`
//     Only two mechanical adaptations were needed for Darling's imports, and both are measured, not
//     guessed (a `swiftc -frontend -typecheck` of these declarations against Darling's SDK):
//       - `- (NSUInteger)count;` is imported as the METHOD `count()` (Darling's NS headers declare it
//         as a method, not a property), so upstream's `anSet.count` is `anSet.count()` here;
//       - `- (id)initWithObjects:(const id [])objects count:(NSUInteger)cnt;` imports as
//         `init(objects: UnsafePointer<AnyObject?>, count: Int)` -- with OPTIONAL elements, as the
//         NSDictionary literal precedent in this directory records -- so upstream's
//         `assumingMemoryBound(to: AnyObject.self)` is `AnyObject?.self` here. The element layout is
//         the same either way (a nullable object pointer), and the buffer holds the unretained
//         pointers `CFSetGetValues` wrote, which the initializer below retains.
//
//   * The ITERATOR is real, not a stub: `NSFastEnumerationIterator` is Swift's thin wrapper over
//     `-countByEnumeratingWithState:objects:count:`, which Darling's NSSet implements
//     (src/external/corefoundation/NSSet.m) and conforms to (Foundation/NSSet.h declares
//     NSFastEnumeration on the class); the type itself and its IteratorProtocol conformance are
//     already in this module (Foundation/NSFastEnumeration.swift) and in the deployed dylib.
//   * `CFSetGetValues` is real and deployed: Darling's CoreFoundation defines it
//     (src/external/corefoundation/CFSet.c:474) and the deployed
//     /System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation exports
//     `_CFSetGetValues`, which is what `init(set:)` needs to read the argument's members.
//
// WHAT IS DELIBERATELY NOT HERE. The rest of what the in-tree corelibs overlay file carries:
// `NSOrderedSet`'s `init(objects:)`/`arrayLiteral` (NSOrderedSet's `arrayLiteral` IS demanded, by
// DVTSourceControl and IDEFoundation -- it is the NSOrderedSet rung's file, `NSOrderedSet.swift`,
// which is where it belongs), `NSSet.init(objects:)` (nothing in this closure binds it), and
// `NSSet : CustomReflectable` with its `customMirror` (likewise unbound). Grepping the graph's unmet
// demands for `So5NSSetC10FoundationE` finds exactly the three names above, so this file adds no
// behaviour that no measurement gates.

@_exported import Foundation // Clang module

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension NSSet : Sequence {
  /// Return an *iterator* over the elements of this *sequence*.
  ///
  /// - Complexity: O(1).
  public func makeIterator() -> NSFastEnumerationIterator {
    return NSFastEnumerationIterator(self)
  }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension NSSet : ExpressibleByArrayLiteral {
  public required convenience init(arrayLiteral elements: Any...) {
    self.init(array: elements)
  }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension NSSet {
  /// Initializes a newly allocated set and adds to it objects from
  /// another given set.
  ///
  /// - Returns: An initialized objects set containing the objects from
  ///   `set`. The returned set might be different than the original
  ///   receiver.
  @nonobjc
  public convenience init(set anSet: __shared NSSet) {
    // FIXME(performance)(compiler limitation): we actually want to do just
    // `self = anSet.copy()`, but Swift does not have factory
    // initializers right now.
    let numElems = anSet.count()
    let stride = MemoryLayout<Optional<UnsafeRawPointer>>.stride
    let alignment = MemoryLayout<Optional<UnsafeRawPointer>>.alignment
    let bufferSize = stride * numElems
    assert(stride == MemoryLayout<AnyObject>.stride)
    assert(alignment == MemoryLayout<AnyObject>.alignment)

    let rawBuffer = UnsafeMutableRawPointer.allocate(
      byteCount: bufferSize, alignment: alignment)
    defer {
      rawBuffer.deallocate()
      _fixLifetime(anSet)
    }
    let valueBuffer = rawBuffer.bindMemory(
     to: Optional<UnsafeRawPointer>.self, capacity: numElems)

    CFSetGetValues(anSet, valueBuffer)
    // The buffer holds the unretained object pointers CFSetGetValues wrote; `-initWithObjects:count:`
    // is what retains them, which is why the caller keeps `anSet` alive until after that call.
    let valueBufferForInit = rawBuffer.assumingMemoryBound(to: AnyObject?.self)
    self.init(objects: valueBufferForInit, count: numElems)
  }
}
