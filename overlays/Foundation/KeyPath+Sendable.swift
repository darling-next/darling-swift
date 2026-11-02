//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

// swift-foundation declares this in Sources/FoundationEssentials/Predicate/PredicateExpression.swift,
// which this overlay does not build. SortDescriptor's `#if FOUNDATION_FRAMEWORK` initializers and
// KeyPathComparator both store a `KeyPath<Root, Value> & Sendable`, so the declaration has to exist
// here for either to compile. The body is upstream's, verbatim: a KeyPath is immutable, so the cast
// only tells the type system something that is already true.
extension KeyPath {
    package var _unsafeAssumeSendable: KeyPath<Root, Value> & Sendable {
        func _unsafeCast<T, U>(_ t: T) -> U {
            t as! U
        }
        return _unsafeCast(self) as KeyPath<Root, Value> & Sendable
    }
}
