//===----------------------------------------------------------------------===//
//
// Darling's Swift `Network` overlay -- NWParameters.
//
// See Network.swift for why this module exists; declarations from the guest SDK's
// Network.swiftinterface, NWParameters at line 2666. Everything here is real storage: the parameters
// object is the container of knobs a connection would be built from, and holding them is exactly
// what can be done without a transport.

import Darwin
import Foundation

public final class NWParameters: CustomDebugStringConvertible {
    /// The protocol stack. There is no stack object to hand out (see NWConnection.swift), so this is
    /// the caller's own options, kept where a caller can read them back.
    public var includePeerToPeer: Bool = false
    public var requiredInterface: NWInterface?
    public var requiredLocalEndpoint: NWEndpoint?
    public var allowLocalEndpointReuse: Bool = false

    public init() {}

    /// The secure-TCP / TCP convenience Apple declares (its `__allocating_init(tls:tcp:)`, which is
    /// the name Notarization binds). The options are retained so a caller can inspect what it asked
    /// for; nothing else is possible without a transport.
    public convenience init(tls: NWProtocolTLS.Options?, tcp: NWProtocolTCP.Options = NWProtocolTCP.Options()) {
        self.init()
        self.tlsOptions = tls
        self.tcpOptions = tcp
    }

    internal var tlsOptions: NWProtocolTLS.Options?
    internal var tcpOptions: NWProtocolTCP.Options?

    public var debugDescription: String {
        "NWParameters(includePeerToPeer: \(includePeerToPeer), requiredInterface: "
            + "\(requiredInterface.map { "\($0)" } ?? "nil"), requiredLocalEndpoint: "
            + "\(requiredLocalEndpoint.map { "\($0)" } ?? "nil"), allowLocalEndpointReuse: \(allowLocalEndpointReuse))"
    }
}
