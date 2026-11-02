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

// From release/5.4 stdlib/public/Darwin/Foundation/FileManager.swift, reduced to enumerator(at:...). Darling has no
// __NSFileManagerEnumeratorAtURL shim, so it calls -enumeratorAtURL:includingPropertiesForKeys:options:errorHandler:
// and bridges the handler's arguments.
//
// Darling: `replaceItemAt(_:withItemAt:backupItemName:options:)` is here too, and it is not a bridge: Darling's
// NSFileManager implements no `-replaceItemAtURL:withItemAtURL:backupItemName:options:resultingItemURL:error:`
// (grepped: the selector is declared in include/Foundation/NSFileManager.h:161 and implemented nowhere in
// src/external/foundation/src), so there is no Objective-C half to delegate to, and the file carries the algorithm
// itself -- Apple's own open source for this module, corelibs'
// Sources/Foundation/FileManager+POSIX.swift `_replaceItem(at:withItemAt:backupItemName:options:)`, which is what
// the Swift-declared `replaceItemAt` in FileManager.swift:1123-1125 calls. See the ported body's own comments.

@_exported import Foundation // Clang module
import Darwin

extension FileManager {
    @available(macOS 10.6, iOS 4.0, *)
    @nonobjc
    public func enumerator(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?,
                           options mask: NSDirectoryEnumerationOptions = NSDirectoryEnumerationOptions(rawValue: 0),
                           errorHandler handler: ((URL, Error) -> Bool)? = nil) -> NSDirectoryEnumerator? {
        return enumerator(at: url, includingPropertiesForKeys: keys.map { $0.map { $0.rawValue } },
                          options: mask, errorHandler: { (url: URL?, error: Error?) -> Bool in
            guard let h = handler else { return true }
            guard let url = url, let error = error else {
                fatalError("FileManager.enumerator(at:) error handler called without a URL or an error")
            }
            return h(url, error)
        })
    }

    /// Replaces the item at `originalItemURL` with the item at `newItemURL`.
    ///
    /// Declaration: Apple's published API for this module, read out of the guest's own SDK
    /// (`Foundation.swiftinterface:476`, in `extension Foundation.FileManager`:
    /// `@available(swift 4)`, `@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)`,
    /// `public func replaceItemAt(_ originalItemURL: Foundation.URL, withItemAt newItemURL:
    /// Foundation.URL, backupItemName: Swift.String? = nil, options:
    /// Foundation.FileManager.ItemReplacementOptions = []) throws -> Foundation.URL?`).  The
    /// NSURL-returning sibling right above it in that interface is the pre-Swift-4 spelling of the
    /// same call.  In this tree the class imports as `NSFileManager` (Foundation.apinotes renames it
    /// to `FileManager`) and the options typedef is the NS_OPTIONS of
    /// src/external/foundation/include/Foundation/NSFileManager.h:20, so the mangled name of what is
    /// declared here is the one the demanding image binds:
    /// `_$sSo13NSFileManagerC10FoundationE13replaceItemAt_04witheF006backupE4Name7optionsAC3URLVSgAI_AISSSgSo0abE18ReplacementOptionsVtKF`.
    ///
    /// Body: Apple's own open source for this module, corelibs'
    /// `Sources/Foundation/FileManager+POSIX.swift:1219-1341`
    /// (`_replaceItem(at:withItemAt:backupItemName:options:)`), which is the implementation the
    /// Swift-declared `replaceItemAt` of `Sources/Foundation/FileManager.swift:1123` calls.  Ported
    /// verbatim except for three platform facts, each measured rather than assumed:
    ///
    ///   * corelibs' test-only `allowPlatformSpecificSyscalls` switch is gone, so the
    ///     platform-specific block always runs, as it does in a shipped corelibs (the switch exists
    ///     for `TestFileManager.swift:1889`, which is not built here);
    ///   * the platform-specific block keeps the Darwin arm only.  `renameatx_np` with
    ///     `RENAME_SWAP` is declared in the SDK's `sys/stdio.h:48` and exported by the deployed
    ///     `/usr/lib/system/libsystem_kernel.dylib` (measured with `llvm-nm`: `T _renameatx_np`), so
    ///     the call resolves in the guest and the file↔directory atomic swap is real here; the
    ///     Glibc arm of that block is Linux-corelibs and is not part of a Darwin target;
    ///   * that arm's fall-through set gains `EINVAL`.  A Darling guest's file system calls ARE the
    ///     host's: the deployed `libsystem_kernel`'s stub for this call loads XNU's number
    ///     (`bsdsyscalls___renameatx_np`, `movl $0x1e8, %eax`) and enters `__darling_bsd_syscall`,
    ///     where Darwin's `RENAME_SWAP` (2) and Linux's `RENAME_EXCHANGE` (2) are the same flag
    ///     value, and Linux answers EINVAL -- not ENOTSUP -- for a filesystem that does not support
    ///     the operation.  corelibs' own Glibc arm states the same thing in as many words ("EINVAL
    ///     may indicate that the filesystem does not support the operation",
    ///     FileManager+POSIX.swift:1299).  Without it, a host filesystem without exchange support
    ///     would make this method throw instead of taking the portable path below, where Darwin's
    ///     real implementation does support the volume.
    ///
    /// The attributes the default options preserve are read through the tree's own file manager
    /// (`attributesOfItem(atPath:)` and `setAttributes(_:ofItemAtPath:)`,
    /// src/external/foundation/src/NSFileManager.m:639 and its `NSFileAttributes` dictionary, whose
    /// keys are the SDK's `NSFileType`/`NSFileCreationDate`/`NSFilePosixPermissions` strings --
    /// include/Foundation/NSFileManager.h:26,40,48 -- because this tree declares no `NSFileAttributeKey`
    /// typedef and therefore no `FileAttributeKey`), and failures come back as the Cocoa error the
    /// failing errno names, with the POSIX error underneath and the URL in `NSURLErrorKey`, exactly as
    /// corelibs' `_NSErrorWithErrno(_:reading: false, url:)` builds it (FoundationErrors.swift:171-207).
    public func replaceItemAt(_ originalItemURL: URL,
                              withItemAt newItemURL: URL,
                              backupItemName: String? = nil,
                              options: NSFileManagerItemReplacementOptions = []) throws -> URL? {
        // 1. Make a backup, if asked to.
        var backupItemURL: URL?
        if let backupItemName = backupItemName {
            let url = originalItemURL.deletingLastPathComponent().appendingPathComponent(backupItemName)
            try copyItem(at: originalItemURL, to: url)
            backupItemURL = url
        }

        // 2. Make sure we have a copy of the original attributes if we're being asked to preserve them (the default).
        let originalAttributes = try attributesOfItem(atPath: originalItemURL.path)
        let newAttributes = try attributesOfItem(atPath: newItemURL.path)

        func applyPostprocessingRequiredByOptions() throws {
            if !options.contains(.usingNewMetadataOnly) {
                var attributesToReapply: [AnyHashable: Any] = [:]
                attributesToReapply[NSFileCreationDate] = originalAttributes[NSFileCreationDate]
                attributesToReapply[NSFilePosixPermissions] = originalAttributes[NSFilePosixPermissions]
                try setAttributes(attributesToReapply, ofItemAtPath: originalItemURL.path)
            }

            // As the very last step, if not explicitly asked to keep the backup, remove it.
            if let backupItemURL = backupItemURL, !options.contains(.withoutDeletingBackupItem) {
                try removeItem(at: backupItemURL)
            }
        }

        // First, a little OS-specific detour.  Blindly try these operations first, and fall back to
        // the non-OS-specific code below if they all fail.
        do {
            let finalErrno: Int32? = originalItemURL.withUnsafeFileSystemRepresentation { (originalFS) -> Int32? in
                return newItemURL.withUnsafeFileSystemRepresentation { (newItemFS) -> Int32? in
                    // Note that Darwin allows swapping a file with a directory this way.
                    if renameatx_np(AT_FDCWD, originalFS, AT_FDCWD, newItemFS, UInt32(RENAME_SWAP)) == 0 {
                        return nil
                    } else {
                        return errno
                    }
                }
            }

            // The fall-through set is corelibs' Darwin arm plus EINVAL: on this target the file
            // system's answer comes from the host (see the header comment).
            if let finalErrno = finalErrno, finalErrno != ENOTSUP, finalErrno != EINVAL {
                throw _FileManagerPOSIXError(finalErrno, url: originalItemURL)
            } else if finalErrno == nil {
                try applyPostprocessingRequiredByOptions()
                return originalItemURL
            }
        }

        // 3. Replace!
        // Are they both regular files?
        let originalType = originalAttributes[NSFileType] as? String
        let newType = newAttributes[NSFileType] as? String
        if originalType == newType, originalType == NSFileTypeRegular {
            let finalErrno: Int32? = originalItemURL.withUnsafeFileSystemRepresentation { (originalFS) -> Int32? in
                return newItemURL.withUnsafeFileSystemRepresentation { (newItemFS) -> Int32? in
                    // This is an atomic operation in many OSes, but is not guaranteed to be atomic by the standard.
                    if rename(newItemFS, originalFS) == 0 {
                        return nil
                    } else {
                        return errno
                    }
                }
            }
            if let theErrno = finalErrno {
                throw _FileManagerPOSIXError(theErrno, url: originalItemURL)
            }
        } else {
            // Only perform a replacement of different object kinds nonatomically.
            let uniqueName = UUID().uuidString
            let tombstoneURL = newItemURL.deletingLastPathComponent().appendingPathComponent(uniqueName)
            try moveItem(at: originalItemURL, to: tombstoneURL)
            try moveItem(at: newItemURL, to: originalItemURL)
            try removeItem(at: tombstoneURL)
        }

        // 4. Reapply attributes if asked to preserve, and delete the backup if not asked otherwise.
        try applyPostprocessingRequiredByOptions()

        return originalItemURL
    }
}

// corelibs Foundation/FoundationErrors.swift `_NSErrorWithErrno(_:reading: false, url:)`: the Cocoa
// error code the failing errno names, the POSIX error underneath it, and the URL the operation was
// for.  This file's own error path, as NSFileHandle.swift has its own for reads and writes.
private func _FileManagerPOSIXError(_ code: Int32, url: URL) -> NSError {
    let cocoaCode: CocoaError.Code
    switch code {
    case ENOENT: cocoaCode = .fileNoSuchFile
    case EPERM, EACCES: cocoaCode = .fileWriteNoPermission
    case ENAMETOOLONG: cocoaCode = .fileWriteInvalidFileName
    case EDQUOT, ENOSPC: cocoaCode = .fileWriteOutOfSpace
    case EROFS: cocoaCode = .fileWriteVolumeReadOnly
    case EEXIST: cocoaCode = .fileWriteFileExists
    default: cocoaCode = .fileWriteUnknown
    }
    // The annotation is load-bearing: this SDK's NSError carries both `-initWithDomain:code:userInfo:`
    // and the class factory `+errorWithDomain:code:userInfo:`, and without a contextual type the
    // compiler picks the factory's failable import, which would put an `NSError?` into
    // `NSUnderlyingErrorKey` instead of the error itself.
    let underlying: NSError = NSError(domain: NSPOSIXErrorDomain, code: Int(code))
    return NSError(domain: NSCocoaErrorDomain,
                   code: cocoaCode.rawValue,
                   userInfo: [NSURLErrorKey: url, NSUnderlyingErrorKey: underlying])
}
