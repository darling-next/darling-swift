// Run against the source-built CryptoKit framework in a normal Darling image.
// Never create an unsafe/fake SecureEnclave receiver to test unreachable methods.
import Foundation
import Security
import CryptoKit
import Darwin

var failures = 0
func check(_ condition: Bool, _ label: String) {
    print(condition ? "ok:" : "FAIL:", label)
    if !condition { failures += 1 }
}
func unavailable(_ label: String, _ operation: () throws -> Void) {
    do {
        try operation()
        check(false, "\(label) unexpectedly succeeded")
    } catch {
        let error = error as NSError
        check(error.domain == NSOSStatusErrorDomain && error.code == Int(errSecUnimplemented), label)
    }
}

check(!SecureEnclave.isAvailable, "missing Secure Enclave provider is unavailable")
unavailable("signing generation with defaults") { _ = try SecureEnclave.P256.Signing.PrivateKey() }
unavailable("signing restore empty data") { _ = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: Data()) }
unavailable("signing restore nonempty data") { _ = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: Data([1, 2, 3])) }
unavailable("key agreement generation with defaults") { _ = try SecureEnclave.P256.KeyAgreement.PrivateKey() }
unavailable("key agreement restore empty data") { _ = try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: Data()) }
unavailable("key agreement restore nonempty data") { _ = try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: Data([1, 2, 3])) }

if let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly, [], nil) {
    for compact in [false, true] {
        unavailable("signing explicit access control compact=\(compact)") {
            _ = try SecureEnclave.P256.Signing.PrivateKey(compactRepresentable: compact, accessControl: access, authenticationContext: nil)
        }
        unavailable("key agreement explicit access control compact=\(compact)") {
            _ = try SecureEnclave.P256.KeyAgreement.PrivateKey(compactRepresentable: compact, accessControl: access, authenticationContext: nil)
        }
    }
} else {
    check(false, "construct independent access control for explicit-argument initializers")
}

let message = Data("CryptoKit software signature smoke".utf8)
let changed = Data("CryptoKit software signature smokf".utf8)
do {
    // NIST SP 800-38D, all-zero 128-bit key/96-bit IV/128-bit plaintext.
    let key = SymmetricKey(data: Data(repeating: 0, count: 16))
    let nonce = try AES.GCM.Nonce(data: Data(repeating: 0, count: 12))
    let plaintext = Data(repeating: 0, count: 16)
    let sealed = try AES.GCM.seal(plaintext, using: key, nonce: nonce)
    check(Array(sealed.ciphertext) == [0x03,0x88,0xda,0xce,0x60,0xb6,0xa3,0x92,0xf3,0x28,0xc2,0xb9,0x71,0xb2,0xfe,0x78], "AES-GCM known ciphertext")
    check(Array(sealed.tag) == [0xab,0x6e,0x47,0xd4,0x2c,0xec,0x13,0xbd,0xf5,0x3a,0x67,0xb2,0x12,0x57,0xbd,0xdf], "AES-GCM known authentication tag")
    let opened = try AES.GCM.open(sealed, using: key)
    check(opened == plaintext, "AES-GCM decrypts authentic ciphertext")
    var badTag = sealed.tag
    badTag[badTag.startIndex] ^= 1
    let corrupted = try AES.GCM.SealedBox(nonce: nonce, ciphertext: sealed.ciphertext, tag: badTag)
    do {
        _ = try AES.GCM.open(corrupted, using: key)
        check(false, "AES-GCM accepted corrupted authentication tag")
    } catch {
        check(true, "AES-GCM rejects corrupted authentication tag")
    }

    let p384 = P384.Signing.PrivateKey()
    let signature384 = try p384.signature(for: SHA384.hash(data: message))
    let restored384 = try P384.Signing.ECDSASignature(rawRepresentation: signature384.rawRepresentation)
    check(p384.publicKey.isValidSignature(restored384, for: SHA384.hash(data: message)), "P384 signs and verifies real digest")
    check(!p384.publicKey.isValidSignature(restored384, for: SHA384.hash(data: changed)), "P384 rejects changed digest")

    let p521 = P521.Signing.PrivateKey()
    let signature521 = try p521.signature(for: SHA512.hash(data: message))
    let restored521 = try P521.Signing.ECDSASignature(rawRepresentation: signature521.rawRepresentation)
    check(p521.publicKey.isValidSignature(restored521, for: SHA512.hash(data: message)), "P521 signs and verifies real digest")
    check(!p521.publicKey.isValidSignature(restored521, for: SHA512.hash(data: changed)), "P521 rejects changed digest")
} catch {
    check(false, "software cryptography unexpectedly threw \(error)")
}

print(failures == 0 ? "CRYPTOKIT_PROVIDER_PASS" : "CRYPTOKIT_PROVIDER_FAIL=\(failures)")
exit(failures == 0 ? 0 : 1)
