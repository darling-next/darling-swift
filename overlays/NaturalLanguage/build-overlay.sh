#!/bin/sh
# Build libswiftNaturalLanguage.dylib (x86_64, guest /usr/lib/swift) into the payload root, where the
# rootless manifest's `libswift*.dylib` glob discovers and declares it.
#
# WHAT THIS BUILDS. A clean-room Swift module named `NaturalLanguage` (that module name is what makes
# the mangled names match: `...C15NaturalLanguageE...` is "extension in NaturalLanguage") exposing the
# four names DVTSmartSearch demands, each answering the absence of the language model it would ask.
# See libswiftNaturalLanguage.swift for the source search that decided the route and for each answer.
#
# THE SHIM. This build has no Clang module for the framework (Apple's SDK ships one, Darling's does
# not, and the SDK's own Swift overlay interface cannot be rebuilt here), so shims/ declares the three
# classes and the four value types the four signatures name, with Apple's spellings -- which is what
# the mangling encodes. shims/DarlingNaturalLanguageShims.h says where each declaration comes from.
#
# Required environment (the same names the sibling overlay recipes use):
#   SWIFT_TOOLCHAIN     usr/ directory of a Swift toolchain (the Linux release works)
#   SWIFT_RESOURCE_DIR  usr/lib/swift from a swift-<version>-RELEASE-osx.pkg (Swift/_Concurrency modules)
#   DARLING_SDK         Darling's MacOSX.sdk (Foundation headers for the shim)
#   DARLING_LD          Darling's ld64 (build/src/external/cctools-port/cctools/ld64/src/x86_64-apple-darwin20-ld)
#   DARLING_LIBSYSTEM   Darling's built libSystem.B.dylib
#   DARLING_ROOT        installed Darling root (libexec/darling): libobjc and CoreFoundation
#   SWIFT_FOUNDATION_MODULES  the overlay modules directory for this target (the tree's own overlay
#                       build writes it; default: $here/../build/modules)
# Optional:
#   SWIFT_DARWIN_ARCH   x86_64 (default)
#   SWIFT_PAYLOAD_LIBS  where the payload's own libswift*.dylib live (default: $payload)
#   NATURALLANGUAGE_OVERLAY_OUT  output directory (default: $here/build-overlay)
set -eu

here=$(cd "$(dirname "$0")" && pwd)
payload=$(cd "$here/../.." && pwd)
libs=${SWIFT_PAYLOAD_LIBS:-$payload}
modules=${SWIFT_FOUNDATION_MODULES:-$here/../build/modules}

: "${SWIFT_TOOLCHAIN:?}" "${SWIFT_RESOURCE_DIR:?}" "${DARLING_SDK:?}" "${DARLING_LD:?}"
: "${DARLING_LIBSYSTEM:?}" "${DARLING_ROOT:?}"

[ -f "$modules/Foundation.swiftmodule" ] || {
	echo "$modules holds no Foundation.swiftmodule (set SWIFT_FOUNDATION_MODULES)" >&2
	exit 2
}

SWIFT_DARWIN_ARCH=${SWIFT_DARWIN_ARCH:-x86_64}
SWIFT_DARWIN_TARGET=${SWIFT_DARWIN_TARGET:-$SWIFT_DARWIN_ARCH-apple-macosx26.0}
out=${NATURALLANGUAGE_OVERLAY_OUT:-$here/build/overlay}

# A clean object/module directory every run: a leftover .swiftmodule from a different source list or
# module cache would be read silently.
rm -rf "$out/obj" "$out/modules" "$out/module-cache"
mkdir -p "$out/obj" "$out/modules" "$out/module-cache"

# The module flags are Apple's own, taken from the first line of the SDK's
# NaturalLanguage.swiftmodule/x86_64-apple-macos.swiftinterface
# (`-autolink-force-load -enable-library-evolution -module-link-name swiftNaturalLanguage
#   -swift-version 5 -library-level api -user-module-version 4.3 -module-name NaturalLanguage`),
# at this tree's macOS 26.0 target, with the language-level features that interface needs.
"$SWIFT_TOOLCHAIN/bin/swiftc" -frontend -c "$here/libswiftNaturalLanguage.swift" \
	-target "$SWIFT_DARWIN_TARGET" -sdk "$DARLING_SDK" -resource-dir "$SWIFT_RESOURCE_DIR" \
	-module-cache-path "$out/module-cache" -swift-version 5 \
	-module-name NaturalLanguage -module-link-name swiftNaturalLanguage -autolink-force-load \
	-enable-library-evolution -library-level api -parse-as-library -O \
	-user-module-version 4.3 \
	-enable-experimental-feature DebugDescriptionMacro -enable-bare-slash-regex \
	-I "$modules" \
	-Xcc -fmodule-map-file="$here/shims/module.modulemap" \
	-emit-module-path "$out/modules/NaturalLanguage.swiftmodule" \
	-o "$out/obj/NaturalLanguage.o"

# The install name, compatibility version and current version are the ones Apple's .tbd declares
# (install-name /usr/lib/swift/libswiftNaturalLanguage.dylib, current-version 4.3), so a client
# built against Apple's SDK binds the same image and the same numbers.
"$DARLING_LD" -dylib -arch "$SWIFT_DARWIN_ARCH" \
	-platform_version macos 26.0 26.0 -syslibroot "$DARLING_SDK" \
	-install_name "/usr/lib/swift/libswiftNaturalLanguage.dylib" \
	-compatibility_version 1.0.0 -current_version 4.3.0 \
	-L "$SWIFT_RESOURCE_DIR/macosx" -L "$libs" \
	"$DARLING_LIBSYSTEM" "$DARLING_ROOT/usr/lib/libobjc.A.dylib" \
	"$DARLING_ROOT/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation" \
	-lswiftFoundation -lswiftCoreFoundation -lswiftObjectiveC -lswiftDarwin -lswiftCore \
	"$out/obj/NaturalLanguage.o" \
	-o "$payload/libswiftNaturalLanguage.dylib"

echo "built $payload/libswiftNaturalLanguage.dylib"
