//===----------------------------------------------------------------------===//
//
// Darling addition to the CryptoKit framework this tree builds.  See README.md, "CryptoKit".
//
// WHY THIS FILE EXISTS.  Xcode 26.3's Contents/SharedFrameworks/CoreDocumentation.framework/
// Versions/A/CoreDocumentation binds, EAGERLY and STRONGLY (LC_DYLD_CHAINED_FIXUPS: every chained
// import is applied when the image loads, so there is no lazy form and a missing strong one stops
// the load), these two names against its CryptoKit ordinal:
//
//   _$s9CryptoKit6SHA512VAA12HashFunctionAAMc   == SHA512 : HashFunction conformance descriptor
//   _$s9CryptoKit6SHA512VMa                     == type metadata accessor for SHA512
//
// (demangled with the toolchain's swift-demangle; they are 2 of the 11 CryptoKit symbols that image
// demands, the other 9 are already answered by the committed binary, and the loader's live stop line
// is the conformance descriptor.)
//
// WHAT THE CLIENT DOES WITH THEM (measured, not assumed; CoreDocumentation's own bind table, decoded
// from LC_DYLD_CHAINED_FIXUPS, plus llvm-objdump on the x86_64 slice).  The image also binds the
// HashFunction protocol requirement thunks (`init()`, `update(bufferPointer:)`, `finalize()`), the
// `SHA512Digest` metadata accessor and the `SHA512Digest : Sequence` conformance descriptor.  Its
// `SwiftDocC.Checksum.sha512(of: Foundation.Data) -> String` (0x6c5140) loads the SHA512 metadata and
// the SHA512 : HashFunction conformance, allocates a SHA512 value on the stack, calls the protocol's
// init, updates it with the data, finalizes to a SHA512Digest, and walks the digest's BYTES through
// the Sequence conformance to build the string it returns.  So the digest is read and used: a wrong
// digest is a wrong checksum in every doc archive this writes, never a crash -- which is why the
// route below is BoringSSL's own SHA-512 rather than anything of our own.
//
// WHY BORINGSSL IS THE HONEST BACKING HERE (measured, not assumed).  The BoringSSL half of
// swift-crypto is compiled into this framework by build-cryptokit.sh, and its streaming SHA-384 and
// SHA-512 entry points are DEFINED by the committed binary:
//
//   llvm-nm --defined-only CryptoKit.framework/Versions/A/CryptoKit
//     T _CCryptoBoringSSL_SHA384_Init  _CCryptoBoringSSL_SHA384_Update  _CCryptoBoringSSL_SHA384_Final
//     T _CCryptoBoringSSL_SHA512_Init  _CCryptoBoringSSL_SHA512_Update  _CCryptoBoringSSL_SHA512_Final
//
// so no new algorithm is written here and no digest is invented: the conformances below are the
// upstream BoringSSL streaming idiom (Digests/BoringSSL/Digest_boring.swift), re-expressed against
// the Darling build's `DarlingBackedHashFunction` protocol, which returns Void instead of Bool.  The
// context type is the plain C struct `SHA512_CTX` -- BoringSSL's SHA384_* take it too, which is what
// the header (CCryptoBoringSSL_sha2.h) and upstream both do -- copied by value, which is what
// DarlingDigestContext(copying:) needs.
//
// WHY THE DECLARATIONS ARE HERE AND NOT IN THE FORK.  swift-crypto declares both hashers in
// Sources/Crypto/Digests/HashFunctions_SHA2.swift, but inside `#if !DARLING_CRYPTOKIT_MODULE` (the
// fork's SHA-256-only policy for this build), so the compiled file carries no SHA384/SHA512 at all.
// The digest types (SHA384Digest/SHA512Digest) are declared ungated in Digests/Digests.swift and ARE
// in the committed binary; only the hashers were missing.  The declarations below are that upstream
// text with the gate removed, kept next to this script rather than in the fork's tree so the
// payload's own diff carries them (the same choice cryptokit-md5sha1.swift records).
//
// SCOPE.  SHA-384 and SHA-512 only.  SHA-256 stays pure Swift (Digest_darling.swift) and
// Insecure.MD5/SHA1 stay as cryptokit-md5sha1.swift left them.  P-384/P-521 signing is NOT turned on
// by this: Signatures/ECDSA.swift has its own `#if !DARLING_CRYPTOKIT_MODULE` gate around the two
// sections that hash with these types, and that gate is untouched.

#if DARLING_CRYPTOKIT_MODULE

import CCryptoBoringSSL

// MARK: - SHA384 and SHA512 (declarations: upstream's text, un-gated)

/// An implementation of Secure Hashing Algorithm 2 (SHA-2) hashing with a 384-bit digest.
public typealias SHA2_384 = SHA384

/// An implementation of Secure Hashing Algorithm 2 (SHA-2) hashing with a 384-bit digest.
///
/// The ``SHA384`` hash implements the ``HashFunction`` protocol for the specific case of SHA-2
/// hashing with a 384-bit digest (``SHA384Digest``).
public struct SHA384: HashFunctionImplementationDetails, Sendable {
    /// The number of bytes that represents the hash function's internal state.
    public static let blockByteCount: Int = 128
    /// The number of bytes in a SHA384 digest.
    public static let byteCount: Int = 48
    /// The digest type for a SHA384 hash function.
    public typealias Digest = SHA384Digest
    var impl: DigestImpl<SHA384>

    /// Creates a SHA384 hash function.
    public init() {
        impl = DigestImpl()
    }

    /// Incrementally updates the hash function with the contents of the buffer.
    public mutating func update(bufferPointer: UnsafeRawBufferPointer) {
        impl.update(data: bufferPointer)
    }

    /// Finalizes the hash function and returns the computed digest.
    public func finalize() -> Self.Digest {
        return impl.finalize()
    }
}

/// An implementation of Secure Hashing Algorithm 2 (SHA-2) hashing with a 512-bit digest.
public typealias SHA2_512 = SHA512

/// An implementation of Secure Hashing Algorithm 2 (SHA-2) hashing with a 512-bit digest.
///
/// The ``SHA512`` hash implements the ``HashFunction`` protocol for the specific case of SHA-2
/// hashing with a 512-bit digest (``SHA512Digest``).
public struct SHA512: HashFunctionImplementationDetails, Sendable {
    /// The number of bytes that represents the hash function's internal state.
    public static let blockByteCount: Int = 128
    /// The number of bytes in a SHA512 digest.
    public static let byteCount: Int = 64
    /// The digest type for a SHA512 hash function.
    public typealias Digest = SHA512Digest
    var impl: DigestImpl<SHA512>

    /// Creates a SHA512 hash function.
    public init() {
        impl = DigestImpl()
    }

    /// Incrementally updates the hash function with the contents of the buffer.
    public mutating func update(bufferPointer: UnsafeRawBufferPointer) {
        impl.update(data: bufferPointer)
    }

    /// Finalizes the hash function and returns the computed digest.
    public func finalize() -> Self.Digest {
        return impl.finalize()
    }
}

// MARK: - SHA-384 and SHA-512 (FIPS 180-4), backed by the linked BoringSSL

extension SHA384: DarlingBackedHashFunction {
    static var digestSize: Int { Int(SHA384_DIGEST_LENGTH) }

    static func initialize() -> SHA512_CTX {
        var context = SHA512_CTX()
        _ = CCryptoBoringSSL_SHA384_Init(&context)
        return context
    }

    static func update(_ context: inout SHA512_CTX, data: UnsafeRawBufferPointer) {
        _ = CCryptoBoringSSL_SHA384_Update(&context, data.baseAddress, data.count)
    }

    static func finalize(_ context: inout SHA512_CTX, digest: UnsafeMutableRawBufferPointer) {
        precondition(digest.count == Self.digestSize)
        _ = CCryptoBoringSSL_SHA384_Final(digest.baseAddress!.assumingMemoryBound(to: UInt8.self), &context)
    }
}

extension SHA512: DarlingBackedHashFunction {
    static var digestSize: Int { Int(SHA512_DIGEST_LENGTH) }

    static func initialize() -> SHA512_CTX {
        var context = SHA512_CTX()
        _ = CCryptoBoringSSL_SHA512_Init(&context)
        return context
    }

    static func update(_ context: inout SHA512_CTX, data: UnsafeRawBufferPointer) {
        _ = CCryptoBoringSSL_SHA512_Update(&context, data.baseAddress, data.count)
    }

    static func finalize(_ context: inout SHA512_CTX, digest: UnsafeMutableRawBufferPointer) {
        precondition(digest.count == Self.digestSize)
        _ = CCryptoBoringSSL_SHA512_Final(digest.baseAddress!.assumingMemoryBound(to: UInt8.self), &context)
    }
}

#endif  // DARLING_CRYPTOKIT_MODULE
