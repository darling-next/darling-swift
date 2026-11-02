#!/bin/sh
# Build the measured StorageKit class surface with a real hdiutil attach/mount.
#
# The class and selector surface is the one CoreDevice binds and sends:
#   overlays/StorageKit/SKInternal.h
# Attach runs /usr/bin/hdiutil in the guest; manager state records the mounted disk.
#
# Required environment:
#   SWIFT_TOOLCHAIN     toolchain root (usr/ directory containing bin/clang)
#   DARLING_SDK         Darling's MacOSX.sdk
#   DARLING_LD          Darling's ld64
#   DARLING_LIBSYSTEM   Darling's built libSystem.B.dylib
#   DARLING_ROOT        installed Darling root (libexec/darling): libobjc and Foundation
# Optional:
#   STORAGEKIT_OUT      object directory (default: $here/build)
set -eu

here=$(cd "$(dirname "$0")" && pwd)
payload=$(cd "$here/../.." && pwd)

: "${SWIFT_TOOLCHAIN:?}" "${DARLING_SDK:?}" "${DARLING_LD:?}"
: "${DARLING_LIBSYSTEM:?}" "${DARLING_ROOT:?}"

arch=x86_64
target="$arch-apple-macosx26.0"
out=${STORAGEKIT_OUT:-$here/build}
dest="$payload/substitutes/System/Library/PrivateFrameworks/StorageKit.framework/Versions/A"

rm -rf "$out/obj"
mkdir -p "$out/obj" "$dest"

for src in "$here"/*.m; do
	obj="$out/obj/$(basename "$src" .m).o"
	"$SWIFT_TOOLCHAIN/bin/clang" -target "$target" -isysroot "$DARLING_SDK" \
		-I "$here" \
		-fobjc-runtime=macosx-10.13 -fblocks -fno-common -O2 -Wall -Wextra \
		-c "$src" -o "$obj"
done

"$DARLING_LD" -dylib -arch "$arch" \
	-platform_version macos 26.0 26.0 -syslibroot "$DARLING_SDK" \
	-install_name "/System/Library/PrivateFrameworks/StorageKit.framework/Versions/A/StorageKit" \
	-compatibility_version 1.0.0 -current_version 1.0.0 \
	-dylib_file /usr/lib/swift/libswiftFoundation.dylib:$DARLING_ROOT/usr/lib/swift/libswiftFoundation.dylib \
	"$out"/obj/*.o \
	"$DARLING_LIBSYSTEM" \
	"$DARLING_ROOT/usr/lib/libobjc.A.dylib" \
	"$DARLING_ROOT/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation" \
	"$DARLING_ROOT/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation" \
	-o "$dest/StorageKit"

echo "built $dest/StorageKit"
