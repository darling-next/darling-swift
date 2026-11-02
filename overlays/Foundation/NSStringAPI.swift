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

// String.Encoding and the NSString-backed String/StringProtocol APIs apps import, based on release/5.4
// stdlib/public/Darwin/Foundation/NSStringEncodings.swift and NSStringAPI.swift.
// Darling:
// - Current SDKs declare these on an unconstrained `extension StringProtocol` taking `Range<String.Index>` (that's how
//   apps' symbols are mangled), not on the 5.4 overlay's `where Index == String.Index` extension, so index
//   conversions go through the UTF-16 view of the receiver.
// - Darling's NSString lacks -stringByAddingPercentEncodingWithAllowedCharacters:, -stringByRemovingPercentEncoding
//   and the localized case properties, so those are implemented in Swift. Its selectors import with their ObjC
//   spellings (uppercaseString(with:), componentsSeparatedByCharacters(in:), data(usingEncoding:)).
// - `init?<S: Sequence>(bytes:encoding:)` is back, verbatim from the release/5.4 file above, because an
//   image in the ladder binds its generic entry point and the reduced tree had dropped it (the
//   DVTFoundation rung; ../DARLING-CHANGES.md).
// - `appendingFormat(_:_:)` is back for the same reason: Xcode 26.3's VoiceBoxClient.framework binds
//   its generic entry point strongly and eagerly, from its Foundation ordinal, and no caller inlines
//   it (the VoiceBoxClient rung; ../DARLING-CHANGES.md).
// - `init(contentsOf: URL)` and `folding(options:locale:)` are back for the same reason: Xcode 26.3's
//   DVTSmartSearch.framework binds both strongly and eagerly from its Foundation ordinal, and no
//   caller inlines them (the contentsOf-URL rung; ../DARLING-CHANGES.md).
// - `decomposedStringWithCanonicalMapping`, `init(contentsOf:usedEncoding:)`, `init?(utf8String:)`
//   and `paragraphRange(for:)` are back for the same reason: Xcode 26.3's DNTDocumentationSupport and
//   IDEFoundation bind them strongly and eagerly from their Foundation ordinal, and no caller inlines
//   them (the payload-queue rung; ../DARLING-CHANGES.md).
// - `precomposedStringWithCanonicalMapping` is here for the same reason: it is one of the eleven
//   Foundation names the next-stops-behind-ArgumentParserInternal rung owes (its property doc comment
//   records the Form KD defect this bridge faithfully reports from src/external/foundation).

@_exported import Foundation // Clang module
import CoreFoundation // for the CFStringTransform bridge behind applyingTransform(_:reverse:)

extension String {
  public struct Encoding : RawRepresentable {
    public var rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let ascii = Encoding(rawValue: 1)
    public static let nextstep = Encoding(rawValue: 2)
    public static let japaneseEUC = Encoding(rawValue: 3)
    public static let utf8 = Encoding(rawValue: 4)
    public static let isoLatin1 = Encoding(rawValue: 5)
    public static let symbol = Encoding(rawValue: 6)
    public static let nonLossyASCII = Encoding(rawValue: 7)
    public static let shiftJIS = Encoding(rawValue: 8)
    public static let isoLatin2 = Encoding(rawValue: 9)
    public static let unicode = Encoding(rawValue: 10)
    public static let windowsCP1251 = Encoding(rawValue: 11)
    public static let windowsCP1252 = Encoding(rawValue: 12)
    public static let windowsCP1253 = Encoding(rawValue: 13)
    public static let windowsCP1254 = Encoding(rawValue: 14)
    public static let windowsCP1250 = Encoding(rawValue: 15)
    public static let iso2022JP = Encoding(rawValue: 21)
    public static let macOSRoman = Encoding(rawValue: 30)
    public static let utf16 = Encoding.unicode
    public static let utf16BigEndian = Encoding(rawValue: 0x90000100)
    public static let utf16LittleEndian = Encoding(rawValue: 0x94000100)
    public static let utf32 = Encoding(rawValue: 0x8c000100)
    public static let utf32BigEndian = Encoding(rawValue: 0x98000100)
    public static let utf32LittleEndian = Encoding(rawValue: 0x9c000100)
  }

  public typealias EnumerationOptions = NSStringEnumerationOptions
  public typealias CompareOptions = NSStringCompareOptions
}

extension StringProtocol {
  /// Encodes a string or substring with the requested NSString encoding.
  public func data(using encoding: String.Encoding, allowLossyConversion: Bool = false) -> Data? {
    let string = String(self)
    if encoding == .utf8 {
      return Data(string.utf8)
    }
    guard let encoded = string._bridgeToObjectiveC().data(
      usingEncoding: encoding.rawValue,
      allowLossyConversion: allowLossyConversion
    ) else {
      return nil
    }
    return encoded
  }
}

extension String.Encoding : Hashable {
  public var hashValue: Int {
    return rawValue.hashValue
  }

  @_alwaysEmitIntoClient
  public func hash(into hasher: inout Hasher) {
    hasher.combine(rawValue)
  }

  public static func ==(lhs: String.Encoding, rhs: String.Encoding) -> Bool {
    return lhs.rawValue == rhs.rawValue
  }
}

extension String.Encoding : CustomStringConvertible {
  // Darling: NSString has no +localizedNameOfStringEncoding:, so the raw value is shown.
  public var description: String {
    return "String.Encoding(rawValue: \(rawValue))"
  }
}

extension String {
  /// Returns a human-readable name for the given encoding.
  ///
  /// Darling: the name comes from CoreFoundation's own encoding table --
  /// `CFStringGetNameOfEncoding(CFStringConvertNSStringEncodingToEncoding(...))` -- which is the
  /// machinery swift-corelibs-foundation's `NSString.localizedName(of:)` uses
  /// (src/external/corefoundation/submodules/swift-corelibs-foundation/Sources/Foundation/NSString.swift:1073,
  /// whose own TODO records this same gap), so the string is the encoding's CANONICAL name and not a
  /// name localized for the current locale: upstream's localized variant reads that from a Foundation
  /// bundle this tree does not carry.  This is the Darwin ABI's function (Xcode 26.3's SWBCore binds
  /// it strongly and eagerly), and returning CoreFoundation's name is the real behaviour available
  /// here rather than a constant or an empty stub.  An encoding CoreFoundation cannot name yields ""
  /// exactly as upstream does.  Darwin's own route through +[NSString localizedNameOfStringEncoding:]
  /// is still absent from this tree (see the description comment above), and the localized variant is
  /// documented as the gap rather than faked.
  public static func localizedName(of encoding: Encoding) -> String {
    guard let name = CFStringGetNameOfEncoding(
      CFStringConvertNSStringEncodingToEncoding(encoding.rawValue)
    ) else {
      return ""
    }
    return name as String
  }
}

extension String {
  /// Returns a `String` initialized by converting given `data` into
  /// Unicode characters using a given `encoding`.
  public init?(data: __shared Data, encoding: Encoding) {
    guard let s = NSString(data: data, encoding: encoding.rawValue) else { return nil }
    self = String._unconditionallyBridgeFromObjectiveC(s)
  }

  /// Creates a new string equivalent to the given bytes interpreted in the
  /// specified encoding.
  ///
  /// - Parameters:
  ///   - bytes: A sequence of bytes to interpret using `encoding`.
  ///   - encoding: The encoding to use to interpret `bytes`.
  public init?<S: Sequence>(bytes: __shared S, encoding: Encoding) where S.Iterator.Element == UInt8 {
    let byteArray = Array(bytes)
    if encoding == .utf8, let str = byteArray.withUnsafeBufferPointer({ String._tryFromUTF8($0) }) {
      self = str
      return
    }
    if let ns = NSString(bytes: byteArray, length: byteArray.count, encoding: encoding.rawValue) {
      self = String._unconditionallyBridgeFromObjectiveC(ns)
    } else {
      return nil
    }
  }

  /// Produces a string containing the bytes in a given C array,
  /// interpreted according to a given encoding.
  public init?(cString: UnsafePointer<CChar>, encoding enc: Encoding) {
    if enc == .utf8, let str = String(validatingCString: cString) {
      self = str
      return
    }
    guard let ns = NSString(cString: cString, encoding: enc.rawValue) else { return nil }
    self = String._unconditionallyBridgeFromObjectiveC(ns)
  }

  /// Produces a string by copying the data from a given null-terminated C array of UTF8-encoded
  /// bytes.
  ///
  /// Declaration: the guest SDK's `Foundation.swiftinterface` line 22516, in its `extension
  /// Swift.String` block: `public init?(utf8String bytes: Swift.UnsafePointer<Swift.CChar>)`.  Body
  /// verbatim from the release/5.4 Darwin overlay this file is based on
  /// (`stdlib/public/Darwin/Foundation/NSStringAPI.swift`), which is also what the in-tree copy of
  /// that file carries (`swift-corelibs-foundation/Sources/Foundation/NSStringAPI.swift:180-191`):
  /// it first asks the stdlib's `String(validatingUTF8:)` (which rejects a non-UTF8 or
  /// non-null-terminated buffer), then falls back to `-[NSString initWithUTF8String:]`
  /// (src/external/foundation/src/NSString.m:735), so the result is a real decode of the bytes or
  /// nil -- never a wrong string.
  public init?(utf8String bytes: UnsafePointer<CChar>) {
    if let str = String(validatingUTF8: bytes) {
      self = str
      return
    }
    if let ns = NSString(utf8String: bytes) {
      self = String._unconditionallyBridgeFromObjectiveC(ns)
    } else {
      return nil
    }
  }

  /// Produces a string containing the bytes in a given buffer, interpreted according to a given encoding,
  /// without copying the buffer. Deprecated by the SDK, which is why the declaration the guest SDK's
  /// Foundation.swiftinterface carries for it (x86_64-apple-macos line 22572) is deprecated too.
  @available(macOS, deprecated: 13, message: "String does not support no-copy initialization")
  @available(iOS, deprecated: 16, message: "String does not support no-copy initialization")
  @available(tvOS, deprecated: 16, message: "String does not support no-copy initialization")
  @available(watchOS, deprecated: 9, message: "String does not support no-copy initialization")
  public init?(bytesNoCopy bytes: UnsafeMutableRawPointer, length: Int, encoding: Encoding, freeWhenDone flag: Bool) {
    guard let ns = NSString(bytesNoCopy: bytes, length: length, encoding: encoding.rawValue, freeWhenDone: flag) else {
      return nil
    }
    self = String._unconditionallyBridgeFromObjectiveC(ns)
  }

  /// Creates a new string that contains the specified number of characters from the given C array of
  /// Unicode characters.
  public init(utf16CodeUnits: UnsafePointer<unichar>, count: Int) {
    self = String._unconditionallyBridgeFromObjectiveC(NSString(characters: utf16CodeUnits, length: count))
  }

  /// Produces a string created by reading data from the file at a
  /// given path interpreted using a given encoding.
  ///
  /// Body verbatim from the release/5.4 Darwin overlay this file is based on
  /// (`stdlib/public/Darwin/Foundation/NSStringAPI.swift`), which is also what the in-tree copy
  /// of that file carries (`swift-corelibs-foundation/Sources/Foundation/NSStringAPI.swift:343`):
  /// the read is Darling's own, over `-[NSString initWithContentsOfFile:encoding:error:]`
  /// (src/external/foundation/src/NSString.m:826, a real read of the file's bytes), and the only
  /// work here is the bridge. A file that cannot be read throws the `NSError` that initializer
  /// produced rather than returning a wrong string.
  public init(contentsOfFile path: __shared String, encoding enc: Encoding) throws {
    let ns = try NSString(contentsOfFile: path, encoding: enc.rawValue)
    self = String._unconditionallyBridgeFromObjectiveC(ns)
  }

  /// Produces a string created by reading data from the file at a given path, letting the
  /// file's own contents decide the encoding.
  ///
  /// Declaration: the guest SDK's `Foundation.swiftinterface` line 22584, in its `extension
  /// Swift.String` block — `public init(contentsOfFile path: __shared Swift.String) throws`,
  /// `@available(macOS, deprecated: 15, message: "Use `init(contentsOfFile:encoding:)` instead")`
  /// (and the iOS 18 / tvOS 18 / watchOS 11 twin of that attribute).  Deprecated by the SDK, not
  /// removed: Xcode 26.3's XCTDaemonControlMobileDevice binds it STRONGLY and eagerly from its
  /// Foundation field (ordinal 7), so a runtime without it cannot load that image at all.
  ///
  /// Body from the in-tree swift-corelibs-foundation reference
  /// (`swift-corelibs-foundation/Sources/Foundation/NSStringAPI.swift:369-372`), which is the same
  /// file this overlay's NSString API comes from: `NSString(contentsOfFile:usedEncoding:)` with a
  /// nil `usedEncoding`, then the bridge.  Apple's own implementation is the same two steps — its
  /// Swift-5.0 back-deployment overlay
  /// (`XcodeDefault.xctoolchain/usr/lib/swift-5.0/macosx/libswiftFoundation.dylib`, x86_64,
  /// `_$sSS10FoundationE14contentsOfFileS2Sh_tKcfC` at vm 0xbdb90) retains the path, passes
  /// `%edx = 0` as the `usedEncoding` argument and then calls `Swift.String._cocoaString(_:)`.
  ///
  /// The read is Darling's own, over `-[NSString initWithContentsOfFile:usedEncoding:error:]`
  /// (src/external/foundation/src/NSString.m:1015, which reads the file's bytes through
  /// `_NSReadBytesFromFile` and detects the encoding in
  /// `_initWithBytesOfUnknownEncoding:length:copy:usedEncoding:`, tolerating a NULL `usedEncoding`
  /// at NSString.m:968), so a file that cannot be read throws the `NSError` that initializer
  /// produced rather than returning a wrong string.
  @available(macOS, deprecated: 15, message: "Use `init(contentsOfFile:encoding:)` instead")
  @available(iOS, deprecated: 18, message: "Use `init(contentsOfFile:encoding:)` instead")
  @available(tvOS, deprecated: 18, message: "Use `init(contentsOfFile:encoding:)` instead")
  @available(watchOS, deprecated: 11, message: "Use `init(contentsOfFile:encoding:)` instead")
  public init(contentsOfFile path: __shared String) throws {
    let ns = try NSString(contentsOfFile: path, usedEncoding: nil)
    self = String._unconditionallyBridgeFromObjectiveC(ns)
  }

  /// Produces a string created by reading data from a given URL interpreted using a given encoding.
  ///
  /// Declaration: the guest SDK's `Foundation.swiftinterface` line 15520, in its `extension
  /// Swift.String` block: `public init(contentsOf url: __shared Foundation.URL, encoding enc:
  /// Swift.String.Encoding) throws`.  Body verbatim from the release/5.4 Darwin overlay this file is
  /// based on (`stdlib/public/Darwin/Foundation/NSStringAPI.swift`), which is also what the in-tree
  /// copy of that file carries (`swift-corelibs-foundation/Sources/Foundation/NSStringAPI.swift:384-390`):
  /// the read is Darling's own, over `-[NSString initWithContentsOfURL:encoding:error:]`
  /// (src/external/foundation/src/NSString.m), a real read of the URL's bytes decoded with the given
  /// encoding, and the only work here is the bridge.  A URL that cannot be read, or whose bytes are
  /// not valid in that encoding, throws the `NSError` that initializer produced rather than returning
  /// a wrong string.
  public init(contentsOf url: __shared URL, encoding enc: Encoding) throws {
    let ns = try NSString(contentsOf: url, encoding: enc.rawValue)
    self = String._unconditionallyBridgeFromObjectiveC(ns)
  }

  /// Produces a string created by reading data from a given URL and returns by reference the
  /// encoding used to interpret the data.
  ///
  /// Declaration: the guest SDK's `Foundation.swiftinterface` line 15522, in its `extension
  /// Swift.String` block: `public init(contentsOf url: __shared Foundation.URL, usedEncoding: inout
  /// Swift.String.Encoding) throws`.  Body verbatim from the release/5.4 Darwin overlay this file is
  /// based on (`stdlib/public/Darwin/Foundation/NSStringAPI.swift`), which is also what the in-tree
  /// copy of that file carries (`swift-corelibs-foundation/Sources/Foundation/NSStringAPI.swift:397-408`):
  /// the read is Darling's own, over `-[NSString initWithContentsOfURL:usedEncoding:error:]`
  /// (src/external/foundation/src/NSString.m:990, a real read of the URL's bytes with BOM/ICU
  /// encoding detection through `_initWithBytesOfUnknownEncoding:length:copy:usedEncoding:`), and
  /// this reports the detected encoding back through the `inout` argument rather than discarding it.
  /// A URL that cannot be read throws the `NSError` that initializer produced rather than returning
  /// a wrong string.
  public init(contentsOf url: __shared URL, usedEncoding: inout Encoding) throws {
    var enc: UInt = 0
    let ns = try NSString(contentsOf: url, usedEncoding: &enc)
    usedEncoding = Encoding(rawValue: enc)
    self = String._unconditionallyBridgeFromObjectiveC(ns)
  }

  /// Produces a string created by reading data from the file at a given URL, detecting the encoding.
  ///
  /// Declaration: the guest SDK's `Foundation.swiftinterface` line 22589, in its `extension
  /// Swift.String` block: `public init(contentsOf url: __shared Foundation.URL) throws` (deprecated
  /// there in favour of `contentsOf:encoding:`, which is the overload next to it).  Body verbatim
  /// from the release/5.4 Darwin overlay this file is based on
  /// (`stdlib/public/Darwin/Foundation/NSStringAPI.swift`, the `contentsOf:` overload that passes
  /// `usedEncoding: nil`), which is also what the in-tree copy of that file carries
  /// (`swift-corelibs-foundation/Sources/Foundation/NSStringAPI.swift:408-414`): the read is
  /// Darling's own, over `-[NSString initWithContentsOfURL:usedEncoding:error:]`
  /// (src/external/foundation/src/NSString.m:990, a real read of the URL's bytes with BOM/ICU
  /// encoding detection through `_initWithBytesOfUnknownEncoding:...`), and the only work here is
  /// the bridge.  The detected encoding is not reported, exactly as upstream.  A URL that cannot be
  /// read throws the `NSError` that initializer produced rather than returning a wrong string.
  public init(contentsOf url: __shared URL) throws {
    let ns = try NSString(contentsOf: url, usedEncoding: nil)
    self = String._unconditionallyBridgeFromObjectiveC(ns)
  }

  /// Returns a `String` object initialized by using a given
  /// format string as a template into which the remaining argument
  /// values are substituted according to given locale information.
  public init(format: __shared String, locale: __shared Locale?, _ args: CVarArg...) {
    self = String(format: format, locale: locale, arguments: args)
  }

  /// Returns a `String` object initialized by using a given
  /// format string as a template into which the remaining argument
  /// values are substituted according to given locale information.
  public init(format: __shared String, locale: __shared Locale?, arguments: __shared [CVarArg]) {
    self = withVaList(arguments) {
      NSString(format: format, locale: locale, arguments: $0) as String
    }
  }

  /// Returns a `Data` containing a representation of
  /// the `String` encoded using a given encoding.
  public func data(using encoding: Encoding, allowLossyConversion: Bool = false) -> Data? {
    if encoding == .utf8 {
      return Data(self.utf8)
    }
    guard let d = _bridgeToObjectiveC().data(usingEncoding: encoding.rawValue, allowLossyConversion: allowLossyConversion) else {
      return nil
    }
    return d
  }
}

// NSStringCompareOptions values (NSString.h), which Darling's NS_OPTIONS import as a raw-value struct.
private let _caseInsensitiveSearch = NSStringCompareOptions(rawValue: 1)
private let _diacriticInsensitiveSearch = NSStringCompareOptions(rawValue: 128)

extension StringProtocol {
  //===--- Bridging helpers -----------------------------------------------===//

  fileprivate var _ns: NSString {
    return String(self)._bridgeToObjectiveC()
  }

  /// The UTF-16 offset of `index` from the start of `self`.
  fileprivate func _utf16Offset(of index: String.Index) -> Int {
    if let s = self as? Substring {
      return s.utf16.distance(from: s.startIndex, to: index)
    }
    let s = String(self)
    return s.utf16.distance(from: s.startIndex, to: index)
  }

  /// The index of `self` at a UTF-16 offset from its start.
  fileprivate func _index(utf16Offset offset: Int) -> String.Index {
    if let s = self as? Substring {
      return s.utf16.index(s.startIndex, offsetBy: offset)
    }
    let s = String(self)
    return s.utf16.index(s.startIndex, offsetBy: offset)
  }

  fileprivate func _nsRange(_ range: Range<String.Index>?) -> NSRange {
    guard let range = range else {
      return NSRange(location: 0, length: utf16.count)
    }
    let lower = _utf16Offset(of: range.lowerBound)
    return NSRange(location: lower, length: _utf16Offset(of: range.upperBound) - lower)
  }

  fileprivate func _range(_ range: NSRange) -> Range<String.Index>? {
    guard range.location != NSNotFound else { return nil }
    return _index(utf16Offset: range.location)..<_index(utf16Offset: range.location + range.length)
  }

  //===--- Case -------------------------------------------------------------===//

  /// A copy of the string with each word changed to its corresponding capitalized spelling.
  public var capitalized: String {
    return _ns.capitalized()
  }

  /// A capitalized representation of the string that is produced using the current locale.
  public var localizedCapitalized: String {
    return _ns.capitalizedString(with: Locale.current)
  }

  /// A lowercase version of the string that is produced using the current locale.
  public var localizedLowercase: String {
    return _ns.lowercaseString(with: Locale.current)
  }

  /// An uppercase version of the string that is produced using the current locale.
  public var localizedUppercase: String {
    return _ns.uppercaseString(with: Locale.current)
  }

  /// Returns a version of the string with all letters converted to uppercase, taking into account the specified
  /// locale.
  public func uppercased(with locale: Locale?) -> String {
    return _ns.uppercaseString(with: locale)
  }

  /// Returns a capitalized representation of the string using the specified locale.
  public func capitalized(with locale: Locale?) -> String {
    return _ns.capitalizedString(with: locale)
  }

  /// Returns a version of the string with all letters converted to lowercase, taking into account the specified
  /// locale.
  public func lowercased(with locale: Locale?) -> String {
    return _ns.lowercaseString(with: locale)
  }

  //===--- Comparison -------------------------------------------------------===//

  /// Returns the result of invoking `compare:options:` with `NSCaseInsensitiveSearch` as the only option.
  public func caseInsensitiveCompare<T : StringProtocol>(_ aString: T) -> ComparisonResult {
    return _ns.caseInsensitiveCompare(String(aString))
  }

  /// Returns a string containing characters this string and the given string have in common,
  /// starting from the beginning of each up to the first characters that aren't equivalent.
  ///
  /// From the vendored Darwin `NSStringAPI.swift` overlay. Keep the unconstrained
  /// generic declaration; `String(aString)` adapts its `_ephemeralString` bridge
  /// to this file's convention. Comparison and receiver spelling belong to the
  /// native `-[NSString commonPrefixWithString:options:]` implementation.
  public func commonPrefix<T : StringProtocol>(with aString: T, options: String.CompareOptions = []) -> String {
    return _ns.commonPrefix(with: String(aString), options: options)
  }

  /// Compares the string and the given string using a case-insensitive, localized, comparison.
  public func localizedCaseInsensitiveCompare<T : StringProtocol>(_ aString: T) -> ComparisonResult {
    return _ns.localizedCaseInsensitiveCompare(String(aString))
  }

  /// Compares the string and the given string as sorted by the Finder.
  public func localizedStandardCompare<T : StringProtocol>(_ string: T) -> ComparisonResult {
    return _ns.localizedStandardCompare(String(string))
  }

  /// Compares the string using the specified options and returns the lexical ordering for the range.
  public func compare<T : StringProtocol>(
    _ aString: T,
    options mask: String.CompareOptions = String.CompareOptions(rawValue: 0),
    range: Range<String.Index>? = nil,
    locale: Locale? = nil
  ) -> ComparisonResult {
    let other = String(aString)
    if let locale = locale {
      return _ns.compare(other, options: mask, range: _nsRange(range), locale: locale)
    }
    return _ns.compare(other, options: mask, range: _nsRange(range))
  }

  /// Performs string transliteration: the transformation represented by `transform`, or its
  /// inverse when `reverse` is true.
  ///
  /// Back for the same reason as the other entries above: Xcode 26.3's IDEFoundation.framework
  /// binds this generic entry point strongly and eagerly from its Foundation ordinal
  /// (`_$sSy10FoundationE17applyingTransform_7reverseSSSgSo08NSStringC0a_SbtF`) and no caller
  /// inlines it. The engine is the tree's own CoreFoundation -- `CFStringTransform` is ICU's
  /// transliterator and answers the same nil-for-invalid-or-irreversible contract -- because the
  /// tree's ObjC NSString has no `-stringByApplyingTransform:reverse:` to delegate to (the
  /// release/5.4 overlay's body did delegate; that method is not there to call). The ObjC side of
  /// this tree would have exposed exactly this call, so the overlay owes only the bridge.
  @available(macOS 10.11, iOS 9.0, tvOS 9.0, watchOS 2.0, *)
  public func applyingTransform(_ transform: StringTransform, reverse: Bool) -> String? {
    let string = CFStringCreateMutable(kCFAllocatorSystemDefault, 0)!
    CFStringReplaceAll(string, String(self) as CFString)
    guard CFStringTransform(string, nil, transform.rawValue as CFString, reverse) else {
      return nil
    }
    return unsafeBitCast(string, to: NSString.self) as String
  }

  //===--- Searching --------------------------------------------------------===//

  /// Finds and returns the range of the first occurrence of a given string within a given range of the `String`,
  /// subject to given options, using the specified locale, if any.
  public func range<T : StringProtocol>(
    of aString: T,
    options mask: String.CompareOptions = String.CompareOptions(rawValue: 0),
    range searchRange: Range<String.Index>? = nil,
    locale: Locale? = nil
  ) -> Range<String.Index>? {
    let other = String(aString)
    let result: NSRange
    if let locale = locale {
      result = _ns.range(of: other, options: mask, range: _nsRange(searchRange), locale: locale)
    } else {
      result = _ns.range(of: other, options: mask, range: _nsRange(searchRange))
    }
    return _range(result)
  }

  /// Finds and returns the range of the first occurrence of a given string, taking the current locale into account.
  public func localizedStandardRange<T : StringProtocol>(of string: T) -> Range<String.Index>? {
    return range(of: string, options: NSStringCompareOptions(rawValue: _caseInsensitiveSearch.rawValue | _diacriticInsensitiveSearch.rawValue),
                 locale: Locale.current)
  }

  /// Returns `true` if `other` is non-empty and contained within `self` by case-sensitive, non-literal search.
  public func contains<T : StringProtocol>(_ other: T) -> Bool {
    return range(of: other) != nil
  }

  /// Returns a Boolean value indicating whether the given string is non-empty and contained within this string by
  /// case-insensitive, non-literal search, taking into account the current locale.
  public func localizedCaseInsensitiveContains<T : StringProtocol>(_ other: T) -> Bool {
    return range(of: other, options: _caseInsensitiveSearch, locale: Locale.current) != nil
  }

  /// Returns a Boolean value indicating whether the string contains the given string, taking the current locale
  /// into account (case and diacritic insensitive).
  public func localizedStandardContains<T : StringProtocol>(_ string: T) -> Bool {
    return localizedStandardRange(of: string) != nil
  }

  /// Finds and returns the range in the `String` of the first character from a given character set found in a
  /// given range with given options.
  public func rangeOfCharacter(
    from aSet: CharacterSet,
    options mask: String.CompareOptions = String.CompareOptions(rawValue: 0),
    range aRange: Range<String.Index>? = nil
  ) -> Range<String.Index>? {
    return _range(_ns.rangeOfCharacter(from: aSet, options: mask, range: _nsRange(aRange)))
  }

  //===--- Splitting, trimming and replacing ---------------------------------===//

  /// Returns an array containing substrings from the string that have been divided by the given separator.
  public func components<T : StringProtocol>(separatedBy separator: T) -> [String] {
    return (_ns.components(separatedBy: String(separator)) ?? []).compactMap { $0 as? String }
  }

  /// Returns an array containing substrings from the string that have been divided by characters in the given set.
  public func components(separatedBy separator: CharacterSet) -> [String] {
    return (_ns.componentsSeparatedByCharacters(in: separator) ?? []).compactMap { $0 as? String }
  }

  /// Returns a new string made by removing from both ends of the `String` characters contained in a given
  /// character set.
  public func trimmingCharacters(in set: CharacterSet) -> String {
    return _ns.trimmingCharacters(in: set)
  }

  /// Replaces a range relative to this receiver, including a nonzero-based substring.
  /// The SDK's StringProtocol implementation uses these native slices; unlike the
  /// older NSString bridge, this needs neither index rebasing nor an NSString copy.
  @inlinable
  public func replacingCharacters<T: StringProtocol, R: RangeExpression>(
    in range: R, with replacement: T
  ) -> String where R.Bound == String.Index {
    var new = ""
    let r = range.relative(to: self)
    if Substring(self).isContiguousUTF8, Substring(replacement).isContiguousUTF8 {
      let prefix = self.utf8.distance(from: self.startIndex, to: r.lowerBound)
      let suffix = self.utf8.distance(from: r.upperBound, to: self.endIndex)
      new.reserveCapacity(prefix + replacement.utf8.count + suffix)
    }
    new += self[..<r.lowerBound]
    new += replacement
    new += self[r.upperBound...]
    return new
  }

  /// Returns a new string in which all occurrences of a target string in a specified range of the string are
  /// replaced by another given string.
  public func replacingOccurrences<Target : StringProtocol, Replacement : StringProtocol>(
    of target: Target,
    with replacement: Replacement,
    options: String.CompareOptions = String.CompareOptions(rawValue: 0),
    range searchRange: Range<String.Index>? = nil
  ) -> String {
    return _ns.replacingOccurrences(of: String(target), with: String(replacement), options: options,
                                    range: _nsRange(searchRange))
  }

  /// Returns a new string formed from the `String` by either removing characters from the end, or by appending as
  /// many occurrences as necessary of a given pad string.
  public func padding<T : StringProtocol>(toLength newLength: Int, withPad padString: T, startingAt padIndex: Int) -> String {
    return _ns.padding(toLength: newLength, with: String(padString), startingAt: padIndex)
  }

  /// Enumerates hard lines without their terminators, stopping when requested.
  /// Uses the release/5.4 Darwin overlay's callback bridge; Darling's unannotated
  /// NSString header imports the non-null line and stop pointer as optionals.
  public func enumerateLines(
    invoking body: @escaping (_ line: String, _ stop: inout Bool) -> Void
  ) {
    _ns.enumerateLines { line, stop in
      var stop_ = false
      body(line!, &stop_)
      if stop_ {
        stop?.pointee = true
      }
    }
  }

  /// Enumerates the substrings of the specified type in the specified range of the string.
  public func enumerateSubstrings<R : RangeExpression>(
    in range: R,
    options opts: String.EnumerationOptions = String.EnumerationOptions(rawValue: 0),
    _ body: @escaping (_ substring: String?, _ substringRange: Range<String.Index>,
                       _ enclosingRange: Range<String.Index>, inout Bool) -> Void
  ) where R.Bound == String.Index {
    let bounds = (self as? Substring).map { range.relative(to: $0) } ?? range.relative(to: String(self))
    _ns.enumerateSubstrings(in: _nsRange(bounds), options: opts) { substring, substringRange, enclosingRange, stop in
      var stop_ = false
      body(substring, self._range(substringRange)!, self._range(enclosingRange)!, &stop_)
      if stop_ {
        stop?.pointee = true
      }
    }
  }

  /// Returns the range of characters representing the paragraph or paragraphs containing a given range.
  ///
  /// Declaration: the guest SDK's `Foundation.swiftinterface` line 15554, in its `extension
  /// Swift.StringProtocol` block: `public func paragraphRange(for range: some RangeExpression<Index>)
  /// -> Swift.Range<Self.Index>`.  Body verbatim from the release/5.4 Darwin overlay this file is
  /// based on (`stdlib/public/Darwin/Foundation/NSStringAPI.swift`), which is also what the in-tree
  /// copy of that file carries (`swift-corelibs-foundation/Sources/Foundation/NSStringAPI.swift:1633-1637`):
  /// the paragraph scan is Darling's own, over `-[NSString paragraphRangeForRange:]`
  /// (src/external/foundation/src/NSString.m:1615, a real scan of the receiver's characters for the
  /// surrounding paragraph separators), and the only work here is the NSRange <-> `Range<String.Index>`
  /// conversion through this file's own `_nsRange`/`_range` helpers.
  public func paragraphRange<R: RangeExpression>(for aRange: R) -> Range<String.Index> where R.Bound == String.Index {
    return _range(_ns.paragraphRange(for: _nsRange(aRange.relative(to: self))))!
  }

  /// Returns the containing hard-line bounds using NSString's UTF-16 scan.
  /// The Darwin overlay's out-parameter bridge is expressed with this file's
  /// existing relative-index helpers so Substring indices retain their base.
  public func getLineStart<R: RangeExpression>(
    _ start: UnsafeMutablePointer<String.Index>,
    end: UnsafeMutablePointer<String.Index>,
    contentsEnd: UnsafeMutablePointer<String.Index>,
    for range: R
  ) where R.Bound == String.Index {
    let bounds = (self as? Substring).map { range.relative(to: $0) }
      ?? range.relative(to: String(self))
    var lineStart = 0, lineEnd = 0, contents = 0
    _ns.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contents, for: _nsRange(bounds))
    contentsEnd.pointee = _index(utf16Offset: contents)
    end.pointee = _index(utf16Offset: lineEnd)
    start.pointee = _index(utf16Offset: lineStart)
  }

  //===--- Normalization and hashing ----------------------------------------===//

  /// A string created by normalizing the string's contents using Form D.
  ///
  /// Declaration: the guest SDK's `Foundation.swiftinterface` line 22692, in its `extension
  /// Swift.StringProtocol` block: `public var decomposedStringWithCanonicalMapping: Swift.String
  /// { get }`.  Body from the release/5.4 Darwin overlay this file is based on
  /// (`stdlib/public/Darwin/Foundation/NSStringAPI.swift`), which is also what the in-tree copy of
  /// that file carries (`swift-corelibs-foundation/Sources/Foundation/NSStringAPI.swift`): the
  /// normalization is Darling's own, over `-[NSString decomposedStringWithCanonicalMapping]`
  /// (src/external/foundation/src/NSString.m:1777, a real `CFStringNormalize` of a mutable copy of
  /// the receiver with `kCFStringNormalizationFormD`, i.e. canonical decomposition, not a
  /// pass-through), and the only work here is the bridge.  `_ns` is this file's own receiver bridge.
  public var decomposedStringWithCanonicalMapping: String {
    return _ns.decomposedStringWithCanonicalMapping()
  }

  /// A string created by precomposing the string's contents using Form C.
  ///
  /// Declaration: the guest SDK's `Foundation.swiftinterface` line 22711, in its `extension
  /// Swift.StringProtocol` block: `public var precomposedStringWithCanonicalMapping: Swift.String
  /// { get }`.  Body from Apple's own open source for this module
  /// (`swift-corelibs-foundation/Sources/Foundation/NSStringAPI.swift:1060-1065`: the receiver's
  /// `precomposedStringWithCanonicalMapping`), which is also what the in-tree copy of that file
  /// carries, and the only work here is the bridge -- `_ns` is this file's own receiver bridge,
  /// exactly as in the Form D sibling above.
  ///
  /// KNOWN DEFECT BELOW, named rather than worked around or hidden: the normalization is Darling's own
  /// `-[NSString precomposedStringWithCanonicalMapping]`
  /// (src/external/foundation/src/NSString.m:1801-1807), which is a real `CFStringNormalize` of a
  /// mutable copy of the receiver -- but with `kCFStringNormalizationFormKD`, i.e. compatibility
  /// DECOMPOSITION, where Form C (canonical COMPOSITION) is what Apple's API and this name promise
  /// (the sibling `decomposedStringWithCompatibilityMapping` below carries Form C for the same reason,
  /// and `decomposedStringWithCanonicalMapping` above carries the correct Form D).  So this property
  /// answers the tree's normalization, not Apple's: a compatibility-decomposed string.  Bridging is
  /// still the truthful implementation -- it is what this tree does with this API, and a Swift-side
  /// re-normalization would give a client a different answer from the Objective-C one for the same
  /// call -- and the correction belongs in src/external/foundation/src/NSString.m, which this overlay
  /// does not own.
  public var precomposedStringWithCanonicalMapping: String {
    return _ns.precomposedStringWithCanonicalMapping()
  }

  /// A string created by normalizing the string's contents using Form KD.
  public var decomposedStringWithCompatibilityMapping: String {
    return _ns.decomposedStringWithCompatibilityMapping()
  }

  /// Returns a string with the given character folding options applied.
  ///
  /// Declaration: the guest SDK's `Foundation.swiftinterface` line 22734, in its `extension
  /// Swift.StringProtocol` block: `public func folding(options: Swift.String.CompareOptions = [],
  /// locale: Foundation.Locale?) -> Swift.String`.  Body verbatim from the release/5.4 Darwin
  /// overlay this file is based on (`stdlib/public/Darwin/Foundation/NSStringAPI.swift:1055-1059`),
  /// which is also what the in-tree copy of that file carries
  /// (`swift-corelibs-foundation/Sources/Foundation/NSStringAPI.swift:1165-1169`): the fold is
  /// Darling's own, over `-[NSString stringByFoldingWithOptions:locale:]`
  /// (src/external/foundation/src/NSString.m:1766, a real `CFStringFold` over ICU -- case,
  /// diacritic and width folding, not a pass-through), and the only work here is the bridge.  `_ns`
  /// is this file's own receiver bridge.  The ObjC selector imports as `folding(options:locale:)`,
  /// the Swift 3 rename the importer carries for `stringByFoldingWithOptions:locale:`, so the
  /// call below needs no `_ns`-facing exception.
  public func folding(options: String.CompareOptions = [], locale: Locale?) -> String {
    return _ns.folding(options: options, locale: locale)
  }

  /// An unsigned integer that can be used as a hash table address.
  public var hash: Int {
    return _ns.hash
  }

  //===--- Encodings and percent encoding ------------------------------------===//

  /// Returns the number of bytes required to store the receiver in the given encoding.
  ///
  /// Declaration: the guest SDK's Foundation.swiftinterface:22706, in its `extension
  /// Swift.StringProtocol` block: `public func lengthOfBytes(using encoding: Swift.String.Encoding)
  /// -> Swift.Int`.  Body verbatim from the release/5.4 Darwin overlay this file is based on
  /// (`stdlib/public/Darwin/Foundation/NSStringAPI.swift`), which is also what the in-tree copy of
  /// that file carries (`swift-corelibs-foundation/Sources/Foundation/NSStringAPI.swift:999-1001`):
  /// the count is Darling's own, over `-[NSString lengthOfBytesUsingEncoding:]`
  /// (src/external/foundation/src/NSString.m:1683, the real O(n) conversion count), and the only
  /// work here is the bridge and the `NSUInteger` -> `Int` fit.  `_ns` is this file's own receiver
  /// bridge; this tree's SDK carries no apinote for the selector, so it imports with its ObjC
  /// spelling `lengthOfBytes(usingEncoding:)`, as the file header notes for `data(usingEncoding:)`.
  public func lengthOfBytes(using encoding: String.Encoding) -> Int {
    return Int(_ns.lengthOfBytes(usingEncoding: encoding.rawValue))
  }

  /// Returns a representation of the string as a C string using a given encoding.
  public func cString(using encoding: String.Encoding) -> [CChar]? {
    let ns = _ns
    return withExtendedLifetime(ns) {
      guard let p = ns.cString(usingEncoding: encoding.rawValue) else { return nil }
      return Array(UnsafeBufferPointer(start: p, count: strlen(p) + 1))
    }
  }

  /// Returns a new string created by replacing all characters in the string not in the specified set with percent
  /// encoded characters.
  public func addingPercentEncoding(withAllowedCharacters allowedCharacters: CharacterSet) -> String? {
    var result = ""
    for byte in utf8 {
      if byte < 0x80, allowedCharacters.contains(Unicode.Scalar(byte)) {
        result.unicodeScalars.append(Unicode.Scalar(byte))
      } else {
        let hex = String(byte, radix: 16, uppercase: true)
        result += byte < 16 ? "%0" + hex : "%" + hex
      }
    }
    return result
  }

  /// A new string made from the string by replacing all percent encoded sequences with the matching UTF-8
  /// characters.
  public var removingPercentEncoding: String? {
    return _percentDecode(String(self))
  }

  //===--- Appending --------------------------------------------------------===//

  /// Returns a new string created by appending the given string.
  ///
  /// Declaration: the guest SDK's `Foundation.swiftinterface` line 22728, in its `extension
  /// Swift.StringProtocol` block: `@inlinable public func appending(_ other: some StringProtocol)
  /// -> Swift.String`, whose body the interface carries as `var result = String(self);
  /// result.append(contentsOf: other); return result`.  That body is used here verbatim: it is real
  /// concatenation over the receiver and the argument, not a bridge, so there is nothing to defer to
  /// the tree's NSString.  (`_ns.appending(_:)` was the release/5.4 body; the SDK's own inlinable
  /// body is the newer spelling of the same result and is what this overlay carries.)
  @inlinable
  public func appending(_ other: some StringProtocol) -> String {
    var result = String(self)
    result.append(contentsOf: other)
    return result
  }

  /// Returns a string created by appending a string constructed from a given
  /// format string and the following arguments.
  ///
  /// Declaration: the guest SDK's Foundation.swiftinterface:22727, in its `extension
  /// Swift.StringProtocol` block: `public func appendingFormat<T>(_ format: T, _ arguments: any
  /// Swift.CVarArg...) -> Swift.String where T : Swift.StringProtocol`.  Body verbatim from the
  /// release/5.4 Darwin overlay this file is based on (`stdlib/public/Darwin/Foundation/NSStringAPI.swift`),
  /// which is also what the in-tree copy of that file carries
  /// (`swift-corelibs-foundation/Sources/Foundation/NSStringAPI.swift:1144-1152`): both format with
  /// `String(format:arguments:)` and append over `-[NSString stringByAppendingString:]`
  /// (src/external/foundation/src/NSString.m:1256).  `format._ephemeralString` is the in-tree
  /// helper for bridging a `StringProtocol` to `String`, which this overlay spells `String(format)`;
  /// `_ns` is this file's own receiver bridge.
  public func appendingFormat<T: StringProtocol>(_ format: T, _ arguments: CVarArg...) -> String {
    return _ns.appending(String(format: String(format), arguments: arguments))
  }

  //===--- Writing ----------------------------------------------------------===//

  /// Writes the contents of the `String` to the file at the given path using the specified encoding.
  public func write<T: StringProtocol>(
    toFile path: T, atomically useAuxiliaryFile: Bool, encoding enc: String.Encoding
  ) throws {
    try _ns.write(toFile: String(path), atomically: useAuxiliaryFile, encoding: enc.rawValue)
  }

  /// Compares `self` and the given string using a localized comparison.
  public func localizedCompare<T: StringProtocol>(_ aString: T) -> ComparisonResult {
    return _ns.localizedCompare(String(aString))
  }

  /// Writes the contents of the `String` to the URL specified by url using the specified encoding.
  public func write(to url: URL, atomically useAuxiliaryFile: Bool, encoding enc: String.Encoding) throws {
    try _ns.write(to: url, atomically: useAuxiliaryFile, encoding: enc.rawValue)
  }
}
