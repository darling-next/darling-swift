#!/bin/sh
# Build CoreML.framework's binary (x86_64, guest /System/Library/Frameworks/CoreML.framework) into the
# payload root, where the rootless manifest's `*.framework` glob discovers and declares it.
#
# WHAT THIS BUILDS. A TRUTHFUL substitute, not an implementation: the image exports the six classes
# DVTSmartSearch demands, and every entry point that asks for a model, a prediction, a multiarray or
# a feature value answers nil with an explicit NSError in Apple's own MLModelErrorDomain. CoreML.m
# holds the measurement, the SDK-header line each signature comes from, and the reasoning.
#
# Required environment (the same names the sibling overlay recipes use):
#   SWIFT_TOOLCHAIN     usr/ directory of a Swift toolchain (the Linux release works; it carries clang)
#   DARLING_SDK         Darling's MacOSX.sdk
#   DARLING_LD          Darling's ld64 (build/src/external/cctools-port/cctools/ld64/src/x86_64-apple-darwin20-ld)
#   DARLING_LIBSYSTEM   Darling's built libSystem.B.dylib
#   DARLING_ROOT        installed Darling root (libexec/darling): libobjc, Foundation, CoreFoundation
#   SWIFT_RESOURCE_DIR  usr/lib/swift from a swift-<version>-RELEASE-osx.pkg
# Optional:
#   SWIFT_DARWIN_ARCH   x86_64 (default)
#   SWIFT_PAYLOAD_LIBS  where the payload's own libswift*.dylib live (default: $payload)
#   COREML_OUT          output directory (default: $here/build)
set -eu

here=$(cd "$(dirname "$0")" && pwd)
payload=$(cd "$here/../.." && pwd)
libs=${SWIFT_PAYLOAD_LIBS:-$payload}

: "${SWIFT_TOOLCHAIN:?}" "${DARLING_SDK:?}" "${DARLING_LD:?}"
: "${DARLING_LIBSYSTEM:?}" "${DARLING_ROOT:?}" "${SWIFT_RESOURCE_DIR:?}"

SWIFT_DARWIN_ARCH=${SWIFT_DARWIN_ARCH:-x86_64}
SWIFT_DARWIN_TARGET=${SWIFT_DARWIN_TARGET:-$SWIFT_DARWIN_ARCH-apple-macosx26.0}
out=${COREML_OUT:-$here/build}
dest="$payload/CoreML.framework/Versions/A"

rm -rf "$out/obj"
mkdir -p "$out/obj" "$dest"

"$SWIFT_TOOLCHAIN/bin/clang" -target "$SWIFT_DARWIN_TARGET" -isysroot "$DARLING_SDK" \
	-fobjc-arc -fno-common -O2 -Wall -Wextra \
	-c "$here/CoreML.m" -o "$out/obj/CoreML.o"

# Compatibility version 1.0.0 is the value dyld enforces and the demand's own (measured from
# DVTSmartSearch's LC_LOAD_DYLIB: compatibility 1.0.0, current 1.0.0).
"$DARLING_LD" -dylib -arch "$SWIFT_DARWIN_ARCH" \
	-platform_version macos 26.0 26.0 -syslibroot "$DARLING_SDK" \
	-install_name "/System/Library/Frameworks/CoreML.framework/Versions/A/CoreML" \
	-compatibility_version 1.0.0 -current_version 1.0.0 \
	-L "$SWIFT_RESOURCE_DIR/macosx" -L "$libs" \
	"$DARLING_LIBSYSTEM" "$DARLING_ROOT/usr/lib/libobjc.A.dylib" \
	"$DARLING_ROOT/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation" \
	"$DARLING_ROOT/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation" \
	-lswiftFoundation -lswiftCoreFoundation -lswiftObjectiveC -lswiftDarwin -lswiftCore \
	"$out/obj/CoreML.o" \
	-o "$dest/CoreML"

echo "built $dest/CoreML"
