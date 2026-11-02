//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

// From release/5.4 stdlib/public/Darwin/Foundation/URL.swift: URLResourceValues and
// URL.resourceValues(forKeys:) over Darling's -resourceValuesForKeys:error:.
// Darling: the writing half is here too -- URL.setResourceValues(_:) and URLResourceValues'
// isExcludedFromBackup setter -- over the same Objective-C surface's -setResourceValues:error:. Both are
// for the next-stops-behind-ArgumentParserInternal rung; each member's own comment names its source, and
// ../DARLING-CHANGES.md carries the rung.

@_exported import Foundation // Clang module

public struct URLResourceValues {
    fileprivate var _values: [URLResourceKey: Any]

    public init() {
        _values = [:]
    }

    fileprivate init(values: [URLResourceKey: Any]) {
        _values = values
    }

    /// All of the resource values, keyed by resource key.
    public var allValues: [URLResourceKey: Any] {
        return _values
    }

    private func _get<T>(_ key : URLResourceKey) -> T? {
        return _values[key] as? T
    }

    private func _number(_ key: URLResourceKey) -> NSNumber? {
        return _get(key)
    }

    /// Records a value the caller set, so `URL.setResourceValues(_:)` has something to write.
    ///
    /// Body from Apple's own open source for this module,
    /// `swift-corelibs-foundation/Sources/Foundation/URL.swift:68-76` (`_set(_:newValue:Bool?)`):
    /// a `Bool?` is stored as an `NSNumber` because that is what the resource-value machinery
    /// carries, and `nil` removes the entry instead of storing a null.  The set (as opposed to just
    /// the dictionary) is corelibs' `_keys`; this file keeps only the dictionary because the only
    /// writer is `URL.setResourceValues(_:)` below, which hands the whole dictionary to NSURL --
    /// exactly what corelibs' own `URL.setResourceValues(_:)` does with `values._values`
    /// (`swift-corelibs-foundation/Sources/Foundation/URL.swift:923-925`).
    private mutating func _set(_ key: URLResourceKey, newValue: Bool?) {
        if let value = newValue {
            _values[key] = NSNumber(value: value)
        } else {
            _values[key] = nil
        }
    }

    /// The date the resource was created.
    public var creationDate: Date? {
        return _get(.creationDateKey)
    }

    /// The URL's path as a file system path.
    public var path: String? {
        return _get(.pathKey)
    }

    /// The canonical absolute filesystem path, resolved by the native provider.
    @available(macOS 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *)
    public var canonicalPath: String? {
        return _get(.canonicalPathKey)
    }

    public var isRegularFile: Bool? {
        return _number(.isRegularFileKey)?.boolValue()
    }

    public var isDirectory: Bool? {
        return _number(.isDirectoryKey)?.boolValue()
    }

    public var isSymbolicLink: Bool? {
        return _number(.isSymbolicLinkKey)?.boolValue()
    }

    // Vendored corelibs URL.swift and swift-foundation swift-6.2-RELEASE expose
    // this read-only optional; adapt it to this overlay's NSNumber bridge.
    // Missing native metadata remains absent, never an invented false value.
    public var isAliasFile: Bool? {
        return _number(.isAliasFileKey)?.boolValue()
    }

    /// A Boolean value that indicates whether the resource is excluded from backups.
    ///
    /// Declaration: the guest SDK's `Foundation.swiftinterface` line 15841, in its `URLResourceValues`
    /// struct: `public var isExcludedFromBackup: Swift.Bool? { get set }`.  Body from Apple's own open
    /// source for this module,
    /// `swift-corelibs-foundation/Sources/Foundation/URL.swift:223-226`
    /// (`get { return _get(.isExcludedFromBackupKey) }` /
    /// `set { _set(.isExcludedFromBackupKey, newValue: newValue) }`), which is also what the in-tree
    /// copy of that file carries: the getter asks the same resource-value machinery as every other
    /// property here, and the setter records the new value for `URL.setResourceValues(_:)` to write.
    ///
    /// What the tree's machinery answers for this key, read from its own sources rather than assumed:
    /// `NSURLIsExcludedFromBackupKey` is an `NSURLResourceKey`
    /// (src/external/foundation/include/Foundation/NSURL.h:43) whose raw value is the string
    /// `NSURLIsExcludedFromBackupKey` (src/external/corefoundation/NSURL.m:60, the same string
    /// `URLResourceKey.swift:59` gives this static member), and `-resourceValuesForKeys:error:`
    /// (`src/external/corefoundation/NSURL.m:1105`, CoreFoundation's
    /// `CFURLCopyResourcePropertiesForKeys`) answers it with `kCFBooleanTrue`
    /// (src/external/corefoundation/NSURL.m:494-497) -- unconditionally, so this answers `true` for
    /// every URL the machinery is asked about, and `nil` only if the key is answered with nothing at
    /// all.  A set is accepted by `-setResourceValues:error:`
    /// (src/external/corefoundation/NSURL.m:1115-1118, `CFURLSetResourcePropertiesForKeys`
    /// (src/external/corefoundation/NSURL.m:949) -> `CFURLSetPropertyForKey`,
    /// src/external/corefoundation/NSURL.m:892-894) as a CFBoolean and kept
    /// in the URL's resource info, which the getter above then reads back: the round trip through one
    /// URL object is real, and whatever the machinery does beyond that is the machinery's, not this
    /// file's.
    public var isExcludedFromBackup: Bool? {
        get { return _number(.isExcludedFromBackupKey)?.boolValue() }
        set { _set(.isExcludedFromBackupKey, newValue: newValue) }
    }

    /// A Boolean value that indicates whether the resource is hidden.
    ///
    /// Declaration: the guest SDK's `Foundation.swiftinterface` line 15717, in its `URLResourceValues`
    /// struct: `public var isHidden: Swift.Bool? { get set }`.  The value is asked of the file system
    /// through the same resource-value machinery as every other property here:
    /// `-resourceValuesForKeys:error:` answers `NSURLIsHiddenKey` from the first character of the
    /// URL's last path component being `.` (src/external/corefoundation/NSURL.m:277-284), so this
    /// answers with a real fact whenever the URL is a file URL.  A resource that cannot be
    /// interrogated (a non-file URL) contributes no entry to the dictionary and this answers `nil`
    /// -- absence, never an invented value.
    public var isHidden: Bool? {
        return _number(.isHiddenKey)?.boolValue()
    }

    /// The time the resource content was last modified.
    ///
    /// Declaration: the guest SDK's `Foundation.swiftinterface` line 15741, in its `URLResourceValues`
    /// struct: `public var contentModificationDate: Foundation.Date? { get set }`.  The value is
    /// asked of the file system through the same resource-value machinery as every other property
    /// here: `-resourceValuesForKeys:error:` answers `NSURLContentModificationDateKey` from the
    /// file's `stat` `st_mtime` (src/external/corefoundation/NSURL.m:319-323), so this answers with
    /// a real fact whenever the URL is a file URL that can be `stat`ed.  A resource that cannot be
    /// interrogated (a non-file URL, or a `stat` failure) contributes no entry to the dictionary and
    /// this answers `nil` -- absence, never an invented date.
    public var contentModificationDate: Date? {
        return _get(.contentModificationDateKey)
    }

    public var fileSize: Int? {
        return _number(.fileSizeKey)?.integerValue()
    }

    // Existing shipped resource getters, from the Darwin URL.swift overlay.
    // Missing optional metadata stays absent; no volume capability is invented.
    public var isReadable: Bool? {
        return _number(.isReadableKey)?.boolValue()
    }

    public var isWritable: Bool? {
        return _number(.isWritableKey)?.boolValue()
    }

    public var isExecutable: Bool? {
        return _number(.isExecutableKey)?.boolValue()
    }

    public var typeIdentifier: String? {
        return _get(.typeIdentifierKey)
    }

    public var volumeSupportsCaseSensitiveNames: Bool? {
        return _number(.volumeSupportsCaseSensitiveNamesKey)?.boolValue()
    }

    /// The optimal block size to use when reading or writing this file's data, in bytes, or nil if
    /// the preferred size is not available.
    ///
    /// The value is asked of the file system through the same resource-value machinery as every
    /// other property here: `-resourceValuesForKeys:error:` answers `NSURLPreferredIOBlockSizeKey`
    /// from `stat`'s `st_blksize` (src/external/corefoundation/NSURL.m:441-449), so this answers
    /// with a real fact whenever the URL is a file URL that can be `stat`ed. Unlike the newer
    /// capacity sibling below, this key IS declared and exported by the tree
    /// (`src/external/foundation/include/Foundation/NSURL.h:38`), so the property is written the
    /// way release/5.4 `stdlib/public/Darwin/Foundation/URL.swift:215` writes it. A resource whose
    /// block size cannot be interrogated (a non-file URL, or a `stat` failure) contributes no entry
    /// to the dictionary and this answers `nil` -- absence, never an invented size.
    public var preferredIOBlockSize: Int? {
        return _get(.preferredIOBlockSizeKey)
    }

    /// The volume's capacity available for important usage, in bytes.
    ///
    /// The value is asked of the file system through the same resource-value machinery as every other
    /// property here: `-resourceValuesForKeys:error:` answers `NSURLVolumeAvailableCapacityForImportantUsageKey`
    /// from `statvfs` (free blocks times the fragment size), so this answers with a real fact whenever
    /// the URL is a file URL on a volume that reports it. The tree's `Foundation/NSURL.h` declares
    /// `NSURLVolumeAvailableCapacityKey` but not this newer sibling (a header gap, not a missing
    /// implementation: src/external/corefoundation/NSURL.m defines the constant and handles the key),
    /// so the key is named by its documented raw value, exactly as `NSURL.m:135` and
    /// `CFURLConstants.c` spell it. A URL whose volume cannot be interrogated (a non-file URL, or a
    /// `statvfs` failure) contributes no entry to the dictionary and this answers `nil` -- absence,
    /// never an invented capacity.
    public var volumeAvailableCapacityForImportantUsage: Int64? {
        return _get(URLResourceKey(rawValue: "NSURLVolumeAvailableCapacityForImportantUsageKey"))
    }
}

extension URL {
    /// Sets the resource values identified by the given values.
    ///
    /// Declaration: the guest SDK's `Foundation.swiftinterface` line 16537, in its `extension
    /// Foundation.URL` block: `public mutating func setResourceValues(_ values:
    /// Foundation.URLResourceValues) throws`.  Body from Apple's own open source for this module,
    /// `swift-corelibs-foundation/Sources/Foundation/URL.swift:923-925`
    /// (`try _writableURL.setResourceValues(values._values)`), which is also what the in-tree copy of
    /// that file carries: the values the struct is carrying are handed to NSURL's
    /// `-setResourceValues:error:` -- the Objective-C surface this file's other `URL` member already
    /// goes through -- which in this tree is `CFURLSetResourcePropertiesForKeys`
    /// (src/external/corefoundation/NSURL.m:949, reached from :1115-1118).
    ///
    /// The receiver is reached with `_bridgeToObjectiveC()` because `URL` wraps the NSURL rather than
    /// carrying resource storage of its own, exactly as `resourceValues(forKeys:)` below does: a write
    /// therefore lands on the same NSURL object a later `resourceValues(forKeys:)` reads, and on the
    /// resource info CoreFoundation keeps for that object
    /// (src/external/corefoundation/NSURL.m:601-620, :904-914).
    ///
    /// Which values are written is corelibs' own answer, not a filter invented here: the whole
    /// dictionary the struct carries -- values the caller set, and any value an earlier
    /// `resourceValues(forKeys:)` read into it -- is passed, and it is the machinery that accepts,
    /// ignores or rejects each key.  `nil` is stored as a removed entry, so a property set back to
    /// `nil` contributes no key.
    public mutating func setResourceValues(_ values: URLResourceValues) throws {
        try _bridgeToObjectiveC().setResourceValues(values._values)
    }

    /// Return a collection of resource values identified by the given resource keys.
    public func resourceValues(forKeys keys: Set<URLResourceKey>) throws -> URLResourceValues {
        let raw = try _bridgeToObjectiveC().resourceValues(forKeys: keys.map { $0.rawValue })
        var values: [URLResourceKey: Any] = [:]
        for (key, value) in raw {
            if let name = key as? String {
                values[URLResourceKey(rawValue: name)] = value
            }
        }
        return URLResourceValues(values: values)
    }
}
