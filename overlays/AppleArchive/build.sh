#!/bin/sh
# Build libswiftAppleArchive.dylib for the guest and copy it beside the other libswift*.dylib.
#
# WHAT THIS BUILDS. AppleArchive.swift, a Swift overlay in which every member is either REAL or a
# documented "cannot", not a subset of Apple's AppleArchive and not a "STUB:" family. REAL: the
# ArchiveCompression codec identifiers, FieldKey/FieldKeySet (a real parsed key set), ArchiveError,
# and a byte stream over a file descriptor (withFileStream/fileStream(fd:) mapped onto the file I/O
# system calls, i.e. libSystem's read/write/pread/pwrite/lseek/close). "CANNOT": every factory and
# member that would need the Apple Archive engine or its block-compression container answers nil or
# the documented error. It exists because /usr/lib/swift/libswiftAppleArchive.dylib is demanded at
# LOAD time by DVTInstrumentsFoundation, which binds exactly 23 symbols from it; the real format work
# is separate (dar-vg6u). Read the header of AppleArchive.swift for the boundary and for the
# measurements behind each "cannot".
#
# NO NEW LINK INPUT is needed for the file I/O calls: they are libSystem entry points, and this image
# already links DARLING_LIBSYSTEM (the built dylib's bind tables show _read/_write/_pread/_pwrite in
# __DATA_CONST __got against libSystem, and the deployed /usr/lib/libSystem.B.dylib re-exports
# /usr/lib/system/libsystem_kernel.dylib, which defines them).
#
# Required environment (same names as ../build.sh, plus one):
#   SWIFT_TOOLCHAIN     usr/ directory of a Swift toolchain (the Linux release works)
#   SWIFT_RESOURCE_DIR  usr/lib/swift from a swift-<version>-RELEASE-osx.pkg (Swift/_Concurrency modules)
#   DARLING_SDK         Darling's MacOSX.sdk (Clang module maps for Darwin/objc, sys/cdefs.h fix)
#   DARLING_LD          Darling's ld64 (build/src/external/cctools-port/cctools/ld64/src/x86_64-apple-darwin20-ld)
#   DARLING_LIBSYSTEM   Darling's built libSystem.B.dylib
#   DARLING_LIBOBJC     Darling's built libobjc.A.dylib
#   SWIFT_SYSTEM_MODULES  directory holding the SDK's System.swiftmodule (x86_64-apple-macos).
#                       Required, and named separately because System is NOT in SWIFT_RESOURCE_DIR:
#                       it is an Apple-SDK-shipped Swift overlay module. The 23 demanded names encode
#                       `System.FilePath`/`System.FileDescriptor` in their mangling, so the module
#                       must be compiled against the real System interface; pointing this at a
#                       different System build would change the ABI the module is compiled for.
#
# HOW THE System DEPENDENCY IS KEPT OFF THE LOAD PATH. entryPath's nil result materialises a
# `System.FilePath?`, which touches the System module's metadata accessor
# `_$s6System8FilePathVMa`. The guest carries no libswiftSystem, and a load command for it would turn
# this rung into an image-not-found one, so swiftc is told `-disable-autolink-library swiftSystem`
# and ld64 is told the one symbol may stay undefined (`-U`). The reference is a LAZY flat bind in
# __DATA_CONST __la_symbol_ptr: dyld does not resolve it at load, and no measured workload calls
# entryPath. It is a known lazy dependency, not a fabricated data symbol.
#
# Output: the built dylib, additionally copied to ../../libswiftAppleArchive.dylib (the payload
# directory the rootless manifest globs) when run with that default.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
payload=$(cd "$here/../.." && pwd)

: "${SWIFT_TOOLCHAIN:?}" "${SWIFT_RESOURCE_DIR:?}" "${DARLING_SDK:?}" "${DARLING_LD:?}"
: "${DARLING_LIBSYSTEM:?}" "${DARLING_LIBOBJC:?}" "${SWIFT_SYSTEM_MODULES:?}"

SWIFT_DARWIN_ARCH=${SWIFT_DARWIN_ARCH:-x86_64}
SWIFT_DARWIN_TARGET=${SWIFT_DARWIN_TARGET:-$SWIFT_DARWIN_ARCH-apple-macosx26.0}
out=${AA_OUT:-$here/build}
mkdir -p "$out/obj" "$out/modules" "$out/include"

# Isolate the SDK's System.swiftmodule in a directory of its own. -I on the whole SDK swift
# directory would also pull its shims/module.modulemap, which redefines _SwiftConcurrencyShims and
# SwiftOverlayShims against SWIFT_RESOURCE_DIR's. A symlink keeps this build reading the SDK's
# interface and nothing else.
ln -sfn "$SWIFT_SYSTEM_MODULES/System.swiftmodule" "$out/include/System.swiftmodule"

"$SWIFT_TOOLCHAIN/bin/swiftc" -frontend -c "$here/AppleArchive.swift" \
	-target "$SWIFT_DARWIN_TARGET" -sdk "$DARLING_SDK" -resource-dir "$SWIFT_RESOURCE_DIR" \
	-module-cache-path "$out/module-cache" -swift-version 5 \
	-module-name AppleArchive -module-link-name swiftAppleArchive -parse-as-library -O \
	-enable-library-evolution \
	-I "$out/include" \
	-disable-autolink-library swiftSystem \
	-emit-module-path "$out/modules/AppleArchive.swiftmodule" \
	-o "$out/obj/AppleArchive.o"

# ld64 demotes nothing here: the exports are the public Swift ABI of the declarations in the source.
# -arch moves with the compiler target, as in ../build-arch.sh, so this builds x86_64 on an
# x86_64-guest host.
"$DARLING_LD" -dylib -arch "$SWIFT_DARWIN_ARCH" \
	-platform_version macos 26.0 26.0 -syslibroot "$DARLING_SDK" \
	-install_name "/usr/lib/swift/libswiftAppleArchive.dylib" \
	-compatibility_version 1.0.0 -current_version 1.0.0 \
	-U '_$s6System8FilePathVMa' \
	-L "$SWIFT_RESOURCE_DIR/macosx" \
	"$out/obj/AppleArchive.o" "$DARLING_LIBSYSTEM" "$DARLING_LIBOBJC" -lswiftCore \
	-o "$out/libswiftAppleArchive.dylib"

cp "$out/libswiftAppleArchive.dylib" "$payload/libswiftAppleArchive.dylib"
echo "built $out/libswiftAppleArchive.dylib and copied it to $payload/libswiftAppleArchive.dylib"
