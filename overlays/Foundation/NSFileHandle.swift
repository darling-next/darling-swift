//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

// Darling: the Swift half of NSFileHandle -- the part the SDK declares in module Foundation and no
// open source carries for this class.
//
// WHY THIS FILE EXISTS (the rung that needed it). Xcode 26.3's
// Contents/SharedFrameworks/DVTInstrumentsFoundation.framework binds, eagerly and strongly,
//
//     _$sSo12NSFileHandleC10FoundationE5write10contentsOfyx_tKAC12DataProtocolRzlF
//       == (extension in Foundation): __C.NSFileHandle.write<A where A: Foundation.DataProtocol>
//                                                  (contentsOf: A) throws -> ()
//
// against its Foundation ordinal, and the deployed /usr/lib/swift/libswiftFoundation.dylib exported
// no NSFileHandle Swift symbol at all, so the guest's dyld stopped at
//
//     Error loading required libraries. If there is an ongoing installation please wait for it to
//     complete. Otherwise reinstall. (dlopen(@rpath/libxcodebuildLoader.dylib, 1):
//       Symbol not found: _$sSo12NSFileHandleC10FoundationE5write10contentsOfyx_tKAC12DataProtocolRzlF
//       Referenced from: .../DVTInstrumentsFoundation.framework/Versions/A/DVTInstrumentsFoundation
//         (which was built for Mac OS X 14.0)
//       Expected in: /System/Library/Frameworks/Foundation.framework/Versions/C/Foundation
//     )                                                                  [measured 2026-10-12]
//
// "Expected in: .../Foundation.framework/..." is the ordinal's blame text, not the file that must
// change: Darling's Foundation.framework is the Objective-C framework, it re-exports
// /usr/lib/swift/libswiftFoundation.dylib, and this module is that dylib -- the same mechanism the
// Morphology rung used.
//
// WHAT THE CLIENT DOES WITH IT (measured from the demanding image's own bind table, not assumed).
// The one symbol it binds for this API is the GENERIC entry point above; it binds NO specialization
// of it (Apple declares the two specializations `exported: false`, so no client can name them, and
// this image names none). What it binds besides is `_$s10Foundation4DataVAA0B8ProtocolAAMc`, the
// accessor for Foundation.Data's DataProtocol conformance, together with Data's metadata
// (`_$s10Foundation4DataVN`, `_$s10Foundation4DataVMn`): the call passes a Foundation.Data and the
// conformance witness table supplies `regions` at run time. The function returns Void and throws, so
// there is no result value to consume beyond the thrown error.
//
// WHERE EVERYTHING COMES FROM (nothing here is invented):
//
//   * The DECLARATION -- spelling, argument label, genericity, `throws` and availability -- is
//     Apple's published API for this module, read out of the guest's own SDK:
//       <Xcode 26.3>/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/
//         Frameworks/Foundation.framework/Modules/Foundation.swiftmodule/arm64e-apple-macos.swiftinterface
//     (line 500, inside `extension Foundation.FileHandle`:
//        @available(macOS 10.15.4, iOS 13.4, watchOS 6.2, tvOS 13.4, *)
//        @_specialize(exported: false, kind: full, where T == Foundation.Data)
//        @_specialize(exported: false, kind: full, where T == Dispatch.DispatchData)
//        public func write<T>(contentsOf data: T) throws where T : Foundation.DataProtocol ).
//     Apple's SDK renames that Objective-C class with NS_SWIFT_NAME(FileHandle); Darling's
//     Foundation/NSFileHandle.h does not, so the class this extension names is `NSFileHandle` --
//     the same imported class, as the demanded mangling says (`So12NSFileHandleC`).
//
//   * The BODY is apple/swift-corelibs-foundation `Sources/Foundation/FileHandle.swift`, which
//     implements this exact API for this exact module name (Apache-2.0 with Runtime Library
//     Exception): `write(contentsOf:)` at line 502 walks `data.regions` and hands each region to
//     `_writeBytes(buf:length:)` at line 382, which writes in a loop, retries `EINTR`, and throws
//     `_NSErrorWithErrno(errno, reading: false)` (FoundationErrors.swift:171) on the first failing
//     errno. Those three pieces are reproduced here; the descriptor is read from the class's own
//     Objective-C surface (`fileDescriptor`) because corelibs' implementation reaches internals
//     (`_fd`, `_isPlatformHandleValid`, `_nulldeviceFileHandle`) that this Objective-C class does
//     not have.
//
//   * The NULL DEVICE is handled where corelibs handles it. `+fileHandleWithNullDevice` returns
//     NSNullFileHandle, whose `-fileDescriptor` is -1 and whose `-writeData:` discards the bytes
//     (src/external/foundation/src/NSFileHandle.m), so a negative descriptor is that handle and
//     nothing else: a CLOSED handle raises NSFileHandleOperationException inside `-fileDescriptor`
//     (FAIL_IF_CLOSED) and never reaches the guard below.
//
// WHAT IS HERE NOW, AND WHAT IS STILL NOT (each with its reason, so a later rung reads it as a decision):
//
//   * `read(upToCount:)` and `seekToEnd()` are here: the XCResultKit rung measured Xcode 26.3's
//     Contents/SharedFrameworks/XCResultKit.framework binding both of them eagerly and strongly, and
//     added them over the same descriptor surface `write(contentsOf:)` uses.
//   * `readToEnd()` is here: the XCTHarness rung measured Xcode 26.3's
//     Contents/SharedFrameworks/XCTHarness.framework/Versions/A/XCTHarness binding it eagerly and
//     strongly (its chained-fixups imports[534], lib_ordinal 12 = Foundation, weak_import = 0) and
//     the coverage graph classifying it as `missing` -- absent from the deployed Foundation, its
//     re-exports and every image the process loads, i.e. a name dyld has nothing to bind
//     (`Symbol not found: _$sSo12NSFileHandleC10FoundationE9readToEndAC4DataVSgyKF` is the shape of
//     that failure, reported for whichever unbindable name the loader reaches first);
//     Contents/SharedFrameworks/AppThinning.framework binds the same name. It is the one-line
//     composition Apple's own open source gives it -- corelibs' `readToEnd()` is
//     `try read(upToCount: Int.max)` -- over the `read(upToCount:)` already below, so the null device
//     and the end-of-file answer stay the ones this file already gives.
//   * `offset()` is here: the next-stops-behind-ArgumentParserInternal rung measured Xcode 26.3's
//     Contents/SharedFrameworks/SwiftBuild.framework/.../SWBUtil binding it eagerly and strongly
//     (the Foundation group of that rung's `--cover` list:
//     `_$sSo12NSFileHandleC10FoundationE6offsets6UInt64VyKF`, weak=False eager=True) and the coverage
//     graph classifying it as `missing` -- absent from the deployed Foundation, its re-exports and
//     every image the process loads.  It is added over the same descriptor surface the names above
//     use, which is where the previous rung said a later one would add it.
//   * Apple's two `@_specialize(exported: false, ...)` attributes for `Data` and `DispatchData`.
//     `exported: false` means no client can bind the specializations -- measured: the demanding image
//     binds only the generic entry point plus Data's DataProtocol conformance accessor -- so here
//     they would specialize a function only this module could call, and nothing in this module calls
//     it.
//   * the error's userInfo beyond the underlying POSIX error, and any Objective-C-visible surface
//     (`NSFileHandleOperationException`, the `NSError **` variants): this API is Swift-only and the
//     Objective-C exception path is the framework's own, in NSFileHandle.m.

@_exported import Foundation // Clang module
import Darwin

@available(macOS 10.15.4, iOS 13.4, watchOS 6.2, tvOS 13.4, *)
extension NSFileHandle {

  /// Writes the bytes of the given data to the file handle.
  ///
  /// - Parameter data: the data to write.
  /// - Throws: an `NSError` in the Cocoa error domain naming the failed write, with the `errno` as
  ///   its underlying `NSPOSIXErrorDomain` error.
  public func write<T: DataProtocol>(contentsOf data: T) throws {
    // Darling's Foundation/NSFileHandle.h declares `- (int)fileDescriptor;` as a method (Apple's SDK
    // declares it a readonly property), so the descriptor is read with a call here.
    let descriptor = self.fileDescriptor()
    // The null device is the one handle whose -fileDescriptor is negative, and writing to it
    // discards the bytes; a closed handle raises at -fileDescriptor instead.
    guard descriptor >= 0 else {
      return
    }
    for region in data.regions {
      try region.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
        guard let baseAddress = bytes.baseAddress, bytes.count > 0 else { return }
        try _FileHandleWriteBytes(descriptor, baseAddress, bytes.count)
      }
    }
  }

  /// Reads the data synchronously from the file handle's file descriptor to the end of the file.
  ///
  /// The declaration is Apple's for this module, read out of the guest's own SDK
  /// (Foundation.swiftinterface:486, `@available(macOS 10.15.4, iOS 13.4, watchOS 6.2, tvOS 13.4, *)`
  /// `public func readToEnd() throws -> Foundation.Data?`), and the body is Apple's own open source
  /// for it: corelibs' `Foundation/FileHandle.swift:487` is
  ///
  ///     public func readToEnd() throws -> Data? {
  ///       guard self != FileHandle._nulldeviceFileHandle else { return nil }
  ///       return try read(upToCount: Int.max)
  ///     }
  ///
  /// -- the null-device answer and the `Int.max` read are both already the ones `read(upToCount:)`
  /// below gives for this class (it answers `nil` for a negative descriptor and reads to end of file
  /// with a 64 KiB buffer), so this is the same composition and not a second implementation.
  ///
  /// Measured client use, so the contract is the one the caller relies on: XCTHarness's
  /// `invokeXCRun` reads a finished child process's captured output with this call (XCTHarness
  /// 0x93f44, receiver = the NSFileHandle it took from the task's pipe at 0x93f30, no arguments),
  /// decodes the returned bytes as UTF-8 (`Data.withContiguousStorageIfAvailable` +
  /// `String(decoding:as:UTF8)`, XCTHarness 0x94036) and destroys the returned value itself
  /// (`Data.SgWOe`, XCTHarness 0x94050): the `Data?` is owned by the caller, and a thrown error is
  /// propagated by the enclosing closure (`swift_allocError`/`swift_willThrow`, XCTHarness 0x93ef4).
  public func readToEnd() throws -> Data? {
    return try read(upToCount: Int.max)
  }

  /// Reads data synchronously up to the specified number of bytes.
  ///
  /// Reads from the handle's file descriptor until `count` bytes have been read or the end of the file
  /// is reached, retrying `EINTR`; the bytes read so far are returned, and a read that is already at
  /// end of file answers `nil` -- the same contract corelibs' `read(upToCount:)` (FileHandle.swift:494)
  /// gives through `_readDataOfLength(_:untilEOF:)`.
  public func read(upToCount count: Int) throws -> Data? {
    let descriptor = self.fileDescriptor()
    // The null device: -fileDescriptor is -1 and a read from it is the empty result, as corelibs
    // answers for its own null-device handle.
    guard descriptor >= 0 else {
      return nil
    }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: min(max(count, 1), 65536))
    while data.count < count {
      let want = min(buffer.count, count - data.count)
      let bytesRead = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, want) }
      if bytesRead < 0 {
        if errno == EINTR { continue }
        throw _FileHandleReadError(errno)
      }
      if bytesRead == 0 {
        break // end of file
      }
      data.append(contentsOf: buffer[0..<bytesRead])
    }
    return data.isEmpty ? nil : data
  }

  /// Returns the file handle's file descriptor's offset, in bytes.
  ///
  /// Declaration: Apple's published API for this module, read out of the guest's own SDK
  /// (`Foundation.swiftinterface:493`, in `extension Foundation.FileHandle`:
  /// `@available(macOS 10.15.4, iOS 13.4, watchOS 6.2, tvOS 13.4, *)`
  /// `public func offset() throws -> Swift.UInt64`).  Darling's Foundation/NSFileHandle.h does not
  /// rename the class with NS_SWIFT_NAME, so the class this extension names is `NSFileHandle` -- the
  /// same imported class, as the demanded mangling says (`So12NSFileHandleC`).
  ///
  /// The body is Apple's own open source for this API, corelibs'
  /// `Sources/Foundation/FileHandle.swift:517-533`: POSIX `lseek(_fd, 0, SEEK_CUR)` with the failing
  /// errno reported through `_NSErrorWithErrno(_:reading: true)`, and the null device answered with 0
  /// before the descriptor is used.  As in `write(contentsOf:)` above, the descriptor comes from the
  /// class's own Objective-C surface (`fileDescriptor()`), because corelibs' implementation reaches
  /// internals (`_fd`, `_isPlatformHandleValid`, `_nulldeviceFileHandle`) that this Objective-C class
  /// does not have; a negative descriptor is that null device and nothing else (a closed handle raises
  /// NSFileHandleOperationException inside `-fileDescriptor`, src/external/foundation/src/NSFileHandle.m),
  /// and the error mapping is this file's `_FileHandleReadError`.
  public func offset() throws -> UInt64 {
    let descriptor = self.fileDescriptor()
    // The null device: -fileDescriptor is -1 and its offset is 0, as corelibs answers for its own
    // null-device handle.
    guard descriptor >= 0 else {
      return 0
    }
    let offset = lseek(descriptor, 0, SEEK_CUR)
    guard offset >= 0 else {
      throw _FileHandleReadError(errno)
    }
    return UInt64(offset)
  }

  /// Returns the offset of the end of the file, in bytes, and moves the handle there.
  ///
  /// corelibs' `seekToEnd()` (FileHandle.swift:537) is `lseek(_fd, 0, SEEK_END)` with the failing errno
  /// reported; the descriptor comes from the class's Objective-C surface here, as in `write(contentsOf:)`
  /// above.
  @discardableResult
  public func seekToEnd() throws -> UInt64 {
    let descriptor = self.fileDescriptor()
    guard descriptor >= 0 else {
      return 0
    }
    let offset = lseek(descriptor, 0, SEEK_END)
    guard offset >= 0 else {
      throw _FileHandleReadError(errno)
    }
    return UInt64(offset)
  }
}

// corelibs Foundation/FileHandle.swift `_writeBytes(buf:length:)` with the descriptor passed in:
// write until the whole region is out, retry EINTR, report the first failing errno.
private func _FileHandleWriteBytes(_ descriptor: Int32, _ buffer: UnsafeRawPointer, _ length: Int) throws {
  var bytesRemaining = length
  while bytesRemaining > 0 {
    var bytesWritten = 0
    repeat {
      bytesWritten = Darwin.write(descriptor, buffer.advanced(by: length - bytesRemaining), bytesRemaining)
    } while bytesWritten < 0 && errno == EINTR
    if bytesWritten <= 0 {
      throw _FileHandleWriteError(errno)
    }
    bytesRemaining -= bytesWritten
  }
}

// corelibs Foundation/FoundationErrors.swift `_NSErrorWithErrno(_:reading: true)`, over the codes
// CocoaError.swift declares; each names the NSFile*Read*Error constant of the SDK's
// Foundation/FoundationErrors.h.
private func _FileHandleReadError(_ code: Int32) -> NSError {
  let cocoaCode: CocoaError.Code
  switch code {
  case EFBIG: cocoaCode = .fileReadTooLarge
  case ENOENT: cocoaCode = .fileReadNoSuchFile
  case EPERM, EACCES: cocoaCode = .fileReadNoPermission
  default: cocoaCode = .fileReadUnknown
  }
  let underlying = NSError(domain: NSPOSIXErrorDomain, code: Int(code))
  return NSError(domain: NSCocoaErrorDomain,
                 code: cocoaCode.rawValue,
                 userInfo: [NSUnderlyingErrorKey: underlying])
}

private func _FileHandleWriteError(_ code: Int32) -> NSError {
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
  let underlying = NSError(domain: NSPOSIXErrorDomain, code: Int(code))
  return NSError(domain: NSCocoaErrorDomain,
                 code: cocoaCode.rawValue,
                 userInfo: [NSUnderlyingErrorKey: underlying])
}
