#!/bin/sh
# Build libswiftUniformTypeIdentifiers.dylib for the guest and copy it beside the other libswift*.dylib.
#
# WHAT THIS BUILDS. This tree's own clean-room UniformTypeIdentifiers overlay (Apache-2.0 with Runtime
# Library Exception application; written for Darling from the public UniformTypeIdentifiers
# declarations), compiled as module `UniformTypeIdentifiers` for x86_64-apple-macosx26.0 with library
# evolution.  It is the Swift half of /usr/lib/swift/libswiftUniformTypeIdentifiers.dylib: `UTType`
# wraps Darling's Objective-C UTType (src/frameworks/UniformTypeIdentifiers), which holds the type
# table; every member is a forward to it.  Nothing here is an Apple binary.
#
# WHY IT IS THE ROUTE (and not the checked-in overlay binary).  The rung after libswiftDemangle is:
#
#   Library not loaded: /usr/lib/swift/libswiftUniformTypeIdentifiers.dylib
#   Referenced from .../XCTHarness.framework/Versions/A/XCTHarness
#
# measured from the guest's Xcode 26.3 XCTHarness, which links the image NON-weakly (LC_LOAD_DYLIB,
# compatibility version 1.0.0, current version 877.2.1) while every OTHER libswift* missing from its
# load commands (CoreImage, IOKit, Metal, OSLog, QuartzCore, simd) is LC_LOAD_WEAK_DYLIB and is
# skipped.  XCTHarness's x86_64 slice binds TEN names from the dependency field
# `libswiftUniformTypeIdentifiers` (nine strong, one weak `__swift_FORCE_LOAD_$_...`), measured per
# dependency field with llvm-nm -m over the thin slice, never by substring:
#
#   _$s22UniformTypeIdentifiers15UTHardwareColorOMa            type metadata accessor for UTHardwareColor
#   _$s22UniformTypeIdentifiers15UTHardwareColorOMn            nominal type descriptor for UTHardwareColor
#   _$s22UniformTypeIdentifiers6UTTypeV10identifierSSvg        UTType.identifier.getter
#   _$s22UniformTypeIdentifiers6UTTypeV13utf8PlainTextACvgZ    static UTType.utf8PlainText.getter
#   _$s22UniformTypeIdentifiers6UTTypeV16_deviceModelCode14enclosureColorACSgSS_AA010UTHardwareI0OSgtcfC
#                                                              UTType.init(_deviceModelCode:enclosureColor:)
#   _$s22UniformTypeIdentifiers6UTTypeV20localizedDescriptionSSSgvg   UTType.localizedDescription.getter
#   _$s22UniformTypeIdentifiers6UTTypeV4textACvgZ              static UTType.text.getter
#   _$s22UniformTypeIdentifiers6UTTypeVMa                     type metadata accessor for UTType
#   _$s22UniformTypeIdentifiers6UTTypeVMn                     nominal type descriptor for UTType
#   __swift_FORCE_LOAD_$_swiftUniformTypeIdentifiers           (weak)
#
# The copy of this overlay that the git-lfs payload carries elsewhere (VibeDarling/darling-swift,
# arm64) cannot serve the rung: it is arm64-only, and it was built from an older revision of this
# source, so it is missing exactly the three macOS 26 names above (UTHardwareColor's Ma/Mn and the
# device-model-code initializer).  Hence a build, not a copy.
#
# MEASURED FIDELITY.  Apple ships a .tbd for this library in the same SDK
# (<Xcode>/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/lib/swift/libswiftUniformTypeIdentifiers.tbd,
# install name /usr/lib/swift/libswiftUniformTypeIdentifiers.dylib, current version 877.2.4,
# swift-abi-version 7) and that file is the ABI this build is measured against: 628 symbols.  The
# build's export trie is compared against it symbol by symbol; the counts and the classes of the
# differences are in the report, not guessed here.  The gaps are the underscored SPI of Apple's
# implementation (the `_macBookPro`/`_iOSDevice`/`_hfsCode`/`_deviceModelCode`/`_enclosureColor`
# family and the URL/String/NSItemProvider extensions), which this clean-room overlay deliberately
# does not declare.
#
# MODULE FLAGS are Apple's own, taken from the SDK's UniformTypeIdentifiers.swiftinterface header
# (`swift-module-flags:` line): -enable-library-evolution -library-level api -autolink-force-load
# -swift-version 5 -user-module-version 877.2.4 -enable-experimental-feature DebugDescriptionMacro
# -enable-bare-slash-regex, at this tree's macOS 26.0 target.
#
# THE ONE COMPILE-TIME INPUT THAT IS NOT A SOURCE.  This module imports Foundation, so the build needs
# a Foundation.swiftmodule for the SAME target whose ABI is the payload's libswiftFoundation.dylib --
# the overlay modules directory the tree's own overlay build produces (overlays/build-arch.sh with
# SWIFT_DARWIN_ARCH=x86_64 writes $here/build/modules).  Point SWIFT_FOUNDATION_MODULES at it; nothing
# verifies it, the way the other recipes' *_SRC variables are not verified either.
#
# REPRODUCIBLE BYTES: verified by building this recipe from two different checkout directories and
# comparing sha256, not by inspection.  See the report for the two paths and the digest.
#
# Required environment (the same names the sibling overlay recipes use):
#   SWIFT_TOOLCHAIN     usr/ directory of a Swift toolchain (the Linux release works; it carries clang)
#   SWIFT_RESOURCE_DIR  usr/lib/swift from a swift-<version>-RELEASE-osx.pkg (Swift/_Concurrency modules)
#   DARLING_SDK         Darling's MacOSX.sdk (the Clang module maps the shim header needs)
#   DARLING_LD          Darling's ld64 (build/src/external/cctools-port/cctools/ld64/src/x86_64-apple-darwin20-ld)
#   DARLING_LIBSYSTEM   Darling's built libSystem.B.dylib
#   DARLING_ROOT        installed Darling root (libexec/darling): libobjc and the framework binaries the
#                       overlay links (UniformTypeIdentifiers, Foundation, CoreFoundation)
# Optional:
#   SWIFT_DARWIN_ARCH           x86_64 (default)
#   SWIFT_FOUNDATION_MODULES    the overlay modules directory for this target (default: $here/../build/modules)
#   SWIFT_PAYLOAD_LIBS          where the payload's own libswift*.dylib live, the images this dylib links
#                               (default: $payload) -- a copy of the recipe outside the payload points it
#                               at the payload, so the two-path reproducibility run links the same inputs
#   UNIFORMTYPEIDENTIFIERS_OUT  output directory (default: $here/build)
set -eu

here=$(cd "$(dirname "$0")" && pwd)
payload=$(cd "$here/../.." && pwd)

: "${SWIFT_TOOLCHAIN:?}" "${SWIFT_RESOURCE_DIR:?}" "${DARLING_SDK:?}" "${DARLING_LD:?}"
: "${DARLING_LIBSYSTEM:?}" "${DARLING_ROOT:?}"

SWIFT_DARWIN_ARCH=${SWIFT_DARWIN_ARCH:-x86_64}
SWIFT_DARWIN_TARGET=${SWIFT_DARWIN_TARGET:-$SWIFT_DARWIN_ARCH-apple-macosx26.0}
modules=${SWIFT_FOUNDATION_MODULES:-$here/../build/modules}
libs=${SWIFT_PAYLOAD_LIBS:-$payload}
out=${UNIFORMTYPEIDENTIFIERS_OUT:-$here/build}

[ -d "$modules" ] || { echo "no overlay modules directory at $modules (set SWIFT_FOUNDATION_MODULES)" >&2; exit 2; }
[ -f "$modules/Foundation.swiftmodule" ] || { echo "$modules holds no Foundation.swiftmodule" >&2; exit 2; }

# A clean object/module directory every run: a leftover .swiftmodule from a different source list or
# module cache would be read silently.
rm -rf "$out/obj" "$out/module-cache" "$out/modules"
mkdir -p "$out/obj" "$out/module-cache" "$out/modules"

# The module flags are Apple's own (see the header). -library-level api is what the SDK's
# swiftinterface records for this module, and it is what makes the compiler emit the resilient
# property accessors Apple's .tbd carries.
"$SWIFT_TOOLCHAIN/bin/swiftc" -frontend -c "$here/UniformTypeIdentifiers.swift" \
	-target "$SWIFT_DARWIN_TARGET" -sdk "$DARLING_SDK" -resource-dir "$SWIFT_RESOURCE_DIR" \
	-module-cache-path "$out/module-cache" -swift-version 5 \
	-module-name UniformTypeIdentifiers -module-link-name swiftUniformTypeIdentifiers -autolink-force-load \
	-enable-library-evolution -library-level api -parse-as-library -O \
	-user-module-version 877.2.4 \
	-enable-experimental-feature DebugDescriptionMacro -enable-bare-slash-regex \
	-I "$modules" \
	-Xcc -fmodule-map-file="$here/shims/module.modulemap" \
	-emit-module-path "$out/modules/UniformTypeIdentifiers.swiftmodule" \
	-o "$out/obj/UniformTypeIdentifiers.o"

# ld64, with the payload's own objects and the guest's own framework binaries as link inputs: the
# overlay's UTTypeReference references come from Darling's UniformTypeIdentifiers framework, its
# Foundation references from the deployed Foundation, and libSystem supplies the rest.  The install
# name, versions and swift-abi are the ones Apple's .tbd declares, so a client built against Apple's
# SDK binds the same image and the same numbers.
"$DARLING_LD" -dylib -arch "$SWIFT_DARWIN_ARCH" \
	-platform_version macos 26.0 26.0 -syslibroot "$DARLING_SDK" \
	-install_name "/usr/lib/swift/libswiftUniformTypeIdentifiers.dylib" \
	-compatibility_version 1.0.0 -current_version 877.2.4 \
	-L "$SWIFT_RESOURCE_DIR/macosx" -L "$libs" \
	"$out/obj/UniformTypeIdentifiers.o" \
	"$DARLING_LIBSYSTEM" "$DARLING_ROOT/usr/lib/libobjc.A.dylib" \
	"$DARLING_ROOT/System/Library/Frameworks/UniformTypeIdentifiers.framework/Versions/A/UniformTypeIdentifiers" \
	"$DARLING_ROOT/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation" \
	"$DARLING_ROOT/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation" \
	-lswiftFoundation -lswiftCoreFoundation -lswiftObjectiveC -lswiftDarwin -lswiftCore \
	-o "$out/libswiftUniformTypeIdentifiers.dylib"

cp "$out/libswiftUniformTypeIdentifiers.dylib" "$payload/libswiftUniformTypeIdentifiers.dylib"
echo "built $out/libswiftUniformTypeIdentifiers.dylib and copied it to $payload/libswiftUniformTypeIdentifiers.dylib"
