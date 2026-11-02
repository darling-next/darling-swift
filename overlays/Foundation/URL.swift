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

// URL, from release/5.4 stdlib/public/Darwin/Foundation/URL.swift.
// Darling: NSURL's accessors are methods returning implicitly unwrapped values, resource values, bookmarks and
// promised items are omitted (Darling's NSURL doesn't implement them), and the path-appending API from newer SDKs
// (DirectoryHint, appending(path:directoryHint:), appending(component:directoryHint:), path(percentEncoded:)) is
// written on top of the NSURL methods and CFURL functions. init?(string:encodingInvalidCharacters:) is the same:
// its strict branch is this tree's URLComponents, because Darling's NSURL has no encodingInvalidCharacters.

@_exported import Foundation // Clang module
internal import _FoundationICU

// Adapted from pinned swift-foundation URLParser+ICU.swift (2024 Apple Inc.,
// Apache-2.0 with Runtime Library Exception): the thread-safe UTS46 singleton,
// decoding error policy, and bounded UTF-8 conversion. The existing URLComponents
// parser remains the authority for component boundaries and percent encoding.
private enum _URLIDNA {
    private static let transcoder: OpaquePointer? = {
        var status = U_ZERO_ERROR
        let options = UInt32(UIDNA_CHECK_BIDI | UIDNA_CHECK_CONTEXTJ
            | UIDNA_NONTRANSITIONAL_TO_UNICODE | UIDNA_NONTRANSITIONAL_TO_ASCII)
        let result = uidna_openUTS46(options, &status)
        return status.rawValue <= 0 ? result : nil
    }()

    static func unicodeHost(_ host: String) -> String? {
        var window: UInt32 = 0
        var hasPunycode = false
        for byte in host.utf8 {
            window = (window << 8) | UInt32(byte | 0x20)
            if window == 0x786e2d2d {
                hasPunycode = true
                break
            }
        }
        guard hasPunycode, let transcoder = transcoder else { return nil }
        var input = host
        return input.withUTF8 { bytes in
            guard bytes.count <= 2048 else { return nil }
            return bytes.withMemoryRebound(to: CChar.self) { source in
                withUnsafeTemporaryAllocation(of: CChar.self, capacity: 2048) { output in
                    var info = UIDNAInfo(size: Int16(MemoryLayout<UIDNAInfo>.size),
                        isTransitionalDifferent: 0, reservedB3: 0, errors: 0,
                        reservedI2: 0, reservedI3: 0)
                    var status = U_ZERO_ERROR
                    let count = uidna_nameToUnicodeUTF8(transcoder, source.baseAddress,
                        Int32(source.count), output.baseAddress, Int32(output.count), &info, &status)
                    let allowed = UInt32(UIDNA_ERROR_EMPTY_LABEL | UIDNA_ERROR_LABEL_TOO_LONG
                        | UIDNA_ERROR_DOMAIN_NAME_TOO_LONG | UIDNA_ERROR_LEADING_HYPHEN
                        | UIDNA_ERROR_TRAILING_HYPHEN | UIDNA_ERROR_HYPHEN_3_4)
                    guard status.rawValue <= 0, info.errors & ~allowed == 0,
                          count > 0, count <= output.count else { return nil }
                    return UnsafeBufferPointer(start: output.baseAddress!, count: Int(count))
                        .withMemoryRebound(to: UInt8.self) { decoded in
                            if decoded.count == bytes.count,
                               zip(bytes, decoded).allSatisfy({ original, converted in
                                   original == converted
                                       || (original >= 65 && original <= 90 && original + 32 == converted)
                               }) {
                                return host
                            }
                            return String(validating: decoded, as: UTF8.self)
                        }
                }
            }
        }
    }
}

public struct URL : ReferenceConvertible, Equatable {
    public typealias ReferenceType = NSURL
    private var _url: NSURL

    /// Initialize with string.
    ///
    /// Returns `nil` if a `URL` cannot be formed with the string (for example, if the string contains characters that are illegal in a URL, or is an empty string).
    public init?(string: __shared String) {
        guard !string.isEmpty, let inner = NSURL(string: string) else { return nil }
        _url = URL._converted(from: inner)
    }

    /// Initialize with string, relative to another URL.
    ///
    /// Returns `nil` if a `URL` cannot be formed with the string (for example, if the string contains characters that are illegal in a URL, or is an empty string).
    public init?(string: __shared String, relativeTo url: __shared URL?) {
        guard !string.isEmpty, let inner = NSURL(string: string, relativeTo: url) else { return nil }
        _url = URL._converted(from: inner)
    }

    /// Initialize with a URL string and the option to add (or skip) IDNA- and percent-encoding of invalid characters.
    ///
    /// If `encodingInvalidCharacters` is false, and the URL string is invalid according to RFC 3986, `nil` is returned.
    /// If `encodingInvalidCharacters` is true, `URL` will try to encode the string to create a valid URL.
    /// If the URL string is still invalid after encoding, `nil` is returned.
    ///
    /// - parameter string: A URL location.
    /// - parameter encodingInvalidCharacters: A Boolean value that indicates whether the initializer attempts to encode any invalid characters in `string`.
    @available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
    public init?(string: __shared String, encodingInvalidCharacters: Bool) {
        guard !string.isEmpty else { return nil }
        if encodingInvalidCharacters {
            // Apple's body is `URL._type.init(string:encodingInvalidCharacters:)` -- NSURL's, whose own doc
            // comment says it "will try to encode the string to create a valid URL". Darling's NSURL (and its
            // whole Foundation and CoreFoundation) has no `encodingInvalidCharacters` anywhere, so the encoding
            // branch is the tree's plain URL-string parser, the same NSURL(string:) the initializer above uses.
            guard let inner = NSURL(string: string) else { return nil }
            _url = URL._converted(from: inner)
        } else {
            // Strict: characters are left as they are and none is encoded, and an RFC 3986-invalid string gives
            // `nil`. This tree's URLComponents parses and validates exactly that (its _isValidPercentEncoded), and
            // `url` is the URL those components form -- the same route `appending(queryItems:)` below takes.
            guard let components = URLComponents(string: string), let url = components.url else { return nil }
            self = url
        }
    }

    /// Initializes a URL from a data representation, optionally resolving it against a base URL.
    ///
    /// Declaration: the guest SDK's `Foundation.swiftinterface` line 16349, in the `URL` extension:
    /// `public init?(dataRepresentation: __shared Foundation.Data, relativeTo base: __shared Foundation.URL?,
    /// isAbsolute: Swift.Bool = false)`.  The in-tree Swift implementation
    /// (`swift-corelibs-foundation/Sources/Foundation/URL.swift:541-548`) wraps
    /// `-[NSURL initWithDataRepresentation:relativeToURL:]` and `+[NSURL absoluteURLWithDataRepresentation:relativeToURL:]`,
    /// which are CoreFoundation's `CFURLCreateWithBytes` and `CFURLCreateAbsoluteURLWithBytes`
    /// (`submodules/swift-corelibs-foundation/CoreFoundation/URL.subproj/CFURL.c:2471,2537`).  Darling's `NSURL`
    /// declares neither initializer, so those CFURL functions are called directly: they turn the bytes into the URL
    /// string without validating or escaping it, and `CFURLGetBytes` returns exactly those bytes, which is what
    /// callers rely on for URI strings that are not themselves valid URL strings.
    @available(macOS 10.11, iOS 9.0, watchOS 2.0, tvOS 9.0, *)
    public init?(dataRepresentation data: __shared Data, relativeTo url: __shared URL?, isAbsolute: Bool = false) {
        guard !data.isEmpty else { return nil }
        let encoding = CFStringEncoding(CFStringBuiltInEncodings.UTF8.rawValue)
        let base = url.map { unsafeBitCast($0._url, to: CFURL.self) }
        let created: CFURL? = data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> CFURL? in
            let bytes = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self)
            if isAbsolute {
                return CFURLCreateAbsoluteURLWithBytes(nil, bytes, data.count, encoding, base, false)
            }
            return CFURLCreateWithBytes(nil, bytes, data.count, encoding, base)
        }
        guard let cfurl = created else { return nil }
        _url = URL._converted(from: unsafeBitCast(cfurl, to: NSURL.self))
    }

    /// Initializes a newly created file URL referencing the local file or directory at path.
    ///
    /// If an empty string is used for the path, then the path is assumed to be ".".
    /// - note: This function avoids an extra file system access to check if the file URL is a directory. You should use it if you know the answer already.
    public init(fileURLWithPath path: __shared String, isDirectory: Bool) {
        _url = URL._converted(from: NSURL(fileURLWithPath: path.isEmpty ? "." : path, isDirectory: isDirectory))
    }

    /// Initializes a newly created file URL referencing the local file or directory at path.
    ///
    /// If an empty string is used for the path, then the path is assumed to be ".".
    public init(fileURLWithPath path: __shared String) {
        _url = URL._converted(from: NSURL(fileURLWithPath: path.isEmpty ? "." : path))
    }

    /// Initializes a newly created file URL referencing the local file or directory at path, relative to a base URL.
    ///
    /// If an empty string is used for the path, then the path is assumed to be ".".
    public init(fileURLWithPath path: __shared String, relativeTo base: __shared URL?) {
        let p = path.isEmpty ? "." : path
        if let base = base, !p.hasPrefix("/") {
            // Not NSURL(string:relativeTo:): spaces, % and #/? in a file name must stay part of the path.
            func fileURL(isDirectory: Bool) -> NSURL {
                return p.withCString {
                    NSURL.fileURL(withFileSystemRepresentation: $0, isDirectory: isDirectory, relativeTo: base)
                } as! NSURL
            }
            var relative = fileURL(isDirectory: p.hasSuffix("/"))
            // Like -initFileURLWithPath:relativeToURL:, ask the file system when there's no trailing slash.
            var info = stat()
            if !p.hasSuffix("/"), stat(relative.fileSystemRepresentation(), &info) == 0, info.st_mode & S_IFMT == S_IFDIR {
                relative = fileURL(isDirectory: true)
            }
            _url = URL._converted(from: relative)
        } else {
            _url = URL._converted(from: NSURL(fileURLWithPath: p))
        }
    }

    /// Creates a relative file URL without probing whether it is a directory.
    public init(fileURLWithPath path: __shared String, isDirectory: Bool, relativeTo base: __shared URL?) {
        let p = path.isEmpty ? "." : path
        _url = p.withCString {
            URL._converted(from: NSURL.fileURL(withFileSystemRepresentation: $0,
                                              isDirectory: isDirectory, relativeTo: base) as! NSURL)
        }
    }

    /// Initializes a newly created file URL referencing the local file or directory at the file system representation of the path. File system representation is a null-terminated C string with canonical UTF-8 encoding.
    public init(fileURLWithFileSystemRepresentation path: UnsafePointer<Int8>, isDirectory: Bool, relativeTo baseURL: __shared URL?) {
        // Not NSURL(fileURLWithFileSystemRepresentation:...): the SDK's NSURL.h declares only the class method
        // +fileURLWithFileSystemRepresentation:isDirectory:relativeToURL:, which is what forwards to
        // -initFileURLWithFileSystemRepresentation:isDirectory:relativeToURL: (see NSURL.m).
        _url = URL._converted(from: NSURL.fileURL(withFileSystemRepresentation: path, isDirectory: isDirectory, relativeTo: baseURL) as! NSURL)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(_url)
    }

    /// Returns the absolute string for the URL.
    public var absoluteString: String {
        if let string = _url.absoluteString() {
            return string
        } else {
            // This should never fail for non-file reference URLs
            return ""
        }
    }

    /// The relative portion of a URL.
    ///
    /// If `baseURL` is nil, or if the receiver is itself absolute, this is the same as `absoluteString`.
    public var relativeString: String {
        return _url.relativeString() ?? ""
    }

    /// Returns the base URL.
    ///
    /// If the URL is itself absolute, then this value is nil.
    public var baseURL: URL? {
        return _url.base()
    }

    /// Returns the absolute URL.
    ///
    /// If the URL is itself absolute, this will return self.
    public var absoluteURL: URL {
        if let url = _url.absolute() {
            return url
        } else {
            // This should never fail for non-file reference URLs
            return self
        }
    }

    /// Returns the scheme of the URL.
    public var scheme: String? {
        return _url.scheme()
    }

    /// Returns true if the scheme is `file:`.
    public var isFileURL: Bool {
        return _url.isFileURL()
    }

    /// If the URL conforms to RFC 1808 (the most common form of URL), returns the host component of the URL; otherwise it returns nil.
    public var host: String? {
        return _url.host()
    }

    /// Returns the host, optionally decoding percent escapes. The modern
    /// Darwin contract strips IPv6 brackets and percent-encodes IDNA-decoded
    /// Unicode for its encoded result (swift-foundation URL_Swift.swift).
    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
    public func host(percentEncoded: Bool = true) -> String? {
        if !percentEncoded {
            return _url.host()
        }
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: true),
              let encoded = components.percentEncodedHost else { return nil }
        if encoded.isEmpty && components.user == nil && components.password == nil && components.port == nil {
            return nil
        }
        if encoded.hasPrefix("[") && encoded.hasSuffix("]") {
            return String(encoded.dropFirst().dropLast())
        }
        if let unicode = _URLIDNA.unicodeHost(encoded), unicode != encoded {
            components.host = unicode
            return components.percentEncodedHost
        }
        return encoded
    }

    /// If the URL conforms to RFC 1808 (the most common form of URL), returns the port component of the URL; otherwise it returns nil.
    public var port: Int? {
        return _url.port()?.integerValue()
    }

    /// If the URL conforms to RFC 1808 (the most common form of URL), returns the user component of the URL; otherwise it returns nil.
    public var user: String? {
        return _url.user()
    }

    /// If the URL conforms to RFC 1808 (the most common form of URL), returns the password component of the URL; otherwise it returns nil.
    public var password: String? {
        return _url.password()
    }

    /// If the URL conforms to RFC 1808 (the most common form of URL), returns the path component of the URL; otherwise it returns an empty string.
    ///
    /// If the URL contains a parameter string, it is appended to the path with a `;`.
    public var path: String {
        if let parameterString = _url.parameterString() {
            if let path = _url.path() {
                return path + ";" + parameterString
            } else {
                return ";" + parameterString
            }
        } else if let path = _url.path() {
            return path
        } else {
            return ""
        }
    }

    /// If the URL conforms to RFC 1808 (the most common form of URL), returns the relative path of the URL; otherwise it returns nil.
    ///
    /// This is the same as path if baseURL is nil.
    public var relativePath: String {
        if let parameterString = _url.parameterString() {
            if let path = _url.relativePath() {
                return path + ";" + parameterString
            } else {
                return ";" + parameterString
            }
        } else if let path = _url.relativePath() {
            return path
        } else {
            return ""
        }
    }

    /// Returns the path of the URL, optionally percent-encoded (macOS 13+ API).
    public func path(percentEncoded: Bool = true) -> String {
        // CFURLCopyPath keeps the trailing slash and the URL's own percent-encoding, which -[NSURL path] drops.
        let absolute = unsafeBitCast(_url.absolute().map { $0 as NSURL } ?? _url, to: CFURL.self)
        var encoded = CFURLCopyPath(absolute).map { $0 as String } ?? ""
        if let parameterString = CFURLCopyParameterString(absolute, nil) {
            encoded += ";" + (parameterString as String)
        }
        guard !percentEncoded else { return encoded }
        return CFURLCreateStringByReplacingPercentEscapes(nil, encoded as CFString, "" as CFString).map { $0 as String } ?? ""
    }

    /// If the URL conforms to RFC 1808 (the most common form of URL), returns the fragment component of the URL; otherwise it returns nil.
    public var fragment: String? {
        return _url.fragment()
    }

    /// If the URL conforms to RFC 1808 (the most common form of URL), returns the query of the URL; otherwise it returns nil.
    public var query: String? {
        return _url.query()
    }

    /// Returns true if the URL path represents a directory.
    public var hasDirectoryPath: Bool {
        // -[NSURL path] drops the trailing slash; Darling's NSURL is toll-free bridged to CFURL.
        return CFURLHasDirectoryPath(unsafeBitCast(_url, to: CFURL.self))
    }

    /// Passes the URL's path in file system representation to `block`.
    ///
    /// File system representation is a null-terminated C string with canonical UTF-8 encoding.
    /// - note: The pointer is not valid outside the context of the block.
    public func withUnsafeFileSystemRepresentation<ResultType>(_ block: (UnsafePointer<Int8>?) throws -> ResultType) rethrows -> ResultType {
        return try block(_url.fileSystemRepresentation())
    }

    // MARK: -
    // MARK: Path manipulation

    /// Returns the path components of the URL, or an empty array if the path is an empty string.
    public var pathComponents: [String] {
        // In accordance with our above change to never return a nil path, here we return an empty array.
        return (_url.pathComponents() as? [String]) ?? []
    }

    /// Returns the last path component of the URL, or an empty string if the path is an empty string.
    public var lastPathComponent: String {
        return _url.lastPathComponent() ?? ""
    }

    /// Returns the path extension of the URL, or an empty string if the path is an empty string.
    public var pathExtension: String {
        return _url.pathExtension() ?? ""
    }

    /// Returns a URL constructed by appending the given path component to self.
    ///
    /// - parameter pathComponent: The path component to add.
    /// - parameter isDirectory: If `true`, then a trailing `/` is added to the resulting path.
    public func appendingPathComponent(_ pathComponent: String, isDirectory: Bool) -> URL {
        if let result = _url.appendingPathComponent(pathComponent, isDirectory: isDirectory) {
            return result
        } else {
            return self
        }
    }

    /// Returns a URL constructed by appending the given path component to self.
    ///
    /// - parameter pathComponent: The path component to add.
    public func appendingPathComponent(_ pathComponent: String) -> URL {
        if let result = _url.appendingPathComponent(pathComponent) {
            return result
        } else {
            return self
        }
    }

    /// Returns a URL constructed by removing the last path component of self.
    ///
    /// This function may either remove a path component or append `/..`.
    ///
    /// If the URL has an empty path (e.g., `http://www.example.com`), then this function will return the URL unchanged.
    public func deletingLastPathComponent() -> URL {
        // This is a slight behavior change from NSURL, but better than returning "http://www.example.com../".
        guard !path.isEmpty, let result = _url.deletingLastPathComponent() else { return self }
        return result
    }

    /// Returns a URL constructed by appending the given path extension to self.
    ///
    /// If the URL has an empty path (e.g., `http://www.example.com`), then this function will return the URL unchanged.
    public func appendingPathExtension(_ pathExtension: String) -> URL {
        guard !path.isEmpty, let result = _url.appendingPathExtension(pathExtension) else { return self }
        return result
    }

    /// Returns a URL constructed by removing any path extension.
    ///
    /// If the URL has an empty path (e.g., `http://www.example.com`), then this function will return the URL unchanged.
    public func deletingPathExtension() -> URL {
        guard !path.isEmpty, let result = _url.deletingPathExtension() else { return self }
        return result
    }

    /// Appends a path component to the URL.
    ///
    /// - parameter pathComponent: The path component to add.
    /// - parameter isDirectory: Use `true` if the resulting path is a directory.
    public mutating func appendPathComponent(_ pathComponent: String, isDirectory: Bool) {
        self = appendingPathComponent(pathComponent, isDirectory: isDirectory)
    }

    /// Appends a path component to the URL.
    ///
    /// - parameter pathComponent: The path component to add.
    public mutating func appendPathComponent(_ pathComponent: String) {
        self = appendingPathComponent(pathComponent)
    }

    /// Appends the given path extension to self.
    ///
    /// If the URL has an empty path (e.g., `http://www.example.com`), then this function will do nothing.
    public mutating func appendPathExtension(_ pathExtension: String) {
        self = appendingPathExtension(pathExtension)
    }

    /// Returns a URL constructed by removing the last path component of self.
    ///
    /// If the URL has an empty path (e.g., `http://www.example.com`), then this function will do nothing.
    public mutating func deleteLastPathComponent() {
        self = deletingLastPathComponent()
    }

    /// Returns a URL constructed by removing any path extension.
    ///
    /// If the URL has an empty path (e.g., `http://www.example.com`), then this function will do nothing.
    public mutating func deletePathExtension() {
        self = deletingPathExtension()
    }

    /// Returns a `URL` with any instances of ".." or "." removed from its path.
    public var standardized : URL {
        guard let result = _url.standardized() else { return self }
        return result
    }

    /// Standardizes the path of a file URL.
    ///
    /// If the `isFileURL` is false, this method does nothing.
    public mutating func standardize() {
        self = self.standardized
    }

    /// Standardizes the path of a file URL. Non-file URLs are unchanged.
    public var standardizedFileURL: URL {
        guard isFileURL, let result = _url.standardizingPath() else { return self }
        return result
    }

    /// Resolves symbolic links in the path of a file URL. Non-file URLs are unchanged.
    public func resolvingSymlinksInPath() -> URL {
        guard isFileURL, let result = _url.resolvingSymlinksInPath() else { return self }
        return result
    }

    // MARK: - Reachability

    /// Returns whether the URL's resource exists and is reachable.
    public func checkResourceIsReachable() throws -> Bool {
        // -checkResourceIsReachableAndReturnError: imports as a throwing method.
        try _url.checkResourceIsReachable()
        return true
    }

    // MARK: - Security scope

    /// Given an instance of `URL` created from a security scoped bookmark, make the resource referenced by the url accessible to the process.
    public func startAccessingSecurityScopedResource() -> Bool {
        return _url.startAccessingSecurityScopedResource()
    }

    /// Revokes the access granted to the url by a prior successful call to startAccessingSecurityScopedResource().
    public func stopAccessingSecurityScopedResource() {
        _url.stopAccessingSecurityScopedResource()
    }

    // MARK: - Bridging Support

    /// We must not store an NSURL without running it through this function. This makes sure that we do not hold a file reference URL, which changes the nullability of many NSURL functions.
    private static func _converted(from url: NSURL) -> NSURL {
        return url
    }

    fileprivate init(reference: __shared NSURL) {
        _url = URL._converted(from: reference).copy() as! NSURL
    }

    private var reference: NSURL {
        return _url
    }

    public static func ==(lhs: URL, rhs: URL) -> Bool {
        return lhs.reference.isEqual(rhs.reference)
    }
}

// MARK: - Path appending with directory hints (macOS 13+ API)

extension URL {
    /// A hint about whether a path refers to a directory.
    public enum DirectoryHint {
        /// The path is a directory; a trailing `/` is added.
        case isDirectory
        /// The path isn't a directory.
        case notDirectory
        /// Infer from the path: a trailing `/` means a directory.
        case inferFromPath
        /// Check the file system (treated like `inferFromPath` here).
        case checkFileSystem
    }

    /// Initializes a URL from a file path, a hint about whether it is a directory, and an optional base URL.
    ///
    /// The path is a file system path, not a URL string: characters that are significant in a URL stay
    /// part of the path. `directoryHint` decides whether the path ends in `/`; as with `DirectoryHint`'s
    /// own comment, `.checkFileSystem` is treated like `.inferFromPath` in this tree, whose file URLs
    /// come from `NSURL` rather than a file system query here. A relative path is resolved against
    /// `base` when one is given, the way `-initFileURLWithPath:relativeToURL:` resolves it.
    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
    public init(filePath path: String, directoryHint: DirectoryHint = .inferFromPath, relativeTo base: URL? = nil) {
        let filePath = path.isEmpty ? "." : path
        let isDirectory: Bool
        switch directoryHint {
        case .isDirectory:
            isDirectory = true
        case .notDirectory:
            isDirectory = false
        case .inferFromPath, .checkFileSystem:
            isDirectory = filePath.hasSuffix("/")
        }
        if let base = base, !filePath.hasPrefix("/") {
            _url = URL._converted(from: filePath.withCString {
                NSURL.fileURL(withFileSystemRepresentation: $0, isDirectory: isDirectory, relativeTo: base) as! NSURL
            })
        } else {
            _url = URL._converted(from: NSURL(fileURLWithPath: filePath, isDirectory: isDirectory))
        }
    }

    private func _appending(_ component: String, hint: DirectoryHint) -> URL {
        switch hint {
        case .isDirectory:
            return appendingPathComponent(component, isDirectory: true)
        case .notDirectory:
            return appendingPathComponent(component, isDirectory: false)
        case .inferFromPath, .checkFileSystem:
            return appendingPathComponent(component, isDirectory: component.hasSuffix("/"))
        }
    }

    /// Returns a URL by appending a path, which may contain several components.
    public func appending<S: StringProtocol>(path: S, directoryHint: DirectoryHint = .inferFromPath) -> URL {
        return _appending(String(path), hint: directoryHint)
    }

    /// Returns a URL by appending a single path component.
    public func appending<S: StringProtocol>(component: S, directoryHint: DirectoryHint = .inferFromPath) -> URL {
        return _appending(String(component), hint: directoryHint)
    }

    /// Returns a URL by appending path components.
    public func appending<S: StringProtocol>(components: S..., directoryHint: DirectoryHint = .inferFromPath) -> URL {
        var result = self
        for (i, component) in components.enumerated() {
            result = result._appending(String(component), hint: i == components.count - 1 ? directoryHint : .isDirectory)
        }
        return result
    }

    /// Appends a path, which may contain several components.
    public mutating func append<S: StringProtocol>(path: S, directoryHint: DirectoryHint = .inferFromPath) {
        self = appending(path: path, directoryHint: directoryHint)
    }

    /// Appends a single path component.
    public mutating func append<S: StringProtocol>(component: S, directoryHint: DirectoryHint = .inferFromPath) {
        self = appending(component: component, directoryHint: directoryHint)
    }

    /// Returns a URL by appending the given query items to the receiver.
    ///
    /// The items are appended to any the URL already carries, through the URL's components; a URL whose
    /// components cannot be formed is returned unchanged, as Apple's implementation does.
    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
    public func appending(queryItems: [URLQueryItem]) -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: true) else { return self }
        var newItems = components.queryItems ?? []
        newItems.append(contentsOf: queryItems)
        components.queryItems = newItems
        return components.url ?? self
    }

    /// Removes the cached resource value identified by a given resource key from the receiver.
    ///
    /// Declaration: the guest SDK's `Foundation.swiftinterface` line 16541, in its `extension
    /// Foundation.URL` block: `public mutating func removeCachedResourceValue(forKey key:
    /// Foundation.URLResourceKey)`.  The release/5.4 Darwin overlay's body is
    /// `_writableURL.removeCachedResourceValue(forKey: key)`, a call to
    /// `-[NSURL removeCachedResourceValueForKey:]`.  This tree's NSURL implements no resource-value
    /// cache at all: `-resourceValuesForKeys:error:` recomputes every requested key on every call
    /// (src/external/corefoundation/NSURL.m:214-330, straight through to
    /// `CFURLCopyResourcePropertiesForKeys`, which re-`stat`s the file), and neither the header
    /// (src/external/foundation/include/Foundation/NSURL.h) nor CFURL
    /// (src/external/corefoundation/CFURL.c) declares or implements any cached-value API.  There is
    /// therefore never a cached value, for any key, to invalidate, and the operation's observable
    /// postcondition -- the next `resourceValues(forKeys:)` reads the file system afresh -- already
    /// holds before the call.  The method is the identity on the receiver's (empty) cache state; it
    /// stands in for no absent work, because there is none to do.
    public mutating func removeCachedResourceValue(forKey key: URLResourceKey) {
    }

    // MARK: - Standard directories (macOS 13+ API)

    /// The home directory for the current user (`~/`).
    ///
    /// Declaration: the guest SDK's `Foundation.swiftinterface` line 16588, in its
    /// `extension Foundation.URL` block: `public static var homeDirectory: Foundation.URL { get }`
    /// (`@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)`).
    ///
    /// Body: Apple's own, from swift-foundation's `Sources/FoundationEssentials/URL/URL.swift:1573`
    /// (the checkout the overlay build fetches, `dbacc67779dc0a41ddc9493acbaa332d76c9fb03`):
    ///     public static var homeDirectory: URL {
    ///         #if FOUNDATION_FRAMEWORK && !os(macOS)
    ///         URL(filePath: NSHomeDirectory(), directoryHint: .isDirectory)
    ///         #elseif FOUNDATION_FRAMEWORK
    ///         if foundation_swift_url_enabled() { return FileManager.default.homeDirectoryForCurrentUser }
    ///         return URL(filePath: NSHomeDirectory(), directoryHint: .isDirectory)
    ///         ...
    /// This overlay is the FOUNDATION_FRAMEWORK case on macOS, whose fallback (and whose
    /// non-macOS body) is the `NSHomeDirectory()` call; the first arm's delegation target,
    /// `FileManager.homeDirectoryForCurrentUser`, does not exist anywhere in this tree's FileManager
    /// (`grep -rn homeDirectoryForCurrentUser src/external/swift/overlays/Foundation/` finds only
    /// the never-compiled swift-foundation checkout), and `URL.homeDirectory` has no other source.
    /// `NSHomeDirectory()` itself IS implemented here -- `src/external/foundation/src/NSPathUtilities.m:389`,
    /// the user's `HOME` with a `/` fallback, the same function `NSTemporaryDirectory()`'s file
    /// documents -- so the written-out arm is Apple's, over this tree's own home-directory
    /// primitive. `DirectoryHint.isDirectory` makes the trailing `/` the `~/` form implies,
    /// exactly as Apple's body does.
    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
    public static var homeDirectory: URL {
        return URL(filePath: NSHomeDirectory(), directoryHint: .isDirectory)
    }
}

extension URL : _ObjectiveCBridgeable {
    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSURL {
        return _url
    }

    public static func _forceBridgeFromObjectiveC(_ source: NSURL, result: inout URL?) {
        if !_conditionallyBridgeFromObjectiveC(source, result: &result) {
            fatalError("Unable to bridge \(_ObjectiveCType.self) to \(self)")
        }
    }

    public static func _conditionallyBridgeFromObjectiveC(_ source: NSURL, result: inout URL?) -> Bool {
        result = URL(reference: source)
        return true
    }

    @_effects(readonly)
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSURL?) -> URL {
        var result: URL?
        _forceBridgeFromObjectiveC(source!, result: &result)
        return result!
    }
}

extension URL : CustomStringConvertible, CustomDebugStringConvertible {
    // Darling: NSURL's -description clashes with +description in Swift, so build NSURL's format here.
    public var description: String {
        if let base = baseURL {
            return relativeString + " -- " + base.description
        }
        return absoluteString
    }

    public var debugDescription: String {
        return description
    }
}

extension NSURL : _HasCustomAnyHashableRepresentation {
    // Must be @nonobjc to avoid infinite recursion during bridging.
    @nonobjc
    public func _toCustomAnyHashable() -> AnyHashable? {
        return AnyHashable(self as URL)
    }
}

extension URL : Codable {
    private enum CodingKeys : Int, CodingKey {
        case base
        case relative
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let relative = try container.decode(String.self, forKey: .relative)
        let base = try container.decodeIfPresent(URL.self, forKey: .base)

        guard let url = URL(string: relative, relativeTo: base) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath,
                                                                    debugDescription: "Invalid URL string."))
        }

        self = url
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.relativeString, forKey: .relative)
        if let base = self.baseURL {
            try container.encode(base, forKey: .base)
        }
    }
}
