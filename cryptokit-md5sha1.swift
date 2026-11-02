//===----------------------------------------------------------------------===//
//
// Darling addition to the CryptoKit framework this tree builds.  See README.md, "CryptoKit".
//
// WHY THIS FILE EXISTS.  Xcode 26.3's Contents/SharedFrameworks/Notarization.framework/Versions/A/
// Notarization binds, EAGERLY and STRONGLY (LC_DYLD_CHAINED_FIXUPS: every chained import is applied
// when the image loads, so there is no lazy form and a missing strong one stops the load), these
// four names against its CryptoKit ordinal:
//
//   _$s9CryptoKit8InsecureO3MD5VAEycfC                             == Insecure.MD5.init()
//   _$s9CryptoKit8InsecureO3MD5V6update13bufferPointerySW_tF       == Insecure.MD5.update(bufferPointer:)
//   _$s9CryptoKit8InsecureO3MD5V8finalizeAC0D6DigestVyF            == Insecure.MD5.finalize()
//   _$s9CryptoKit8InsecureO3MD5VMa                                 == type metadata accessor for Insecure.MD5
//
// (demangled with the toolchain's swift-demangle; the four are 4 of the 19 CryptoKit symbols that
// image demands, and the other 15 are already answered by the committed binary.)
//
// The committed binary does not answer them, and the reason is mechanical, not a bug in CryptoKit:
// Insecure.MD5 and Insecure.SHA1 are declared in swift-crypto's
// Sources/Crypto/Insecure/Insecure_HashFunctions.swift, which build-cryptokit.sh does not compile
// (it compiles Insecure/Insecure.swift, which declares only the `Insecure` namespace and the digest
// types).  Adding that file alone is not enough: its two hash functions store `DigestImpl<SHA1>` and
// `DigestImpl<MD5>`, and under -D DARLING_CRYPTOKIT_MODULE `DigestImpl` is `DarlingDigestImpl`
// (Sources/Crypto/Digests/HashFunctions.swift line 19), whose generic constraint is
// `DarlingBackedHashFunction` (Sources/Crypto/Digests/Darling/Digest_darling.swift).  The fork
// conforms only SHA256 to that protocol, because it supplies a pure-Swift SHA-256; the upstream
// conformances for MD5 and SHA1 live in Digests/BoringSSL/Digest_boring.swift, which this build does
// not compile either (its protocol is `BoringSSLBackedHashFunction`, a different shape).
//
// WHY BORINGSSL IS THE HONEST BACKING HERE (measured, not assumed).  The BoringSSL half of
// swift-crypto is compiled into this framework by build-cryptokit.sh, and its streaming MD5 and SHA-1
// entry points are DEFINED by the committed binary:
//
//   llvm-nm --defined-only CryptoKit.framework/Versions/A/CryptoKit
//     T _CCryptoBoringSSL_MD5_Init   _CCryptoBoringSSL_MD5_Update   _CCryptoBoringSSL_MD5_Final
//     T _CCryptoBoringSSL_SHA1_Init  _CCryptoBoringSSL_SHA1_Update  _CCryptoBoringSSL_SHA1_Final
//
// so no new algorithm is written here and no digest is invented: the conformances below are the
// upstream BoringSSL streaming idiom (Digests/BoringSSL/Digest_boring.swift), re-expressed against
// the Darling build's `DarlingBackedHashFunction` protocol, which returns Void instead of Bool.  The
// context types are plain C structs (MD5_CTX, SHA_CTX), copied by value, which is what
// DarlingDigestContext(copying:) needs -- the same value semantics the pure-Swift SHA-256 context has.
//
// SCOPE.  Insecure.MD5 and Insecure.SHA1 only; both are declared together in the one upstream file
// this build now compiles, and both are backed by the same already-linked BoringSSL objects.  The
// secure hashes are not touched here: SHA-256 stays pure Swift, and SHA-384/512 -- added later, for
// CoreDocumentation -- live in cryptokit-sha384sha512.swift beside this file.

#if DARLING_CRYPTOKIT_MODULE

import CCryptoBoringSSL

extension Insecure.MD5: DarlingBackedHashFunction {
    static var digestSize: Int { Int(MD5_DIGEST_LENGTH) }

    static func initialize() -> MD5_CTX {
        var context = MD5_CTX()
        _ = CCryptoBoringSSL_MD5_Init(&context)
        return context
    }

    static func update(_ context: inout MD5_CTX, data: UnsafeRawBufferPointer) {
        _ = CCryptoBoringSSL_MD5_Update(&context, data.baseAddress, data.count)
    }

    static func finalize(_ context: inout MD5_CTX, digest: UnsafeMutableRawBufferPointer) {
        precondition(digest.count == Self.digestSize)
        _ = CCryptoBoringSSL_MD5_Final(digest.baseAddress!.assumingMemoryBound(to: UInt8.self), &context)
    }
}

extension Insecure.SHA1: DarlingBackedHashFunction {
    static var digestSize: Int { Int(SHA_DIGEST_LENGTH) }

    static func initialize() -> SHA_CTX {
        var context = SHA_CTX()
        _ = CCryptoBoringSSL_SHA1_Init(&context)
        return context
    }

    static func update(_ context: inout SHA_CTX, data: UnsafeRawBufferPointer) {
        _ = CCryptoBoringSSL_SHA1_Update(&context, data.baseAddress, data.count)
    }

    static func finalize(_ context: inout SHA_CTX, digest: UnsafeMutableRawBufferPointer) {
        precondition(digest.count == Self.digestSize)
        _ = CCryptoBoringSSL_SHA1_Final(digest.baseAddress!.assumingMemoryBound(to: UInt8.self), &context)
    }
}

#endif  // DARLING_CRYPTOKIT_MODULE
