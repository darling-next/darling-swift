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

// From release/5.4 stdlib/public/Darwin/Foundation/NSCoder.swift, reduced to decodeObject(of:forKey:). Darling has no
// _SwiftFoundationOverlayShims, so the methods call -decodeObjectOfClass:forKey: and -decodeObjectOfClasses:forKey:
// directly.

@_exported import Foundation // Clang module

extension NSCoder {
  public func decodeObject<DecodedObjectType>(
    of cls: DecodedObjectType.Type, forKey key: String
  ) -> DecodedObjectType?
    where DecodedObjectType : NSCoding, DecodedObjectType : NSObject {
    let result: Any? = decodeObject(of: cls as AnyClass, forKey: key)
    return result as? DecodedObjectType
  }

  @nonobjc
  public func decodeObject(of classes: [AnyClass]?, forKey key: String) -> Any? {
    var classesAsNSObjects: NSSet?
    if let theClasses = classes {
      classesAsNSObjects = NSSet(array: theClasses.map { $0 as AnyObject })
    }
    // Darling imports the NSSet parameter as Set<AnyHashable>, which can't hold class objects, so call the
    // implementation with the Objective-C types.
    typealias DecodeObjectOfClasses = @convention(c) (NSCoder, Selector, NSSet?, NSString) -> AnyObject?
    let selector = Selector(("decodeObjectOfClasses:forKey:"))
    let decode = unsafeBitCast(method(for: selector), to: DecodeObjectOfClasses.self)
    return decode(self, selector, classesAsNSObjects, key as NSString)
  }

  /// Decodes the top-level object with a class whitelist through the Objective-C
  /// `-decodeTopLevelObjectOfClasses:forKey:error:` selector.  The selector reports a
  /// decoding failure through `NSError`; Cocoa error 4865 (`NSCoderValueNotFoundError`)
  /// is the ordinary "no value for this key" result and is not thrown.  This is the real
  /// selector route, but the base coder can only produce that one error, so this is not a
  /// claim that every native decoding-failure policy is reproduced.
  @nonobjc
  @available(macOS 10.11, iOS 9.0, *)
  public func decodeTopLevelObject(of classes: [AnyClass]?, forKey key: String) throws -> Any? {
    var classesAsNSObjects: NSSet?
    if let theClasses = classes {
      classesAsNSObjects = NSSet(array: theClasses.map { $0 as AnyObject })
    }
    typealias DecodeTopLevelOfClasses = @convention(c)
      (NSCoder, Selector, NSSet?, NSString, UnsafeMutablePointer<NSError?>?) -> AnyObject?
    let selector = Selector(("decodeTopLevelObjectOfClasses:forKey:error:"))
    let decode = unsafeBitCast(method(for: selector), to: DecodeTopLevelOfClasses.self)
    var error: NSError?
    let result = decode(self, selector, classesAsNSObjects, key as NSString, &error)
    if let error = error, error.code() != 4865 {
      throw error
    }
    return result
  }

  /// Decodes an array of objects of a given class for a given key.
  ///
  /// Declaration: the guest SDK's `Foundation.swiftinterface` line 778, in its `extension
  /// Foundation.NSCoder`: `@nonobjc public func decodeArrayOfObjects<DecodedObject>(ofClass cls:
  /// DecodedObject.Type, forKey key: Swift.String) -> [DecodedObject]? where DecodedObject :
  /// ObjectiveC.NSObject, DecodedObject : Foundation.NSSecureCoding`.  Apple's body decodes through a
  /// class-whitelisted `-decodeArrayOfObjectsOfClasses:forKey:`; this tree's NSCoder does not define
  /// that selector (src/external/foundation/include/Foundation/NSCoder.h:54-55 declares only
  /// `-decodeObjectOfClass:forKey:` and `-decodeObjectOfClasses:forKey:`), so the same whitelist is
  /// applied through the latter -- the array class plus the element class, which is exactly the set
  /// the keyed unarchiver checks -- and the result is bound to `[DecodedObject]`.  A stored value
  /// that is not an array, or that holds an object of another class, answers nil rather than a
  /// wrongly-typed array.
  @nonobjc
  public func decodeArrayOfObjects<DecodedObject>(
    ofClass cls: DecodedObject.Type, forKey key: String
  ) -> [DecodedObject]?
    where DecodedObject : NSObject, DecodedObject : NSSecureCoding {
    guard let decoded = decodeObject(of: [NSArray.self, cls as AnyClass], forKey: key) else { return nil }
    guard let array = decoded as? [Any] else { return nil }
    var result: [DecodedObject] = []
    result.reserveCapacity(array.count)
    for element in array {
      guard let object = element as? DecodedObject else { return nil }
      result.append(object)
    }
    return result
  }
}
