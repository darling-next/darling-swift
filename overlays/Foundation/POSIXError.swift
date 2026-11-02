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

// From release/5.4 stdlib/public/Darwin/Foundation/NSError.swift: POSIXError, its bridging
// conformance and the code type it is bridged through. The static code table is limited to
// measured client demands, as in CocoaError.swift. `POSIXErrorCode` itself already exists -- it is
// `Darwin.POSIXErrorCode`, declared by this payload's own libswiftDarwin overlay and exported by the
// deployed /usr/lib/swift/libswiftDarwin.dylib -- so only the Foundation half is declared here.
//
// WHY THIS FILE EXISTS (measured 2026-10-13): the loader's live stop line was
//
//   Symbol not found: _$s10Foundation10POSIXErrorVAA21_BridgedStoredNSErrorAAMc
//     Referenced from: .../DNTDocumentationSupport.framework/Versions/A/DNTDocumentationSupport
//     Expected in: /System/Library/Frameworks/Foundation.framework/Versions/C/Foundation
//
// and DNTDocumentationSupport's own chained fixups import exactly three Foundation-field names for
// this type -- the conformance descriptor (bind #1029, __DATA_CONST 0x251300), the metadata accessor
// (#1030, 0x251308) and the nominal type descriptor (#1031, 0x251310), all eager and strong -- plus
// `Darwin.POSIXErrorCode.init(rawValue:)` (#1772, 0x252a38, /usr/lib/swift/libswiftDarwin.dylib).
// The demanding code is DNTDocumentationSupport's own `URL.setExtendedAttribute(named:value:)` /
// `URL.extendedAttribute(named:)` family: it builds `POSIXErrorCode(rawValue: errno)` (0xcbc31),
// instantiates the concrete metadata for `(attributeName: String, returnCode: Int,
// underlyingError: POSIXError)`, and calls the `_BridgedStoredNSError` protocol extension's
// `init(_:userInfo:)` (0xcba8 -> `_$s10Foundation21_BridgedStoredNSErrorPAAE_8userInfox4CodeQz_SDySSypGtcfC`)
// with the POSIXError metadata in %rsi and this conformance descriptor in %rdx. The conformance is
// therefore DISPATCHED THROUGH, not merely referenced: a descriptor that does not describe a real
// conformance would give the client a garbage witness table, and a wrong `Code` raw type would give
// it a wrong errno.

@_exported import Foundation // Clang module
import Darwin

/// Describes an error in the POSIX error domain.
public struct POSIXError : _BridgedStoredNSError {
  public let _nsError: NSError

  public init(_nsError error: NSError) {
    precondition(error.domain() == NSPOSIXErrorDomain)
    self._nsError = error
  }

  public static var errorDomain: String { return NSPOSIXErrorDomain }

  public var hashValue: Int {
    return _nsError.hashValue
  }

  public typealias Code = POSIXErrorCode
}

extension POSIXErrorCode : _ErrorCodeProtocol {
  public typealias _ErrorType = POSIXError
}

extension POSIXError {
  /// Operation canceled.
  public static var ECANCELED: POSIXErrorCode {
    return .ECANCELED
  }
}
