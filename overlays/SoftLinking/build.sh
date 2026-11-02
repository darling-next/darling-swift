#!/bin/sh
# Build SoftLinking.framework's binary (x86_64, guest PrivateFrameworks path) and place it under
# ../../substitutes/System/Library/PrivateFrameworks/SoftLinking.framework/Versions/A/.
#
# WHAT THIS BUILDS. The REAL soft-linking entry points Apple's private SoftLinking.framework
# exports -- __sl_dlopen and __sl_dlopen_audited -- as a small C library. SoftLinking.c carries the
# measurement (the rung, the single bind IDEFoundation makes, the call shape read off the two call
# sites in this Xcode, the directive grammar taken from ld64's open source) and states what each
# entry point does, including the one thing it cannot know: the meaning of the directive's flag
# token, which it therefore does not interpret.
#
# WHY NOT A STUB. A stub exporting the two names would satisfy the loader and then lie: IDEFoundation
# does not merely bind __sl_dlopen, it CALLS it to load SceneKit.framework and then asks the result
# for an Objective-C class. So this file performs a real dlopen of the path the caller passes and
# returns its handle, and reports the failure the way the caller expects (a malloc'd message it
# prints and aborts on).
#
# IT IS HEADLESS: the image's only load command is /usr/lib/libSystem.B.dylib (measured on the
# linked file), because dlopen, dlerror, malloc, fprintf and strncmp all come from it. That is the
# same shape Apple's own copy has.
#
# VERSIONS. Apple's tbd declares this install name at current-version 67; the referrer's load
# command asks for compatibility version 1.0.0 at current version 67.0.0 (measured with
# llvm-objdump --macho --dylibs-used on IDEFoundation). dyld enforces the COMPATIBILITY version
# only, and 1.0.0 is what the demand asks for. The current version here is this substitute's own
# 1.0.0, as in the sibling substitute recipes: claiming Apple's 67 would claim a revision of an
# Apple implementation this file is not.
#
# REPRODUCIBLE BYTES: verified by building this recipe from two different checkout directories and
# comparing sha256, not by inspection.
#
# Required environment (the same names the sibling overlay recipes use):
#   SWIFT_TOOLCHAIN     usr/ directory of a Swift toolchain (the Linux release works; it carries clang)
#   DARLING_SDK         Darling's MacOSX.sdk
#   DARLING_LD          Darling's ld64 (build/src/external/cctools-port/cctools/ld64/src/x86_64-apple-darwin20-ld)
#   DARLING_LIBSYSTEM   Darling's built libSystem.B.dylib
# Optional:
#   SWIFT_DARWIN_ARCH      x86_64 (default)
#   SOFTLINKING_OUT        output directory (default: $here/build)
set -eu

here=$(cd "$(dirname "$0")" && pwd)
payload=$(cd "$here/../.." && pwd)

: "${SWIFT_TOOLCHAIN:?}" "${DARLING_SDK:?}" "${DARLING_LD:?}" "${DARLING_LIBSYSTEM:?}"

SWIFT_DARWIN_ARCH=${SWIFT_DARWIN_ARCH:-x86_64}
SWIFT_DARWIN_TARGET=${SWIFT_DARWIN_TARGET:-$SWIFT_DARWIN_ARCH-apple-macosx26.0}
out=${SOFTLINKING_OUT:-$here/build}
dest="$payload/substitutes/System/Library/PrivateFrameworks/SoftLinking.framework/Versions/A"

rm -rf "$out/obj"
mkdir -p "$out/obj" "$dest"

"$SWIFT_TOOLCHAIN/bin/clang" -target "$SWIFT_DARWIN_TARGET" -isysroot "$DARLING_SDK" \
	-fno-common -O2 -Wall -Wextra \
	-c "$here/SoftLinking.c" -o "$out/obj/SoftLinking.o"

"$DARLING_LD" -dylib -arch "$SWIFT_DARWIN_ARCH" \
	-platform_version macos 26.0 26.0 -syslibroot "$DARLING_SDK" \
	-install_name "/System/Library/PrivateFrameworks/SoftLinking.framework/Versions/A/SoftLinking" \
	-compatibility_version 1.0.0 -current_version 1.0.0 \
	"$DARLING_LIBSYSTEM" \
	"$out/obj/SoftLinking.o" \
	-o "$dest/SoftLinking"

echo "built $dest/SoftLinking"
