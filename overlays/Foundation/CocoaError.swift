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

// From release/5.4 stdlib/public/Darwin/Foundation/NSError.swift: CocoaError and its Code, with only the codes apps
// import (the full code table is left out).

@_exported import Foundation // Clang module

public typealias NSCocoaError = CocoaError

/// Describes errors within the Cocoa error domain.
public struct CocoaError : _BridgedStoredNSError {
  public let _nsError: NSError

  public init(_nsError error: NSError) {
    precondition(error.domain() == NSCocoaErrorDomain)
    self._nsError = error
  }

  public static var errorDomain: String { return NSCocoaErrorDomain }

  public var hashValue: Int {
    return _nsError.hashValue
  }

  /// The error code itself.
  public struct Code : RawRepresentable, Hashable, _ErrorCodeProtocol {
    public typealias _ErrorType = CocoaError

    public let rawValue: Int

    public init(rawValue: Int) {
      self.rawValue = rawValue
    }
  }
}

extension CocoaError.Code {
  /// `NSUserCancelledError` (3072).
  public static var userCancelled: CocoaError.Code {
    return CocoaError.Code(rawValue: 3072)
  }

  /// `NSFormattingError` (2048), which the format styles' parse strategies throw.
  public static var formatting: CocoaError.Code {
    return CocoaError.Code(rawValue: 2048)
  }

  /// `NSFileNoSuchFileError` (4).
  public static var fileNoSuchFile: CocoaError.Code {
    return CocoaError.Code(rawValue: 4)
  }

  /// `NSKeyValueValidationError` (1024), thrown when a value fails validation -- what
  /// `Morphology.setCustomPronoun(_:forLanguage:)` reports for an unsupported pronoun.
  public static var keyValueValidation: CocoaError.Code {
    return CocoaError.Code(rawValue: 1024)
  }

  /// `NSFileReadUnknownError` (256), what the file handle API reports for a read that failed with
  /// an errno it has no more specific code for.
  public static var fileReadUnknown: CocoaError.Code {
    return CocoaError.Code(rawValue: 256)
  }

  /// `NSFileReadNoPermissionError` (257) -- a read that failed with `EPERM` or `EACCES`.
  public static var fileReadNoPermission: CocoaError.Code {
    return CocoaError.Code(rawValue: 257)
  }

  /// `NSFileReadInvalidFileNameError` (258).
  public static var fileReadInvalidFileName: CocoaError.Code {
    return CocoaError.Code(rawValue: 258)
  }

  /// `NSFileReadNoSuchFileError` (260) -- a read that failed with `ENOENT`.
  public static var fileReadNoSuchFile: CocoaError.Code {
    return CocoaError.Code(rawValue: 260)
  }

  /// `NSFileReadTooLargeError` (263) -- a read that failed with `EFBIG`.
  public static var fileReadTooLarge: CocoaError.Code {
    return CocoaError.Code(rawValue: 263)
  }

  @available(macOS, introduced: 10.7) @available(iOS, introduced: 5.0)
  public static var fileWriteFileExists: CocoaError.Code {
    return CocoaError.Code(rawValue: 516)
  }

  /// `NSFileWriteUnknownError` (512), what the file handle API reports for a write that failed with
  /// an errno it has no more specific code for.
  public static var fileWriteUnknown: CocoaError.Code {
    return CocoaError.Code(rawValue: 512)
  }

  /// `NSFileWriteNoPermissionError` (513) -- a write that failed with `EPERM` or `EACCES`.
  public static var fileWriteNoPermission: CocoaError.Code {
    return CocoaError.Code(rawValue: 513)
  }

  /// `NSFileWriteInvalidFileNameError` (514) -- a write that failed with `ENAMETOOLONG`.
  public static var fileWriteInvalidFileName: CocoaError.Code {
    return CocoaError.Code(rawValue: 514)
  }

  /// `NSFileWriteOutOfSpaceError` (640) -- a write that failed with `EDQUOT` or `ENOSPC`.
  public static var fileWriteOutOfSpace: CocoaError.Code {
    return CocoaError.Code(rawValue: 640)
  }

  /// `NSFileWriteVolumeReadOnlyError` (642) -- a write that failed with `EROFS`.
  public static var fileWriteVolumeReadOnly: CocoaError.Code {
    return CocoaError.Code(rawValue: 642)
  }

  @available(macOS, introduced: 10.13) @available(iOS, introduced: 11.0)
  public static var coderInvalidValue: CocoaError.Code {
    return CocoaError.Code(rawValue: 4866)
  }

  @available(macOS, introduced: 10.5) @available(iOS, introduced: 2.0)
  public static var executableNotLoadable: CocoaError.Code {
    return CocoaError.Code(rawValue: 3584)
  }
}

extension CocoaError {
  // Keep release/5.4 NSError.swift's factory and URL precedence; the current
  // corelibs split moves CocoaError into FoundationEssentials, which this
  // Objective-C Foundation overlay cannot replace wholesale.
  public static func error(_ code: CocoaError.Code,
                           userInfo: [AnyHashable: Any]? = nil,
                           url: URL? = nil) -> Error {
    var info: [String: Any] = userInfo as? [String: Any] ?? [:]
    if let url = url {
      info[NSURLErrorKey] = url
    }
    return NSError(domain: NSCocoaErrorDomain, code: code.rawValue, userInfo: info)
  }

  /// `NSUserCancelledError` (3072).
  public static var userCancelled: CocoaError.Code {
    return CocoaError.Code(rawValue: 3072)
  }

  /// `NSFormattingError`, declared on both types as in the SDK.
  public static var formatting: CocoaError.Code {
    return CocoaError.Code(rawValue: 2048)
  }

  /// `NSFileNoSuchFileError`, declared on both types as in the SDK.
  public static var fileNoSuchFile: CocoaError.Code {
    return CocoaError.Code(rawValue: 4)
  }

  /// `NSKeyValueValidationError`, declared on both types as in the SDK.
  public static var keyValueValidation: CocoaError.Code {
    return CocoaError.Code(rawValue: 1024)
  }

  /// `NSFileReadUnknownError` (256), what the file handle API reports for a read that failed with
  /// an errno it has no more specific code for.
  public static var fileReadUnknown: CocoaError.Code {
    return CocoaError.Code(rawValue: 256)
  }

  /// `NSFileReadNoPermissionError` (257) -- a read that failed with `EPERM` or `EACCES`.
  public static var fileReadNoPermission: CocoaError.Code {
    return CocoaError.Code(rawValue: 257)
  }

  /// `NSFileReadInvalidFileNameError`, declared on both types as in the SDK.
  public static var fileReadInvalidFileName: CocoaError.Code {
    return CocoaError.Code(rawValue: 258)
  }

  /// `NSFileReadNoSuchFileError` (260) -- a read that failed with `ENOENT`.
  public static var fileReadNoSuchFile: CocoaError.Code {
    return CocoaError.Code(rawValue: 260)
  }

  /// `NSFileReadTooLargeError` (263) -- a read that failed with `EFBIG`.
  public static var fileReadTooLarge: CocoaError.Code {
    return CocoaError.Code(rawValue: 263)
  }

  @available(macOS, introduced: 10.7) @available(iOS, introduced: 5.0)
  public static var fileWriteFileExists: CocoaError.Code {
    return CocoaError.Code(rawValue: 516)
  }

  /// `NSFileWriteUnknownError` (512), what the file handle API reports for a write that failed with
  /// an errno it has no more specific code for.
  public static var fileWriteUnknown: CocoaError.Code {
    return CocoaError.Code(rawValue: 512)
  }

  /// `NSFileWriteNoPermissionError` (513) -- a write that failed with `EPERM` or `EACCES`.
  public static var fileWriteNoPermission: CocoaError.Code {
    return CocoaError.Code(rawValue: 513)
  }

  /// `NSFileWriteInvalidFileNameError` (514) -- a write that failed with `ENAMETOOLONG`.
  public static var fileWriteInvalidFileName: CocoaError.Code {
    return CocoaError.Code(rawValue: 514)
  }

  /// `NSFileWriteOutOfSpaceError` (640) -- a write that failed with `EDQUOT` or `ENOSPC`.
  public static var fileWriteOutOfSpace: CocoaError.Code {
    return CocoaError.Code(rawValue: 640)
  }

  /// `NSFileWriteVolumeReadOnlyError` (642) -- a write that failed with `EROFS`.
  public static var fileWriteVolumeReadOnly: CocoaError.Code {
    return CocoaError.Code(rawValue: 642)
  }

  @available(macOS, introduced: 10.13) @available(iOS, introduced: 11.0)
  public static var coderInvalidValue: CocoaError.Code {
    return CocoaError.Code(rawValue: 4866)
  }

  @available(macOS, introduced: 10.5) @available(iOS, introduced: 2.0)
  public static var executableNotLoadable: CocoaError.Code {
    return CocoaError.Code(rawValue: 3584)
  }
}
