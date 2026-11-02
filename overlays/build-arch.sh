#!/bin/sh
# Build the arm64 slices of the Swift SDK overlays in this directory and merge them with the
# x86_64 slices already in the repository (Swift 5.2.2 builds from swift.org).
#
# Required environment:
#   SWIFT_TOOLCHAIN     usr/ directory of a Swift 6.3.3 toolchain (the Linux release works)
#   SWIFT_RESOURCE_DIR  usr/lib/swift from swift-6.3.3-RELEASE-osx.pkg (Swift/_Concurrency modules, shims, clang headers)
#   DARLING_SDK         Darling's MacOSX.sdk, including the Clang module maps and API notes for
#                       Darwin, ObjectiveC, Dispatch, os, CoreFoundation and the sys/cdefs.h default-platform fix
#   DARLING_LD          Darling's ld64 (build/src/external/cctools-port/cctools/ld64/src/aarch64-apple-darwin20-ld)
#   DARLING_LIBSYSTEM   Darling's built libSystem.B.dylib
#   DARLING_ROOT        installed Darling root (libexec/darling): libobjc and CoreFoundation are linked from it
# Optional:
#   LD_EXTRA_FLAGS      extra ld64 flags, e.g. the -dylib_file mappings Darling's own executables link with
#   DARLING_LIBOBJC     Objective-C link input (defaults to DARLING_ROOT/usr/lib/libobjc.A.dylib)
#   SWIFT_SYSTEM_MODULES genuine SDK directory containing System.swiftmodule (AppleArchive-only build)
set -eu

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/.." && pwd)
: "${SWIFT_TOOLCHAIN:?}" "${SWIFT_RESOURCE_DIR:?}" "${DARLING_SDK:?}" "${DARLING_LD:?}" "${DARLING_LIBSYSTEM:?}" "${DARLING_ROOT:?}"
command -v llvm-lipo >/dev/null || { echo "llvm-lipo is required" >&2; exit 2; }
LD_EXTRA_FLAGS=${LD_EXTRA_FLAGS:-}
DARLING_LIBOBJC=${DARLING_LIBOBJC:-"$DARLING_ROOT/usr/lib/libobjc.A.dylib"}
# Darling targets this host builds for. Upstream builds arm64 slices and merges them with the
# x86_64 5.2.2 binaries already in the repository; on an x86_64-only host the same sources are
# built straight for x86_64 instead, so both the compiler target and ld64's -arch move together.
SWIFT_DARWIN_ARCH=${SWIFT_DARWIN_ARCH:-arm64}
SWIFT_DARWIN_TARGET=${SWIFT_DARWIN_TARGET:-$SWIFT_DARWIN_ARCH-apple-macosx26.0}
out=${OVERLAY_BUILD_DIR:-"$here/build"}
mkdir -p "$out/modules" "$out/obj"

# Write one source path per line, quoted, for swiftc's response file. Backslashes and quotes
# are escaped: LLVM's tokenizer would otherwise turn such a path into a different filename
# silently rather than failing.
write_source() {
	printf '"%s"\n' "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')" >> "$2"
}

# Collect every .swift under a directory into a response file, in a stable order.
collect_sources() {
	: > "$2"
	find "$1" -name '*.swift' | LC_ALL=C sort | while IFS= read -r f; do write_source "$f" "$2"; done
}

# build_module <Module> <sources...> [--sources-from <file of paths>]
#              [-- <extra swiftc -frontend flags>] [--link <extra ld inputs>]
# Source paths may contain spaces; flags and link inputs may not, since both are expanded as word
# lists on the command line.
build_module() {
	module=$1
	shift
	mkdir -p "${MODULE_OUTPUT_DIR:-$out/modules}"
	swift_flags=""
	link_inputs=""
	mode=src
	: > "$out/$module.sources"
	for arg in "$@"; do
		case "$arg" in
			--) mode=flags ;;
			--link) mode=link ;;
			--sources-from) mode=srcfile ;;
			*) case "$mode" in
				src) write_source "$arg" "$out/$module.sources" ;;
				srcfile) while IFS= read -r src_line; do
						[ -n "$src_line" ] || continue
						write_source "$src_line" "$out/$module.sources"
					done < "$arg" ;;
				flags) swift_flags="$swift_flags $arg" ;;
				link) link_inputs="$link_inputs $arg" ;;
			esac ;;
		esac
	done

	# Library evolution, like Apple's SDK overlays, so binaries built against the macOS SDK use the same access patterns.
	# shellcheck disable=SC2086
	"$SWIFT_TOOLCHAIN/bin/swiftc" -frontend -c @"$out/$module.sources" \
		-target "$SWIFT_DARWIN_TARGET" -sdk "$DARLING_SDK" -resource-dir "$SWIFT_RESOURCE_DIR" \
		-module-cache-path "$out/module-cache" -swift-version 5 \
		-module-name "$module" -module-link-name "swift$module" -autolink-force-load \
		-enable-library-evolution -parse-as-library -O \
		-I "$out/modules" -I "$SWIFT_RESOURCE_DIR/shims" \
		-Xcc -fmodule-map-file="$here/shims/overlay-shims.modulemap" \
		-emit-module-path "${MODULE_OUTPUT_DIR:-$out/modules}/$module.swiftmodule" \
		-o "$out/obj/$module.o" $swift_flags

	# shellcheck disable=SC2086
	"$DARLING_LD" -dylib -arch "$SWIFT_DARWIN_ARCH" -platform_version macos 26.0 26.0 -syslibroot "$DARLING_ROOT" \
		-install_name "/usr/lib/swift/libswift$module.dylib" \
		-compatibility_version 1.0.0 -current_version 1.0.0 \
		$LD_EXTRA_FLAGS \
		-L "$SWIFT_RESOURCE_DIR/macosx" -L "$out" \
		"$out/obj/$module.o" "$DARLING_LIBSYSTEM" "$DARLING_LIBOBJC" \
		-lswiftCore $link_inputs \
		-o "$out/libswift$module.dylib"
}

corefoundation="$DARLING_ROOT/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation"

build_module Darwin "$here"/Darwin/*.swift
# macOS split the Darwin overlay without changing its Swift ABI name. The
# Foundation groups and header overlays below reexport the single real Darwin
# implementation, so errno state and type metadata are never duplicated.
darwin_modules="Darwin _DarwinFoundation1 _DarwinFoundation2 _DarwinFoundation3 _errno _math _stdio _time sys_time _signal unistd"
# These are runtime-only facades, not SDK source modules. Keep their generated
# Swift modules off the import path, where they would shadow Clang SDK modules.
for group in 1 2 3; do
	MODULE_OUTPUT_DIR="$out/runtime-modules" build_module "_DarwinFoundation$group" "$here/Darwin/Split/RuntimeReexport.swift" \
		--link -reexport_library "$out/libswiftDarwin.dylib"
done
for module in _errno _math; do
	MODULE_OUTPUT_DIR="$out/runtime-modules" build_module "$module" "$here/Darwin/Split/RuntimeReexport.swift" \
		--link -reexport_library "$out/libswift_DarwinFoundation1.dylib"
done
for module in _stdio _time sys_time; do
	MODULE_OUTPUT_DIR="$out/runtime-modules" build_module "$module" "$here/Darwin/Split/RuntimeReexport.swift" \
		--link -reexport_library "$out/libswift_DarwinFoundation2.dylib"
done
for module in _signal unistd; do
	MODULE_OUTPUT_DIR="$out/runtime-modules" build_module "$module" "$here/Darwin/Split/RuntimeReexport.swift" \
		--link -reexport_library "$out/libswift_DarwinFoundation3.dylib"
done

# A focused Darwin rebuild still uses the ordinary compiler/linker and binary
# publication path. No installed image or guest prefix is modified here.
publish_modules() {
	for module in "$@"; do
		dylib="libswift$module.dylib"
		if [ "$SWIFT_DARWIN_ARCH" = arm64 ]; then
			llvm-lipo -thin x86_64 "$repo/$dylib" -output "$out/$dylib.x86_64" 2>/dev/null || cp "$repo/$dylib" "$out/$dylib.x86_64"
			llvm-lipo -create "$out/$dylib.x86_64" "$out/$dylib" -output "$repo/$dylib"
			rm "$out/$dylib.x86_64"
		elif [ -f "$repo/$dylib" ] && llvm-lipo "$repo/$dylib" -verify_arch arm64 2>/dev/null; then
			# Updating Intel must not discard an already shipped arm64 provider.
			llvm-lipo -thin arm64 "$repo/$dylib" -output "$out/$dylib.arm64" 2>/dev/null || cp "$repo/$dylib" "$out/$dylib.arm64"
			llvm-lipo -create "$out/$dylib.arm64" "$out/$dylib" -output "$repo/$dylib"
			rm "$out/$dylib.arm64"
		else
			cp "$out/$dylib" "$repo/$dylib"
		fi
		echo "updated $dylib: $(llvm-lipo -archs "$repo/$dylib")"
	done
}
if [ "${DARWIN_ONLY:-0}" = 1 ]; then
	# shellcheck disable=SC2086
	publish_modules $darwin_modules
	exit 0
fi

# AppleArchive's existing engine-independent overlay uses System only in public
# signatures and inlined descriptor/whence accessors. Rebuild its real value and
# file-I/O surface without replacing other payloads or claiming an archive engine.
if [ "${DARLING_SWIFT_APPLEARCHIVE_ONLY:-0}" = 1 ]; then
	: "${SWIFT_SYSTEM_MODULES:?directory containing the genuine SDK System.swiftmodule}"
	test -d "$SWIFT_SYSTEM_MODULES/System.swiftmodule"
	test -f "$DARLING_ROOT/usr/lib/swift/libswiftSystem.dylib"
	# Import only System's genuine module, not adjacent SDK Darwin overlays and
	# shim module maps that conflict with the matching prerequisites built above.
	mkdir -p "$out/sdk-modules"
	cp -R "$SWIFT_SYSTEM_MODULES/System.swiftmodule" "$out/sdk-modules/"
	build_module AppleArchive "$here/AppleArchive/AppleArchive.swift" -- \
		-I "$out/sdk-modules" \
		--link "$DARLING_ROOT/usr/lib/swift/libswiftSystem.dylib"
	publish_modules AppleArchive
	exit 0
fi

build_module ObjectiveC "$here/ObjectiveC/ObjectiveC.swift" -- -disable-objc-attr-requires-foundation-module --link -lswiftDarwin
build_module CoreFoundation "$here"/CoreFoundation/*.swift --link "$corefoundation" -lswiftDarwin
"$SWIFT_TOOLCHAIN/bin/clang++" -target "$SWIFT_DARWIN_TARGET" -isysroot "$DARLING_SDK" -I "$here/Dispatch/include" \
	-std=c++17 -fobjc-arc -O2 -c "$here/Dispatch/Dispatch.mm" -o "$out/obj/Dispatch.mm.o"
"$SWIFT_TOOLCHAIN/bin/clang" -target "$SWIFT_DARWIN_TARGET" -isysroot "$DARLING_SDK" -fobjc-arc -O2 \
	-c "$here/Dispatch/DarlingSerialExecutor.m" -o "$out/obj/DarlingSerialExecutor.m.o"
build_module Dispatch "$here"/Dispatch/*.swift --link "$out/obj/Dispatch.mm.o" "$out/obj/DarlingSerialExecutor.m.o" -lswiftObjectiveC -lswiftDarwin
build_module os "$here/os/os.swift" -- -Xcc -fmodule-map-file="$here/os/shims/module.modulemap" --link -lswiftDarwin -lswiftObjectiveC -lswiftDispatch
build_module XPC "$here/XPC/XPC.swift" -- -Xcc -fmodule-map-file="$here/XPC/shims/module.modulemap" --link -lswiftDarwin -lswiftObjectiveC -lswiftDispatch

# OSLog: the Swift refinements of OSLog.framework, which this tree builds (src/frameworks/OSLog).  The
# guest demands exactly one symbol from this dylib -- SWBBuildSystem's STRONG, eager bind
#   _$sSo10OSLogStoreC0A0E10getEntries4with2at8matchings11AnySequenceVySo0A5EntryCGSo0A17EnumeratorOptionsV_So0A8PositionCSgSo11NSPredicateCSgtKF
#     = (extension in OSLog) __C.OSLogStore.getEntries(with: __C.OSLogEnumeratorOptions,
#                                                      at: __C.OSLogPosition?,
#                                                      matching: __C.NSPredicate?)
#                throws -> Swift.AnySequence<__C.OSLogEntry>
# -- so the module name has to be OSLog (Swift mangles the module into every symbol) and the shim
# module has to declare the framework's classes under their own Objective-C names, which is what
# OSLog/shims/module.modulemap does (the same shape as UniformTypeIdentifiers/shims).  The body runs
# the framework's real enumerator (see OSLog/OSLog.swift), it is not an empty symbol.
#
# OSLog's NSError bridge needs Foundation.swiftmodule, not just the linked dylib.
# Full builds call this after Foundation; focused builds reuse its built modules.
build_oslog() {
	oslog_framework="$DARLING_ROOT/System/Library/Frameworks/OSLog.framework/Versions/A/OSLog"
	oslog_foundation=$1
	[ -f "$oslog_foundation" ] || oslog_foundation="$DARLING_ROOT/usr/lib/swift/libswiftFoundation.dylib"
	build_module OSLog "$here/OSLog/OSLog.swift" -- -Xcc -fmodule-map-file="$here/OSLog/shims/module.modulemap" --link "$oslog_framework" "$oslog_foundation" -lswiftCoreFoundation -lswiftObjectiveC -lswiftDarwin
	cp "$out/libswiftOSLog.dylib" "$repo/libswiftOSLog.dylib"
	echo "updated libswiftOSLog.dylib: $(llvm-lipo -archs "$repo/libswiftOSLog.dylib")"
}

# Focused iteration on the OSLog overlay, the same shape as NETWORK_ONLY/COMBINE_ONLY below: build
# ONLY it, against the payload's Foundation overlay, and copy nothing else into the payload.
if [ "${DARLING_SWIFT_OSLOG_ONLY:-0}" = 1 ]; then
	build_oslog "${DARLING_SWIFT_FOUNDATION_OVERLAY:-$repo/libswiftFoundation.dylib}"
	echo "built OSLog overlay at $out/libswiftOSLog.dylib"
	exit 0
fi

# Network: Apple's is closed source and pure Swift, and the value half of it is what Xcode 26.3's
# Notarization.framework binds -- 138 names, all of them eager and strong, measured by decoding that
# image's LC_DYLD_CHAINED_FIXUPS (see overlays/Network/Network.swift for the numbers). The
# declarations come from the guest SDK's Network.swiftinterface; the transport half refuses
# explicitly, because this guest has no network stack to serve it.
#
# Installed as /usr/lib/swift/libswiftNetwork.dylib, which Network.framework re-exports as an ordinal
# -- the same shape as Foundation.framework re-exporting libswiftFoundation.dylib. Apple's own
# framework carries these names today (they are in the SDK's Network.tbd as
# $ld$previous$/usr/lib/swift/libswiftNetwork.dylib$... entries), which is why the client binds them
# against the framework's ordinal and not against the dylib.
#
# build_network takes the libswiftFoundation.dylib to link against: the two call sites have different
# ones available. A full run has just built it into $out; the focused run below has not, and links
# the copy already in the payload.
build_network() {
	network_foundation_framework="${DARLING_FOUNDATION:-$DARLING_ROOT/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation}"
	build_module Network "$here"/Network/*.swift -- \
		-Xcc -fmodule-map-file="$here/Network/shims/module.modulemap" \
		--link "$1" "$network_foundation_framework" "$corefoundation" -lswiftCoreFoundation -lswiftDarwin -lswiftObjectiveC -lswiftDispatch
	cp "$out/libswiftNetwork.dylib" "$repo/libswiftNetwork.dylib"
	echo "updated libswiftNetwork.dylib: $(llvm-lipo -archs "$repo/libswiftNetwork.dylib")"
}

# Focused iteration on the Network overlay: build ONLY it, against the Foundation overlay already in
# the payload. It runs here, before the Combine build, so that a focused build never rewrites
# Combine.framework/Versions/A/Combine (which this wave must not touch), and it copies nothing else
# into the payload.
if [ "${DARLING_SWIFT_NETWORK_ONLY:-0}" = 1 ]; then
	build_network "$repo/libswiftFoundation.dylib"
	exit 0
fi

# Combine: OpenCombine built as module `Combine`, so its mangled names match what apps import.
# Unlike the overlays above this is a framework binary, not a /usr/lib/swift dylib, and it has no
# x86_64 slice to merge with. See overlays/README.md.
#
# Built before Foundation, and its .swiftmodule goes into "$out/modules": the Foundation overlay
# imports Combine for NSObject.KeyValueObservingPublisher, so every client of Foundation has to be
# able to load Combine, as with Apple's SDK. Combine itself is compiled without -I "$out/modules".
#
# OpenCombine is fetched rather than vendored, for the same reason swift-collections is above.
# The fork adds functional Merge and MergeMany publishers; the Darwin-specific adaptations
# remain in Combine/patches/, applied below.
#
# Pinned BY COMMIT on purpose: a branch reference would make this build non-reproducible.
# This commit is on cristim/OpenCombine's feature/darling-merge-publishers branch and is
# proposed upstream as OpenCombine PR #258.
# OPENCOMBINE_SRC can point at an already-fetched checkout, the way SWIFT_COLLECTIONS_SRC does
# above, so an offline build needs no network. Nothing verifies that checkout, so point it at the
# pinned commit.
OPENCOMBINE_URL=${OPENCOMBINE_URL:-https://github.com/cristim/OpenCombine.git}
OPENCOMBINE_COMMIT=${OPENCOMBINE_COMMIT:-10df981a64800643559490d72174f43438562e73}
opencombine_src=${OPENCOMBINE_SRC:-$out/OpenCombine}
if [ -z "${OPENCOMBINE_SRC:-}" ]; then
	if [ ! -d "$opencombine_src/.git" ]; then
		git clone --quiet --filter=blob:none "$OPENCOMBINE_URL" "$opencombine_src"
	fi
	git -C "$opencombine_src" fetch --quiet origin "$OPENCOMBINE_COMMIT" \
		|| git -C "$opencombine_src" fetch --quiet origin
	git -C "$opencombine_src" checkout --quiet --detach "$OPENCOMBINE_COMMIT"
fi

# Patch a copy, never the checkout: OPENCOMBINE_SRC may point at one this build does not own, and
# rebuilding from scratch each time is what makes the patches apply exactly once.
rm -rf "$out/combine-src"
cp -R "$opencombine_src/Sources/OpenCombine" "$out/combine-src"
for p in "$here"/Combine/patches/*.patch; do
	patch -p1 -s -d "$out/combine-src" < "$p"
done

"$SWIFT_TOOLCHAIN/bin/clang" -target "$SWIFT_DARWIN_TARGET" -isysroot "$DARLING_SDK" \
	-I "$opencombine_src/Sources/COpenCombineHelpers/include" -Wall -Wextra -O2 -fvisibility=hidden \
	-c "$here/Combine/helpers.c" -o "$out/obj/CombineHelpers.o"

# find order is filesystem order, so the source list goes through collect_sources' LC_ALL=C sort.
collect_sources "$out/combine-src" "$out/Combine.sources"
"$SWIFT_TOOLCHAIN/bin/swiftc" -frontend -c @"$out/Combine.sources" \
	-target "$SWIFT_DARWIN_TARGET" -sdk "$DARLING_SDK" -resource-dir "$SWIFT_RESOURCE_DIR" \
	-module-cache-path "$out/module-cache" -swift-version 5 \
	-module-name Combine \
	-enable-library-evolution -parse-as-library -O \
	-Xcc -fmodule-map-file="$opencombine_src/Sources/COpenCombineHelpers/include/module.modulemap" \
	-emit-module-path "$out/modules/Combine.swiftmodule" \
	-o "$out/obj/Combine.o"

mkdir -p "$repo/Combine.framework/Versions/A"
# shellcheck disable=SC2086
"$DARLING_LD" -dylib -arch "$SWIFT_DARWIN_ARCH" -platform_version macos 26.0 26.0 -syslibroot "$DARLING_ROOT" \
	-install_name "/System/Library/Frameworks/Combine.framework/Versions/A/Combine" \
	-compatibility_version 1.0.0 -current_version 1.0.0 \
	$LD_EXTRA_FLAGS \
	-L "$SWIFT_RESOURCE_DIR/macosx" \
	"$out/obj/Combine.o" "$out/obj/CombineHelpers.o" \
	"$DARLING_LIBSYSTEM" "$DARLING_ROOT/usr/lib/libobjc.A.dylib" \
	-lswiftCore \
	-o "$repo/Combine.framework/Versions/A/Combine"
echo "updated Combine.framework: $(llvm-lipo -archs "$repo/Combine.framework/Versions/A/Combine")"

# Focused iteration on Combine itself: the framework binary above has just been written into the
# payload, so a rung whose subject is Combine builds only that and leaves every overlay dylib (and
# their x86_64/arm64 merges below) untouched. Placed after the Combine link, like
# DARLING_SWIFT_NETWORK_ONLY above, and before the Foundation overlay that links Combine.
if [ "${DARLING_SWIFT_COMBINE_ONLY:-0}" = 1 ]; then
	echo "built Combine.framework at $repo/Combine.framework/Versions/A/Combine"
	exit 0
fi

# The Dispatch module's Combine conformance (Dispatch/Scheduler.swift: `extension DispatchQueue :
# Combine.Scheduler` with the nested SchedulerTimeType/Stride/SchedulerOptions) can only be compiled
# once Combine.swiftmodule exists, and the Dispatch build above runs before Combine. The file is
# guarded by `DARLING_DISPATCH_COMBINE`, which the build above does not pass, so its first pass
# compiles it empty; the module is linked a SECOND time here, with the define and against Combine, and
# THIS link is the one that ships (it overwrites $out/obj/Dispatch.o, $out/modules/Dispatch.swiftmodule
# and $out/libswiftDispatch.dylib, and the merge loop below takes $out/libswiftDispatch.dylib).
#
# `canImport(Combine)` cannot be the guard: $out/modules keeps the Combine.swiftmodule from the
# previous build, so the earlier link would compile the conformance and then fail to resolve Combine's
# protocol descriptors.
#
# The two modules are not reordered instead: the focused-path exits must keep their places relative to
# Combine (DARLING_SWIFT_NETWORK_ONLY exits before the Combine block so a network-only build never
# rewrites Combine.framework, and it needs the Dispatch/os/XPC builds above it). IDEFoundation binds
# the conformance and the SchedulerOptions metadata from libswiftDispatch eagerly and strongly.
build_module Dispatch "$here"/Dispatch/*.swift -- -D DARLING_DISPATCH_COMBINE --link "$out/obj/Dispatch.mm.o" "$out/obj/DarlingSerialExecutor.m.o" "$repo/Combine.framework/Versions/A/Combine" -lswiftObjectiveC -lswiftDarwin
echo "updated libswiftDispatch.dylib (with the Combine conformance): $(llvm-lipo -archs "$out/libswiftDispatch.dylib")"

# Focused iteration on the Dispatch overlay, the same shape as NETWORK_ONLY/COMBINE_ONLY above: the
# Combine-enabled Dispatch link has just written $out/libswiftDispatch.dylib, so a rung whose subject
# is Dispatch builds only that and leaves every other overlay dylib untouched. As with the
# Foundation-focused path, the caller copies the built dylib into the payload.
if [ "${DARLING_SWIFT_DISPATCH_ONLY:-0}" = 1 ]; then
	echo "built Dispatch overlay at $out/libswiftDispatch.dylib"
	exit 0
fi

# AttributedString stores its text in swift-collections' BigString. Both modules are an
# implementation detail of the Foundation overlay: they are compiled without library evolution
# and their objects are linked straight into libswiftFoundation, the way Apple's Foundation
# links CollectionsInternal, rather than shipped as dylibs of their own.
build_object() {
	module=$1
	srcdir=$2
	collect_sources "$srcdir" "$out/$module.sources"
	"$SWIFT_TOOLCHAIN/bin/swiftc" -frontend -c @"$out/$module.sources" \
		-target "$SWIFT_DARWIN_TARGET" -sdk "$DARLING_SDK" -resource-dir "$SWIFT_RESOURCE_DIR" \
		-module-cache-path "$out/module-cache" -swift-version 5 \
		-module-name "$module" -parse-as-library -O \
		-I "$out/modules" \
		-emit-module-path "$out/modules/$module.swiftmodule" \
		-o "$out/obj/$module.o"
}
# swift-collections is fetched rather than vendored: unlike overlays/Foundation/*, which is Apple
# overlay source adapted for Darling, these files are consumed exactly as upstream ships them.
#
# Pinned BY COMMIT on purpose: a branch or tag reference would make this build non-reproducible.
# c11818f3... is the commit tag 1.1.6 points at; check that with
#   git ls-remote https://github.com/apple/swift-collections.git refs/tags/1.1.6
# SWIFT_COLLECTIONS_SRC can point at an already-fetched checkout, the way SWIFT_PKG does for the
# toolchain in the top-level build.sh, so an offline build needs no network. Nothing verifies that
# checkout, so point it at the pinned commit.
SWIFT_COLLECTIONS_URL=${SWIFT_COLLECTIONS_URL:-https://github.com/apple/swift-collections.git}
SWIFT_COLLECTIONS_COMMIT=${SWIFT_COLLECTIONS_COMMIT:-c11818f3cae0780656baa430b49e7f163f08dffd}
collections_src=${SWIFT_COLLECTIONS_SRC:-$out/swift-collections}
if [ -z "${SWIFT_COLLECTIONS_SRC:-}" ]; then
	if [ ! -d "$collections_src/.git" ]; then
		git clone --quiet --filter=blob:none "$SWIFT_COLLECTIONS_URL" "$collections_src"
	fi
	git -C "$collections_src" fetch --quiet origin "$SWIFT_COLLECTIONS_COMMIT" \
		|| git -C "$collections_src" fetch --quiet origin
	git -C "$collections_src" checkout --quiet --detach "$SWIFT_COLLECTIONS_COMMIT"
fi
build_object InternalCollectionsUtilities "$collections_src/Sources/InternalCollectionsUtilities"
build_object _RopeModule "$collections_src/Sources/RopeModule"

# Keep the linked-in swift-collections symbols out of libswiftFoundation's export table, the way
# Apple hides CollectionsInternal. The patterns go in a file rather than on the command line
# because build_module re-splits its link inputs, where a bare '*' would be glob-expanded.
printf '_$s11_RopeModule*\n_$s28InternalCollectionsUtilities*\n' > "$out/unexported.txt"

# swift-cmark (swiftlang's cmark-gfm fork, BSD-2-Clause, see Foundation/LICENSE-swift-cmark.txt) is
# the CommonMark/GFM parser under AttributedString's Markdown initializers. Fetched and pinned like
# swift-collections, and linked into libswiftFoundation the same way: CMARK_GFM_STATIC_DEFINE plus
# -fvisibility=hidden make every cmark symbol private to the dylib, so none is exported.
# 924936d0... is tag swift-6.3.3-RELEASE; check that with
#   git ls-remote https://github.com/swiftlang/swift-cmark.git refs/tags/swift-6.3.3-RELEASE
# SWIFT_CMARK_SRC can point at an already-fetched checkout for an offline build. Nothing verifies
# that checkout, so point it at the pinned commit.
SWIFT_CMARK_URL=${SWIFT_CMARK_URL:-https://github.com/swiftlang/swift-cmark.git}
SWIFT_CMARK_COMMIT=${SWIFT_CMARK_COMMIT:-924936d0427cb25a61169739a7660230bffa6ea6}
cmark_src=${SWIFT_CMARK_SRC:-$out/swift-cmark}
if [ -z "${SWIFT_CMARK_SRC:-}" ]; then
	if [ ! -d "$cmark_src/.git" ]; then
		git clone --quiet --filter=blob:none "$SWIFT_CMARK_URL" "$cmark_src"
	fi
	git -C "$cmark_src" fetch --quiet origin "$SWIFT_CMARK_COMMIT" \
		|| git -C "$cmark_src" fetch --quiet origin
	git -C "$cmark_src" checkout --quiet --detach "$SWIFT_CMARK_COMMIT"
fi
# The same sources as the package's cmark-gfm and cmark-gfm-extensions targets, in LC_ALL=C order
# so the link order is stable.
mkdir -p "$out/obj/cmark"
: > "$out/cmark-objects.list"
find "$cmark_src/src" "$cmark_src/extensions" -maxdepth 1 -name '*.c' | LC_ALL=C sort | while IFS= read -r c; do
	obj="$out/obj/cmark/$(basename "$(dirname "$c")")-$(basename "$c" .c).o"
	"$SWIFT_TOOLCHAIN/bin/clang" -target "$SWIFT_DARWIN_TARGET" -isysroot "$DARLING_SDK" -O2 \
		-fvisibility=hidden -DCMARK_GFM_STATIC_DEFINE -DNDEBUG \
		-I "$cmark_src/src/include" -I "$cmark_src/extensions/include" -c "$c" -o "$obj"
	printf '%s\n' "$obj" >> "$out/cmark-objects.list"
done
cmark_flags="-Xcc -DCMARK_GFM_STATIC_DEFINE -Xcc -I$cmark_src/src/include -Xcc -fmodule-map-file=$cmark_src/src/include/module.modulemap -Xcc -fmodule-map-file=$cmark_src/extensions/include/module.modulemap"

# swift-foundation supplies AttributedString and the FormatStyle protocols. Fetched, not vendored,
# for the same reason as swift-collections: 34 of the 37 files are taken exactly as upstream ships
# them. The three that Darling has to change live in Foundation/ and are listed in
# DARLING-CHANGES.md; they are simply not taken from the checkout here.
#
# Pinned BY COMMIT on purpose: a branch reference would make this build non-reproducible.
# dbacc67779... is tag swift-6.3.3-RELEASE; check that with
#   git ls-remote https://github.com/swiftlang/swift-foundation.git refs/tags/swift-6.3.3-RELEASE
# SWIFT_FOUNDATION_SRC can point at an already-fetched checkout for an offline build. Nothing
# verifies that checkout, so point it at the pinned commit. It is never written to.
SWIFT_FOUNDATION_URL=${SWIFT_FOUNDATION_URL:-https://github.com/swiftlang/swift-foundation.git}
SWIFT_FOUNDATION_COMMIT=${SWIFT_FOUNDATION_COMMIT:-dbacc67779dc0a41ddc9493acbaa332d76c9fb03}
foundation_src=${SWIFT_FOUNDATION_SRC:-$out/swift-foundation}
if [ -z "${SWIFT_FOUNDATION_SRC:-}" ]; then
	if [ ! -d "$foundation_src/.git" ]; then
		git clone --quiet --filter=blob:none "$SWIFT_FOUNDATION_URL" "$foundation_src"
	fi
	git -C "$foundation_src" fetch --quiet origin "$SWIFT_FOUNDATION_COMMIT" \
		|| git -C "$foundation_src" fetch --quiet origin
	git -C "$foundation_src" checkout --quiet --detach "$SWIFT_FOUNDATION_COMMIT"
fi

: > "$out/foundation-upstream.list"
while IFS= read -r rel; do
	[ -n "$rel" ] || continue
	printf '%s\n' "$foundation_src/Sources/FoundationEssentials/$rel" >> "$out/foundation-upstream.list"
done <<'UPSTREAM_FILES'
AttributedString/AttributeContainer.swift
AttributedString/AttributedString+AttributeTransformation.swift
AttributedString/AttributedString+CharacterView.swift
AttributedString/AttributedString+Guts.swift
AttributedString/AttributedString+IndexTracking.swift
AttributedString/AttributedString+IndexValidity.swift
AttributedString/AttributedString+Runs+AttributeSlices.swift
AttributedString/AttributedString+Runs+Run.swift
AttributedString/AttributedString+Runs.swift
AttributedString/AttributedString+UTF16View.swift
AttributedString/AttributedString+UTF8View.swift
AttributedString/AttributedString+UnicodeScalarView.swift
AttributedString/AttributedString+_InternalRun.swift
AttributedString/AttributedString+_InternalRuns.swift
AttributedString/AttributedString+_InternalRunsSlice.swift
AttributedString/AttributedString.swift
AttributedString/AttributedStringAttributeConstrainingBehavior.swift
AttributedString/AttributedStringCodable.swift
AttributedString/AttributedSubstring.swift
AttributedString/Collection Stdlib Defaults.swift
AttributedString/DiscontiguousAttributedSubstring.swift
AttributedString/String.Index+ABI.swift
CodableWithConfiguration.swift
Formatting/BinaryInteger+NumericStringRepresentation.swift
Formatting/Date+ISO8601FormatStyle.swift
Formatting/DiscreteFormatStyle.swift
Formatting/FormatParsingUtilities.swift
Formatting/FormatStyle.swift
Formatting/FormatterCache.swift
Formatting/ParseStrategy.swift
Formatting/ParseableFormatStyle.swift
JSON/BufferView.swift
JSON/BufferViewIndex.swift
JSON/BufferViewIterator.swift
Locale/Locale+Language.swift
LockedState.swift
OutputBuffer.swift
SortComparator.swift
String/BidirectionalCollection.swift
String/StringBlocks.swift
UPSTREAM_FILES

# ICU-backed format styles, unmodified, over Darling's ICU 66 as `_FoundationICU` (shims/FoundationICU.h);
# Foundation/FormattingSupport.swift supplies the Locale and Calendar internals (see DARLING-CHANGES.md).
while IFS= read -r rel; do
	[ -n "$rel" ] || continue
	printf '%s\n' "$foundation_src/Sources/FoundationInternationalization/$rel" >> "$out/foundation-upstream.list"
done <<'UPSTREAM_INTL_FILES'
BinaryFloatingPoint.swift
Date+ICU.swift
Duration+Utils.swift
Formatting/ByteCountFormatStyle.swift
Formatting/Date/Date+AnchoredRelativeFormatStyle.swift
Formatting/Date/Date+RelativeFormatStyle.swift
Formatting/Date/Date+VerbatimFormatStyle.swift
Formatting/Date/DateFieldSymbol.swift
Formatting/Date/DateFormatString.swift
Formatting/Date/DateFormatStyle.swift
Formatting/Date/DateParseStrategy.swift
Formatting/Date/ICUDateFormatter.swift
Formatting/Date/ICURelativeDateFormatter.swift
Formatting/Duration+Formatting.swift
Formatting/Duration+TimeFormatStyle.swift
Formatting/ICUListFormatter.swift
Formatting/ListFormatStyle.swift
Formatting/Number/BinaryFloatingPoint+FormatStyle.swift
Formatting/Number/BinaryInteger+FormatStyle.swift
Formatting/Number/FloatingPointFormatStyle.swift
Formatting/Number/FloatingPointParseStrategy.swift
Formatting/Number/ICULegacyNumberFormatter.swift
Formatting/Number/ICUNumberFormatter.swift
Formatting/Number/IntegerFormatStyle.swift
Formatting/Number/IntegerParseStrategy.swift
Formatting/Number/NumberAttributedFormat.swift
Formatting/Number/NumberFormatStyleConfiguration.swift
ICU/ICU+FieldPositer.swift
ICU/ICU+Foundation.swift
RangeExpression.swift
TimeInterval+Utils.swift
UPSTREAM_INTL_FILES

# The SortDescriptor API is the live stall of the ladder: IDEFoundation binds Foundation.SortDescriptor
# metadata (SortDescriptorVMn), its String-keypath `init(_:comparator:)`, String.StandardComparator's
# metadata and `.localizedStandard`, and Sequence.sorted(using:). It lives in swift-foundation under
# `#if FOUNDATION_FRAMEWORK`, and defining FOUNDATION_FRAMEWORK for the whole module changes the code
# path of three files this build already compiles (ICUDateFormatter needs Locale.customDateFormat,
# NumberFormatStyleConfiguration needs Formatter.Context, ICUNumberFormatter changes path -- measured),
# so the define cannot be module-wide. Instead the guard is renamed to a Darling-only define in copies
# of just the two files that carry the API, and that define is passed to the module build; no other
# file opts in. The checkout is never written to: the copies land under $out, like the
# swift-collections/swift-cmark objects below.
mkdir -p "$out/darling-foundation-darwin"
for intl_rel in String/String+SortComparator.swift String/SortDescriptor.swift; do
	darling_src="$out/darling-foundation-darwin/$(basename "$intl_rel")"
	sed 's/FOUNDATION_FRAMEWORK/DARLING_FOUNDATION_FRAMEWORK/g' \
		"$foundation_src/Sources/FoundationInternationalization/$intl_rel" > "$darling_src"
	printf '%s\n' "$darling_src" >> "$out/foundation-upstream.list"
done

# Intentionally partial: String, Array, Dictionary and String bridging, plus AttributedString and
# the FormatStyle protocols (see README).
#
# One C global the Foundation field owes: NSURLErrorBackgroundTaskCancelledReasonKey is an
# `NSString * const` that a client dereferences directly, so it cannot be a Swift declaration; the
# Foundation overlay's own Objective-C file carries it (see
# overlays/Foundation/NSURLErrorConstants.m for why it lives here and not in the off-limits
# src/external/foundation tree).
"$SWIFT_TOOLCHAIN/bin/clang" -target "$SWIFT_DARWIN_TARGET" -isysroot "$DARLING_SDK" -O2 \
	-c "$here/Foundation/NSURLErrorConstants.m" -o "$out/obj/Foundation-NSURLErrorConstants.o"
# One class the Foundation field owes, for the same reason: no image in this tree defines
# NSURLSessionTaskTransactionMetrics, so the overlay defines it as a real class object a client's
# type metadata can point at (see overlays/Foundation/NSURLSessionTaskTransactionMetrics.m).
"$SWIFT_TOOLCHAIN/bin/clang" -target "$SWIFT_DARWIN_TARGET" -isysroot "$DARLING_SDK" -O2 \
	-c "$here/Foundation/NSURLSessionTaskTransactionMetrics.m" -o "$out/obj/Foundation-NSURLSessionTaskTransactionMetrics.o"
# DARLING_FOUNDATION overrides which Foundation slice is linked, so a slice
# built in the build tree can be linked before it is installed into the
# running root; the default is unchanged.
foundation="${DARLING_FOUNDATION:-$DARLING_ROOT/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation}"
# CFNetwork owns the native session transports. Foundation.framework reexports
# their public classes directly on both architectures; no overlay export shim.
# DARLING_CFNETWORK overrides the slice like DARLING_FOUNDATION.
cfnetwork="${DARLING_CFNETWORK:-$DARLING_ROOT/System/Library/Frameworks/CFNetwork.framework/Versions/A/CFNetwork}"
# shellcheck disable=SC2086
build_module Foundation "$here"/Foundation/*.swift --sources-from "$out/foundation-upstream.list" -- -package-name swift-foundation -D DARLING_FOUNDATION_FRAMEWORK $cmark_flags --link -unexported_symbols_list "$out/unexported.txt" "$out/obj/_RopeModule.o" "$out/obj/InternalCollectionsUtilities.o" -filelist "$out/cmark-objects.list" "$out/obj/Foundation-NSURLErrorConstants.o" "$out/obj/Foundation-NSURLSessionTaskTransactionMetrics.o" "$foundation" "$cfnetwork" "$corefoundation" "$DARLING_ROOT/usr/lib/libicucore.A.dylib" "$repo/Combine.framework/Versions/A/Combine" -lswiftDarwin -lswiftObjectiveC -lswiftCoreFoundation -lswiftDispatch

# Build just Foundation for focused overlay changes without rebuilding or replacing
# the other shipped Swift dylibs.
if [ "${DARLING_SWIFT_FOUNDATION_ONLY:-0}" = 1 ]; then
	echo "built Foundation overlay at $out/libswiftFoundation.dylib"
	exit 0
fi
build_oslog "$out/libswiftFoundation.dylib"


# The Network overlay links the Foundation overlay that was just built (see build_network above).
build_network "$out/libswiftFoundation.dylib"

coregraphics="$DARLING_ROOT/System/Library/Frameworks/CoreGraphics.framework/Versions/A/CoreGraphics"
build_module CoreGraphics "$here"/CoreGraphics/*.swift -- -Xcc -fmodule-map-file="$here/CoreGraphics/shims/module.modulemap" --link "$coregraphics" "$corefoundation" -lswiftCoreFoundation -lswiftDarwin

# The AppKit, QuartzCore and CoreText overlays re-export their Clang module, but only where the SDK ships one:
# swift-darling's own SDK carries none of these frameworks, while an SDK built over Darling's in-tree headers
# does. Without the re-export the Swift module shadows the Clang module and hides every Objective-C
# type behind it; with it, against an SDK that has no such module, the import is a hard error.
clang_module_flag() {
	if [ -f "$DARLING_SDK/System/Library/Frameworks/$1.framework/Modules/module.modulemap" ]; then
		printf -- '-D DARLING_%s_CLANG_MODULE' "$2"
	fi
}

# Minimal clean-room AppKit overlay (see README).
appkit="$DARLING_ROOT/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit"
build_module AppKit "$here/AppKit/AppKit.swift" -- $(clang_module_flag AppKit APPKIT) -Xcc -fmodule-map-file="$here/AppKit/shims/module.modulemap" -Xcc -fmodule-map-file="$here/CoreGraphics/shims/module.modulemap" --link "$appkit" "$foundation" -lswiftFoundation -lswiftCoreGraphics -lswiftCoreFoundation -lswiftObjectiveC -lswiftDarwin

# Minimal clean-room QuartzCore overlay (see README).
build_module QuartzCore "$here/QuartzCore/QuartzCore.swift" -- $(clang_module_flag QuartzCore QUARTZCORE) -Xcc -fmodule-map-file="$here/QuartzCore/shims/module.modulemap"

# Intentionally partial: the vector and matrix conversions and SCNBoundingVolume only (see README).
scenekit="$DARLING_ROOT/System/Library/Frameworks/SceneKit.framework/Versions/A/SceneKit"
build_module SceneKit "$here/SceneKit/SceneKit.swift" -- -Xcc -fmodule-map-file="$here/SceneKit/shims/module.modulemap" -Xcc -fmodule-map-file="$here/CoreGraphics/shims/module.modulemap" --link "$scenekit" "$foundation" "$corefoundation" -lswiftFoundation -lswiftCoreGraphics -lswiftCoreFoundation -lswiftObjectiveC -lswiftDarwin

# UniformTypeIdentifiers is arm64-only: the x86_64 slice built from ../libswiftUniformTypeIdentifiers.S held
# placeholder values, so there is nothing to merge with.
uti="$DARLING_ROOT/System/Library/Frameworks/UniformTypeIdentifiers.framework/Versions/A/UniformTypeIdentifiers"
build_module UniformTypeIdentifiers "$here/UniformTypeIdentifiers/UniformTypeIdentifiers.swift" -- $(clang_module_flag UniformTypeIdentifiers UNIFORMTYPEIDENTIFIERS) -Xcc -fmodule-map-file="$here/UniformTypeIdentifiers/shims/module.modulemap" --link "$uti" "$foundation" "$corefoundation" -lswiftFoundation -lswiftCoreFoundation -lswiftObjectiveC -lswiftDarwin
cp "$out/libswiftUniformTypeIdentifiers.dylib" "$repo/libswiftUniformTypeIdentifiers.dylib"
echo "updated libswiftUniformTypeIdentifiers.dylib: $(llvm-lipo -archs "$repo/libswiftUniformTypeIdentifiers.dylib")"

# Intentionally partial: AttributedString.AdaptiveImageGlyph only (see README). arm64-only, like UniformTypeIdentifiers:
# there is no x86_64 slice to merge with.
coretext="$DARLING_ROOT/System/Library/Frameworks/CoreText.framework/Versions/A/CoreText"
build_module CoreText "$here/CoreText/CoreText.swift" -- $(clang_module_flag CoreText CORETEXT) -package-name DarlingCoreText -Xcc -fmodule-map-file="$here/CoreText/shims/module.modulemap" -Xcc -fmodule-map-file="$here/UniformTypeIdentifiers/shims/module.modulemap" --link "$coretext" "$foundation" -lswiftUniformTypeIdentifiers -lswiftFoundation -lswiftCoreFoundation -lswiftObjectiveC -lswiftDarwin
cp "$out/libswiftCoreText.dylib" "$repo/libswiftCoreText.dylib"
echo "updated libswiftCoreText.dylib: $(llvm-lipo -archs "$repo/libswiftCoreText.dylib")"

# GroupActivities: Apple's is closed source and pure Swift, with no open-source twin, so the source
# here declares only the public API shape, which is what makes the mangled names match what apps
# bind. Deliberately inert: SharePlay needs a coordination daemon Darling does not have. See
# overlays/README.md.
#
# Links against Combine.framework above for the 9 Combine symbols the @Published properties pull in,
# so Combine must be built first and stays a non-weak runtime dependency of the installed framework.
collect_sources "$here/GroupActivities/Sources" "$out/GroupActivities.sources"
mkdir -p "$out/modules-groupactivities"
"$SWIFT_TOOLCHAIN/bin/swiftc" -frontend -c @"$out/GroupActivities.sources" \
	-target "$SWIFT_DARWIN_TARGET" -sdk "$DARLING_SDK" -resource-dir "$SWIFT_RESOURCE_DIR" \
	-module-cache-path "$out/module-cache" -swift-version 5 \
	-module-name GroupActivities \
	-enable-library-evolution -parse-as-library -O \
	-I "$out/modules" \
	-emit-module-path "$out/modules-groupactivities/GroupActivities.swiftmodule" \
	-o "$out/obj/GroupActivities.o"

mkdir -p "$repo/GroupActivities.framework/Versions/A"
# shellcheck disable=SC2086
"$DARLING_LD" -dylib -arch "$SWIFT_DARWIN_ARCH" -platform_version macos 26.0 26.0 -syslibroot "$DARLING_ROOT" \
	-install_name "/System/Library/Frameworks/GroupActivities.framework/Versions/A/GroupActivities" \
	-compatibility_version 1.0.0 -current_version 1.0.0 \
	$LD_EXTRA_FLAGS \
	-L "$SWIFT_RESOURCE_DIR/macosx" \
	"$out/obj/GroupActivities.o" \
	"$repo/Combine.framework/Versions/A/Combine" \
	"$DARLING_LIBSYSTEM" "$DARLING_ROOT/usr/lib/libobjc.A.dylib" \
	-lswiftCore \
	-o "$repo/GroupActivities.framework/Versions/A/GroupActivities"
echo "updated GroupActivities.framework: $(llvm-lipo -archs "$repo/GroupActivities.framework/Versions/A/GroupActivities")"

# CryptoKit: Apple's is closed source and pure Swift. swift-crypto deliberately mirrors its public
# API, so building it as module `CryptoKit` makes the mangled names match what apps import. Darling
# cannot link BoringSSL into this framework, so the fork below supplies a pure-Swift SHA-256 and
# neutralises the `canImport(CryptoKit)` guards that would otherwise collapse the package into an
# empty module re-exporting itself. See overlays/README.md and the fork's DARLING-CHANGES.md.
#
# Pinned BY COMMIT on purpose: a branch reference would make this build non-reproducible.
CRYPTOKIT_FORK_URL=${CRYPTOKIT_FORK_URL:-https://github.com/cristim/swift-crypto.git}
CRYPTOKIT_FORK_COMMIT=${CRYPTOKIT_FORK_COMMIT:-c4105ade5fbe6866375ec65146cac733d53a1146}
crypto_src="$out/swift-crypto"
if [ ! -d "$crypto_src/.git" ]; then
	git clone --quiet --filter=blob:none "$CRYPTOKIT_FORK_URL" "$crypto_src"
fi
git -C "$crypto_src" fetch --quiet origin "$CRYPTOKIT_FORK_COMMIT" \
	|| git -C "$crypto_src" fetch --quiet origin
git -C "$crypto_src" checkout --quiet --detach "$CRYPTOKIT_FORK_COMMIT"

# SHA-256 and HMAC-SHA-256 only: that is what the corpus binds. See overlays/README.md.
cryptokit_sources="
	Sources/Crypto/Digests/Digest.swift
	Sources/Crypto/Digests/Digests.swift
	Sources/Crypto/Digests/HashFunctions.swift
	Sources/Crypto/Digests/HashFunctions_SHA2.swift
	Sources/Crypto/Digests/Darling/Digest_darling.swift
	Sources/Crypto/Keys/Symmetric/SymmetricKeys.swift
	Sources/Crypto/Insecure/Insecure.swift
	Sources/Crypto/Util/ArraySpanHelpers.swift
	Sources/Crypto/Util/Data+ArraySpan.swift
	Sources/Crypto/Util/PrettyBytes.swift
	Sources/Crypto/Util/SafeCompare.swift
	Sources/Crypto/Util/SecureBytes.swift
	Sources/Crypto/Util/Zeroization.swift
	Sources/Crypto/Util/BoringSSL/SafeCompare_boring.swift
	Sources/Crypto/Util/BoringSSL/RNG_boring.swift
	Sources/Crypto/Util/BoringSSL/InlineArray+withBytes_boring.swift
	Sources/Crypto/Util/BoringSSL/Optional+withUnsafeBytes_boring.swift
"
cryptokit_files=""
for f in $cryptokit_sources; do
	cryptokit_files="$cryptokit_files $crypto_src/$f"
done
# These three live in a directory whose name contains spaces, so they are passed separately.
mac_dir="$crypto_src/Sources/Crypto/Message Authentication Codes"

mkdir -p "$out/modules-cryptokit"
# shellcheck disable=SC2086
"$SWIFT_TOOLCHAIN/bin/swiftc" -frontend -c $cryptokit_files \
	"$mac_dir/HMAC/HMAC.swift" "$mac_dir/MessageAuthenticationCode.swift" "$mac_dir/MACFunctions.swift" \
	-target "$SWIFT_DARWIN_TARGET" -sdk "$DARLING_SDK" -resource-dir "$SWIFT_RESOURCE_DIR" \
	-module-cache-path "$out/module-cache" -swift-version 5 \
	-module-name CryptoKit \
	-D DARLING_CRYPTOKIT_MODULE -enable-experimental-feature Lifetimes \
	-enable-library-evolution -parse-as-library -O \
	-I "$out/modules" \
	-Xcc -fmodule-map-file="$here/shims/overlay-shims.modulemap" \
	-emit-module-path "$out/modules-cryptokit/CryptoKit.swiftmodule" \
	-o "$out/obj/CryptoKit.o"

mkdir -p "$repo/CryptoKit.framework/Versions/A"
# shellcheck disable=SC2086
"$DARLING_LD" -dylib -arch "$SWIFT_DARWIN_ARCH" -platform_version macos 26.0 26.0 -syslibroot "$DARLING_ROOT" \
	-install_name "/System/Library/Frameworks/CryptoKit.framework/Versions/A/CryptoKit" \
	-compatibility_version 1.0.0 -current_version 1.0.0 \
	$LD_EXTRA_FLAGS \
	-L "$SWIFT_RESOURCE_DIR/macosx" -L "$out" \
	"$out/obj/CryptoKit.o" \
	"$DARLING_LIBSYSTEM" "$DARLING_ROOT/usr/lib/libobjc.A.dylib" \
	-lswiftCore -lswiftFoundation -lswiftCoreFoundation -lswiftDarwin -lswiftObjectiveC \
	-o "$repo/CryptoKit.framework/Versions/A/CryptoKit"
echo "updated CryptoKit.framework: $(llvm-lipo -archs "$repo/CryptoKit.framework/Versions/A/CryptoKit")"

# shellcheck disable=SC2086
publish_modules $darwin_modules ObjectiveC CoreFoundation Dispatch os XPC Foundation CoreGraphics AppKit QuartzCore SceneKit
