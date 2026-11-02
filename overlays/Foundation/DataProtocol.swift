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

#if os(macOS) || os(iOS)
import Darwin
#elseif os(Linux)
import Glibc
#endif

// Darling: `DispatchData`'s DataProtocol conformance below is an extension of a type that lives in
// another module (Dispatch, whose declaration is overlays/Dispatch/Data.swift), which is why this
// file imports it; the conformance itself belongs to Foundation, exactly as Apple declares it
// (`Foundation.swiftinterface:20860`).
import Dispatch

//===--- DataProtocol -----------------------------------------------------===//

public protocol DataProtocol : RandomAccessCollection where Element == UInt8, SubSequence : DataProtocol {
    // FIXME: Remove in favor of opaque type on `regions`.
    associatedtype Regions: BidirectionalCollection where Regions.Element : DataProtocol & ContiguousBytes, Regions.Element.SubSequence : ContiguousBytes

    /// A `BidirectionalCollection` of `DataProtocol` elements which compose a
    /// discontiguous buffer of memory.  Each region is a contiguous buffer of
    /// bytes.
    ///
    /// The sum of the lengths of the associated regions must equal `self.count`
    /// (such that iterating `regions` and iterating `self` produces the same
    /// sequence of indices in the same number of index advancements).
    var regions: Regions { get }

    /// Returns the first found range of the given data buffer.
    ///
    /// A default implementation is given in terms of `self.regions`.
    func firstRange<D: DataProtocol, R: RangeExpression>(of: D, in: R) -> Range<Index>? where R.Bound == Index

    /// Returns the last found range of the given data buffer.
    ///
    /// A default implementation is given in terms of `self.regions`.
    func lastRange<D: DataProtocol, R: RangeExpression>(of: D, in: R) -> Range<Index>? where R.Bound == Index

    /// Copies `count` bytes from the start of the buffer to the destination
    /// buffer.
    ///
    /// A default implementation is given in terms of `copyBytes(to:from:)`.
    @discardableResult
    func copyBytes(to: UnsafeMutableRawBufferPointer, count: Int) -> Int

    /// Copies `count` bytes from the start of the buffer to the destination
    /// buffer.
    ///
    /// A default implementation is given in terms of `copyBytes(to:from:)`.
    @discardableResult
    func copyBytes<DestinationType>(to: UnsafeMutableBufferPointer<DestinationType>, count: Int) -> Int

    /// Copies the bytes from the given range to the destination buffer.
    ///
    /// A default implementation is given in terms of `self.regions`.
    @discardableResult
    func copyBytes<R: RangeExpression>(to: UnsafeMutableRawBufferPointer, from: R) -> Int where R.Bound == Index

    /// Copies the bytes from the given range to the destination buffer.
    ///
    /// A default implementation is given in terms of `self.regions`.
    @discardableResult
    func copyBytes<DestinationType, R: RangeExpression>(to: UnsafeMutableBufferPointer<DestinationType>, from: R) -> Int where R.Bound == Index
}

//===--- MutableDataProtocol ----------------------------------------------===//

public protocol MutableDataProtocol : DataProtocol, MutableCollection, RangeReplaceableCollection {
    /// Replaces the contents of the buffer at the given range with zeroes.
    ///
    /// A default implementation is given in terms of
    /// `replaceSubrange(_:with:)`.
    mutating func resetBytes<R: RangeExpression>(in range: R) where R.Bound == Index
}

//===--- DataProtocol Extensions ------------------------------------------===//

extension DataProtocol {
    public func firstRange<D: DataProtocol>(of data: D) -> Range<Index>? {
        return self.firstRange(of: data, in: self.startIndex ..< self.endIndex)
    }

    public func lastRange<D: DataProtocol>(of data: D) -> Range<Index>? {
        return self.lastRange(of: data, in: self.startIndex ..< self.endIndex)
    }

    @discardableResult
    public func copyBytes(to ptr: UnsafeMutableRawBufferPointer) -> Int {
        return copyBytes(to: ptr, from: self.startIndex ..< self.endIndex)
    }

    @discardableResult
    public func copyBytes<DestinationType>(to ptr: UnsafeMutableBufferPointer<DestinationType>) -> Int {
        return copyBytes(to: ptr, from: self.startIndex ..< self.endIndex)
    }

    @discardableResult
    public func copyBytes(to ptr: UnsafeMutableRawBufferPointer, count: Int) -> Int {
        return copyBytes(to: ptr, from: self.startIndex ..< self.index(self.startIndex, offsetBy: count))
    }

    @discardableResult
    public func copyBytes<DestinationType>(to ptr: UnsafeMutableBufferPointer<DestinationType>, count: Int) -> Int {
        return copyBytes(to: ptr, from: self.startIndex ..< self.index(self.startIndex, offsetBy: count))
    }

    @discardableResult
    public func copyBytes<R: RangeExpression>(to ptr: UnsafeMutableRawBufferPointer, from range: R) -> Int where R.Bound == Index {
        precondition(ptr.baseAddress != nil)

        let concreteRange = range.relative(to: self)
        let slice = self[concreteRange]

        // The type isn't contiguous, so we need to copy one region at a time.
        var offset = 0
        let rangeCount = distance(from: concreteRange.lowerBound, to: concreteRange.upperBound)
        var amountToCopy = Swift.min(ptr.count, rangeCount)
        for region in slice.regions {
            guard amountToCopy > 0 else {
                break
            }

            region.withUnsafeBytes { buffer in
                let offsetPtr = UnsafeMutableRawBufferPointer(rebasing: ptr[offset...])
                let buf = UnsafeRawBufferPointer(start: buffer.baseAddress, count: Swift.min(buffer.count, amountToCopy))
                offsetPtr.copyMemory(from: buf)
                offset += buf.count
                amountToCopy -= buf.count
            }
        }

        return offset
    }

    @discardableResult
    public func copyBytes<DestinationType, R: RangeExpression>(to ptr: UnsafeMutableBufferPointer<DestinationType>, from range: R) -> Int where R.Bound == Index {
        return self.copyBytes(to: UnsafeMutableRawBufferPointer(start: ptr.baseAddress, count: ptr.count * MemoryLayout<DestinationType>.stride), from: range)
    }

    private func matches<D: DataProtocol>(_ data: D, from index: Index) -> Bool {
        var haystackIndex = index
        var needleIndex = data.startIndex
        
        while true {
            guard self[haystackIndex] == data[needleIndex] else { return false }
            
            haystackIndex = self.index(after: haystackIndex)
            needleIndex = data.index(after: needleIndex)
            if needleIndex == data.endIndex {
                // i.e. needle is found.
                return true
            } else if haystackIndex == endIndex {
                return false
            }
        }
    }
    
    public func firstRange<D: DataProtocol, R: RangeExpression>(of data: D, in range: R) -> Range<Index>? where R.Bound == Index {
        let r = range.relative(to: self)
        let length = data.count
        
        if length == 0 || length > distance(from: r.lowerBound, to: r.upperBound) {
            return nil
        }
        
        var position = r.lowerBound
        while position < r.upperBound && distance(from: position, to: r.upperBound) >= length {
            if matches(data, from: position) {
                return position..<index(position, offsetBy: length)
            }
            position = index(after: position)
        }
        return nil
    }
    
    public func lastRange<D: DataProtocol, R: RangeExpression>(of data: D, in range: R) -> Range<Index>? where R.Bound == Index {
        let r = range.relative(to: self)
        let length = data.count
        
        if length == 0 || length > distance(from: r.lowerBound, to: r.upperBound) {
            return nil
        }
        
        var position = index(r.upperBound, offsetBy: -length)
        while position >= r.lowerBound {
            if matches(data, from: position) {
                return position..<index(position, offsetBy: length)
            }
            position = index(before: position)
        }
        return nil
    }
}

extension DataProtocol where Self : ContiguousBytes {
    public func copyBytes<DestinationType, R: RangeExpression>(to ptr: UnsafeMutableBufferPointer<DestinationType>, from range: R) where R.Bound == Index {
        precondition(ptr.baseAddress != nil)

        let concreteRange = range.relative(to: self)
        withUnsafeBytes { fullBuffer in
            let adv = distance(from: startIndex, to: concreteRange.lowerBound)
            let delta = distance(from: concreteRange.lowerBound, to: concreteRange.upperBound)
            memcpy(ptr.baseAddress!, fullBuffer.baseAddress?.advanced(by: adv), delta)
        }
    }
}

//===--- MutableDataProtocol Extensions -----------------------------------===//

extension MutableDataProtocol {
    public mutating func resetBytes<R: RangeExpression>(in range: R) where R.Bound == Index {
        let r = range.relative(to: self)
        let count = distance(from: r.lowerBound, to: r.upperBound)
        replaceSubrange(r, with: repeatElement(UInt8(0), count: count))
    }
}

//===--- DataProtocol Conditional Conformances ----------------------------===//

extension Slice : DataProtocol where Base : DataProtocol {
    public typealias Regions = [Base.Regions.Element.SubSequence]

    public var regions: [Base.Regions.Element.SubSequence] {
        let sliceLowerBound = startIndex
        let sliceUpperBound = endIndex
        var regionUpperBound = base.startIndex

        return base.regions.compactMap { (region) -> Base.Regions.Element.SubSequence? in
            let regionLowerBound = regionUpperBound
            regionUpperBound = base.index(regionUpperBound, offsetBy: region.count)

            /*
             [------ Region ------]
             [--- Slice ---] =>

                      OR

             [------ Region ------]
                 <= [--- Slice ---]
             */
            if sliceLowerBound >= regionLowerBound && sliceUpperBound <= regionUpperBound {
                let regionRelativeSliceLowerBound = region.index(region.startIndex, offsetBy: base.distance(from: regionLowerBound, to: sliceLowerBound))
                let regionRelativeSliceUpperBound = region.index(region.startIndex, offsetBy: base.distance(from: regionLowerBound, to: sliceUpperBound))
                return region[regionRelativeSliceLowerBound..<regionRelativeSliceUpperBound]
            }

            /*
             [--- Region ---] =>
             [------ Slice ------]

                      OR

               <= [--- Region ---]
             [------ Slice ------]
             */
            if regionLowerBound >= sliceLowerBound && regionUpperBound <= sliceUpperBound {
                return region[region.startIndex..<region.endIndex]
            }

            /*
             [------ Region ------]
                 [------ Slice ------]
             */
            if sliceLowerBound >= regionLowerBound && sliceLowerBound <= regionUpperBound {
                let regionRelativeSliceLowerBound = region.index(region.startIndex, offsetBy: base.distance(from: regionLowerBound, to: sliceLowerBound))
                return region[regionRelativeSliceLowerBound..<region.endIndex]
            }

            /*
                 [------ Region ------]
             [------ Slice ------]
             */
            if regionLowerBound >= sliceLowerBound && regionLowerBound <= sliceUpperBound {
                let regionRelativeSliceUpperBound = region.index(region.startIndex, offsetBy: base.distance(from: regionLowerBound, to: sliceUpperBound))
                return region[region.startIndex..<regionRelativeSliceUpperBound]
            }

            /*
             [--- Region ---]
                              [--- Slice ---]

                      OR

                             [--- Region ---]
             [--- Slice ---]
             */
            return nil
        }
    }
}

//===--- DispatchData Conditional Conformance -----------------------------===//

// Darling: `DispatchData`'s conformance, from Apple's own open source for this module
// (`swift-corelibs-foundation/Sources/Foundation/DispatchData+DataProtocol.swift`, the whole file --
// the file is exactly this and nothing else, so nothing was reduced), declared the way the guest
// SDK's `Foundation.swiftinterface:20860-20893` declares it: the nested `Region` conforms to
// `DataProtocol` and `ContiguousBytes`, and `DispatchData` itself gets `regions` and therefore the
// `Regions` associated type.  The body is corelibs' verbatim, over this tree's `DispatchData`
// (overlays/Dispatch/Data.swift), whose `Index` is `Int` and which hands each contiguous range to
// `enumerateBytes`, so `bytes[position - index]` and `index + bytes.count` are the same integer
// arithmetic corelibs wrote.
//
// The one difference from corelibs' file: the SDK also declares `Region : Sendable`
// (`Foundation.swiftinterface:20861`).  That conformance is not declared here.  `DispatchData` in
// overlays/Dispatch/Data.swift is a struct holding an unmanaged `__DispatchData` pointer and is not
// `Sendable`; `Region` stores an `owner: DispatchData`, so a `Sendable` declaration would be a
// conformance claim this tree cannot keep, and the five names this rung was measured to owe -- the
// metadata accessor `RegionVMa`, the nominal descriptor `RegionVMn`, the `DataProtocol` conformance
// descriptor, the `ContiguousBytes` witness table and the `regions` getter -- do not involve
// `Sendable` at all.
extension DispatchData : DataProtocol {
    public struct Region : DataProtocol, ContiguousBytes {
        internal let bytes: UnsafeBufferPointer<UInt8>
        internal let index: DispatchData.Index
        internal let owner: DispatchData
        internal init(bytes: UnsafeBufferPointer<UInt8>, index: DispatchData.Index, owner: DispatchData) {
            self.bytes = bytes
            self.index = index
            self.owner = owner
        }

        public var regions: CollectionOfOne<Region> {
            return CollectionOfOne(self)
        }

        public subscript(position: DispatchData.Index) -> UInt8 {
            precondition(index <= position && position <= index + bytes.count)
            return bytes[position - index]
        }

        public var startIndex: DispatchData.Index {
            return index
        }

        public var endIndex: DispatchData.Index {
            return index + bytes.count
        }

        public func withUnsafeBytes<ResultType>(_ body: (UnsafeRawBufferPointer) throws -> ResultType) rethrows -> ResultType {
            return try body(UnsafeRawBufferPointer(bytes))
        }
    }

    public var regions: [Region] {
        var regions = [Region]()
        enumerateBytes { (bytes, index, stop) in
            regions.append(Region(bytes: bytes, index: index, owner: self))
        }
        return regions
    }
}
