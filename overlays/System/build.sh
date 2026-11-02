#!/bin/sh
# Build libswiftSystem.dylib for the guest and copy it beside the other libswift*.dylib.
#
# WHAT THIS BUILDS. The REAL Swift System overlay: apple/swift-system (Apache-2.0 with Runtime
# Library Exception), the open-source project Apple's /usr/lib/swift/libswiftSystem.dylib is built
# from, compiled here as module `System` for x86_64-apple-macosx26.0 with -enable-library-evolution.
# It is NOT a substitute: every mangled name a client binds comes out of this build's own export trie.
#
# WHY. `/usr/lib/swift/libswiftSystem.dylib` is the rung after libswiftAppleArchive: the guest's Xcode
# 26.3 DVTInstrumentsFoundation hard-links it (LC_LOAD_DYLIB, compatibility version 1.0.0) and binds
# exactly TWO symbols from it, both non-lazily (__DATA_CONST,__got):
#
#   _$s6System8FilePathVMa      type metadata accessor for System.FilePath
#   _$s6System8FilePathVyACSScfC System.FilePath.init(Swift.String) -> System.FilePath
#
# MEASURED FIDELITY. Apple ships a .tbd for this library at
# <Xcode>/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/lib/swift/libswiftSystem.tbd, and
# that file is the ABI this build is measured against: 657 mangled symbols, of which this build
# exports 650 and exports NOTHING Apple does not (mine-only = 0). The seven it does not export, all
# measured from the export trie and demangled by hand, are:
#   * five `System.Mach.Port` members spelling `_context` as Swift.UInt
#     (_$s6System4MachO4PortV8_contextSuvg/vs/vM, ...ReceiveRight...E4name7context...tcfC, and the two
#     ...name_Su7contextt... functions). This build spells the same members Swift.UInt64, because on
#     this target `mach_port_context_t` is UInt64 -- and Apple's own tbd carries BOTH spellings,
#     under two `targets:` groups, so that file merges more than one build rather than describing one.
#   * _$s6System13MachPortRightTL, the MachPortRight protocol's requirements base descriptor --
#     "protocol requirements base descriptor for System.MachPortRight". Upstream 1.6.6 declares that
#     protocol empty (`public protocol MachPortRight {}`), so the compiler emits no base descriptor.
#     No client in the guest's load closure demands it (scripts/closure_analyze.py reports MISS 0).
# The pin below is the tag whose availability-macro table
# matches the SDK interface's resolved availability exactly (macOS 11.0 / 12.0 / 12.3 / 14.4 groups,
# i.e. Package.swift's SYSTEM_ABI_STABLE `osAvailability` column), which is why 1.6.6 and not the
# newest release is named here: 1.7.x adds FileSystem types (Stat/FileType/FileMode/...) that Apple's
# tbd does not carry, so it would show up as mine-only symbols.
#
# THE ONE NON-OBVIOUS DEPENDENCY. swift-system's Darwin sources `import Darwin` for Darwin.errno,
# Darwin.open and Darwin.openat -- the Swift OVERLAY of the Clang module, not the Clang module alone:
# the C prototypes are variadic (`int openat(int, const char *, int, ...)`), and the clang importer
# imports a variadic function as unavailable, so only the overlay's non-variadic shims make the calls
# compile. Two overlays exist in this environment and NEITHER can be used as shipped:
#   * Apple's own SDK interface (<Xcode>/MacOSX.sdk/usr/lib/swift/Darwin.swiftmodule) is refused by
#     this compiler outright -- measured: "failed to build module '_DarwinFoundation1'; this SDK is
#     not supported by the compiler (the SDK is built with 'Apple Swift version 6.2', while this
#     compiler is 'Swift version 6.3.1')" -- and it also `import _DarwinFoundation1._math`, a
#     submodule Darling's regenerated modulemaps do not define (Darling names it Darwin.C_math).
#   * so the Darwin overlay MODULE is compiled here from this tree's own overlays/Darwin sources
#     (the same sources the x86_64 libswiftDarwin.dylib in the payload was built from), and only its
#     .swiftmodule is used: a compile-time declaration of Darwin.errno/open/openat. The three symbols
#     the System object then references (_$s6Darwin5errnos5Int32Vvg, _$s6Darwin4open..., and the
#     openat pair) are exported by that deployed libswiftDarwin.dylib, so the dylib this produces
#     links -lswiftDarwin and binds them there -- the same layering Apple has.
#
# Required environment (same names as ../build.sh, plus two):
#   SWIFT_TOOLCHAIN     usr/ directory of a Swift toolchain (the Linux release works)
#   SWIFT_RESOURCE_DIR  usr/lib/swift from a swift-<version>-RELEASE-osx.pkg (Swift/_Concurrency modules)
#   DARLING_SDK         Darling's MacOSX.sdk (Clang module maps for Darwin/objc, sys/cdefs.h fix)
#   DARLING_LD          Darling's ld64 (build/src/external/cctools-port/cctools/ld64/src/x86_64-apple-darwin20-ld)
#   DARLING_LIBSYSTEM   Darling's built libSystem.B.dylib
#   DARLING_LIBOBJC     Darling's built libobjc.A.dylib
#   DARWIN_OVERLAY_SRC  this tree's overlays/Darwin directory (default: ../Darwin beside this script)
#   SWIFT_SYSTEM_SRC    an existing checkout of the pinned swift-system commit (offline build); the
#                       checkout is not modified, only read. Nothing verifies it, so point it at the
#                       pinned commit: a checkout of another revision builds another ABI silently.
#
# Output: the built dylib, additionally copied to ../../libswiftSystem.dylib (the payload directory
# the rootless manifest globs) when run with that default.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
payload=$(cd "$here/../.." && pwd)

: "${SWIFT_TOOLCHAIN:?}" "${SWIFT_RESOURCE_DIR:?}" "${DARLING_SDK:?}" "${DARLING_LD:?}"
: "${DARLING_LIBSYSTEM:?}" "${DARLING_LIBOBJC:?}"

SWIFT_DARWIN_ARCH=${SWIFT_DARWIN_ARCH:-x86_64}
SWIFT_DARWIN_TARGET=${SWIFT_DARWIN_TARGET:-$SWIFT_DARWIN_ARCH-apple-macosx26.0}
out=${SYSTEM_OUT:-$here/build}
work=${SWIFT_SYSTEM_BUILD_DIR:-$out/swift-system}

# Pinned BY COMMIT, not by tag, so a moved tag cannot change what this builds. 1.6.6, chosen by the
# availability-macro measurement in the header.
SWIFT_SYSTEM_URL=${SWIFT_SYSTEM_URL:-https://github.com/apple/swift-system}
SWIFT_SYSTEM_COMMIT=${SWIFT_SYSTEM_COMMIT:-0b30161977799fd949f7f6848586b82ff6764f73}

src=${SWIFT_SYSTEM_SRC:-$work}
if [ -z "${SWIFT_SYSTEM_SRC:-}" ]; then
	if [ ! -d "$work/.git" ]; then git clone --quiet --filter=blob:none "$SWIFT_SYSTEM_URL" "$work"; fi
	git -C "$work" fetch --quiet origin "$SWIFT_SYSTEM_COMMIT" || git -C "$work" fetch --quiet origin
	git -C "$work" checkout --quiet --detach "$SWIFT_SYSTEM_COMMIT"
fi

darwin_src=${DARWIN_OVERLAY_SRC:-$here/../Darwin}
[ -d "$darwin_src" ] || { echo "no Darwin overlay sources at $darwin_src" >&2; exit 2; }
[ -d "$src/Sources/System" ] || { echo "no swift-system sources at $src" >&2; exit 2; }

# A clean object directory every run: -frontend -c with -whole-module-optimization writes one object,
# but a stale module cache or a leftover .swiftmodule from a different source list would be linked
# silently.
rm -rf "$out/obj" "$out/modules" "$out/module-cache" "$out/darwin"
mkdir -p "$out/obj" "$out/modules" "$out/module-cache" \
	"$out/darwin/modules" "$out/darwin/obj" "$out/darwin/mcache"

# 1. The Darwin overlay module, compile-time only (see the header). This is the tree's own source,
#    built for the same target as everything else, so its ABI is the payload libswiftDarwin's.
#    -I "$out/darwin/modules" is where it lands; the module cache is separate so the two builds
#    cannot serve each other a stale Darwin.
"$SWIFT_TOOLCHAIN/bin/swiftc" -frontend -c "$darwin_src"/*.swift \
	-target "$SWIFT_DARWIN_TARGET" -sdk "$DARLING_SDK" -resource-dir "$SWIFT_RESOURCE_DIR" \
	-module-cache-path "$out/darwin/mcache" -swift-version 5 \
	-module-name Darwin -module-link-name swiftDarwin \
	-enable-library-evolution -parse-as-library -O \
	-Xcc -fmodule-map-file="$darwin_src/../shims/overlay-shims.modulemap" \
	-emit-module-path "$out/darwin/modules/Darwin.swiftmodule" \
	-o "$out/darwin/obj/Darwin.o"

# 2. The System module. The source list is the Darwin set, derived from the checkout the same way
#    Package.swift derives it (everything under Sources/System except CMakeLists.txt and the
#    Linux-only IORing sources), so a pin that adds a file compiles it here too. LC_ALL=C sort
#    because find's order is filesystem order.
sources="$out/System.sources"
LC_ALL=C find "$src/Sources/System" -name '*.swift' ! -path '*/IORing/*' | LC_ALL=C sort > "$sources"
[ -s "$sources" ] || { echo "empty source list from $src/Sources/System" >&2; exit 2; }

# -library-level api, -module-link-name swiftSystem and -user-module-version 72.2 are taken from the
# SDK's own System.swiftinterface module flags; -target x86_64-apple-macos26.2 in that interface is
# the SDK's own deployment target, kept here at this tree's 26.0 as the other overlays do.
#
# The AvailabilityMacro list is Package.swift's `availability` array in its SYSTEM_ABI_STABLE form
# (`osAvailability`), which is the form the SDK interface's resolved availability matches: each
# `System <version>` macro must be defined or the sources do not compile.
set -- \
	-enable-experimental-feature 'AvailabilityMacro=System 0.0.1:macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0' \
	-enable-experimental-feature 'AvailabilityMacro=System 0.0.2:macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0' \
	-enable-experimental-feature 'AvailabilityMacro=System 0.0.3:macOS 12.3, iOS 15.4, watchOS 8.5, tvOS 15.4' \
	-enable-experimental-feature 'AvailabilityMacro=System 1.1.0:macOS 12.3, iOS 15.4, watchOS 8.5, tvOS 15.4' \
	-enable-experimental-feature 'AvailabilityMacro=System 1.1.1:macOS 14.4, iOS 17.4, watchOS 10.4, tvOS 17.4' \
	-enable-experimental-feature 'AvailabilityMacro=System 1.2.0:macOS 14.4, iOS 17.4, watchOS 10.4, tvOS 17.4' \
	-enable-experimental-feature 'AvailabilityMacro=System 1.2.1:macOS 14.4, iOS 17.4, watchOS 10.4, tvOS 17.4' \
	-enable-experimental-feature 'AvailabilityMacro=System 1.3.0:macOS 14.4, iOS 17.4, watchOS 10.4, tvOS 17.4' \
	-enable-experimental-feature 'AvailabilityMacro=System 1.3.1:macOS 14.4, iOS 17.4, watchOS 10.4, tvOS 17.4, visionOS 1.0' \
	-enable-experimental-feature 'AvailabilityMacro=System 1.3.2:macOS 14.4, iOS 17.4, watchOS 10.4, tvOS 17.4, visionOS 1.0' \
	-enable-experimental-feature 'AvailabilityMacro=System 1.4.0:macOS 14.4, iOS 17.4, watchOS 10.4, tvOS 17.4, visionOS 1.0' \
	-enable-experimental-feature 'AvailabilityMacro=System 1.4.1:macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, visionOS 9999' \
	-enable-experimental-feature 'AvailabilityMacro=System 1.4.2:macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, visionOS 9999' \
	-enable-experimental-feature 'AvailabilityMacro=System 1.5.0:macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, visionOS 9999' \
	-enable-experimental-feature 'AvailabilityMacro=System 1.6.0:macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, visionOS 9999' \
	-enable-experimental-feature 'AvailabilityMacro=System 1.6.1:macOS 9999, iOS 9999, watchOS 9999, tvOS 9999, visionOS 9999'

"$SWIFT_TOOLCHAIN/bin/swiftc" -frontend -c @"$sources" \
	-target "$SWIFT_DARWIN_TARGET" -sdk "$DARLING_SDK" -resource-dir "$SWIFT_RESOURCE_DIR" \
	-module-cache-path "$out/module-cache" -swift-version 5 -O -whole-module-optimization \
	-module-name System -module-link-name swiftSystem \
	-enable-library-evolution -library-level api -parse-as-library \
	-enable-experimental-feature Lifetimes \
	-enable-experimental-feature DebugDescriptionMacro \
	-enable-bare-slash-regex \
	-user-module-version 72.2 \
	-DSYSTEM_PACKAGE_DARWIN \
	-I "$out/darwin/modules" \
	"$@" \
	-emit-module-path "$out/modules/System.swiftmodule" \
	-o "$out/obj/System.o"

# ld64 demotes nothing here: the exports are the public Swift ABI of the declarations in the sources.
# -U is NOT used: the object's three Darwin-overlay references are resolved against the payload's
# own libswiftDarwin.dylib, which exports them (that is the whole point of step 1).
"$DARLING_LD" -dylib -arch "$SWIFT_DARWIN_ARCH" \
	-platform_version macos 26.0 26.0 -syslibroot "$DARLING_SDK" \
	-install_name "/usr/lib/swift/libswiftSystem.dylib" \
	-compatibility_version 1.0.0 -current_version 72.2.0 \
	-L "$SWIFT_RESOURCE_DIR/macosx" -L "$payload" \
	"$out/obj/System.o" "$DARLING_LIBSYSTEM" "$DARLING_LIBOBJC" -lswiftCore -lswiftDarwin \
	-o "$out/libswiftSystem.dylib"

cp "$out/libswiftSystem.dylib" "$payload/libswiftSystem.dylib"
echo "built $out/libswiftSystem.dylib and copied it to $payload/libswiftSystem.dylib"
