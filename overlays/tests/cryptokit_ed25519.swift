// Compile with the source-built CryptoKit module; run in the matching normal image.
// Independent known-answer vectors: RFC 8032 section 7.1, tests 1 and 3.
import Foundation
import CryptoKit
import Darwin

var failures = 0
func check(_ value: Bool, _ label: String) {
    print(value ? "ok:" : "FAIL:", label)
    if !value { failures += 1 }
}
func hex(_ string: String) -> Data {
    let bytes = Array(string.utf8)
    precondition(bytes.count % 2 == 0)
    func digit(_ byte: UInt8) -> UInt8 { byte <= 57 ? byte - 48 : byte - 87 }
    return Data(stride(from: 0, to: bytes.count, by: 2).map { digit(bytes[$0]) * 16 + digit(bytes[$0 + 1]) })
}

// Force the DataProtocol multi-region path, without relying on DispatchData's
// implementation-dependent coalescing. The collection and its regions agree.
struct SegmentedBytes: DataProtocol {
    let regions: [Data]
    private let bytes: [UInt8]
    init(_ regions: [Data]) {
        self.regions = regions
        self.bytes = regions.flatMap { Array($0) }
    }
    var startIndex: Int { bytes.startIndex }
    var endIndex: Int { bytes.endIndex }
    func index(after i: Int) -> Int { bytes.index(after: i) }
    func index(before i: Int) -> Int { bytes.index(before: i) }
    subscript(i: Int) -> UInt8 { bytes[i] }
}

do {
    let emptyKey = try Curve25519.Signing.PublicKey(rawRepresentation: hex("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"))
    let emptySignature = hex("e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b")
    check(emptyKey.isValidSignature(emptySignature, for: Data()), "RFC8032 empty message")
    check(emptyKey.isValidSignature(SegmentedBytes([Data(emptySignature.prefix(17)), Data(emptySignature.dropFirst(17))]), for: SegmentedBytes([])), "RFC8032 empty zero-region message")

    let keyBytes = hex("fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025")
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyBytes)
    let signature = hex("6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a")
    let message = hex("af82")
    let splitSignature = SegmentedBytes([Data(signature.prefix(31)), Data(signature.dropFirst(31))])
    let splitMessage = SegmentedBytes([hex("af"), hex("82")])
    check(key.rawRepresentation == keyBytes, "public key round trip")
    check(key.isValidSignature(signature, for: message), "RFC8032 two-byte message")
    check(key.isValidSignature(splitSignature, for: message), "segmented signature")
    check(key.isValidSignature(signature, for: splitMessage), "segmented message")
    check(key.isValidSignature(splitSignature, for: splitMessage), "both inputs segmented")
    check(!key.isValidSignature(signature, for: hex("af83")), "tampered message rejected")
    var badSignature = signature
    badSignature[0] ^= 1
    check(!key.isValidSignature(badSignature, for: message), "tampered signature rejected")
    var badKey = keyBytes
    badKey[0] ^= 1
    let changedKey = try Curve25519.Signing.PublicKey(rawRepresentation: badKey)
    check(!changedKey.isValidSignature(signature, for: message), "tampered public key rejected")
    for length in [0, 1, 63, 65] {
        check(!key.isValidSignature(Data(repeating: 0, count: length), for: message), "signature length \(length) rejected")
    }
    for length in [0, 31, 33, 64] {
        do {
            _ = try Curve25519.Signing.PublicKey(rawRepresentation: Data(repeating: 0, count: length))
            check(false, "key length \(length) accepted")
        } catch CryptoKitError.incorrectKeySize {
            check(true, "key length \(length) throws incorrectKeySize")
        } catch {
            check(false, "key length \(length) wrong error: \(error)")
        }
    }
} catch {
    check(false, "unexpected error: \(error)")
}
print(failures == 0 ? "CRYPTOKIT_ED25519_PASS" : "CRYPTOKIT_ED25519_FAIL=\(failures)")
exit(failures == 0 ? 0 : 1)
