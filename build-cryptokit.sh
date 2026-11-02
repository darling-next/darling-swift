#!/bin/bash
# Build CryptoKit.framework for x86_64 from swift-crypto, as module `CryptoKit`.
#
# This is bash, not sh: the parallel C/C++ step exports its compile function with `export -f`, which
# dash (the /bin/sh here) rejects as an illegal option for a special builtin and then EXITS ON, so
# under sh this script stops silently right after printing the file counts (measured 2026-10-13:
# rc=2, no further output, an empty object directory).
#
# Provenance: sources are cristim/swift-crypto (the Darling fork of apple/swift-crypto, Apache-2.0
# with the Runtime Library Exception) pinned BY COMMIT, checked out by this script rather than
# vendored here. Built on Linux with swift-6.3.1-RELEASE-ubuntu24.04, targeting
# x86_64-apple-macosx26.0 against Darling's MacOSX.sdk. The C++ half of BoringSSL is compiled with
# Darling's own src/external/libcxx/include (the same libc++ the guest's /usr/lib/libc++.1.dylib is
# built from), because no Darwin C++ standard library ships anywhere in this environment; the dylib
# is linked with Darling's ld64. No Apple code is vendored.
#
# BoringSSL/XKCP and wrapper lists come from the pinned fork's CMakeLists.txt.
set -eu
# Inputs must identify the compiler, SDK, matching product image and source-built
# overlay modules explicitly. Historical /tmp caches and default prefixes are not
# build authorities. See README.md for the canonical workspace invocation.
: "${SWIFT_TOOLCHAIN:?}" "${SWIFT_RESOURCE_DIR:?}" "${DARLING_SDK:?}"
: "${DARLING_LD:?}" "${DARLING_LIBSYSTEM:?}" "${DARLING_ROOT:?}"
: "${DARLING_LIBCXX_HEADERS:?}" "${OVERLAY_MODULES:?}" "${CRYPTOKIT_BUILD_DIR:?}"
here=$(cd "$(dirname "$0")" && pwd)
OVERLAY_SHIMS=${OVERLAY_SHIMS:-"$here/overlays/shims/overlay-shims.modulemap"}
OVERLAY_LIBRARIES=${OVERLAY_LIBRARIES:-"$here"}
CRYPTOKIT_FORK_URL=${CRYPTOKIT_FORK_URL:-https://github.com/cristim/swift-crypto.git}
CRYPTOKIT_FORK_COMMIT=${CRYPTOKIT_FORK_COMMIT:-c4105ade5fbe6866375ec65146cac733d53a1146}
TARGET=x86_64-apple-macosx26.0
work=$CRYPTOKIT_BUILD_DIR
src="$work/swift-crypto"
out="$work/out"
if [ ! -d "$src/.git" ]; then git clone --quiet --filter=blob:none "$CRYPTOKIT_FORK_URL" "$src"; fi
git -C "$src" fetch --quiet origin "$CRYPTOKIT_FORK_COMMIT" || git -C "$src" fetch --quiet origin
git -C "$src" checkout --quiet --detach "$CRYPTOKIT_FORK_COMMIT"
# This local patch carries the initializer compatibility change and the upstream
# buffer-based AEAD path for Foundation without Data.mutableBytes.
# P384/P521 use the fork's real signing code and our existing SHA384/SHA512.
# Refuse source/patch drift rather than silently omitting a necessary change.
git -C "$src" apply "$here/cryptokit-darling.patch"
# A clean object directory every run: the link globs "$out"/obj/*.o, and a source list that changed
# since the last run would otherwise leave stale objects behind (measured: XKCP's files appearing
# twice under two name spellings, which ld reports as "34 duplicate symbols").
rm -rf "$out/obj" "$out/modules" "$out/modules-wrapper"
mkdir -p "$out/obj" "$out/modules" "$out/modules-wrapper" "$out/module-cache"
python3 -B "$here/extract-cryptokit-sources.py" "$src" "$work" > "$work/lists.txt"
CFLAGS="-target $TARGET -isysroot $DARLING_SDK -I $src/Sources/CCryptoBoringSSL/include -I $src/Sources/CCryptoBoringSSL -O2"
CXXFLAGS="$CFLAGS -std=c++17 -nostdinc++ -isystem $DARLING_LIBCXX_HEADERS"
echo "compiling BoringSSL/XKCP: $(wc -l < "$work/list-boringssl.txt") + $(wc -l < "$work/list-xkcp.txt") files"
while read -r f; do
	case "$f" in
	*.cc) echo "cxx|$src/Sources/CCryptoBoringSSL/$f|$out/obj/cc_$(echo "$f" | tr '/.' '__').o" ;;
	*.c)  echo "cc|$src/Sources/CCryptoBoringSSL/$f|$out/obj/c_$(echo "$f" | tr '/.' '__').o" ;;
	*.S|*.s) echo "cc|$src/Sources/CCryptoBoringSSL/$f|$out/obj/s_$(echo "$f" | tr '/.' '__').o" ;;
	esac
done < "$work/list-boringssl.txt" > "$work/jobs.txt"
while read -r f; do
	case "$f" in
	*.c) echo "cc|$src/Sources/$f|$out/obj/x_$(echo "$f" | tr '/.' '__').o" ;;
	esac
done < "$work/list-xkcp.txt" >> "$work/jobs.txt"
# the XKCP C headers, and the shim target's own sources (shims.c is listed by CXKCPShims)
XKCP_INC="-I $src/Sources/CXKCP/include -I $src/Sources/CXKCP -I $src/Sources/CXKCPShims/include"
compile_one() {
	kind=${1%%|*}; rest=${1#*|}; file=${rest%%|*}; obj=${rest##*|}
	case "$kind" in
	cc) "$SWIFT_TOOLCHAIN/bin/clang" $CFLAGS $XKCP_INC -c "$file" -o "$obj" ;;
	cxx) "$SWIFT_TOOLCHAIN/bin/clang++" $CXXFLAGS $XKCP_INC -c "$file" -o "$obj" ;;
	esac
}
export -f compile_one 2>/dev/null || true
export SWIFT_TOOLCHAIN CFLAGS CXXFLAGS XKCP_INC
xargs -P "$(nproc)" -I{} bash -c 'compile_one "$@"' _ {} < "$work/jobs.txt" || { echo "C/C++ COMPILE FAILED" >&2; exit 1; }
echo "C/C++ objects: $(ls "$out/obj" | wc -l)"
# The lists are read into "$@" rather than a space-joined string: several of the fork's paths
# contain spaces ("ASN1/Basic ASN1 Types/...", "Message Authentication Codes/..."), and a joined
# string splits them into bogus inputs.
set --
while read -r f; do set -- "$@" "$src/Sources/CryptoBoringWrapper/$f"; done < "$work/list-wrapper_swift.txt"
"$SWIFT_TOOLCHAIN/bin/swiftc" -frontend -c "$@" \
	-target $TARGET -sdk "$DARLING_SDK" -resource-dir "$SWIFT_RESOURCE_DIR" -module-cache-path "$out/module-cache" \
	-swift-version 5 -package-name com.apple.swift-crypto -module-name CryptoBoringWrapper -enable-experimental-feature Lifetimes \
	-enable-library-evolution -parse-as-library -O \
	-I "$out/modules" -I "$OVERLAY_MODULES" -Xcc -fmodule-map-file="$OVERLAY_SHIMS" \
	-Xcc "-I$src/Sources/CCryptoBoringSSL/include" -Xcc -fmodule-map-file="$src/Sources/CCryptoBoringSSL/include/module.modulemap" \
	-emit-module-path "$out/modules-wrapper/CryptoBoringWrapper.swiftmodule" -o "$out/obj/CryptoBoringWrapper.o"
echo "CryptoBoringWrapper built"
# Crypto: the module itself, named CryptoKit.
#
# Keep the supported software surface backed by the pinned fork, including its
# complete AEAD implementation (not an AES.GCM metadata-only declaration).
# Nonces.swift shares AES and ChaChaPoly declarations, so both real AEADs are
# compiled. Digest_darling.swift replaces Digest_boring.swift for this backend.
# Ed25519 uses the pinned fork's complete authoritative signing/key family and
# its existing BoringSSL backend, rather than a replacement algorithm or shim.
# Comparison: apple/swift-crypto main and PureSwift/swift-crypto master both use
# the same region-flattening verification design and ED25519_verify primitive.
# Keep the family together (including its genuine private-key implementation):
# Ed25519Keys.swift and EdDSA_boring.swift define both halves in shared files.
# Contiguous inputs stay borrowed; only discontiguous fields are flattened.
set --
while IFS= read -r f; do
	case "$f" in ''|'#'*) continue ;; esac
	set -- "$@" "$src/Sources/Crypto/$f"
done <<'CRYPTOKIT_SOURCES'
Digests/Digest.swift
PRF/AES.swift
AEADs/Cipher.swift
AEADs/Nonces.swift
AEADs/AES/GCM/AES-GCM.swift
AEADs/AES/GCM/BoringSSL/AES-GCM_boring.swift
AEADs/ChachaPoly/ChaChaPoly.swift
AEADs/ChachaPoly/BoringSSL/ChaChaPoly_boring.swift
Digests/Digests.swift
CryptoKitErrors.swift
CryptoError_boring.swift
Digests/HashFunctions.swift
Digests/HashFunctions_SHA2.swift
Digests/Darling/Digest_darling.swift
Keys/Symmetric/SymmetricKeys.swift
Insecure/Insecure.swift
# Insecure.SHA1 and Insecure.MD5 live here, not in Insecure.swift.  Both need the
# DarlingBackedHashFunction conformances cryptokit-md5sha1.swift (next to this script) supplies;
# Notarization.framework binds four Insecure.MD5 names eagerly, and this is the file that declares
# them.  See cryptokit-md5sha1.swift and README.md, "CryptoKit".
Insecure/Insecure_HashFunctions.swift
Util/ArraySpanHelpers.swift
Util/Data+ArraySpan.swift
Util/PrettyBytes.swift
Util/SafeCompare.swift
Util/SecureBytes.swift
Util/Zeroization.swift
Util/BoringSSL/SafeCompare_boring.swift
Util/BoringSSL/RNG_boring.swift
Util/BoringSSL/InlineArray+withBytes_boring.swift
Util/BoringSSL/Optional+withUnsafeBytes_boring.swift
Message Authentication Codes/HMAC/HMAC.swift
Message Authentication Codes/MessageAuthenticationCode.swift
Message Authentication Codes/MACFunctions.swift
Signatures/ECDSA.swift
Signatures/Signature.swift
Signatures/Ed25519.swift
Signatures/BoringSSL/EdDSA_boring.swift
Keys/EC/Curve25519.swift
Keys/EC/Ed25519Keys.swift
Keys/EC/BoringSSL/Ed25519_boring.swift
Key Derivation/HKDF.swift
Key Derivation/ANSIx963.swift
Signatures/BoringSSL/ECDSA_boring.swift
Signatures/BoringSSL/ECDSASignature_boring.swift
Keys/EC/NISTCurvesKeys.swift
Keys/EC/BoringSSL/NISTCurvesKeys_boring.swift
Key Agreement/ECDH.swift
Key Agreement/DH.swift
Key Agreement/BoringSSL/ECDH_boring.swift
Util/BoringSSL/CryptoKitErrors_boring.swift
ASN1/ASN1.swift
ASN1/ECDSASignature.swift
ASN1/PEMDocument.swift
ASN1/PKCS8PrivateKey.swift
ASN1/SEC1PrivateKey.swift
ASN1/SubjectPublicKeyInfo.swift
ASN1/Basic ASN1 Types/ASN1Any.swift
ASN1/Basic ASN1 Types/ASN1BitString.swift
ASN1/Basic ASN1 Types/ASN1Boolean.swift
ASN1/Basic ASN1 Types/ASN1Identifier.swift
ASN1/Basic ASN1 Types/ASN1Integer.swift
ASN1/Basic ASN1 Types/ASN1Null.swift
ASN1/Basic ASN1 Types/ASN1OctetString.swift
ASN1/Basic ASN1 Types/ASN1Strings.swift
ASN1/Basic ASN1 Types/ArraySliceBigint.swift
ASN1/Basic ASN1 Types/GeneralizedTime.swift
ASN1/Basic ASN1 Types/ObjectIdentifier.swift
CRYPTOKIT_SOURCES
# This repository's own Darling additions (kept next to this script rather than in the fork's tree,
# so they are visible in the payload's own diff):
#   cryptokit-md5sha1.swift      the MD5/SHA-1 DarlingBackedHashFunction conformances;
#   cryptokit-sha384sha512.swift the SHA-384/512 hasher declarations HashFunctions_SHA2.swift
#                                compiles out under this flag, plus their conformances over the same
#                                BoringSSL streaming idiom.  CoreDocumentation binds SHA512's type
#                                metadata and its HashFunction conformance, and hashes with them.
set -- "$@" "$here/cryptokit-md5sha1.swift" "$here/cryptokit-sha384sha512.swift" \
	"$here/cryptokit-secureenclave.swift"
"$SWIFT_TOOLCHAIN/bin/swiftc" -frontend -c "$@" \
	-target $TARGET -sdk "$DARLING_SDK" -resource-dir "$SWIFT_RESOURCE_DIR" -module-cache-path "$out/module-cache" \
	-swift-version 5 -package-name com.apple.swift-crypto -module-name CryptoKit -D DARLING_CRYPTOKIT_MODULE \
	-enable-experimental-feature Lifetimes -enable-library-evolution -parse-as-library -O \
	-I "$out/modules" -I "$out/modules-wrapper" -I "$OVERLAY_MODULES" \
	-Xcc -fmodule-map-file="$OVERLAY_SHIMS" \
	-Xcc -fmodule-map-file="$here/cryptokit-shims/module.modulemap" \
	-Xcc "-I$src/Sources/CCryptoBoringSSL/include" -Xcc -fmodule-map-file="$src/Sources/CCryptoBoringSSL/include/module.modulemap" \
	-Xcc "-I$src/Sources/CXKCP/include" -Xcc -fmodule-map-file="$src/Sources/CXKCP/include/module.modulemap" \
	-Xcc "-I$src/Sources/CXKCPShims/include" -Xcc -fmodule-map-file="$src/Sources/CXKCPShims/include/module.modulemap" \
	-emit-module-path "$out/modules/CryptoKit.swiftmodule" -o "$out/obj/CryptoKit.o"
echo "CryptoKit module built"
# link
mkdir -p "$work/framework/CryptoKit.framework/Versions/A"
"$DARLING_LD" -dylib -arch x86_64 -platform_version macos 26.0 26.0 -syslibroot "$DARLING_ROOT" \
	-install_name "/System/Library/Frameworks/CryptoKit.framework/Versions/A/CryptoKit" \
	-compatibility_version 1.0.0 -current_version 1.0.0 \
	-L "$SWIFT_RESOURCE_DIR/macosx" -L "$OVERLAY_LIBRARIES" \
	-dylib_file "/usr/lib/libc++abi.dylib:$DARLING_ROOT/usr/lib/libc++abi.dylib" \
	"$out"/obj/*.o \
	"$DARLING_LIBSYSTEM" "$DARLING_ROOT/usr/lib/libobjc.A.dylib" "$DARLING_ROOT/usr/lib/libc++.1.dylib" \
	"$DARLING_ROOT/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation" \
	"$DARLING_ROOT/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation" \
	"$DARLING_ROOT/System/Library/Frameworks/Security.framework/Versions/A/Security" \
	"$DARLING_ROOT/System/Library/Frameworks/LocalAuthentication.framework/Versions/A/LocalAuthentication" \
	-lswiftCore -lswiftFoundation -lswiftCoreFoundation -lswiftDarwin -lswiftObjectiveC \
	-o "$work/framework/CryptoKit.framework/Versions/A/CryptoKit"
echo "linked: $(stat -c%s "$work/framework/CryptoKit.framework/Versions/A/CryptoKit") bytes"
# Update only the source-owned generated payload, after the complete link
# succeeds. Normal Darling installation publishes it; never copy it into a prefix
# or an already published runtime image.
install -m 755 "$work/framework/CryptoKit.framework/Versions/A/CryptoKit" \
	"$here/CryptoKit.framework/Versions/A/CryptoKit"
