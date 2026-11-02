#!/bin/sh
# Build ArgumentParserInternal.framework for the guest and copy it to this payload's
# private-frameworks/ directory at the install path the loader demands.
#
# WHY THIS EXISTS. Xcode 26.3's new build system is provided by the plug-in
# com.apple.dt.IDEXCBuildSupportCore; its binary cannot load without
#   /System/Library/PrivateFrameworks/ArgumentParserInternal.framework/Versions/A/ArgumentParserInternal
# because SWBUtil.framework (bundle SwiftBuild.framework/.../SWBBuildService.bundle) hard-links that
# path and binds 65 strong eager symbols from it. The image does not exist anywhere in this tree, and
# the guest refuses the whole plug-in with "Reason: image not found" (measured; see
# darling-workspace/evidence/new-build-system-rung). This script supplies it BY SOURCE: it builds
# Apple's own open-source implementation (apple/swift-argument-parser) under the module name Apple's
# image uses, `ArgumentParserInternal`, and links it at the demanded install name. It is a real
# implementation of the module, not a stub or an alias: nothing here re-points at another image and
# nothing answers "absent".
#
# HOW THE VERSION AND THE FLAGS WERE CHOSEN (measured, not guessed).
# The contract of record is the SDK's MACOSX.sdk/System/Library/PrivateFrameworks/
# ArgumentParserInternal.framework/ArgumentParserInternal.tbd (swift-abi-version 7, 707 names). Building
# this script's flags for each upstream release and diffing the built export trie against that
# declaration gives:
#   1.3.1 682 names, 682/707 of the tbd; 1.4.0 691, 689/707; **1.5.0 and 1.5.1 707, 706/707**;
#   1.7.0 796, 698/707; 1.7.2 800, 698/707; 1.8.0 832, 698/707 (1.6.x cannot be built here: it needs
#   Foundation's non-optional ProcessInfo.environment, and this tree's Foundation declares it optional).
# So 1.5.1 is the release whose ABI is Apple's, and `-swift-version 5 -O -enable-library-evolution`
# (the flags Apple's SDK overlays are built with) reproduce it: every protocol requirement/descriptor
# and every `vpMV` field descriptor of the declaration matches name for name.
#
# THE ONE NAME THAT DOES NOT COME FROM UPSTREAM. The tbd also declares
#   _$s22ArgumentParserInternal20CommandConfigurationV11commandName06_superdG08abstract5usage10discussion7version13shouldDisplay11subcommands17defaultSubcommand9helpNames...tcfC
# i.e. the `_superCommandName` memberwise initializer with the *pre-aliases* parameter list. No upstream
# release has that shape while ALSO having the rest of the 1.5 surface: 1.3.1 has the shape but not the
# surface, 1.4.0 adds `aliases`, 1.5.0 adds `groupedSubcommands` (all three measured). Apple's internal
# copy therefore froze that one initializer at its older ABI; this build cannot produce it from
# upstream, and it is not in the 65-symbol demand of the plug-in that needs the image. Everything else
# — 706 of 707 — matches exactly.
#
# Required environment:
#   SWIFT_TOOLCHAIN     usr/ directory of a Swift toolchain (the Linux release works; 6.3.1 measured)
#   SWIFT_RESOURCE_DIR  usr/lib/swift from swift-<version>-RELEASE-osx.pkg (Swift/_Concurrency modules)
#   DARLING_SDK         Darling's MacOSX.sdk (Clang module maps for Darwin/objc, sys/cdefs.h fix)
#   DARLING_LD          Darling's ld64 (build/src/external/cctools-port/cctools/ld64/src/x86_64-apple-darwin20-ld)
#   DARLING_LIBSYSTEM   Darling's built libSystem.B.dylib
#   DARLING_LIBOBJC     Darling's built libobjc.A.dylib
#   DARLING_ROOT        installed Darling root (libexec/darling); the Foundation framework binary and
#                       CoreFoundation come from it, unless overridden below
# Optional:
#   DARLING_FOUNDATION_MODULES  directory holding the Swift Foundation module interface the guest's
#                       libswiftFoundation.dylib was built from (default: ../build/modules, the
#                       overlays' own output). Compiled against THAT interface, not the SDK's, so the
#                       declarations this module is compiled for are the ones the deployed runtime
#                       implements.
#   DARLING_FOUNDATION  the Foundation framework binary to link (default: $DARLING_ROOT/.../Foundation)
#   SWIFT_ARGUMENT_PARSER_URL / SWIFT_ARGUMENT_PARSER_COMMIT
#                       upstream source and the exact revision fetched (default: the release below)
set -eu

here=$(cd "$(dirname "$0")" && pwd)
payload=$(cd "$here/../.." && pwd)

: "${SWIFT_TOOLCHAIN:?}" "${SWIFT_RESOURCE_DIR:?}" "${DARLING_SDK:?}" "${DARLING_LD:?}"
: "${DARLING_LIBSYSTEM:?}" "${DARLING_LIBOBJC:?}" "${DARLING_ROOT:?}"

# The upstream release whose exported ABI is the SDK declaration's (see above). The URL and the commit
# are pinned together: `git ls-remote <URL> refs/tags/1.5.1` is the ref resolution recorded when this
# was written, and the clone is checked out DETACHED at that commit, so the payload is content-addressed
# by git and never by a moving branch:
#   git ls-remote https://github.com/apple/swift-argument-parser.git refs/tags/1.5.1
#   -> 011f0c765fb46d9cac61bca19be0527e99c98c8b
SWIFT_ARGUMENT_PARSER_URL=${SWIFT_ARGUMENT_PARSER_URL:-https://github.com/apple/swift-argument-parser.git}
SWIFT_ARGUMENT_PARSER_COMMIT=${SWIFT_ARGUMENT_PARSER_COMMIT:-011f0c765fb46d9cac61bca19be0527e99c98c8b}

SWIFT_DARWIN_ARCH=${SWIFT_DARWIN_ARCH:-x86_64}
SWIFT_DARWIN_TARGET=${SWIFT_DARWIN_TARGET:-$SWIFT_DARWIN_ARCH-apple-macosx26.0}
out=${API_OUT:-$here/build}
sap_src=${SWIFT_ARGUMENT_PARSER_SRC:-$out/swift-argument-parser}
foundation_modules=${DARLING_FOUNDATION_MODULES:-$here/../build/modules}
foundation=${DARLING_FOUNDATION:-$DARLING_ROOT/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation}
corefoundation=${DARLING_COREFOUNDATION:-$DARLING_ROOT/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation}

if [ ! -d "$foundation_modules" ]; then
	echo "no Swift Foundation module interface at $foundation_modules: build the overlays first" >&2
	exit 1
fi

mkdir -p "$out/obj" "$out/modules" "$out/cache" "$out/src"

# Fetch the pinned revision (never a branch), then build from a COPY of its sources: the checkout is
# not written to, and the two source transforms below land on the copy, like overlays/build-arch.sh's
# swift-foundation copies.
if [ ! -d "$sap_src/.git" ]; then
	git clone --quiet --filter=blob:none "$SWIFT_ARGUMENT_PARSER_URL" "$sap_src"
fi
git -C "$sap_src" fetch --quiet origin "$SWIFT_ARGUMENT_PARSER_COMMIT" \
	|| git -C "$sap_src" fetch --quiet origin
git -C "$sap_src" checkout --quiet --detach "$SWIFT_ARGUMENT_PARSER_COMMIT"
echo "== upstream $(git -C "$sap_src" rev-parse HEAD) $(git -C "$sap_src" describe --tags --exact-match 2>/dev/null || true)"

rm -rf "$out/src/ArgumentParser" "$out/src/ArgumentParserToolInfo"
cp -a "$sap_src/Sources/ArgumentParser" "$out/src/ArgumentParser"
mkdir -p "$out/src/ArgumentParserToolInfo"
cp "$sap_src/Sources/ArgumentParserToolInfo/ToolInfo.swift" "$out/src/ArgumentParserToolInfo/"

# TWO TRANSFORMS, both required by the module name and both on the copy:
#
# (1) Apple's image is ONE module. Its declaration carries ToolInfo's types as `ArgumentParserInternal.
#     ToolInfoV0` (measured: the tbd's `_$s22ArgumentParserInternal10ToolInfoV...`), i.e. Apple compiles
#     upstream's separate ArgumentParserToolInfo target INTO the renamed module. So ToolInfo.swift joins
#     this module, and the `import ArgumentParserToolInfo` each of its five users carries is dropped
#     (there is no such module to import once the target is gone).
find "$out/src" -name '*.swift' -exec sed -i -E \
	-e '/^(internal )?@?_?exported import ArgumentParserToolInfo$/d' \
	-e '/^(internal )?import ArgumentParserToolInfo$/d' {} +

: > "$out/sources.list"
find "$out/src" -name '*.swift' | LC_ALL=C sort | while IFS= read -r f; do
	printf '"%s"\n' "$f" >> "$out/sources.list"
done

# (2) The module name. `-module-name ArgumentParserInternal` is what puts `22ArgumentParserInternal`
#     into every mangled name, and `-enable-library-evolution` is what emits the resilient protocol
#     requirement descriptors (…Tq/…Tj) and `vpMV` field descriptors the client binds.
#     The Foundation module resolves through DARLING_FOUNDATION_MODULES, so the module this build is
#     compiled against is the one the deployed libswiftFoundation.dylib implements.
"$SWIFT_TOOLCHAIN/bin/swiftc" -frontend -c @"$out/sources.list" \
	-target "$SWIFT_DARWIN_TARGET" -sdk "$DARLING_SDK" -resource-dir "$SWIFT_RESOURCE_DIR" \
	-module-cache-path "$out/cache" -swift-version 5 \
	-module-name ArgumentParserInternal \
	-parse-as-library -O -enable-library-evolution \
	-I "$foundation_modules" \
	-emit-module-path "$out/modules/ArgumentParserInternal.swiftmodule" \
	-o "$out/obj/ArgumentParserInternal.o"

# The install name IS the path the loader demands (measured verbatim in the plug-in's refusal), and the
# link inputs are the images this code actually calls: Darling's Foundation framework (which re-exports
# the Swift Foundation implementation), CoreFoundation, libSystem and libobjc, plus the Swift runtime
# and the Foundation/Darwin/Dispatch/ObjectiveC swift overlays from the payload. No symbol is left
# undefined: every name the SDK's ArgumentParserInternal declaration carries — and all 65 the plug-in
# demands — is exported by this image or reached through one of these.
"$DARLING_LD" -dylib -arch "$SWIFT_DARWIN_ARCH" \
	-platform_version macos 26.0 26.0 -syslibroot "$DARLING_SDK" \
	-install_name "/System/Library/PrivateFrameworks/ArgumentParserInternal.framework/Versions/A/ArgumentParserInternal" \
	-compatibility_version 1.0.0 -current_version 1.0.0 \
	-L "$SWIFT_RESOURCE_DIR/macosx" -L "$here/../build" \
	"$out/obj/ArgumentParserInternal.o" \
	"$foundation" "$corefoundation" "$DARLING_LIBSYSTEM" "$DARLING_LIBOBJC" \
	-lswiftCore -lswiftFoundation -lswiftDarwin -lswiftDispatch -lswiftObjectiveC -lswift_StringProcessing \
	-o "$out/ArgumentParserInternal"

# The payload: the built binary at its own install path under this payload's private-frameworks/, which
# is both the file the rootless deploy declares and the sha256 chain's source. The directory mirrors
# the guest path because that is what the deploy's private-framework glob reads back.
dest="$payload/private-frameworks/ArgumentParserInternal.framework/Versions/A"
mkdir -p "$dest"
cp "$out/ArgumentParserInternal" "$dest/ArgumentParserInternal"
echo "built $out/ArgumentParserInternal and copied it to $dest/ArgumentParserInternal"
