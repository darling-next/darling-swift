// The Swift refinements of OSLog.framework (darling src/frameworks/OSLog), built as the module OSLog
// the same way the tree's other overlays are built (overlays/build-arch.sh).
//
// Swift mangles a module name into every symbol, and the overlay module's name is the FRAMEWORK's
// module name, which is what makes these names match the ones clients import.  The one symbol the
// guest demands from this dylib is
//
//   _$sSo10OSLogStoreC0A0E10getEntries4with2at8matchings11AnySequenceVySo0A5EntryCGSo0A17EnumeratorOptionsV_So0A8PositionCSgSo11NSPredicateCSgtKF
//     = (extension in OSLog) __C.OSLogStore.getEntries(with: __C.OSLogEnumeratorOptions,
//                                                      at: __C.OSLogPosition?,
//                                                      matching: __C.NSPredicate?)
//                throws -> Swift.AnySequence<__C.OSLogEntry>
//   (measured from SWBBuildSystem's own bind table, field libswiftOSLog, STRONG and eager)
//
// The body is not a stub: it runs the framework's real enumerator over the real store and walks it,
// so the value a caller gets is the sequence of OSLogEntry objects OSLogStore produced from the ASL
// records libsystem_trace wrote.  An error the store reports (no store reachable, an unusable
// position, a predicate the entries cannot answer) is thrown, not swallowed.

import Foundation
// The framework's Objective-C classes come from the shim: Darling's SDK has no Clang module for
// OSLog.framework (it is this tree's own framework), so the declarations live in OSLog/shims and the
// build passes -fmodule-map-file for them (the same shape as UniformTypeIdentifiers).
import _DarlingOSLogShims

extension OSLogStore {
	/// The entries of the store, in the order the options ask for, filtered by a predicate whose keys
	/// are the entries' own properties.
	public func getEntries(with options: OSLogEnumeratorOptions = [],
	                       at position: OSLogPosition? = nil,
	                       matching predicate: NSPredicate? = nil) throws -> AnySequence<OSLogEntry> {
		let enumerator = try entriesEnumerator(with: options, position: position, predicate: predicate)
		return AnySequence(OSLogEntryEnumeratorSequence(enumerator: enumerator))
	}
}

/// NSEnumerator is not a Swift Sequence, so the sequence the API promises is this walk over
/// `nextObject()`, casting each element to the class the enumerator yields.  The cast cannot fail for
/// an enumerator this framework produced (it only ever holds OSLogEntry instances); the precondition
/// states that rather than silently dropping an element one could not read.
struct OSLogEntryEnumeratorSequence: Sequence, IteratorProtocol {
	private let enumerator: NSEnumerator

	init(enumerator: NSEnumerator) {
		self.enumerator = enumerator
	}

	mutating func next() -> OSLogEntry? {
		guard let object = enumerator.nextObject() else {
			return nil
		}

		precondition(object is OSLogEntry,
		             "OSLogStore's enumerator yielded \(type(of: object)); it yields OSLogEntry only")
		return object as? OSLogEntry
	}
}
