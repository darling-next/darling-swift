//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

// NSData's conformance to the Swift StringProtocol/collection protocol family, adapted from
// swift-corelibs-foundation's Sources/Foundation/NSData+DataProtocol.swift (the tree carries that file,
// but this overlay -- not that Foundation -- is what builds the guest's Foundation).
//
// Why the ladder needs it: IDEDistribution.framework binds the *inherited* conformance descriptor
// `_$sSo6NSDataCST10FoundationMc` (__C.NSData : Swift.Sequence) eagerly and strongly from
// Foundation.framework, and Apple's own Foundation exports it -- the tbd lists the whole inherited
// closure for the one declared conformance (`...DataProtocolACMc`, `...SK...`, `...ST...`, `...Sk...`,
// `...Sl...`).  The closure is emitted from the DataProtocol conformance, so declaring it is the whole
// answer; there is no separate `extension NSData : Sequence` to write (Swift forbids the redundant one).
//
// The bodies are the swift-corelibs bodies, with `enumerateBytes` replaced by direct access to this
// object's own `bytes`/`length`: the tree's overlay declares no Swift `enumerateBytes` on NSData, and
// one region and one indexed byte read are what the two overrides below actually need.
extension NSData : DataProtocol {

    @nonobjc
    public var startIndex: Int { return 0 }

    @nonobjc
    public var endIndex: Int { return length() }

    @nonobjc
    public func lastRange<D, R>(of data: D, in r: R) -> Range<Int>? where D : DataProtocol, R : RangeExpression, NSData.Index == R.Bound {
        return Range<Int>(range(of: Data(data), options: .backwards, range: NSRange(r)))
    }

    @nonobjc
    public func firstRange<D, R>(of data: D, in r: R) -> Range<Int>? where D : DataProtocol, R : RangeExpression, NSData.Index == R.Bound {
        return Range<Int>(range(of: Data(data), options: [], range: NSRange(r)))
    }

    @nonobjc
    public var regions: [Data] {
        // One region: this object's bytes, borrowed rather than copied, kept valid by holding the
        // receiver alive for as long as the Data is.
        return [Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: bytes),
                     count: length(),
                     deallocator: .custom({ [self] _, _ in withExtendedLifetime(self) { } }))]
    }

    @nonobjc
    public subscript(position: Int) -> UInt8 {
        return bytes.load(fromByteOffset: position, as: UInt8.self)
    }
}
