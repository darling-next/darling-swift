//===----------------------------------------------------------------------===//
//
// Darling's Swift `Network` overlay -- the protocol-stack half.
//
// See Network.swift for why this module exists. Declarations come from the guest SDK's
// Network.swiftinterface (line numbers cited per type). The classes here are the containers that
// describe a protocol stack; their TCP option storage is real, and the two members that would need a
// live Security protocol object refuse explicitly instead of inventing one -- Darling's
// Security.framework does not export sec_protocol_options_create (measured: llvm-nm of the deployed
// Security has _sec_protocol_options_create_config and no _sec_protocol_options_create), so no
// sec_protocol_options_t can be produced honestly.

import Darwin
import Foundation
// Security.framework in Darling's SDK has no Modules/module.modulemap, so the two protocol-object
// types the TLS members name come in through this overlay's own shim (see shims/module.modulemap).
// The C type is the same one Apple's interface names -- the probe below mangles to
// So23OS_sec_protocol_options_p / So24OS_sec_protocol_metadata_p, which is exactly what the demand
// carries.
import _DarlingNetworkSecurityShims

// MARK: - NWProtocol  (interface line 1279)

public class NWProtocol: @unchecked Sendable {
    internal init() {}
}

// MARK: - NWProtocolOptions  (interface line 1271)

public class NWProtocolOptions: @unchecked Sendable {
    internal init() {}

    public var debugDescription: String {
        "\(type(of: self))"
    }
}

// MARK: - NWProtocolMetadata  (interface line 1275)

public class NWProtocolMetadata: @unchecked Sendable {
    internal init() {}

    public var debugDescription: String {
        "\(type(of: self))"
    }
}

// MARK: - NWProtocolDefinition  (interface line 1262)

/// The identity of a protocol: what `NWConnection.metadata(definition:)` and the `definition`
/// statics are keyed by.
public class NWProtocolDefinition: Equatable, CustomDebugStringConvertible, @unchecked Sendable {
    public let identifier: String

    public init(identifier: String) {
        self.identifier = identifier
    }

    public static func == (lhs: NWProtocolDefinition, rhs: NWProtocolDefinition) -> Bool {
        lhs.identifier == rhs.identifier
    }

    public var debugDescription: String {
        identifier
    }
}

// MARK: - NWProtocolTCP  (interface line 2120)

public class NWProtocolTCP: NWProtocol, @unchecked Sendable {
    /// TCP options. Every member here is real storage: Apple's are the knobs that would be handed to
    /// the transport, and storing them is exactly what can be done without a transport.
    public class Options: NWProtocolOptions, @unchecked Sendable {
        public var noDelay: Bool = false
        public var noPush: Bool = false
        public var noOptions: Bool = false
        public var enableKeepalive: Bool = false
        public var keepaliveCount: Int = 0
        public var keepaliveIdle: Int = 0
        public var keepaliveInterval: Int = 0
        public var maximumSegmentSize: Int = 0
        public var connectionTimeout: Int = 0
        public var connectionDropTime: Int = 0
        public var retransmitFinDrop: Bool = false
        public var disableAckStretching: Bool = false

        public override init() {
            super.init()
        }
    }
}

// MARK: - NWProtocolTLS  (interface line 189)

public class NWProtocolTLS: NWProtocol, @unchecked Sendable {
    public static let definition = NWProtocolDefinition(identifier: "com.apple.network.tls")

    public class Options: NWProtocolOptions, @unchecked Sendable {
        /// Apple's hands back the `sec_protocol_options_t` the stack is configured with. This guest
        /// cannot produce one -- Security.framework exports no `sec_protocol_options_create`, and a
        /// made-up opaque handle would crash the caller later instead of telling it the truth now --
        /// so this refuses, by name.
        public var securityProtocolOptions: sec_protocol_options_t {
            darlingNetworkUnserved("NWProtocolTLS.Options.securityProtocolOptions")
        }

        public override init() {
            super.init()
        }
    }

    public class Metadata: NWProtocolMetadata, @unchecked Sendable {
        /// Same reason as `Options.securityProtocolOptions`: there is no protocol instance to report
        /// metadata for.
        public var securityProtocolMetadata: sec_protocol_metadata_t {
            darlingNetworkUnserved("NWProtocolTLS.Metadata.securityProtocolMetadata")
        }
    }
}
