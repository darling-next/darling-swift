// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Darling's current Secure Enclave capability contract, not a software key backend.
//
// API declarations: Xcode 26.3 macOS SDK CryptoKit.swiftinterface and
// https://developer.apple.com/documentation/cryptokit/secureenclave
// No implementation exists in cristim/swift-crypto at
// c4105ade5fbe6866375ec65146cac733d53a1146 or the reviewed upstream/forks.
// The SDK ships declarations/link stubs, not a reusable system CryptoKit binary.
//
// Security's SecCTKKey implementation requires CryptoTokenKit token creation,
// public-key and signing operations. Darling's ctkclient.c implements none of
// them. Its absence is a capability failure, never permission to use BoringSSL
// keys as hardware keys. SecItem.c maps a token NotImplemented error to
// errSecUnimplemented; this file uses that OSStatus, without claiming Apple's
// undocumented exact CryptoKit unavailable-provider error identity.
//
// Every initializer throws before initializing storage: there are no valid
// values on this backend. The SDK's nonthrowing properties remain ordinary
// immutable stored properties, not trapping getters or fabricated key/data.
// Enabling a provider requires genuine token admission, opaque key restoration,
// authenticated public-key retrieval and signing before these types can become
// inhabited. See README.md, "Secure Enclave capability".

import Foundation
import Security
import LocalAuthentication

public enum SecureEnclave: Sendable {
    /// This backend has no Secure Enclave token provider.
    public static var isAvailable: Bool { false }

    private static func unavailableProvider() -> NSError {
        NSError(
            domain: NSOSStatusErrorDomain,
            code: Int(errSecUnimplemented),
            userInfo: [NSLocalizedDescriptionKey: "Secure Enclave token provider is unavailable"]
        )
    }

    public enum P256: Sendable {
        public enum Signing: Sendable {
            public struct PrivateKey: Sendable {
                public let publicKey: CryptoKit.P256.Signing.PublicKey
                public let dataRepresentation: Data

                public init(dataRepresentation: Data, authenticationContext: LAContext? = nil) throws {
                    throw SecureEnclave.unavailableProvider()
                }

                public init(
                    compactRepresentable: Bool = true,
                    accessControl: SecAccessControl = SecAccessControlCreateWithFlags(
                        nil, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly, [], nil
                    )!,
                    authenticationContext: LAContext? = nil
                ) throws {
                    throw SecureEnclave.unavailableProvider()
                }

                public func signature<D: Digest>(for digest: D) throws -> CryptoKit.P256.Signing.ECDSASignature {
                    throw SecureEnclave.unavailableProvider()
                }

                public func signature<D: DataProtocol>(for data: D) throws -> CryptoKit.P256.Signing.ECDSASignature {
                    throw SecureEnclave.unavailableProvider()
                }
            }
        }

        public enum KeyAgreement: Sendable {
            public struct PrivateKey: Sendable, DiffieHellmanKeyAgreement {
                public let publicKey: CryptoKit.P256.KeyAgreement.PublicKey
                public let dataRepresentation: Data

                public init(dataRepresentation: Data, authenticationContext: LAContext? = nil) throws {
                    throw SecureEnclave.unavailableProvider()
                }

                public init(
                    compactRepresentable: Bool = true,
                    accessControl: SecAccessControl = SecAccessControlCreateWithFlags(
                        nil, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly, [], nil
                    )!,
                    authenticationContext: LAContext? = nil
                ) throws {
                    throw SecureEnclave.unavailableProvider()
                }

                public func sharedSecretFromKeyAgreement(
                    with publicKeyShare: CryptoKit.P256.KeyAgreement.PublicKey
                ) throws -> SharedSecret {
                    throw SecureEnclave.unavailableProvider()
                }
            }
        }
    }
}
