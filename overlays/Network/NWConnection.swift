//===----------------------------------------------------------------------===//
//
// Darling's Swift `Network` overlay -- NWConnection and NWListener.
//
// See Network.swift for why this module exists; declarations from the guest SDK's
// Network.swiftinterface (NWListener at line 678, NWConnection at line 2198).
//
// THE TRANSPORT IS WHAT CANNOT BE SERVED, AND IT IS REFUSED BY NAME. This guest has no network stack:
// the tree's own C API for it, libnetwork (re-exported by Network.framework), is stubs that print
// "libnetwork stub called: <name>" and return NULL -- nw_connection_create returns NULL and
// nw_connection_start is a print (src/external/libnetwork/src/nw/connection.m) -- and there is no
// Network.framework implementation behind it. So:
//
//   * constructing a connection is real: `init(to:using:)` keeps the endpoint and parameters, and
//     `endpoint`, `parameters`, `state` (.setup, truthfully: it was never started), `currentPath`
//     (nil, truthfully: there is no path), `metadata(definition:)` (nil, truthfully: nothing was
//     negotiated), `batch(_:)` (it is a scoping helper and only runs the block) and `cancel()` (a
//     no-op: there is no transport to cancel) answer honestly;
//   * every operation that would need the transport -- `start(queue:)`, `send(...)`, `receive(...)`,
//     `startDataTransferReport()`, `requestEstablishmentReport(queue:completion:)` -- calls
//     darlingNetworkUnserved, i.e. stops with the reason. Returning instead would tell the caller
//     that a connection started, or hand it a report of a transfer that never happened;
//   * `NWListener` cannot be constructed at all: `init(using:on:)` is `throws`, so it throws a real
//     Swift error (the same NSFeatureUnsupportedError the Foundation overlay's URLSession uses for
//     its unserved async API) rather than refusing later. `start(queue:)`/`cancel()` are present for
//     the loader and refuse/no-op as above.

import Darwin
import Dispatch
import Foundation

public final class NWConnection: CustomDebugStringConvertible {
    public enum State: Equatable, Sendable {
        case setup
        case waiting(NWError)
        case preparing
        case ready
        case failed(NWError)
        case cancelled

        public static func == (a: NWConnection.State, b: NWConnection.State) -> Bool {
            switch (a, b) {
            case (.setup, .setup), (.preparing, .preparing), (.ready, .ready), (.cancelled, .cancelled):
                return true
            case (.waiting(let x), .waiting(let y)), (.failed(let x), .failed(let y)):
                return x == y
            default:
                return false
            }
        }
    }

    /// A message boundary / metadata bundle. Apple's carries protocol metadata; nothing is ever
    /// negotiated here, so this keeps the identity fields a caller sets and reports no metadata.
    public class ContentContext: @unchecked Sendable {
        public let identifier: String
        public let expirationMilliseconds: UInt64
        public let relativePriority: Double
        public let isFinal: Bool
        public let antecedent: ContentContext?

        public init(identifier: String, expiration: UInt64 = 0, priority: Double = 0.5,
                    isFinal: Bool = false, antecedent: ContentContext? = nil,
                    metadata: [NWProtocolMetadata]? = []) {
            self.identifier = identifier
            self.expirationMilliseconds = expiration
            self.relativePriority = priority
            self.isFinal = isFinal
            self.antecedent = antecedent
        }

        public var protocolMetadata: [NWProtocolMetadata] { [] }

        public func protocolMetadata(definition: NWProtocolDefinition) -> NWProtocolMetadata? { nil }

        public static let defaultMessage = ContentContext(identifier: "defaultMessage")
        public static let finalMessage = ContentContext(identifier: "finalMessage", isFinal: true)
        public static let defaultStream = ContentContext(identifier: "defaultStream")
    }

    public enum SendCompletion {
        case contentProcessed((NWError?) -> Void)
        case idempotent
    }

    /// Apple's carries the timings of a real connection attempt. No attempt can be made here, so
    /// there is nothing in it and nothing creates one -- see requestEstablishmentReport below.
    public struct EstablishmentReport: CustomDebugStringConvertible, Sendable {
        public var debugDescription: String { "NWConnection.EstablishmentReport(unavailable)" }
    }

    /// Apple's is a handle to a transfer that is running, and it is a CLASS (interface line 2411,
    /// `public class PendingDataTransferReport : @unchecked Sendable`) -- which the demand's own
    /// mangling says too (`...25PendingDataTransferReportCMa`, `C` and not `V`). No transfer can run
    /// here; see startDataTransferReport below.
    public class PendingDataTransferReport: @unchecked Sendable {
        public init() {}
    }

    public let endpoint: NWEndpoint
    public let parameters: NWParameters

    public var stateUpdateHandler: ((State) -> Void)?
    public var pathUpdateHandler: ((NWPath) -> Void)?
    public var betterPathUpdateHandler: ((Bool) -> Void)?

    public init(to endpoint: NWEndpoint, using parameters: NWParameters) {
        self.endpoint = endpoint
        self.parameters = parameters
    }

    /// Truthful: the connection was never started, so it is in .setup.
    public var state: State { .setup }

    /// Truthful: there is no path.
    public var currentPath: NWPath? { nil }

    public func start(queue: DispatchQueue) {
        darlingNetworkUnserved("NWConnection.start(queue:)")
    }

    /// A no-op, and honestly so: nothing was started, so there is nothing to cancel. The state stays
    /// .setup rather than being moved to .cancelled, because no cancellation event happened.
    public func cancel() {}

    public func send(content: Data?, contentContext: ContentContext = .defaultMessage,
                     isComplete: Bool = true, completion: SendCompletion) {
        darlingNetworkUnserved("NWConnection.send(content:contentContext:isComplete:completion:)")
    }

    public func receive(minimumIncompleteLength: Int, maximumLength: Int,
                        completion: @escaping (Data?, ContentContext?, Bool, NWError?) -> Void) {
        darlingNetworkUnserved("NWConnection.receive(minimumIncompleteLength:maximumLength:completion:)")
    }

    /// Runs the block. Apple's guarantees that the block runs with the connection's internal state
    /// quiesced; with no transport there is no state to quiesce, so this is just the block.
    public func batch(_ block: () -> Void) {
        block()
    }

    /// Truthful: nothing was negotiated, so no protocol metadata exists.
    public func metadata(definition: NWProtocolDefinition) -> NWProtocolMetadata? { nil }

    public func startDataTransferReport() -> PendingDataTransferReport {
        darlingNetworkUnserved("NWConnection.startDataTransferReport()")
    }

    public func requestEstablishmentReport(queue: DispatchQueue,
                                           completion: @escaping (EstablishmentReport?) -> Void) {
        darlingNetworkUnserved("NWConnection.requestEstablishmentReport(queue:completion:)")
    }

    public var debugDescription: String {
        "NWConnection(to: \(endpoint), state: \(state))"
    }
}

public final class NWListener: CustomDebugStringConvertible {
    /// A Bonjour service description. Real: it is the caller's own text.
    public struct Service: Equatable, CustomDebugStringConvertible, Sendable {
        public let name: String?
        public let type: String
        public let domain: String?
        public let txtRecord: Data?

        public init(name: String? = nil, type: String, domain: String? = nil, txtRecord: Data? = nil) {
            self.name = name
            self.type = type
            self.domain = domain
            self.txtRecord = txtRecord
        }

        public static func == (lhs: Service, rhs: Service) -> Bool {
            lhs.name == rhs.name && lhs.type == rhs.type && lhs.domain == rhs.domain
                && lhs.txtRecord == rhs.txtRecord
        }

        public var debugDescription: String {
            "\(name ?? "_").\(type)\(domain.map { "." + $0 } ?? "")"
        }
    }

    public enum State: Equatable, Sendable {
        case setup
        case waiting(NWError)
        case ready
        case failed(NWError)
        case cancelled

        public static func == (a: NWListener.State, b: NWListener.State) -> Bool {
            switch (a, b) {
            case (.setup, .setup), (.ready, .ready), (.cancelled, .cancelled):
                return true
            case (.waiting(let x), .waiting(let y)), (.failed(let x), .failed(let y)):
                return x == y
            default:
                return false
            }
        }
    }

    public let parameters: NWParameters
    public var stateUpdateHandler: ((State) -> Void)?
    public var newConnectionHandler: ((NWConnection) -> Void)?
    public var service: Service?

    /// Refused at construction, not later: a listener exists to accept connections and this guest
    /// cannot accept any, so the caller gets an error it can handle instead of a listener that never
    /// becomes ready. NSFeatureUnsupportedError (3328), the same error the Foundation overlay's
    /// URLSession returns for its unserved async API.
    public init(using parameters: NWParameters, on port: NWEndpoint.Port = .any) throws {
        self.parameters = parameters
        throw NSError(
            domain: NSCocoaErrorDomain,
            code: 3328, // NSFeatureUnsupportedError
            userInfo: [
                NSLocalizedDescriptionKey: "NWListener is not implemented on Darling: this guest has no "
                    + "network stack, so nothing can listen on \(port).",
            ]
        )
    }

    /// Truthful: the listener was never started.
    public var state: State { .setup }

    /// Truthful: no port was ever bound.
    public var port: NWEndpoint.Port? { nil }

    public func start(queue: DispatchQueue) {
        darlingNetworkUnserved("NWListener.start(queue:)")
    }

    /// A no-op, for the same reason as NWConnection.cancel(): there is nothing to cancel.
    public func cancel() {}

    public var debugDescription: String {
        "NWListener(parameters: \(parameters), state: \(state))"
    }
}
