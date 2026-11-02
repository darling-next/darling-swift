/*
 Accelerate -- the BNNS subset of /usr/lib/swift/libswiftAccelerate.dylib, built for Darling.

 WHAT THIS BUILDS. The Swift overlay for module `Accelerate`, compiled for x86_64-apple-macosx26.0
 with library evolution, carrying the modern BNNS API surface the guest's load closure demands. It
 is the Swift half of /usr/lib/swift/libswiftAccelerate.dylib: `BNNS.Shape`, the `BNNSScalar`
 protocol and its conformances, and the `BNNSNDArrayDescriptor` extension, over the Clang types the
 shim in shims/ declares.

 WHY. The rung after SoftLinking is:

   Library not loaded: /usr/lib/swift/libswiftAccelerate.dylib
   Referenced from .../DVTSmartSearch.framework/Versions/A/DVTSmartSearch

 measured from the guest's Xcode 26.3 DVTSmartSearch, which links the image NON-weakly
 (LC_LOAD_DYLIB, compatibility version 1.0.0, current version 77.0.0), and which binds FOUR names
 from the dependency field `libswiftAccelerate`, all four through `__DATA_CONST,__got` (eager,
 non-lazy), and NOTHING else from that field (measured per dependency field with
 `llvm-objdump --macho --dyld-info`, never by substring):

   _$s10Accelerate4BNNSO5ShapeO6vectoryAESi_SitcAEmFWC
     enum case for Accelerate.BNNS.Shape.vector(Accelerate.BNNS.Shape.Type) -> (Swift.Int, Swift.Int)
     -> Accelerate.BNNS.Shape
   _$s10Accelerate4BNNSO5ShapeOMa
     type metadata accessor for Accelerate.BNNS.Shape
   _$sSf10Accelerate10BNNSScalarAAWP
     protocol witness table for Swift.Float : Accelerate.BNNSScalar in Accelerate
   _$sSo21BNNSNDArrayDescriptora10AccelerateE4data5shapeABSgSryxG_AC4BNNSO5ShapeOtcAC10BNNSScalarRzlufC
     (extension in Accelerate):__C.BNNSNDArrayDescriptor.init<A where A: Accelerate.BNNSScalar>
     (data: Swift.UnsafeMutableBufferPointer<A>, shape: Accelerate.BNNS.Shape) -> __C.BNNSNDArrayDescriptor?

 The referrer uses them together: it builds a 1D shape with `Shape.vector`, wraps a buffer in a
 `BNNSNDArrayDescriptor` with the initializer, and allocates the buffer that way before filling it
 with the BNNS random generator (DVTSmartSearch also binds BNNSCreateRandomGenerator,
 BNNSRandomFillUniformFloat and BNNSDestroyRandomGenerator from Accelerate's libBNNS, and nine vDSP
 names from libvDSP: same call path). So the four names are not decoration -- the case constructor,
 the metadata accessor, the witness table and the initializer have to agree with each other for the
 call to work, which is why this is a real subset rather than four exported symbols.

 WHERE THE DECLARATIONS COME FROM. Apple publishes the SDK's Swift interface for this module, and
 every declaration below is copied from it (macOS 26's MacOSX.sdk:
 usr/lib/swift/Accelerate.swiftmodule/x86_64-apple-macos.swiftinterface) --
 `public enum BNNS.Shape` with `case vector(_: Swift.Int, stride: Swift.Int = 0)`, `var rank: Int`,
 `var size: (Int, Int, Int, Int, Int, Int, Int, Int)`, `var stride: (...)`, `var layout:
 BNNSDataLayout`; `public protocol BNNSScalar { static var bnnsDataType: BNNSDataType { get } }`
 and its conformances; and the descriptor's `init?<T>(data: UnsafeMutableBufferPointer<T>, shape:
 BNNS.Shape)`. The module flags are the same file's `swift-module-flags:` line. The constants the
 implementations return are Apple's public `bnns_constants.h` values, carried in shims/.

 NO OPEN-SOURCE SOURCE EXISTS FOR THIS API, and that was searched rather than assumed:

   * swiftlang/swift `stdlib/public/Darwin/Accelerate` exists at swift-5.1-RELEASE and
     swift-5.2-RELEASE (35 files: Accelerate.swift, AccelerateBuffer.swift, BNNS.swift.gyb,
     Quadrature.swift, vDSP_*.swift, vForce_Operations.swift, vImage_*.swift) and at
     `stdlib/public/SDK/Accelerate` (BNNS.swift.gyb + CMakeLists.txt) at swift-4.0-RELEASE through
     swift-5.0-RELEASE; from swift-5.3-RELEASE the directory is gone. All 35 files at
     swift-5.2-RELEASE were fetched and searched: NONE of the four demanded names' declarations --
     no `BNNS.Shape`, no `BNNSScalar`, no `BNNSNDArrayDescriptor` extension -- occurs in any of
     them. The open-source overlay is the pre-`Shape` BNNS filter API (BNNSFilter and friends).
   * swiftlang/swift at swift-5.9-RELEASE and swift-6.2.4-RELEASE has no `stdlib/public/Darwin`
     at all (`stdlib/public` holds Platform, ClangOverlays, Concurrency, ...), so the modern API
     never entered the open-source tree.
   * The last Accelerate overlay revision is therefore swift-5.2-RELEASE, and it does not declare
     this API. Where it exists, its declarations were used; where it does not, the declarations
     come from the SDK's own published interface, which is the same source a client compiles
     against, and the constants from Apple's published headers.

 WHAT IT DELIBERATELY DOES NOT DECLARE, and this is the boundary rather than an oversight. Only
 the ONE Shape case the closure demands, `.vector`: the other cases' `size`/`stride` members need
 Apple's per-case dimension orderings (bnns.h documents that `BNNSDataLayoutRowMajorMatrix` and
 `BNNSDataLayout2DFirstMajor` fill `size[]` in different orders for the same data), which the
 declarations do not state, so this overlay cannot answer them without guessing. A client that
 binds another case or another member of the module binds a symbol this dylib does not export and
 fails at LOAD -- the correct direction, and the same boundary the sibling overlays state. The
 module's vDSP, vImage, Quadrature, BNNSTensor, BNNSGraph and optimizer families are likewise not
 here; nothing in the load closure demands them.

 WHAT THE IMPLEMENTATIONS DO, and where they answer rather than compute:

   * `Shape.vector(n, stride: s)` stores what the case carries. `rank` is 1, `size` is (n,1,1,...)
     and `stride` is (s,0,0,...), which is bnns.h's convention for the dimensions a layout does
     not use, and `layout` is BNNSDataLayoutVector, the 1-dimensional layout (bnns_constants.h).
     `stride` is returned as given: bnns.h documents 0 as "contiguous in this axis" and leaves the
     consumer to expand it, so this overlay does not pre-expand it either.
   * `BNNSScalar.bnnsDataType` answers the data type each Swift type corresponds to, from Apple's
     own constants (Float -> BNNSDataTypeFloat32, Int8 -> BNNSDataTypeInt8, Bool ->
     BNNSDataTypeBoolean, ...). No conformance invents a value, and Float16 is absent for the same
     reason the SDK marks it unavailable on Intel macOS.
   * `BNNSNDArrayDescriptor.init?(data:shape:)` copies the shape into the descriptor (layout, size,
     stride), points `data` at the buffer's base address and sets `data_type` from the element
     type, exactly the fields bnns_structures.h documents ("Returns a new n-dimensional array
     descriptor that references the same data as the specified pointer", in the SDK's own
     documentation of this initializer). `flags`, `table_data`, `table_data_type`, `data_scale` and
     `data_bias` keep the zero a default-initialized descriptor has; bnns_structures.h documents
     0.0 for `data_scale` as "will be set to 1.0 during computation", and no table is passed.
     It reports failure (nil) in exactly one case: a negative shape stride, which
     bnns_structures.h's `size_t stride[]` has no encoding for -- so the initializer refuses it
     instead of turning it into a huge unsigned stride. That is this implementation's stated
     failure condition, not a claim about Apple's.
*/
import _DarlingAccelerateBNNSShims

/* Accelerate.BNNS is an empty enum that namespaces the overlay, and the SDK's interface carries the
   same availability on it (`@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)`). */
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public enum BNNS {
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
extension BNNS {
	/* One case, because it is the only one this overlay can answer: `.vector` is the 1-dimensional
	   layout, so its size and stride have one dimension each and no ordering to guess. */
	public enum Shape {
		/* bnns_structures.h: `stride` is the increment in values between a value and the next;
		   0 means contiguous in this axis. */
		case vector(Int, stride: Int = 0)

		public var rank: Int {
			switch self {
			case .vector:
				return 1
			}
		}

		public var size: (Int, Int, Int, Int, Int, Int, Int, Int) {
			switch self {
			case let .vector(n, _):
				return (n, 1, 1, 1, 1, 1, 1, 1)
			}
		}

		public var stride: (Int, Int, Int, Int, Int, Int, Int, Int) {
			switch self {
			case let .vector(_, s):
				return (s, 0, 0, 0, 0, 0, 0, 0)
			}
		}

		public var layout: BNNSDataLayout {
			switch self {
			case .vector:
				return BNNSDataLayoutVector
			}
		}
	}
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public protocol BNNSScalar {
	static var bnnsDataType: BNNSDataType { get }
}

/* One conformance per type the SDK's interface conforms, each returning Apple's own constant for
   that type (bnns_constants.h). Float16 is not among them: the interface marks it unavailable on
   Intel macOS, which is the slice this dylib is built for. */
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
extension Float: BNNSScalar {
	public static var bnnsDataType: BNNSDataType { BNNSDataTypeFloat32 }
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
extension Int8: BNNSScalar {
	public static var bnnsDataType: BNNSDataType { BNNSDataTypeInt8 }
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
extension Int16: BNNSScalar {
	public static var bnnsDataType: BNNSDataType { BNNSDataTypeInt16 }
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
extension Int32: BNNSScalar {
	public static var bnnsDataType: BNNSDataType { BNNSDataTypeInt32 }
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
extension Int64: BNNSScalar {
	public static var bnnsDataType: BNNSDataType { BNNSDataTypeInt64 }
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
extension UInt8: BNNSScalar {
	public static var bnnsDataType: BNNSDataType { BNNSDataTypeUInt8 }
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
extension UInt16: BNNSScalar {
	public static var bnnsDataType: BNNSDataType { BNNSDataTypeUInt16 }
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
extension UInt32: BNNSScalar {
	public static var bnnsDataType: BNNSDataType { BNNSDataTypeUInt32 }
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
extension UInt64: BNNSScalar {
	public static var bnnsDataType: BNNSDataType { BNNSDataTypeUInt64 }
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
extension Bool: BNNSScalar {
	public static var bnnsDataType: BNNSDataType { BNNSDataTypeBoolean }
}

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
extension BNNSNDArrayDescriptor {
	public init?<T: BNNSScalar>(data: UnsafeMutableBufferPointer<T>, shape: BNNS.Shape) {
		let size = shape.size
		let stride = shape.stride

		/* bnns_structures.h types stride[] as size_t and the shape carries Int strides: a negative
		   stride has no encoding in the descriptor, so this initializer reports failure rather than
		   converting it into a huge unsigned value. */
		guard stride.0 >= 0, stride.1 >= 0, stride.2 >= 0, stride.3 >= 0,
		      stride.4 >= 0, stride.5 >= 0, stride.6 >= 0, stride.7 >= 0 else {
			return nil
		}

		var descriptor = BNNSNDArrayDescriptor()
		descriptor.flags = 0
		descriptor.layout = shape.layout
		descriptor.size = (size_t(size.0), size_t(size.1), size_t(size.2), size_t(size.3),
		                   size_t(size.4), size_t(size.5), size_t(size.6), size_t(size.7))
		descriptor.stride = (size_t(stride.0), size_t(stride.1), size_t(stride.2), size_t(stride.3),
		                     size_t(stride.4), size_t(stride.5), size_t(stride.6), size_t(stride.7))
		descriptor.data = UnsafeMutableRawPointer(data.baseAddress)
		descriptor.data_type = T.bnnsDataType
		self = descriptor
	}
}
