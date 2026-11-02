#!/bin/sh
# Build NaturalLanguage.framework's binary (x86_64, guest /System/Library/Frameworks) into the payload
# root, where the rootless manifest's `*.framework` glob discovers and declares it.
#
# WHAT THIS BUILDS. The Objective-C half of a TRUTHFUL substitute: the five names the two referrers
# demand, with the factories the clients are measured to send answering nil (there is no language
# asset or tagger engine in this guest) and the two constants carrying their documented values.
# NaturalLanguage.m holds the measurement, the SDK-header line each declaration comes from, and the
# reasoning. The Swift half (libswiftNaturalLanguage.dylib) is ../NaturalLanguage/build-overlay.sh.
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
#   NATURALLANGUAGE_OUT output directory (default: $here/build)
set -eu

here=$(cd "$(dirname "$0")" && pwd)
payload=$(cd "$here/../.." && pwd)
libs=${SWIFT_PAYLOAD_LIBS:-$payload}

: "${SWIFT_TOOLCHAIN:?}" "${DARLING_SDK:?}" "${DARLING_LD:?}"
: "${DARLING_LIBSYSTEM:?}" "${DARLING_ROOT:?}" "${SWIFT_RESOURCE_DIR:?}"

SWIFT_DARWIN_ARCH=${SWIFT_DARWIN_ARCH:-x86_64}
SWIFT_DARWIN_TARGET=${SWIFT_DARWIN_TARGET:-$SWIFT_DARWIN_ARCH-apple-macosx26.0}
out=${NATURALLANGUAGE_OUT:-$here/build}
dest="$payload/NaturalLanguage.framework/Versions/A"

rm -rf "$out/obj"
mkdir -p "$out/obj" "$dest"

"$SWIFT_TOOLCHAIN/bin/clang" -target "$SWIFT_DARWIN_TARGET" -isysroot "$DARLING_SDK" \
	-fobjc-arc -fno-common -O2 -Wall -Wextra \
	-c "$here/NaturalLanguage.m" -o "$out/obj/NaturalLanguage.o"

# Compatibility version 1.0.0 is the value dyld enforces and the demand's own (measured from both
# referrers' LC_LOAD_DYLIB: compatibility 1.0.0, current 114.0.0). The current version is this
# substitute's own 1.0.0: dyld does not enforce it, and claiming Apple's would claim Apple's build.
"$DARLING_LD" -dylib -arch "$SWIFT_DARWIN_ARCH" \
	-platform_version macos 26.0 26.0 -syslibroot "$DARLING_SDK" \
	-install_name "/System/Library/Frameworks/NaturalLanguage.framework/Versions/A/NaturalLanguage" \
	-compatibility_version 1.0.0 -current_version 1.0.0 \
	-L "$SWIFT_RESOURCE_DIR/macosx" -L "$libs" \
	"$DARLING_LIBSYSTEM" "$DARLING_ROOT/usr/lib/libobjc.A.dylib" \
	"$DARLING_ROOT/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation" \
	"$DARLING_ROOT/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation" \
	-lswiftFoundation -lswiftCoreFoundation -lswiftObjectiveC -lswiftDarwin -lswiftCore \
	"$out/obj/NaturalLanguage.o" \
	-o "$dest/NaturalLanguage"

echo "built $dest/NaturalLanguage"
