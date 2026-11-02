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

// Foundation.RunLoop : Combine.Scheduler -- the run-loop scheduler, from the release/5.4 Darwin
// overlay this directory is based on (`stdlib/public/Darwin/Foundation/RunLoop.swift` in the Swift
// 5.x sources, carried in-tree at
// swift-corelibs-foundation/Darwin/Foundation-swiftoverlay/Schedulers+RunLoop.swift).
//
// Darling's Foundation overlay does not vendor the Timer block initializers as Swift declarations,
// but it `@_exported import`s the Clang module, so the ObjC `+[NSTimer timerWithTimeInterval:
// repeats:block:]` / `-[NSTimer initWithFireDate:interval:repeats:block:]` and `-[NSRunLoop
// performBlock:]` / `performSelector:withObject:afterDelay:` import with their Swift spellings
// (`Timer(fire:interval:repeats:block:)`, `Timer(timeInterval:repeats:block:)`,
// `RunLoop.perform(_:)`, `perform(_:with:afterDelay:)`) and the bodies below are the 5.x overlay's
// verbatim: a delay-0 `performSelector:withObject:afterDelay:` for immediate scheduling, and a real
// `Timer` added to the run loop for the repeating case, whose `Cancellable` invalidates it.
//
// The declarations are checked against the guest SDK's Foundation.swiftinterface lines 330-391
// (`extension Foundation.RunLoop : Combine.Scheduler`): the nested `SchedulerTimeType`, its
// `Stride`, the empty `SchedulerOptions`, the three `schedule` overloads, `now` and
// `minimumTolerance`.  `SchedulerTimeType` and `Stride` are `Codable` in the SDK; the encoders are
// the synthesised ones (a `date`/`magnitude` member), which is the only honest representation
// available -- the tree carries no source for Apple's, and no image in this closure binds either
// `encode(to:)` or `init(from:)`.

@_exported import Foundation // Clang module
import Combine

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension RunLoop: Scheduler {
    /// The scheduler time type used by the run loop.
    public struct SchedulerTimeType: Strideable, Codable, Hashable, Sendable {
        /// The date represented by this type.
        public var date: Date

        /// Initializes a run loop scheduler time with the given date.
        public init(_ date: Date) {
            self.date = date
        }

        /// Returns the distance to another run loop scheduler time.
        public func distance(to other: RunLoop.SchedulerTimeType) -> SchedulerTimeType.Stride {
            return Stride(floatLiteral: date.distance(to: other.date))
        }

        /// Returns a run loop scheduler time calculated by advancing this instance's time by the
        /// given interval.
        public func advanced(by n: SchedulerTimeType.Stride) -> RunLoop.SchedulerTimeType {
            return SchedulerTimeType(date.advanced(by: n.timeInterval))
        }

        /// The interval by which run loop times advance.
        public struct Stride: ExpressibleByFloatLiteral, Comparable, SignedNumeric, Codable, SchedulerTimeIntervalConvertible, Sendable {
            public typealias FloatLiteralType = TimeInterval
            public typealias IntegerLiteralType = TimeInterval
            public typealias Magnitude = TimeInterval

            /// The value of this time interval in seconds.
            public var magnitude: TimeInterval

            /// The value of this time interval in seconds.
            public var timeInterval: TimeInterval {
                return magnitude
            }

            public init(integerLiteral value: TimeInterval) {
                magnitude = value
            }

            public init(floatLiteral value: TimeInterval) {
                magnitude = value
            }

            public init(_ timeInterval: TimeInterval) {
                magnitude = timeInterval
            }

            public init?<T>(exactly source: T) where T: BinaryInteger {
                if let d = TimeInterval(exactly: source) {
                    magnitude = d
                } else {
                    return nil
                }
            }

            public static func < (lhs: Stride, rhs: Stride) -> Bool {
                return lhs.magnitude < rhs.magnitude
            }

            public static func * (lhs: Stride, rhs: Stride) -> Stride {
                return Stride(lhs.timeInterval * rhs.timeInterval)
            }

            public static func + (lhs: Stride, rhs: Stride) -> Stride {
                return Stride(lhs.magnitude + rhs.magnitude)
            }

            public static func - (lhs: Stride, rhs: Stride) -> Stride {
                return Stride(lhs.magnitude - rhs.magnitude)
            }

            public static func *= (lhs: inout Stride, rhs: Stride) {
                let result = lhs * rhs
                lhs = result
            }

            public static func += (lhs: inout Stride, rhs: Stride) {
                let result = lhs + rhs
                lhs = result
            }

            public static func -= (lhs: inout Stride, rhs: Stride) {
                let result = lhs - rhs
                lhs = result
            }

            public static func seconds(_ s: Int) -> Stride {
                return Stride(Double(s))
            }

            public static func seconds(_ s: Double) -> Stride {
                return Stride(s)
            }

            public static func milliseconds(_ ms: Int) -> Stride {
                return Stride(Double(ms) / 1_000.0)
            }

            public static func microseconds(_ us: Int) -> Stride {
                return Stride(Double(us) / 1_000_000.0)
            }

            public static func nanoseconds(_ ns: Int) -> Stride {
                return Stride(Double(ns) / 1_000_000_000.0)
            }
        }
    }

    /// Options that affect the operation of the run loop scheduler.
    public struct SchedulerOptions: Sendable { }

    public func schedule(options: SchedulerOptions?, _ action: @escaping () -> Void) {
        self.perform(action)
    }

    public func schedule(after date: SchedulerTimeType,
                         tolerance: SchedulerTimeType.Stride,
                         options: SchedulerOptions?,
                         _ action: @escaping () -> Void) {
        let ti = date.date.timeIntervalSince(Date())
        self.perform(#selector(self.runLoopScheduled), with: _CombineRunLoopAction(action), afterDelay: ti)
    }

    public func schedule(after date: SchedulerTimeType,
                         interval: SchedulerTimeType.Stride,
                         tolerance: SchedulerTimeType.Stride,
                         options: SchedulerOptions?,
                         _ action: @escaping () -> Void) -> Cancellable {
        // Darling's SDK imports -[NSTimer initWithFireDate:interval:repeats:block:] as a failable
        // initializer (the header carries no nullability annotation on it), and the tolerance
        // accessor as the method pair -tolerance / -setTolerance: rather than a property, so this
        // unwraps once and calls setTolerance(_:).  A nil here means the timer object could not be
        // allocated; there is no schedule to hand back, so it traps rather than inventing a
        // Cancellable for work that was never scheduled.
        guard let timer = Timer(fire: date.date, interval: interval.timeInterval, repeats: true, block: { _ in action() }) else {
            preconditionFailure("could not allocate the repeating run-loop timer")
        }

        timer.setTolerance(tolerance.timeInterval)
        self.add(timer, forMode: .default)

        return AnyCancellable { timer.invalidate() }
    }

    public var now: SchedulerTimeType {
        return SchedulerTimeType(Date())
    }

    public var minimumTolerance: SchedulerTimeType.Stride {
        return 0.0
    }

    @objc
    fileprivate func runLoopScheduled(action: _CombineRunLoopAction) {
        action.action()
    }
}

@objc
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
private class _CombineRunLoopAction: NSObject {
    let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }
}
