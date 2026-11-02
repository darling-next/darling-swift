/*
 The Clang declarations the Accelerate overlay compiles against.

 WHY A SHIM. The Swift module `Accelerate` is the SDK overlay over the Clang module `Accelerate`
 (Apple's own interface opens with `@_exported import Accelerate` and
 `@_exported import Accelerate.vecLib.BNNS`), and the Swift half of the modern BNNS API names three
 Clang types: `BNNSNDArrayDescriptor`, `BNNSDataType` and `BNNSDataLayout`. Darling's SDK has no
 Clang module for the framework's vecLib subframework -- `MacOSX.sdk/System/Library/Frameworks/
 Accelerate.framework` carries `Headers/Accelerate.h` and no `Modules/module.modulemap`, and the
 vecLib headers are not in the SDK at all -- so the overlay declares the three types it names, the
 way `overlays/AppKit`, `overlays/SceneKit` and `overlays/UniformTypeIdentifiers` declare theirs.

 THE DECLARATIONS ARE APPLE'S, and this is the only place they are asserted. The struct is
 transcribed from Apple's public `bnns_structures.h` (the field order this file carries is the
 documented ABI, and Darling's own `src/frameworks/Accelerate/vecLib/BNNS/include/BNNS/BNNS.h`
 transcribes the same order for the same reason: a client built against Apple's header and a client
 built against this one exchange identical values). The two enums are transcribed from Apple's
 public `bnns_constants.h`, where they are spelled
 `BNNS_ENUM(BNNSDataType, uint32_t, ...)` / `BNNS_ENUM(BNNSDataLayout, uint32_t, ...)`, which
 expands to `typedef enum : uint32_t { ... } <name>`; only the constants this overlay uses are
 carried. No value here is invented, and no constant Apple publishes is given a different value.

 WHY THE TYPEDEFS MATTER FOR THE ABI. Apple's `BNNSDataType` and `BNNSDataLayout` are fixed
 underlying type C enums, which the Swift importer turns into structs -- that is why Apple's own
 library exports e.g. `_$sSo12BNNSDataTypea10AccelerateE5floatABvgZ` and
 `_$s10Accelerate4BNNSO5ShapeO6layoutSo14BNNSDataLayoutavg` (`So<len><name>`: the Clang-imported
 type, not a Swift type of the same name). Declaring them the same way is what makes this build
 emit the same mangled names; a `uint32_t` typedef instead would mangle them as `s6UInt32V` and a
 client's protocol witness and `Shape.layout` would not bind.
*/
#ifndef DARLING_ACCELERATE_BNNS_SHIMS_H
#define DARLING_ACCELERATE_BNNS_SHIMS_H

#include <stddef.h>
#include <stdint.h>

/* bnns.h: the descriptor's arrays are this long; `size`/`stride` use only the first n entries,
   where n is the layout's dimensionality. */
#define BNNS_MAX_TENSOR_DIMENSION 8

/* bnns_structures.h: flags is `BNNSNDArrayFlags`, a uint32_t bit field. */
typedef uint32_t BNNSNDArrayFlags;

/* bnns_constants.h. Only the constant the overlay's Shape maps to: BNNSDataLayoutVector is the
   1-dimensional layout, and `Shape.vector(_:stride:)` is the only Shape case this overlay
   declares. */
typedef enum : uint32_t {
	BNNSDataLayoutVector = 0x10000,
} BNNSDataLayout;

/* bnns_constants.h. The members the BNNSScalar conformances return; the bit layout is Apple's
   (Float/Int/UInt/Indexed/Miscellaneous ranges and the element width in the low bits). Float16,
   BFloat16, Int1/2/4, UInt1/2/3/4/6 and Indexed1/2/4/8 are not carried because no conformance
   in this overlay returns them. */
typedef enum : uint32_t {
	BNNSDataTypeFloatBit              = 0x10000,
	BNNSDataTypeFloat32               = BNNSDataTypeFloatBit | 32,

	BNNSDataTypeIntBit                = 0x20000,
	BNNSDataTypeInt8                  = BNNSDataTypeIntBit | 8,
	BNNSDataTypeInt16                 = BNNSDataTypeIntBit | 16,
	BNNSDataTypeInt32                 = BNNSDataTypeIntBit | 32,
	BNNSDataTypeInt64                 = BNNSDataTypeIntBit | 64,

	BNNSDataTypeUIntBit               = 0x40000,
	BNNSDataTypeUInt8                 = BNNSDataTypeUIntBit | 8,
	BNNSDataTypeUInt16                = BNNSDataTypeUIntBit | 16,
	BNNSDataTypeUInt32                = BNNSDataTypeUIntBit | 32,
	BNNSDataTypeUInt64                = BNNSDataTypeUIntBit | 64,

	BNNSDataTypeMiscellaneousBit      = 0x100000,
	BNNSDataTypeBoolean               = BNNSDataTypeMiscellaneousBit | 8,
} BNNSDataType;

/* bnns_structures.h, field for field and in its order. The overlay's descriptor extension reads
   and writes flags, layout, size, stride, data and data_type; table_data, table_data_type,
   data_scale and data_bias stay at the zero their default initializer leaves them at. */
typedef struct {
	BNNSNDArrayFlags flags;
	BNNSDataLayout layout;

	size_t size[BNNS_MAX_TENSOR_DIMENSION];
	size_t stride[BNNS_MAX_TENSOR_DIMENSION];

	void *data;
	BNNSDataType data_type;

	void *table_data;
	BNNSDataType table_data_type;

	float data_scale;
	float data_bias;
} BNNSNDArrayDescriptor;

#endif
