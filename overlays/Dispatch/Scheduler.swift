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

// Dispatch.DispatchQueue : Combine.Scheduler -- the dispatch-queue scheduler.
//
// Darling's Dispatch overlay is compiled into the module named `Dispatch`, so this conformance has
// to be declared here (and not in a separate OpenCombineDispatch-like module) to bind the mangled
// symbols the guest bind: the conformance descriptor
// `_$sSo17OS_dispatch_queueC7Combine9Scheduler8DispatchMc` and the metadata accessors of the
// conformance's nested options type
// `_$sSo17OS_dispatch_queueC8DispatchE16SchedulerOptionsVMa` /
// `_$sSo17OS_dispatch_queueC8DispatchE16SchedulerOptionsVMn`.
//
// In this tree's SDK `DispatchQueue` is the `SwiftName` that
// `usr/include/Dispatch.apinotes` (lines 59-60) gives to the ObjC class `OS_dispatch_queue`; a
// `DispatchQueue` Swift extension therefore mangles as `So17OS_dispatch_queueC` and, from the
// Dispatch module, as `So17OS_dispatch_queueC8DispatchE...`.
//
// The declarations are checked against the guest SDK's Dispatch interface lines 529-610
// (`extension Dispatch.DispatchQueue : Combine.Scheduler` in
// .../MacOSX.sdk/usr/lib/swift/Dispatch.swiftmodule/x86_64-apple-macos.swiftinterface): the nested
// `SchedulerTimeType` (Strideable, Codable, Hashable, Sendable) with its nested `Stride`
// (SchedulerTimeIntervalConvertible, Comparable, SignedNumeric, ExpressibleByFloatLiteral,
// Hashable, Codable), the `SchedulerOptions` (Sendable), `minimumTolerance`, `now` and the three
// `schedule` overloads.  The extension carries the SDK's `@available(macOS 10.15, ...)`.
//
// The bodies are OpenCombine's own, taken from its pinned checkout in this tree
// (overlays/build/OpenCombine/Sources/OpenCombineDispatch/DispatchQueue+Scheduler.swift, OpenCombine
// commit 10df981a64800643559490d72174f43438562e73), with its `OCombine` namespace collapsed onto
// `DispatchQueue` itself: `queue.async(...)` becomes `self.async(...)`,
// `queue.asyncAfter(...)` becomes `self.asyncAfter(...)`,
// `DispatchSource.makeTimerSource(queue: queue)` becomes `... (queue: self)`, and
// `OCombine.SchedulerTimeType` becomes `DispatchQueue.SchedulerTimeType`.  Its private
// `clampedIntProduct` helper is carried here as a fileprivate func.
//
// The file is one `DARLING_DISPATCH_COMBINE` block: build-arch.sh links the Dispatch module twice --
// once in its usual place, before Combine, and once again after Combine, where the define and the
// Combine framework are passed to the link. `canImport(Combine)` cannot be the gate: $out/modules
// keeps the Combine.swiftmodule from the previous build, so the earlier link would compile this
// conformance and then fail to resolve Combine's protocol descriptors.

#if DARLING_DISPATCH_COMBINE

import Combine

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension DispatchQueue: Scheduler {

	/// The scheduler time type used by the dispatch queue.
	public struct SchedulerTimeType: Strideable, Codable, Hashable, Sendable {

		/// The dispatch time represented by this type.
		public var dispatchTime: DispatchTime

		/// Creates a dispatch queue time type instance.
		///
		/// - Parameter time: The dispatch time to represent.
		public init(_ time: DispatchTime) {
			dispatchTime = time
		}

		/// Returns the distance to another dispatch queue time.
		///
		/// - Parameter other: Another dispatch queue time.
		/// - Returns: The time interval between this time and the provided time.
		public func distance(to other: SchedulerTimeType) -> Stride {
			return Stride(dispatchTime.distance(to: other.dispatchTime))
		}

		/// Returns a dispatch queue scheduler time calculated by advancing
		/// this instance's time by the given interval.
		///
		/// - Parameter n: A time interval to advance.
		/// - Returns: A dispatch queue time advanced by the given
		///   interval from this instance's time.
		public func advanced(by stride: Stride) -> SchedulerTimeType {
			return stride.magnitude == .max
				? .init(.distantFuture)
				: .init(dispatchTime + stride.timeInterval)
		}

		public func hash(into hasher: inout Hasher) {
			hasher.combine(dispatchTime.rawValue)
		}

		public func encode(to encoder: Encoder) throws {
			var container = encoder.singleValueContainer()
			try container.encode(dispatchTime.uptimeNanoseconds)
		}

		public init(from decoder: Decoder) throws {
			let container = try decoder.singleValueContainer()
			dispatchTime = try .init(uptimeNanoseconds: container.decode(UInt64.self))
		}

		@_alwaysEmitIntoClient
		public static func < (lhs: SchedulerTimeType, rhs: SchedulerTimeType) -> Bool {
			return lhs.dispatchTime < rhs.dispatchTime
		}

		/// A type that represents the distance between two values.
		public struct Stride: SchedulerTimeIntervalConvertible,
		                      Comparable,
		                      SignedNumeric,
		                      ExpressibleByFloatLiteral,
		                      Hashable,
		                      Codable {

			/// If created via floating point literal, the value is
			/// converted to nanoseconds via multiplication.
			public typealias FloatLiteralType = Double

			/// Nanoseconds, same as DispatchTimeInterval.
			public typealias IntegerLiteralType = Int

			/// A type that can represent the absolute value of any possible
			/// value of the conforming type.
			public typealias Magnitude = Int

			private var _nanoseconds: Int64

			/// The value of this time interval in nanoseconds.
			public var magnitude: Int {
				get {
					return Int(_nanoseconds)
				}
				set {
					_nanoseconds = Int64(newValue)
				}
			}

			/// A `DispatchTimeInterval` created with the value of this type
			/// in nanoseconds.
			public var timeInterval: DispatchTimeInterval {
				return .nanoseconds(magnitude)
			}

			private init(magnitude: Int64) {
				_nanoseconds = magnitude
			}

			/// Creates a dispatch queue time interval from the given
			/// dispatch time interval.
			///
			/// - Parameter timeInterval: A dispatch time interval.
			public init(_ timeInterval: DispatchTimeInterval) {
				switch timeInterval {
				case .seconds(let seconds):
					self = .seconds(seconds)
				case .milliseconds(let milliseconds):
					self = .milliseconds(milliseconds)
				case .microseconds(let microseconds):
					self = .microseconds(microseconds)
				case .nanoseconds(let nanoseconds):
					self = .nanoseconds(nanoseconds)
				case .never:
					self = .nanoseconds(.max)
				}
			}

			/// Creates a dispatch queue time interval from a floating-point
			/// seconds value.
			///
			/// - Parameter value: The number of seconds, as a `Double`.
			public init(floatLiteral value: Double) {
				self = .seconds(value)
			}

			/// Creates a dispatch queue time interval from an integer seconds value.
			///
			/// - Parameter value: The number of seconds, as an `Int`.
			public init(integerLiteral value: Int) {
				self = .seconds(value)
			}

			/// Creates a dispatch queue time interval from a binary integer type.
			///
			/// If `exactly` cannot convert to an `Int`, the resulting time interval
			/// is `nil`.
			///
			/// - Parameter exactly: A binary integer representing a time interval.
			public init?<Source: BinaryInteger>(exactly source: Source) {
				guard let value = Int(exactly: source) else { return nil }
				self = .seconds(value)
			}

			public static func < (lhs: Stride, rhs: Stride) -> Bool {
				return lhs._nanoseconds < rhs._nanoseconds
			}

			public static func * (lhs: Stride, rhs: Stride) -> Stride {
				// OpenCombine's own body here returns zero for every product. A multiplication that
				// silently answers zero is not a semantics any client can be given, so this is the
				// clamped product of the two magnitudes, the same arithmetic -- and the same helper --
				// the `seconds`/`milliseconds`/`microseconds` conversions below already use.
				return Stride(magnitude: clampedIntProduct(lhs._nanoseconds, rhs._nanoseconds))
			}

			public static func + (lhs: Stride, rhs: Stride) -> Stride {
				return Stride(magnitude: lhs._nanoseconds + rhs._nanoseconds)
			}

			public static func - (lhs: Stride, rhs: Stride) -> Stride {
				return Stride(magnitude: lhs._nanoseconds - rhs._nanoseconds)
			}

			public static func -= (lhs: inout Stride, rhs: Stride) {
				lhs._nanoseconds -= rhs._nanoseconds
			}

			public static func *= (lhs: inout Stride, rhs: Stride) {
				lhs = lhs * rhs
			}

			public static func += (lhs: inout Stride, rhs: Stride) {
				lhs._nanoseconds += rhs._nanoseconds
			}

			public static func seconds(_ value: Double) -> Stride {
				let nanoseconds = value * 1_000_000_000
				if nanoseconds >= Double(Int64.max) {
					return Stride(magnitude: .max)
				}
				if nanoseconds <= Double(Int64.min) {
					return Stride(magnitude: .min)
				}
				return Stride(magnitude: Int64(nanoseconds))
			}

			public static func seconds(_ value: Int) -> Stride {
				return Stride(magnitude: clampedIntProduct(Int64(value),
				                                           1_000_000_000))
			}

			public static func milliseconds(_ value: Int) -> Stride {
				return Stride(magnitude: clampedIntProduct(Int64(value), 1_000_000))
			}

			public static func microseconds(_ value: Int) -> Stride {
				return Stride(magnitude: clampedIntProduct(Int64(value), 1_000))
			}

			public static func nanoseconds(_ value: Int) -> Stride {
				return Stride(magnitude: Int64(value))
			}
		}
	}

	/// Options that affect the operation of the dispatch queue scheduler.
	public struct SchedulerOptions: Sendable {

		/// The dispatch queue quality of service.
		public var qos: DispatchQoS

		/// The dispatch queue work item flags.
		public var flags: DispatchWorkItemFlags

		/// The dispatch group, if any, that should be used for performing actions.
		public var group: DispatchGroup?

		public init(qos: DispatchQoS = .unspecified,
		            flags: DispatchWorkItemFlags = [],
		            group: DispatchGroup? = nil) {
			self.qos = qos
			self.flags = flags
			self.group = group
		}
	}

	public var minimumTolerance: SchedulerTimeType.Stride {
		return .nanoseconds(0)
	}

	public var now: SchedulerTimeType {
		return .init(.now())
	}

	public func schedule(options: SchedulerOptions?,
	                     _ action: @escaping () -> Void) {
		let options = options ?? .init()
		self.async(group: options.group,
		           qos: options.qos,
		           flags: options.flags,
		           execute: action)
	}

	public func schedule(after date: SchedulerTimeType,
	                     tolerance: SchedulerTimeType.Stride,
	                     options: SchedulerOptions?,
	                     _ action: @escaping () -> Void) {
		let options = options ?? .init()
		self.asyncAfter(deadline: date.dispatchTime,
		                qos: options.qos,
		                flags: options.flags,
		                execute: action)
	}

	/// Performs the action at some time after the specified date, at the specified
	/// frequency, optionally taking into account tolerance if possible.
	public func schedule(after date: SchedulerTimeType,
	                     interval: SchedulerTimeType.Stride,
	                     tolerance: SchedulerTimeType.Stride,
	                     options: SchedulerOptions?,
	                     _ action: @escaping () -> Void) -> Cancellable {
		let options = options ?? .init()
		let timer = DispatchSource.makeTimerSource(queue: self)
		timer.setEventHandler(qos: options.qos,
		                      flags: options.flags,
		                      handler: action)
		timer.schedule(deadline: date.dispatchTime,
		               repeating: interval.timeInterval,
		               leeway: tolerance.timeInterval)
		timer.resume()
		return AnyCancellable(timer.cancel)
	}
}

// This function is taken from swift-corelibs-libdispatch:
// https://github.com/apple/swift-corelibs-libdispatch/blob/c992dacf3ca114806e6ac9ffc9113b19255be9fe/src/swift/Time.swift#L134-L144
//
// Returns m1 * m2, clamped to the range [Int64.min, Int64.max].
// Because of the way this function is used, we can always assume
// that m2 > 0.
fileprivate func clampedIntProduct(_ lhs: Int64, _ rhs: Int64) -> Int64 {
	assert(rhs > 0, "multiplier must be positive")
	let (result, overflow) = lhs.multipliedReportingOverflow(by: rhs)
	if overflow {
		return lhs > 0 ? .max : .min
	}
	return result
}

#endif
