#!/bin/sh
# Build libswiftDemangle.dylib for the guest and copy it beside the other libswift*.dylib.
#
# WHAT THIS BUILDS. The REAL demangler library the open-source Swift project builds for
# /usr/lib/swift/libswiftDemangle.dylib: swiftlang/swift at tag swift-6.2.4-RELEASE, from
# lib/Demangling (11 files) plus lib/SwiftDemangle (SwiftDemangle.cpp, MangleHack.cpp), compiled here
# as C++ for x86_64-apple-macosx26.0. It is NOT a substitute: every mangled name a client binds comes
# out of this build's own export trie, and the demangling it performs is the demangler's real work.
#
# WHY. `/usr/lib/swift/libswiftDemangle.dylib` is the rung after libswiftSystem. Measured from the
# bind table of the guest's Xcode 26.3 XCTHarness (the ONLY referrer of this install name inside
# libxcodebuildLoader's load closure, and it links the image NON-weakly):
#
#   dependency field libswiftDemangle, 3 symbols, all non-lazy (__DATA_CONST,__got):
#     _swift_demangle_getDemangledName
#     _swift_demangle_getModuleName
#     _swift_demangle_getSimplifiedDemangledName
#
# All three are plain C entry points (no Swift mangling), which is why this rung is a real C++ build
# rather than a Swift module.
#
# MEASURED FIDELITY, and it is exact. Apple ships a .tbd for this library in the same SDK
# (<Xcode>/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/lib/swift/libswiftDemangle.tbd)
# and that file is the ABI this build is measured against: it names 235 symbols for the x86_64-macos
# target (237 across all three target groups). This build's export trie carries all 235 -- and
# NOTHING Apple's file does not:
#
#   symbols here absent from Apple's tbd: ZERO
#   Apple's symbols absent here:          ZERO
#
# The same 235-symbol set is what the toolchain's own copy exports
# (XcodeDefault.xctoolchain/usr/lib/libswiftDemangle.dylib, `llvm-nm -g --defined-only`: 235), so
# file and tbd agree, and this build reproduces both.
#
# THE ONE SOURCE APPLE'S SHIPPED LIBRARY DOES NOT CONTAIN. lib/Demangling/CMakeLists.txt lists
# OldRemangler.cpp, but Apple's shipped library clearly does not carry it, measured rather than
# assumed: that file defines four non-assert string literals nothing else defines
# (`<curry-thunk>`, `<autodiff-function>`, `<method-descriptor>`, `<reabstraction-thunk>`) and all
# four are absent from Apple's shipped binary (zero occurrences) while present in a build that
# includes the file. Consistently, the three symbols OldRemangler.cpp alone defines --
# swift::Demangle::mangleNodeOld(Node*), mangleNodeOld(Node*, NodeFactory&) and
# mangleNodeAsObjcCString(Node*, NodeFactory&) -- are absent from Apple's tbd AND from its binary.
# This recipe therefore compiles the same source set Apple ships; including OldRemangler.cpp would
# export exactly those three extra names (measured: 238 symbols, 3 of them outside Apple's ABI) and
# no client in the load closure demands any of them. Old *de*mangling is NOT dropped: OldDemangler.cpp
# is compiled and SWIFT_SUPPORT_OLD_MANGLING=1 is set, which is the flag Context.cpp/Demangler.cpp
# need for the `_Tt` names still present in ObjC metadata.
#
# COMPILE FLAGS, all justified rather than guessed: -DNDEBUG (Apple's binary carries no assert
# expression strings, so it is a release build), and -fno-exceptions -fno-rtti (Apple's binary has no
# __gcc_except_table section and no typeinfo/vtable references). -O2, -DSWIFT_SUPPORT_OLD_MANGLING=1,
# -DSWIFT_STDLIB_HAS_TYPE_PRINTING=1 and -DLLVM_DISABLE_ABI_BREAKING_CHECKS_ENFORCING=1 are the flags
# lib/Demangling/CMakeLists.txt sets for this library.
#
# The demangler needs LLVM headers but no LLVM library: it imports zero llvm:: symbols (Apple's copy
# is the same, it links libobjc/libc++/libSystem only). The LLVM sources it includes are
# ADT/{ArrayRef,DenseMap,PointerIntPair,StringRef,StringSwitch}.h and Support/Compiler.h.
#
# REPRODUCIBLE BYTES, and it is not free. The demangler's always-on assertion macro
# (DEMANGLER_ALWAYS_ASSERT in Demangler.cpp) expands to a call carrying __FILE__, so without help
# exactly one source path -- "$src/lib/Demangling/Demangler.cpp" -- lands in the image and its bytes
# follow the directory the recipe happened to build in, which makes a committed payload unreproducible
# and a deploy receipt unverifiable. -ffile-prefix-map="$src"= (empty replacement, so the checkout
# prefix is deleted rather than replaced) rewrites it to
# "/lib/Demangling/Demangler.cpp"; that string is the ONLY absolute build path in this image (the
# remaining absolute strings are the install names of the images it links:
# /usr/lib/{libSystem.B,libobjc.A,libc++.1,libc++abi}.dylib and its own). No debug info is emitted, so
# -fdebug-prefix-map has nothing else to rewrite. Verified by building this recipe from two different
# checkout directories and comparing sha256, not by inspection.
#
# ONE LOAD-COMMAND DIFFERENCE FROM APPLE. Apple's copy links libobjc, libc++ and libSystem; this build
# additionally records LC_LOAD_DYLIB /usr/lib/libc++abi.dylib, because the tree's libc++.1.dylib
# re-export alone does not let ld64 bind __Znwm/__ZdlPv (see the ld64 comment below). That cannot
# break the load: the guest prefix carries /usr/lib/libc++abi.dylib, and the prefix's libc++.1.dylib
# itself names it with LC_REEXPORT_DYLIB, so no guest that loads libc++ can lack it -- and the image
# was measured loading in the guest ("dyld: loaded: ... /usr/lib/swift/libswiftDemangle.dylib"), which
# is only reached with its whole dependency set resolved.
#
# Required environment (the same names the other overlay recipes use, plus six):
#   SWIFT_TOOLCHAIN     usr/ directory of a Swift toolchain (the Linux release works; it carries clang)
#   DARLING_SDK         Darling's MacOSX.sdk (Clang module maps, sys/cdefs.h fix)
#   DARLING_LD          Darling's ld64 (build/src/external/cctools-port/cctools/ld64/src/x86_64-apple-darwin20-ld)
#   DARLING_LIBSYSTEM   Darling's built libSystem.B.dylib
#   DARLING_LIBOBJC     Darling's built libobjc.A.dylib
#   DARLING_LIBCXX      Darling's built libc++.1.dylib
#   DARLING_LIBCXXABI   Darling's built libc++abi.dylib (resolved under /usr/lib/libc++abi.dylib)
#   LLVM_INCLUDE        LLVM headers with ADT/{ArrayRef,DenseMap,PointerIntPair,StringRef,StringSwitch}.h
#                       (default /usr/lib/llvm-18/include)
#   LIBCXX_INCLUDE      libc++ headers whose ABI matches the libc++ the guest links. Darling's SDK
#                       ships no libc++, so this must be pointed at a libc++ (in this environment the
#                       Xcode SDK's usr/include/c++/v1).
# Optional:
#   SWIFT_DEMANGLE_SRC  an existing checkout of the pinned commit (offline build); the checkout is not
#                       modified, only read. Nothing verifies it, so point it at the pinned commit: a
#                       checkout of another revision builds another ABI silently.
#
# Output: the built dylib, additionally copied to ../../libswiftDemangle.dylib (the payload directory
# the rootless manifest globs) when run with that default.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
payload=$(cd "$here/../.." && pwd)

: "${SWIFT_TOOLCHAIN:?}" "${DARLING_SDK:?}" "${DARLING_LD:?}" "${DARLING_LIBSYSTEM:?}"
: "${DARLING_LIBOBJC:?}" "${DARLING_LIBCXX:?}" "${DARLING_LIBCXXABI:?}" "${LIBCXX_INCLUDE:?}"
: "${LLVM_INCLUDE:=/usr/lib/llvm-18/include}"

SWIFT_DARWIN_ARCH=${SWIFT_DARWIN_ARCH:-x86_64}
SWIFT_DARWIN_TARGET=${SWIFT_DARWIN_TARGET:-$SWIFT_DARWIN_ARCH-apple-macosx26.0}
# The version Apple's own toolchain copy of this library carries; the guest's Xcode 26.3 XCTHarness
# requires compatibility version 1.0.0 of the load, which 6.2.4.0 satisfies.
SWIFT_DEMANGLE_VERSION=${SWIFT_DEMANGLE_VERSION:-6.2.4}
out=${SWIFT_DEMANGLE_OUT:-$here/build}
work=${SWIFT_DEMANGLE_BUILD_DIR:-$out/swift}

# Pinned BY COMMIT, not by tag, so a moved tag cannot change what this builds. 6.2.4 is the revision
# Apple's own libswiftDemangle carries (LC_ID_DYLIB current version 6.2.4), and the revision whose
# export set this build reproduces exactly (see the fidelity measurement in the header).
SWIFT_DEMANGLE_URL=${SWIFT_DEMANGLE_URL:-https://github.com/swiftlang/swift}
SWIFT_DEMANGLE_REF=${SWIFT_DEMANGLE_REF:-swift-6.2.4-RELEASE}
SWIFT_DEMANGLE_COMMIT=${SWIFT_DEMANGLE_COMMIT:-ee343b46aef81c3ac7c5d7960cb35a41a88c5a9b}

src=${SWIFT_DEMANGLE_SRC:-$work}
if [ -z "${SWIFT_DEMANGLE_SRC:-}" ]; then
	# Partial, sparse, single-commit clone: the demangler is a few files under a repository of
	# hundreds of megabytes, and the checkout must not be able to serve a stray revision.
	rm -rf "$work"
	mkdir -p "$out"
	git clone --filter=blob:none --no-checkout --depth 1 --branch "$SWIFT_DEMANGLE_REF" \
		"$SWIFT_DEMANGLE_URL" "$work"
	(cd "$work" && git sparse-checkout init --cone \
		&& git sparse-checkout set lib/Demangling lib/SwiftDemangle include/swift/Demangling \
			include/swift/Basic include/swift/Runtime include/swift/ABI include/swift/AST \
			include/swift/SwiftDemangle \
		&& git checkout --quiet "$SWIFT_DEMANGLE_COMMIT")
fi
[ -d "$src/lib/Demangling" ] || { echo "no swift Demangling sources at $src" >&2; exit 2; }
[ -d "$src/lib/SwiftDemangle" ] || { echo "no swift SwiftDemangle sources at $src" >&2; exit 2; }

# A clean object directory every run: a leftover object from a different source list would be linked
# silently.
rm -rf "$out/obj"; mkdir -p "$out/obj"

# The exact source list, in the CMakeLists' order, with the one measured omission explained in the
# header (OldRemangler.cpp: Apple's shipped library does not contain it).
sources="
$src/lib/Demangling/Demangler.cpp
$src/lib/Demangling/Context.cpp
$src/lib/Demangling/ManglingUtils.cpp
$src/lib/Demangling/NodeDumper.cpp
$src/lib/Demangling/NodePrinter.cpp
$src/lib/Demangling/OldDemangler.cpp
$src/lib/Demangling/Punycode.cpp
$src/lib/Demangling/Remangler.cpp
$src/lib/Demangling/Errors.cpp
$src/lib/Demangling/CrashReporter.cpp
$src/lib/SwiftDemangle/SwiftDemangle.cpp
$src/lib/SwiftDemangle/MangleHack.cpp
"

for f in $sources; do
	"$SWIFT_TOOLCHAIN/bin/clang++" -c \
		-target "$SWIFT_DARWIN_TARGET" -isysroot "$DARLING_SDK" -stdlib=libc++ \
		-I "$LIBCXX_INCLUDE" -I "$LLVM_INCLUDE" -I "$src/include" \
		-ffile-prefix-map="$src"= \
		-O2 -DNDEBUG -fno-exceptions -fno-rtti \
		-DLLVM_DISABLE_ABI_BREAKING_CHECKS_ENFORCING=1 \
		-DSWIFT_SUPPORT_OLD_MANGLING=1 \
		-DSWIFT_STDLIB_HAS_TYPE_PRINTING=1 \
		"$f" -o "$out/obj/$(basename "$f" .cpp).o"
done

# ld64 needs a file for the re-exported libc++abi (the tree's libc++.1.dylib re-exports it; the link
# records it as a direct dependency, which Apple's copy does not have because its libc++ stub folds
# the re-export into libc++.1.dylib). Both images exist in the guest.
"$DARLING_LD" -dylib -arch "$SWIFT_DARWIN_ARCH" \
	-platform_version macos 26.0 26.0 -syslibroot "$DARLING_SDK" \
	-install_name "/usr/lib/swift/libswiftDemangle.dylib" \
	-compatibility_version 1.0.0 -current_version "$SWIFT_DEMANGLE_VERSION" \
	-dylib_file "/usr/lib/libc++abi.dylib:$DARLING_LIBCXXABI" \
	"$out"/obj/*.o "$DARLING_LIBSYSTEM" "$DARLING_LIBOBJC" "$DARLING_LIBCXX" \
	-o "$out/libswiftDemangle.dylib"

cp "$out/libswiftDemangle.dylib" "$payload/libswiftDemangle.dylib"
echo "built $out/libswiftDemangle.dylib and copied it to $payload/libswiftDemangle.dylib"
