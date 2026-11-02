#!/bin/sh
# Build RemoteServiceDiscovery.framework's binary (x86_64+i386 by default, guest PrivateFrameworks
# path) and place it under ../../substitutes/System/Library/PrivateFrameworks/.
#
# WHAT THIS BUILDS. The measured broker/device/service client surface, including the three
# com.apple.remoted.control commands. It is a genuine client of the existing XPC transport: when the
# broker/control services are absent it returns the real XPC error (NULL/false/-1), never a synthetic
# device, reply, or empty catalog. RemoteServiceDiscovery.c records the native measurements.
#
# The x86_64 slice is the measured consumer slice. The i386 slice is built because the canonical
# RemoteXPC target is universal and links this image; it is not a claim of a separately measured
# i386 consumer.
#
# Required environment (the same names the sibling overlay recipes use):
#   SWIFT_TOOLCHAIN     usr/ directory of a Swift toolchain (the Linux release works; it carries clang)
#   DARLING_SDK         Darling's MacOSX.sdk
#   DARLING_LD          Darling's ld64 (build/src/external/cctools-port/cctools/ld64/src/x86_64-apple-darwin20-ld)
#   DARLING_LIBSYSTEM   Darling's built libSystem.B.dylib
#   DARLING_ROOT        installed Darling root (libexec/darling): libobjc and CoreFoundation come from it
# Optional:
#   SWIFT_DARWIN_ARCH   single architecture override (for example x86_64)
#   SWIFT_DARWIN_ARCHS  architecture list (default: x86_64 i386)
#   SWIFT_DARWIN_TARGET target triple override for a single-architecture build
#   REMOTESERVICEDISCOVERY_OUT  output directory (default: $here/build)
set -eu

here=$(cd "$(dirname "$0")" && pwd)
payload=$(cd "$here/../.." && pwd)

: "${SWIFT_TOOLCHAIN:?}" "${DARLING_SDK:?}" "${DARLING_LD:?}"
: "${DARLING_LIBSYSTEM:?}" "${DARLING_ROOT:?}"

if [ -n "${SWIFT_DARWIN_ARCH:-}" ]; then
	archs=$SWIFT_DARWIN_ARCH
else
	archs=${SWIFT_DARWIN_ARCHS:-"x86_64 i386"}
fi
out=${REMOTESERVICEDISCOVERY_OUT:-$here/build}
dest="$payload/substitutes/System/Library/PrivateFrameworks/RemoteServiceDiscovery.framework/Versions/A"
slices=""

rm -rf "$out/obj"
mkdir -p "$out/obj" "$dest"

for arch in $archs; do
	if [ -n "${SWIFT_DARWIN_TARGET:-}" ]; then
		target=$SWIFT_DARWIN_TARGET
	else
		target="$arch-apple-macosx26.0"
	fi
	object="$out/obj/RemoteServiceDiscovery.$arch.o"
	slice="$out/obj/RemoteServiceDiscovery.$arch"
	"$SWIFT_TOOLCHAIN/bin/clang" -target "$target" -isysroot "$DARLING_SDK" \
		-fno-common -fblocks -O2 -Wall -Wextra -x objective-c \
		-c "$here/RemoteServiceDiscovery.c" -o "$object"

	# Compatibility version 1.0.0 is the value dyld enforces and the demand's own (measured from
	# XCTDaemonControl's LC_LOAD_DYLIB). The current version is this substitute's own 1.0.0: dyld
	# does not enforce it, and claiming Apple's 202.60.3 would claim an implementation this image
	# lacks.
	"$DARLING_LD" -dylib -arch "$arch" \
		-platform_version macos 26.0 26.0 -syslibroot "$DARLING_SDK" \
		-install_name "/System/Library/PrivateFrameworks/RemoteServiceDiscovery.framework/Versions/A/RemoteServiceDiscovery" \
		-compatibility_version 1.0.0 -current_version 1.0.0 \
		"$DARLING_LIBSYSTEM" "$DARLING_ROOT/usr/lib/libobjc.A.dylib" \
		"$DARLING_ROOT/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation" \
		"$object" -o "$slice"
	slices="$slices $slice"
done

if [ "$(echo $archs | wc -w)" -gt 1 ]; then
	# shellcheck disable=SC2086
	"$SWIFT_TOOLCHAIN/bin/llvm-lipo" -create $slices -output "$dest/RemoteServiceDiscovery"
else
	cp "$slice" "$dest/RemoteServiceDiscovery"
fi

echo "built $dest/RemoteServiceDiscovery"
