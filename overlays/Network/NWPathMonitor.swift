//===----------------------------------------------------------------------===//
//
// Darling's Swift `Network` overlay -- NWPathMonitor, and the NWPath.Status it reports.
//
// See Network.swift for why this module exists; the declarations come from the guest SDK's own
// interface (.../Network.framework/Modules/Network.swiftmodule/x86_64-apple-macos.swiftinterface):
// `@_objcRuntimeName(_TtC7Network14_NWPathMonitor) final public class NWPathMonitor` at line 945,
// `pathUpdateHandler` at 955, `start(queue:)` at 960, `cancel()` at 961, `init()` at 967 and
// `init(requiredInterfaceType:)` at 976; `NWPath.Status` at 877 (cases at 878-880) and
// `NWPath.status` at 887.
//
// WHAT THE DEMAND IS.  Xcode 26.3's Contents/SharedFrameworks/ContentDelivery.framework binds eleven
// names of this class and of NWPath.Status against its Network ordinal, all eager and strong
// (LC_DYLD_CHAINED_FIXUPS imports[251..261], lib_ordinal 6 = Network, weak_import 0), and reaches
// them from two adjacent functions: it creates the monitor through the type metadata plus
// init(requiredInterfaceType:) (0x128d56 metadata, 0x128d70 init), installs a handler through
// pathUpdateHandler's setter (0x128f32), starts it on a real dispatch queue (0x128f71) and cancels
// it on teardown (0x1290f2, 0x129177).  The handler (0x129000) READS the path's status
// (0x12903d, through NWPath.Status's metadata at 0x129016) and maps it to an integer it passes on:
// 1 for .satisfied, 0 for .unsatisfied, 2 for .requiresConnection, -1 for a status it does not know
// (0x12904d-0x1290a8).  So the status is read and used; it is not decoration.
//
// WHAT IS REAL, AND WHY `start(queue:)` IS NOT REFUSED.  The monitor is real state -- the interface
// type it was created with and the handler -- and the one observation it can make is this guest's
// own: there is no path.  The tree says so itself: libnetwork, the C API behind Network.framework,
// answers every path query with a stub -- `nw_path_get_status` returns `nw_path_status_invalid`,
// `nw_path_monitor_create` returns NULL, and the interface/expense/address queries answer
// false/NULL (src/external/libnetwork/src/nw/path.m:141-147,179-215) -- so no path exists and nothing can
// ever change one.  Apple's `NWPath.Status` case that means exactly that is `.unsatisfied` ("no path
// is available"); `.requiresConnection` would claim an interface exists that a connection could
// activate, and `.satisfied` would claim a usable path, so neither is ever produced here.
//
// The overlay's transport rule (refuse with darlingNetworkUnserved, see NWConnection.swift) is about
// operations that would assert a success that did not happen -- a connection that started, bytes
// that were sent.  Starting a path monitor asserts none of that: it begins delivering the current
// path, and the current path is a fact this guest can state.  So `start(queue:)` delivers it once,
// on the given queue, the way Apple's monitor delivers the initial path when it starts, and no
// further update ever arrives because nothing can change it.  A client that decides "no network" is
// right; a client that waited forever would not be told anything true.
//
// Absent on purpose, as everywhere in this overlay -- no demand in this load closure names them and
// none is invented here. Of the class (interface lines 945-1004): `currentPath` (946), `queue` (963),
// `init()` (967), `ethernetChannel` (973), `init(prohibitedInterfaceTypes:)` (978), `debugDescription`
// (985) and the `AsyncSequence` half (`next()` 991, `makeAsyncIterator()` 999). Of `NWPath`: the
// whole live-path snapshot Apple fills in -- `UnsatisfiedReason`/`unsatisfiedReason`, `LinkQuality`/
// `linkQuality`, `availableInterfaces`, `isExpensive`, `isConstrained`, `isUltraConstrained`,
// `supportsIPv4`/`supportsIPv6`/`supportsDNS`, `gateways` and `usesInterfaceType(_:)` -- none of which
// this guest could fill with anything but a made-up value.

import Darwin
import Dispatch
import Foundation

/// (interface line 945) `final public class NWPathMonitor`
///
/// The `@_objcRuntimeName(_TtC7Network14_NWPathMonitor)` Apple declares only renames the class in the
/// Objective-C runtime; every name the demand binds is Swift-mangled (`7Network13NWPathMonitor`), so
/// the attribute is not reproduced here and nothing binds it.
public final class NWPathMonitor {
    /// The interface type the monitor was created to watch (interface line 976).
    ///
    /// Apple reports only a path that has an interface of this type. With no interface of any type in
    /// this guest the value cannot change the answer, but it is the monitor's real construction state
    /// and is kept rather than dropped, so a future interface source needs no new input.
    private let requiredInterfaceType: NWInterface.InterfaceType

    /// (interface line 955) `final public var pathUpdateHandler: (@Sendable (_ newPath: NWPath) -> Void)?`
    ///
    /// Declared WITHOUT `@Sendable`, which is what the demand binds: ContentDelivery's chained-fixup
    /// import for the setter is `...17pathUpdateHandleryAA0B0VcSgvs`, and `@Sendable` would mangle
    /// the property's function type with a `Y` the demanded name does not carry (measured: a property
    /// of type `@Sendable (P) -> Void` mangles as `...yAA1PVYbcSgvs`, the same property unmarked as
    /// `...yAA1PVcSgvs`). The type is ABI-identical either way, and the closure cannot outlive the
    /// guest process, so the demand's spelling is the one used.
    public var pathUpdateHandler: ((NWPath) -> Void)?

    /// (interface line 976) `public init(requiredInterfaceType: Network.NWInterface.InterfaceType)`
    public init(requiredInterfaceType: NWInterface.InterfaceType) {
        self.requiredInterfaceType = requiredInterfaceType
    }

    /// (interface line 960) `final public func start(queue: Dispatch.DispatchQueue)`
    ///
    /// Delivers the current path -- unsatisfied, the guest's own state (see the file header) -- once,
    /// on the queue. The handler is taken here rather than read on the queue so that the delivery
    /// never races with a concurrent write to the property.
    public func start(queue: DispatchQueue) {
        let handler = pathUpdateHandler
        let path = NWPath(localEndpoint: nil, remoteEndpoint: nil, status: .unsatisfied)
        queue.async { handler?(path) }
    }

    /// (interface line 961) `final public func cancel()`
    ///
    /// A no-op, and honestly so, like `NWConnection.cancel()`: nothing was started, so there is
    /// nothing to tear down and nothing to release. Apple's monitor calls its handler on the queue it
    /// was started with, and a monitor cancelled immediately after `start` can still receive that
    /// already-queued initial path; so can this one -- what it must NOT do is keep reporting changes
    /// afterwards, and since the path cannot change, it does not.
    public func cancel() {}
}
