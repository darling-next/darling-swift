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

// Array <-> NSArray bridging and the NSArray array-literal conformance, from release/5.4
// stdlib/public/Darwin/Foundation/NSArray.swift (the conformance is the first extension in that
// file, the bridging follows it). Darling's NSArray has no Swift annotations, so no other
// declaration of that upstream file is kept here.
//
// The array-literal conformance is BACK because Xcode 26.3's DVTFoundation binds, eagerly and
// strongly,
//
//     _$sSo7NSArrayC10FoundationE12arrayLiteralABypd_tcfC
//       == (extension in Foundation): __C.NSArray.init(arrayLiteral: Any...) -> __C.NSArray
//
// against its Foundation ordinal, and this module exported no NSArray Swift symbol at all, so an
// image in this closure stops with `Symbol not found: _...arrayLiteral...` /
// `Expected in: .../Foundation.framework/...` once the earlier names of the same rung are supplied.
// The one symbol the image binds is this initializer -- no specialization of it and no conformance
// accessor -- and its one call site (DVTFoundation 0x2c0d60) builds the literal on the stack and
// passes the returned NSArray straight to an Objective-C message, so the elements have to be there:
// `self.init(array: elements)` bridges them through -[NSArray initWithArray:]
// (src/external/foundation/include/Foundation/NSArray.h:79), which is a real implementation.

@_exported import Foundation // Clang module
@_spi(Foundation) import Swift

extension NSArray : ExpressibleByArrayLiteral {
  /// Create an instance initialized with `elements`.
  public required convenience init(arrayLiteral elements: Any...) {
    // Let bridging take care of it.
    self.init(array: elements)
  }
}

extension Array : _ObjectiveCBridgeable {

  /// Private initializer used for bridging.
  ///
  /// The provided `NSArray` will be copied to ensure that the copy can
  /// not be mutated by other code.
  internal init(_cocoaArray: __shared NSArray) {
    assert(_isBridgedVerbatimToObjectiveC(Element.self),
      "Array can be backed by NSArray only when the element type can be bridged verbatim to Objective-C")
    self = Array(_immutableCocoaArray: _cocoaArray.copy() as AnyObject)
  }

  @_semantics("convertToObjectiveC")
  public func _bridgeToObjectiveC() -> NSArray {
    return unsafeBitCast(self._bridgeToObjectiveCImpl(), to: NSArray.self)
  }

  public static func _forceBridgeFromObjectiveC(
    _ source: NSArray,
    result: inout Array?
  ) {
    // If we have the appropriate native storage already, just adopt it.
    if let native =
        Array._bridgeFromObjectiveCAdoptingNativeStorageOf(source) {
      result = native
      return
    }

    if _fastPath(_isBridgedVerbatimToObjectiveC(Element.self)) {
      // Forced down-cast (possible deferred type-checking)
      result = Array(_cocoaArray: source)
      return
    }

    result = _arrayForceCast([AnyObject](_cocoaArray: source))
  }

  public static func _conditionallyBridgeFromObjectiveC(
    _ source: NSArray,
    result: inout Array?
  ) -> Bool {
    // Construct the result array by conditionally bridging each element.
    let anyObjectArr = [AnyObject](_cocoaArray: source)

    result = _arrayConditionalCast(anyObjectArr)
    return result != nil
  }

  @_effects(readonly)
  public static func _unconditionallyBridgeFromObjectiveC(
    _ source: NSArray?
  ) -> Array {
    // `nil` has historically been used as a stand-in for an empty
    // array; map it to an empty array instead of failing.
    if _slowPath(source == nil) { return Array() }

    // If we have the appropriate native storage already, just adopt it.
    if let native =
        Array._bridgeFromObjectiveCAdoptingNativeStorageOf(source!) {
      return native
    }

    if _fastPath(_isBridgedVerbatimToObjectiveC(Element.self)) {
      // Forced down-cast (possible deferred type-checking)
      return Array(_cocoaArray: source!)
    }

    return _arrayForceCast([AnyObject](_cocoaArray: source!))
  }
}
