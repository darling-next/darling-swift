#!/bin/sh
# Build libCoreEntitlements.dylib (x86_64, guest /usr/lib) and place it under ../../substitutes/.
#
# WHAT THIS BUILDS. A TRUTHFUL substitute, not an implementation: the image exports the six names
# DVTPortal demands (measured per dependency field), answers the four operations with an explicit
# "not implemented in this guest" CE_Error_t, and declares CECRuntime NULL and kCENoError as the
# "no error" CFStringRef the name claims. libCoreEntitlements.c carries the full measurement, the
# client call sites the shapes come from, and the reasoning for each answer.
#
# REPRODUCIBLE: the same source and the same toolchain inputs produce the same bytes from any
# checkout directory (the recipe reads nothing outside its own directory and the environment).
#
# Required environment (the same names the sibling overlay recipes use):
#   SWIFT_TOOLCHAIN     usr/ directory of a Swift toolchain (the Linux release works; it carries clang)
#   DARLING_SDK         Darling's MacOSX.sdk (CoreFoundation headers, sys/cdefs.h default-platform fix)
#   DARLING_LD          Darling's ld64 (build/src/external/cctools-port/cctools/ld64/src/x86_64-apple-darwin20-ld)
#   DARLING_LIBSYSTEM   Darling's built libSystem.B.dylib
#   DARLING_ROOT        installed Darling root (libexec/darling): libobjc and CoreFoundation come from it
# Optional:
#   SWIFT_DARWIN_ARCH   x86_64 (default)
#   COREENTITLEMENTS_OUT output directory (default: $here/build)
set -eu

here=$(cd "$(dirname "$0")" && pwd)
payload=$(cd "$here/../.." && pwd)

: "${SWIFT_TOOLCHAIN:?}" "${DARLING_SDK:?}" "${DARLING_LD:?}"
: "${DARLING_LIBSYSTEM:?}" "${DARLING_ROOT:?}"

SWIFT_DARWIN_ARCH=${SWIFT_DARWIN_ARCH:-x86_64}
SWIFT_DARWIN_TARGET=${SWIFT_DARWIN_TARGET:-$SWIFT_DARWIN_ARCH-apple-macosx26.0}
out=${COREENTITLEMENTS_OUT:-$here/build}
dest="$payload/substitutes/usr/lib"

rm -rf "$out/obj"
mkdir -p "$out/obj" "$dest"

"$SWIFT_TOOLCHAIN/bin/clang" -target "$SWIFT_DARWIN_TARGET" -isysroot "$DARLING_SDK" \
	-fno-common -O2 -Wall -Wextra \
	-c "$here/libCoreEntitlements.c" -o "$out/obj/libCoreEntitlements.o"

# The compatibility version is the value dyld enforces and the demand's own value (measured from
# DVTPortal's LC_LOAD_DYLIB: compatibility 1.0.0). The current version is this substitute's own
# 1.0.0: dyld does not enforce it, and claiming Apple's would claim an implementation this image
# does not have.
"$DARLING_LD" -dylib -arch "$SWIFT_DARWIN_ARCH" \
	-platform_version macos 26.0 26.0 -syslibroot "$DARLING_SDK" \
	-install_name "/usr/lib/libCoreEntitlements.dylib" \
	-compatibility_version 1.0.0 -current_version 1.0.0 \
	"$DARLING_LIBSYSTEM" "$DARLING_ROOT/usr/lib/libobjc.A.dylib" \
	"$DARLING_ROOT/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation" \
	"$out/obj/libCoreEntitlements.o" \
	-o "$dest/libCoreEntitlements.dylib"

echo "built $dest/libCoreEntitlements.dylib"
