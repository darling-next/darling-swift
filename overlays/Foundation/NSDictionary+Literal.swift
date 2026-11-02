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

// From release/5.4 stdlib/public/Darwin/Foundation/NSDictionary.swift (the dictionary literal conformance). Darling
// imports -initWithObjects:forKeys:count: with optional element pointers.

@_exported import Foundation // Clang module

private func duckCastToNSCopying(_ x: Any) -> NSCopying {
  return _unsafeReferenceCast(x as AnyObject, to: NSCopying.self)
}

extension NSDictionary : ExpressibleByDictionaryLiteral {
  public required convenience init(
    dictionaryLiteral elements: (Any, Any)...
  ) {
    let objects: [AnyObject?] = elements.map { $0.1 as AnyObject }
    let keys: [NSCopying?] = elements.map { duckCastToNSCopying($0.0) }
    self.init(objects: objects, forKeys: keys, count: elements.count)
  }
}

// The same release/5.4 file's other half: `extension NSDictionary : Sequence` and its Iterator.
extension NSDictionary : Sequence {
  // FIXME: A class because we can't pass a struct with class fields through an
  // [objc] interface without prematurely destroying the references.
  // NOTE: older runtimes had
  // _TtCE10FoundationCSo12NSDictionary8Iterator as the ObjC name. The
  // two must coexist, so it was renamed. The old name must not be used
  // in the new runtime.
  @_objcRuntimeName(_TtCE10FoundationCSo12NSDictionary9_Iterator)
  final public class Iterator : IteratorProtocol {
    var _fastIterator: NSFastEnumerationIterator
    var _dictionary: NSDictionary {
      return _fastIterator.enumerable as! NSDictionary
    }

    public typealias Element = (key: Any, value: Any)

    public func next() -> (key: Any, value: Any)? {
      if let key = _fastIterator.next() {
        // Deliberately avoid the subscript operator in case the dictionary
        // contains non-copyable keys. This is rare since NSMutableDictionary
        // requires them, but we don't want to paint ourselves into a corner.
        return (key: key, value: _dictionary.object(forKey: key)!)
      }
      return nil
    }

    internal init(_ _dict: __shared NSDictionary) {
      _fastIterator = NSFastEnumerationIterator(_dict)
    }
  }

  public typealias Element = (key: Any, value: Any)

  /// Return an *iterator* over the elements of this *sequence*.
  ///
  /// - Complexity: O(1).
  public func makeIterator() -> Iterator {
    return Iterator(self)
  }
}
