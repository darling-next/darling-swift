//===----------------------------------------------------------------------===//
//
// Darling's Swift `Network` overlay -- the value half.
//
// WHY THIS MODULE EXISTS.  Xcode 26.3's Contents/SharedFrameworks/Notarization.framework/Versions/A/
// Notarization binds 138 names against its Network ordinal
// (/System/Library/Frameworks/Network.framework/Versions/A/Network, ordinal 12 of its 24 dylibs),
// ALL of them eager and strong: the image is LC_DYLD_CHAINED_FIXUPS, so every import is applied when
// it loads and there is no lazy form to defer (measured 2026-10-13 by decoding
// LC_DYLD_CHAINED_FIXUPS: 4084 bind fixups, 138 in the Network field, 0 of them weak, all in
// __DATA_CONST,__got).  Apple's own framework exports them (they are in the SDK's Network.tbd, as
// $ld$previous$/usr/lib/swift/libswiftNetwork.dylib$$1$10.15$14.0$_$s7Network... entries, i.e. Apple
// moved them out of libswiftNetwork.dylib into the framework); this tree's Network.framework is
// Objective-C only, so the framework re-exports this overlay as an ordinal, exactly the way
// Foundation.framework re-exports libswiftFoundation.dylib (see src/frameworks/Network/CMakeLists.txt
// and src/external/foundation/CMakeLists.txt).
//
// DECLARATIONS come from the guest SDK's own interface:
//   <Xcode 26.3>/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/
//     Network.framework/Modules/Network.swiftmodule/x86_64-apple-macos.swiftinterface
// (line numbers cited per type below).  Nothing about a signature is invented; a member the demand
// does not name and this file does not implement is simply absent, and is called out where it would
// otherwise look accidental (see NWError.dns).
//
// WHAT IS REAL AND WHAT IS NOT.  The value types here (endpoints, hosts, ports, addresses, the
// interface descriptor, paths, errors) are real: they are pure data with no dependency on a network
// stack, and every demanded member of them is implemented for real.  What CANNOT be served is the
// transport: this guest has no network stack at all -- the tree's own C API for it, libnetwork
// (/usr/lib/libnetwork.dylib, re-exported by Network.framework) is stubs that print "libnetwork stub
// called: <name>" and return NULL (src/external/libnetwork/src/nw/connection.m: nw_connection_create
// returns NULL, nw_connection_start is a print), and Darling's Security.framework does not export
// sec_protocol_options_create (measured: llvm-nm of the deployed Security has
// _sec_protocol_options_create_config and no _sec_protocol_options_create).  Those operations fail
// explicitly -- fatalError with the reason, or, where the declaration can throw, a real Swift error
// -- and never return a plausible wrong value or a fabricated success.  See NWConnection.swift.

import Darwin
import Dispatch
import Foundation

/// The explicit observable failure every transport operation in this overlay uses.
///
/// The declaration cannot throw (`start(queue:)` returns Void), so the honest answer is to stop with
/// the reason rather than return a value that looks like success: a caller that cannot be served
/// must not be told that it was.  Kept in one place so the message is uniform and greppable.
@inline(never)
internal func darlingNetworkUnserved(_ what: String, file: StaticString = #fileID, line: UInt = #line) -> Never {
    fatalError("Darling: \(what) cannot be served: this guest has no network stack "
        + "(libnetwork's nw_* entry points are stubs and there is no Network.framework implementation "
        + "to drive them). The symbol resolves so the loader can start the process; the operation is "
        + "refused rather than faked.", file: file, line: line)
}

// MARK: - NWError  (interface line 654)

/// Errors the Network API reports.
///
/// Apple's declaration also has `case dns(dnssd.DNSServiceErrorType)`. It is NOT declared here: the
/// Darling SDK carries no `dnssd` module to name the type from, and no client in this load closure
/// binds it (the 138 demanded names include only `posix` and `tls`). A client that binds `dns` would
/// find it missing; that is stated rather than papered over with a differently-mangled case.
public enum NWError : Error, CustomDebugStringConvertible, Equatable {
    case posix(POSIXErrorCode)
    case tls(OSStatus)
    case wifiAware(Int32)

    public var debugDescription: String {
        switch self {
        case .posix(let code):
            return "POSIXErrorCode(rawValue: \(code.rawValue)): \(String(cString: strerror(code.rawValue)))"
        case .tls(let status):
            return "TLS error: \(status)"
        case .wifiAware(let status):
            return "Wi-Fi Aware error: \(status)"
        }
    }

    public static func == (a: NWError, b: NWError) -> Bool {
        switch (a, b) {
        case (.posix(let x), .posix(let y)):
            return x == y
        case (.tls(let x), .tls(let y)):
            return x == y
        case (.wifiAware(let x), .wifiAware(let y)):
            return x == y
        default:
            return false
        }
    }
}

// MARK: - NWInterface  (interface line 805)

/// A network interface, as much of it as this overlay's clients name.
public struct NWInterface: Hashable, CustomDebugStringConvertible, Sendable {
    public enum InterfaceType: Sendable {
        case other
        case wifi
        case cellular
        case wiredEthernet
        case loopback
    }

    /// The interface's BSD name, e.g. "en0".
    public let name: String
    /// The interface's index, i.e. `if_nametoindex`.
    public let index: Int
    public let type: InterfaceType

    public init(name: String, index: Int, type: InterfaceType = .other) {
        self.name = name
        self.index = index
        self.type = type
    }

    public var debugDescription: String {
        "NWInterface \(name)(\(index)) \(type)"
    }

    public static func == (lhs: NWInterface, rhs: NWInterface) -> Bool {
        lhs.name == rhs.name && lhs.index == rhs.index && lhs.type == rhs.type
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(index)
    }
}

// MARK: - IPAddress, IPv4Address, IPv6Address  (interface lines 305, 322, 359)

public protocol IPAddress: Sendable {
    var rawValue: Data { get }
    init?(_ rawValue: Data, _ interface: NWInterface?)
    init?(_ string: String)
    var interface: NWInterface? { get }
    var isLoopback: Bool { get }
    var isLinkLocal: Bool { get }
    var isMulticast: Bool { get }
}

/// An IPv4 address: four bytes and, optionally, the interface it was learned on.
public struct IPv4Address: IPAddress, Hashable, CustomDebugStringConvertible {
    public static let any = IPv4Address(Data([0, 0, 0, 0]), nil)!
    public static let broadcast = IPv4Address(Data([255, 255, 255, 255]), nil)!
    public static let loopback = IPv4Address(Data([127, 0, 0, 1]), nil)!
    public static let allHostsGroup = IPv4Address(Data([224, 0, 0, 1]), nil)!
    public static let allRoutersGroup = IPv4Address(Data([224, 0, 0, 2]), nil)!
    public static let allReportsGroup = IPv4Address(Data([224, 0, 0, 22]), nil)!
    public static let mdnsGroup = IPv4Address(Data([224, 0, 0, 251]), nil)!

    public let interface: NWInterface?
    private let bytes: (UInt8, UInt8, UInt8, UInt8)

    public var rawValue: Data {
        Data([bytes.0, bytes.1, bytes.2, bytes.3])
    }

    public init?(_ rawValue: Data, _ interface: NWInterface? = nil) {
        guard rawValue.count == 4 else { return nil }
        let b = [UInt8](rawValue)
        self.bytes = (b[0], b[1], b[2], b[3])
        self.interface = interface
    }

    /// Parses dotted-quad text. Returns nil for anything else, which is what Apple's does.
    public init?(_ string: String) {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var octets = [UInt8]()
        octets.reserveCapacity(4)
        for part in parts {
            guard !part.isEmpty, let value = UInt8(part) else { return nil }
            octets.append(value)
        }
        self.init(Data(octets), nil)
    }

    public var isLoopback: Bool { bytes.0 == 127 }
    public var isLinkLocal: Bool { bytes.0 == 169 && bytes.1 == 254 }
    public var isMulticast: Bool { bytes.0 >= 224 && bytes.0 <= 239 }

    public var debugDescription: String {
        "\(bytes.0).\(bytes.1).\(bytes.2).\(bytes.3)"
    }

    public static func == (lhs: IPv4Address, rhs: IPv4Address) -> Bool {
        lhs.bytes == rhs.bytes
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
}

/// An IPv6 address: sixteen bytes and, optionally, the interface it was learned on.
public struct IPv6Address: IPAddress, Hashable, CustomDebugStringConvertible {
    public static let any = IPv6Address(Data(repeating: 0, count: 16), nil)!
    public static let loopback = IPv6Address(Data(repeating: 0, count: 15) + Data([1]), nil)!

    public enum Scope: UInt8 {
        case nodeLocal = 1
        case linkLocal = 2
        case siteLocal = 5
        case organizationLocal = 8
        case global = 14
    }

    public let interface: NWInterface?
    private let bytes: [UInt8]

    public var rawValue: Data { Data(bytes) }

    public init?(_ rawValue: Data, _ interface: NWInterface? = nil) {
        guard rawValue.count == 16 else { return nil }
        self.bytes = [UInt8](rawValue)
        self.interface = interface
    }

    /// Parses IPv6 text: groups of up to four hex digits, one `::` for a run of zero groups, and a
    /// trailing dotted quad for the IPv4-mapped forms. Returns nil for anything else.
    public init?(_ string: String) {
        let text = string.split(separator: "%", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let halves = text.components(separatedBy: "::")
        guard halves.count <= 2 else { return nil }
        func groups(_ part: String) -> [UInt16]? {
            if part.isEmpty { return [] }
            var out = [UInt16]()
            let pieces = part.split(separator: ":", omittingEmptySubsequences: false)
            for (index, piece) in pieces.enumerated() {
                if piece.isEmpty { return nil }
                if index == pieces.count - 1, piece.contains(".") {
                    guard let v4 = IPv4Address(String(piece)) else { return nil }
                    let b = [UInt8](v4.rawValue)
                    out.append((UInt16(b[0]) << 8) | UInt16(b[1]))
                    out.append((UInt16(b[2]) << 8) | UInt16(b[3]))
                    continue
                }
                guard piece.count <= 4, let value = UInt16(piece, radix: 16) else { return nil }
                out.append(value)
            }
            return out
        }
        guard let head = groups(halves[0]) else { return nil }
        var assembled = head
        if halves.count == 2 {
            guard let tail = groups(halves[1]), 8 - head.count - tail.count >= 1 else { return nil }
            assembled.append(contentsOf: repeatElement(0, count: 8 - head.count - tail.count))
            assembled.append(contentsOf: tail)
        }
        guard assembled.count == 8 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(16)
        for group in assembled {
            bytes.append(UInt8(group >> 8))
            bytes.append(UInt8(group & 0xFF))
        }
        self.init(Data(bytes), nil)
    }

    public var isAny: Bool { bytes.allSatisfy { $0 == 0 } }
    public var isLoopback: Bool { isAny == false && bytes[0..<15].allSatisfy { $0 == 0 } && bytes[15] == 1 }
    public var isLinkLocal: Bool { bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80 }
    public var isMulticast: Bool { bytes[0] == 0xFF }
    public var isIPv4Mapped: Bool {
        bytes[0..<10].allSatisfy { $0 == 0 } && bytes[10] == 0xFF && bytes[11] == 0xFF
    }

    public var asIPv4: IPv4Address? {
        guard isIPv4Mapped else { return nil }
        return IPv4Address(Data(bytes[12..<16]), interface)
    }

    public var multicastScope: Scope? {
        guard isMulticast else { return nil }
        return Scope(rawValue: bytes[1] & 0x0F)
    }

    public var debugDescription: String {
        var groups = [UInt16]()
        var index = 0
        while index < 16 {
            groups.append((UInt16(bytes[index]) << 8) | UInt16(bytes[index + 1]))
            index += 2
        }
        // Canonical form: the longest run of two or more zero groups collapses to "::".
        var bestStart = -1
        var bestLength = 0
        var start = -1
        var length = 0
        for (i, group) in groups.enumerated() {
            if group == 0 {
                if start < 0 { start = i }
                length += 1
                if length > bestLength { bestLength = length; bestStart = start }
            } else {
                start = -1
                length = 0
            }
        }
        if bestLength < 2 { bestStart = -1; bestLength = 0 }
        var pieces = [String]()
        var i = 0
        while i < 8 {
            if i == bestStart {
                pieces.append("")
                i += bestLength
                continue
            }
            pieces.append(String(groups[i], radix: 16))
            i += 1
        }
        var text = pieces.joined(separator: ":")
        if text.isEmpty {
            text = "::"
        } else {
            if text.hasPrefix(":") { text = ":" + text }
            if text.hasSuffix(":") { text += ":" }
        }
        if let interface { text += "%\(interface.name)" }
        return text
    }

    public static func == (lhs: IPv6Address, rhs: IPv6Address) -> Bool {
        lhs.bytes == rhs.bytes
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
}

// MARK: - NWEndpoint  (interface line 439)

/// A network endpoint: the thing a connection is to, or a listener is on.
public enum NWEndpoint: Hashable, CustomDebugStringConvertible, Sendable {
    case hostPort(host: Host, port: Port)
    case service(name: String, type: String, domain: String, interface: NWInterface?)
    case unix(path: String)
    case url(_ url: URL)

    public enum Host: Hashable, CustomDebugStringConvertible, ExpressibleByStringLiteral, Sendable {
        public typealias StringLiteralType = String

        case name(String, NWInterface?)
        case ipv4(IPv4Address)
        case ipv6(IPv6Address)

        public init(stringLiteral: String) {
            self.init(stringLiteral)
        }

        /// Text form: dotted-quad becomes `.ipv4`, anything with a colon becomes `.ipv6`, everything
        /// else is a name. This is Apple's split, and it is why this initializer cannot fail.
        public init(_ string: String) {
            if let v4 = IPv4Address(string) {
                self = .ipv4(v4)
            } else if string.contains(":"), let v6 = IPv6Address(string) {
                self = .ipv6(v6)
            } else {
                self = .name(string, nil)
            }
        }

        public var interface: NWInterface? {
            switch self {
            case .name(_, let interface): return interface
            case .ipv4(let address): return address.interface
            case .ipv6(let address): return address.interface
            }
        }

        public var debugDescription: String {
            switch self {
            case .name(let name, _): return name
            case .ipv4(let address): return address.debugDescription
            case .ipv6(let address): return address.debugDescription
            }
        }

        public static func == (a: Host, b: Host) -> Bool {
            switch (a, b) {
            case (.name(let x, let xi), .name(let y, let yi)):
                return x == y && xi == yi
            case (.ipv4(let x), .ipv4(let y)):
                return x == y
            case (.ipv6(let x), .ipv6(let y)):
                return x == y
            default:
                return false
            }
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(debugDescription)
        }
    }

    public struct Port: Hashable, CustomDebugStringConvertible, ExpressibleByIntegerLiteral, RawRepresentable, Sendable {
        public typealias IntegerLiteralType = UInt16
        public typealias RawValue = UInt16

        public static let any = Port(rawValue: 0)!
        public static let ssh = Port(rawValue: 22)!
        public static let smtp = Port(rawValue: 25)!
        public static let http = Port(rawValue: 80)!
        public static let pop = Port(rawValue: 110)!
        public static let imap = Port(rawValue: 143)!
        public static let https = Port(rawValue: 443)!
        public static let imaps = Port(rawValue: 993)!
        public static let socks = Port(rawValue: 1080)!

        public var rawValue: UInt16

        /// Apple's is failable; a port number is a port number, so this one always succeeds.
        public init?(rawValue: UInt16) {
            self.rawValue = rawValue
        }

        public init(integerLiteral value: IntegerLiteralType) {
            self.rawValue = value
        }

        public var debugDescription: String {
            switch rawValue {
            case 0: return "any"
            case 22: return "ssh"
            case 25: return "smtp"
            case 80: return "http"
            case 110: return "pop"
            case 143: return "imap"
            case 443: return "https"
            case 993: return "imaps"
            case 1080: return "socks"
            default: return "\(rawValue)"
            }
        }
    }

    public var interface: NWInterface? {
        switch self {
        case .hostPort(let host, _): return host.interface
        case .service(_, _, _, let interface): return interface
        case .unix: return nil
        case .url: return nil
        }
    }

    public static func == (lhs: NWEndpoint, rhs: NWEndpoint) -> Bool {
        switch (lhs, rhs) {
        case (.hostPort(let lh, let lp), .hostPort(let rh, let rp)):
            return lh == rh && lp == rp
        case (.service(let ln, let lt, let ld, let li), .service(let rn, let rt, let rd, let ri)):
            return ln == rn && lt == rt && ld == rd && li == ri
        case (.unix(let lp), .unix(let rp)):
            return lp == rp
        case (.url(let lu), .url(let ru)):
            return lu == ru
        default:
            return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(debugDescription)
    }

    public var debugDescription: String {
        switch self {
        case .hostPort(let host, let port):
            return "\(host):\(port)"
        case .service(let name, let type, let domain, _):
            return "\(name).\(type)\(domain.isEmpty ? "" : "." + domain)"
        case .unix(let path):
            return path
        case .url(let url):
            return url.absoluteString
        }
    }
}

// MARK: - NWPath  (interface line 873)

/// A path: what the connection would travel over. The endpoints are pure data and real; the status
/// is the one observation this guest can honestly make, and `NWPathMonitor` is where it comes from.
public struct NWPath: Equatable, CustomDebugStringConvertible, Sendable {
    /// (interface line 877) `public enum Status` with exactly Apple's three cases, in Apple's order.
    ///
    /// `.unsatisfied` is what every path in this guest reports: there is no path source at all (see
    /// NWPathMonitor.swift for the tree's own answers -- libnetwork's `nw_path_get_status` returns
    /// `nw_path_status_invalid`, `nw_path_monitor_create` returns NULL). `.requiresConnection` would
    /// claim an interface exists that a connection could activate and `.satisfied` that a usable path
    /// exists; neither is true here, so neither is ever produced.
    public enum Status: Sendable {
        case satisfied
        case unsatisfied
        case requiresConnection
    }

    public let localEndpoint: NWEndpoint?
    public let remoteEndpoint: NWEndpoint?

    /// (interface line 887) `public let status: Network.NWPath.Status`.
    public let status: Status

    /// No default for `status`: a status is a claim about the path, so every caller states which one
    /// it is making rather than inheriting one.
    public init(localEndpoint: NWEndpoint?, remoteEndpoint: NWEndpoint?, status: Status) {
        self.localEndpoint = localEndpoint
        self.remoteEndpoint = remoteEndpoint
        self.status = status
    }

    public var debugDescription: String {
        "NWPath(status: \(status), local: \(localEndpoint.map { "\($0)" } ?? "nil"), remote: \(remoteEndpoint.map { "\($0)" } ?? "nil"))"
    }

    public static func == (lhs: NWPath, rhs: NWPath) -> Bool {
        lhs.status == rhs.status
            && lhs.localEndpoint == rhs.localEndpoint
            && lhs.remoteEndpoint == rhs.remoteEndpoint
    }
}
