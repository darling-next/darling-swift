#!/bin/sh
# Build libswiftAccelerate.dylib (the BNNS subset) for the guest and copy it beside the other
# libswift*.dylib in the payload.
#
# WHAT THIS BUILDS. The Swift overlay for module `Accelerate`, compiled as x86_64-apple-macosx26.0
# with library evolution: `BNNS.Shape` (the `.vector` case with rank/size/stride/layout), the
# `BNNSScalar` protocol and ten conformances, and
# `BNNSNDArrayDescriptor.init?(data:shape:)`. Accelerate.swift carries the measurement (the rung,
# the four names DVTSmartSearch binds, their demangled shapes, the source search that found no
# open-source revision of this API, and the boundary of what is declared and why).
#
# WHY IT IS A BUILD. There is no Accelerate overlay in the payload to copy: `/usr/lib/swift/
# libswiftAccelerate.dylib` has never been part of it, and the last open-source revision of the
# overlay (swiftlang/swift, stdlib/public/Darwin/Accelerate, swift-5.2-RELEASE) does not declare
# this API at all -- both were searched, not assumed (see Accelerate.swift's header). The
# declarations here are the SDK's own public interface for the module and the constants are Apple's
# published ones.
#
# IT IS HEADLESS ON PURPOSE: it links libswiftCore and libSystem only (measured on the linked
# image's LC_LOAD_DYLIB list), because the API it implements asks the C library for nothing --
# `Shape` is pure Swift, and the descriptor initializer only fills a struct. Both images exist in
# every prefix, so this dylib adds no dependency the deploy has to resolve.
#
# VERSIONS. Apple's own tbd for this install name (same SDK, usr/lib/swift/libswiftAccelerate.tbd)
# declares install-name /usr/lib/swift/libswiftAccelerate.dylib, current-version 77 and
# swift-abi-version 7, and the referrer's load command asks for compatibility version 1.0.0 at
# current version 77.0.0 -- measured with llvm-objdump --macho --dylibs-used on DVTSmartSearch.
# The numbers below are those; dyld enforces the compatibility version only.
#
# MODULE FLAGS are the SDK interface's own `swift-module-flags:` line for this module, minus the
# `-target-variant` (no Mac Catalyst slice here) and with this tree's target.
#
# FIDELITY, measured against that tbd. The build's export trie carries 61 symbols and every one of
# them is in Apple's x86_64-macos symbol set -- ZERO in the mine-only direction -- and all four
# names the referrer binds are among them. What is NOT here is the rest of the module (vDSP,
# vImage, Quadrature, BNNSTensor, BNNSGraph, the optimizer families and the other Shape cases);
# a client binding any of those fails at load, which is the correct direction and the boundary
# Accelerate.swift states.
#
# REPRODUCIBLE BYTES: verified by building this recipe from two different checkout directories and
# comparing sha256, not by inspection; no build path or other host state reaches the image (no
# debug info is emitted and no source carries __FILE__), so no prefix map is needed. The report
# carries the two paths and the digest.
#
# Required environment (the same names the sibling overlay recipes use):
#   SWIFT_TOOLCHAIN     usr/ directory of a Swift toolchain (the Linux release works; it carries clang)
#   SWIFT_RESOURCE_DIR  usr/lib/swift from a swift-<version>-RELEASE-osx.pkg (libswiftCore to link against)
#   DARLING_SDK         Darling's MacOSX.sdk
#   DARLING_LD          Darling's ld64 (build/src/external/cctools-port/cctools/ld64/src/x86_64-apple-darwin20-ld)
#   DARLING_LIBSYSTEM   Darling's built libSystem.B.dylib
# Optional:
#   SWIFT_DARWIN_ARCH    x86_64 (default)
#   SWIFT_PAYLOAD_LIBS   where the payload's own libswift*.dylib live, one of the images this dylib
#                        links (default: $payload) -- a copy of the recipe outside the payload points
#                        it at the payload, so the two-path reproducibility run links the same inputs
#   SWIFT_ACCELERATE_OUT output directory (default: $here/build)
set -eu

here=$(cd "$(dirname "$0")" && pwd)
payload=$(cd "$here/../.." && pwd)

: "${SWIFT_TOOLCHAIN:?}" "${SWIFT_RESOURCE_DIR:?}" "${DARLING_SDK:?}" "${DARLING_LD:?}"
: "${DARLING_LIBSYSTEM:?}"

SWIFT_DARWIN_ARCH=${SWIFT_DARWIN_ARCH:-x86_64}
SWIFT_DARWIN_TARGET=${SWIFT_DARWIN_TARGET:-$SWIFT_DARWIN_ARCH-apple-macosx26.0}
libs=${SWIFT_PAYLOAD_LIBS:-$payload}
out=${SWIFT_ACCELERATE_OUT:-$here/build}

# A clean object/module directory every run: a leftover .swiftmodule or module cache from a
# different source list or toolchain would be read silently.
rm -rf "$out/obj" "$out/module-cache" "$out/modules"
mkdir -p "$out/obj" "$out/module-cache" "$out/modules"

"$SWIFT_TOOLCHAIN/bin/swiftc" -frontend -c "$here/Accelerate.swift" \
	-target "$SWIFT_DARWIN_TARGET" -sdk "$DARLING_SDK" -resource-dir "$SWIFT_RESOURCE_DIR" \
	-module-cache-path "$out/module-cache" -swift-version 5 \
	-module-name Accelerate -module-link-name swiftAccelerate -autolink-force-load \
	-enable-library-evolution -library-level api -parse-as-library -O \
	-user-module-version 77 \
	-enable-experimental-feature DebugDescriptionMacro -enable-bare-slash-regex \
	-Xcc -fmodule-map-file="$here/shims/module.modulemap" \
	-emit-module-path "$out/modules/Accelerate.swiftmodule" \
	-o "$out/obj/Accelerate.o"

# ld64, with libSystem and the payload's libswiftCore as the only link inputs (see the header).
"$DARLING_LD" -dylib -arch "$SWIFT_DARWIN_ARCH" \
	-platform_version macos 26.0 26.0 -syslibroot "$DARLING_SDK" \
	-install_name "/usr/lib/swift/libswiftAccelerate.dylib" \
	-compatibility_version 1.0.0 -current_version 77 \
	-L "$SWIFT_RESOURCE_DIR/macosx" -L "$libs" \
	"$out/obj/Accelerate.o" \
	"$DARLING_LIBSYSTEM" \
	-lswiftCore \
	-o "$out/libswiftAccelerate.dylib"

cp "$out/libswiftAccelerate.dylib" "$payload/libswiftAccelerate.dylib"
echo "built $out/libswiftAccelerate.dylib and copied it to $payload/libswiftAccelerate.dylib"
