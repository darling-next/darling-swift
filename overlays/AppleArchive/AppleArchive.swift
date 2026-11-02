// AppleArchive — a Swift overlay for Darling whose members are either REAL or a documented "cannot".
//
// WHAT THIS FILE IS. It is not a subset of Apple's AppleArchive, and no member pretends: every
// declaration below either does the real thing on this runtime's own primitives, or answers "cannot"
// (nil, or the documented `UnimplementedAppleArchive.notSupported`) instead of returning a plausible
// substitute for an engine this tree does not have.
//
// REAL HERE (the comment above each says what it is built on):
//   * ArchiveFlags                        - a real OptionSet: its raw value is the AABI flag set.
//   * ArchiveCompression                  - the six AABI codec identifiers with the raw values the
//                                           SDK's AppleArchive/AADefs.h defines.
//   * ArchiveError                        - the module's error type, as the SDK interface declares it.
//   * ArchiveHeader.FieldKey              - a real 3-letter key, with the documented precondition.
//   * ArchiveHeader.FieldKeySet           - a real key set: it parses and serialises the documented
//                                           "AAA,BBB,CCC" string and is a RandomAccessCollection +
//                                           SetAlgebra over the keys it holds.
//   * ArchiveByteStream over a descriptor - withFileStream / fileStream(fd:), and read/write/pread/
//                                           pwrite/seek/cancel/close mapped to the file I/O system
//                                           calls (the AABI contract for a file stream).
//
// "CANNOT" HERE, and the measurements behind that boundary. Everything that would need an Apple
// Archive ENGINE — the archive container itself and the AABI block-compression container:
//   * ArchiveByteStream.compressionStream(using:writingTo:blockSize:flags:threadCount:)  -> nil
//   * ArchiveByteStream.compressionStream(appendingTo:flags:threadCount:)                -> nil
//   * ArchiveByteStream.decompressionStream(readingFrom:flags:threadCount:)              -> nil
//   * ArchiveByteStream.fileStream(path:mode:options:permissions:)                       -> nil
//   * ArchiveStream.encodeStream / decodeStream / extractStream / process / readHeader /
//     readBlob / close / field(forKey:)                                                  -> nil / error
//   * ArchiveHeader.entryPath                                                            -> nil
//   * ArchiveHeader.FieldKeySet.defaultForArchive / .defaultForManifest: NOT DECLARED at all
//     (see the note beside the class).
// Why:
//   * src/libAppleArchive is DELIBERATELY symbol-less: its CMakeLists says a client that binds a real
//     AA* symbol must fail LOUDLY at load rather than call something that answers wrongly. The AABI
//     format is unimplemented work (dar-vg6u); the C interface (usr/include/AppleArchive in the SDK)
//     is present as documentation only, and no implementation of that format exists in this tree.
//   * The compression layer under it is equally empty. The deployed libcompression.dylib is
//     src/libcompression: seven functions whose bodies return 0 / COMPRESSION_STATUS_ERROR, including
//     compression_encode_buffer, compression_decode_buffer and compression_stream_init. There is no
//     codec in this runtime to build a stream on.
//   * An AppleArchive compression stream is also NOT the raw codec stream. AAByteStream.h documents
//     AACompressionOutputStreamOpen as "Create a block compression (pbz*) sequential output stream"
//     and AACompressionOutputStreamOpenExisting as appending to such an existing (pbz*) stream ("If
//     smaller than block size, the last block in the existing stream will be modified"). The pbz*
//     container is nowhere in this tree and nothing in the SDK documents its bytes.
//   * Apple's open-source lzfse IS in the tree (src/external/lzfse, and
//     build/<builddir>/src/external/lzfse/liblzfse.a is a guest Mach-O archive of it), but (a) its
//     whole public surface is buffer-level — lzfse.h exposes lzfse_encode_buffer/lzfse_decode_buffer
//     over the raw lzfse block format, not a stream container — and (b) it is NOT deployed: a name
//     search over the whole prefix finds no lzfse artifact at all (measured under
//     prefix-verify14: neither libexec/darling/usr/lib, nor usr/lib, nor anywhere else), so no
//     stream this module emitted could be a pbz* stream and nothing in the tree could check that
//     Apple's reader would accept it. Emitting bytes anyway would be a fabricated stream, and
//     `compressionStream(appendingTo:)` would need the pbz* block parsing on top of that.
//   * The one thing that IS complete is a descriptor: the file I/O system calls. That is what the
//     byte stream here is built on, and it is why withFileStream/fileStream(fd:) are real while every
//     factory that needs the AABI container is not.
//
// WHY IT EXISTS AT ALL. /usr/lib/swift/libswiftAppleArchive.dylib is demanded at load time by
// DVTInstrumentsFoundation and by Xcode 26.3's new build system (SWBUtil), which bind their names from
// it. Loading is not implementing (nothing in a measured workload calls these members), but a name
// that exists must still answer truthfully when something does call it.
//
// ABI. The public shapes below follow the SDK's x86_64-apple-macos.swiftinterface so the Swift ABI
// metadata a client recorded carries the same names. Two declaration details are load-bearing:
//   * the statically dispatched members (`entryPath`, `writeDirectoryContents`) are declared in
//     EXTENSIONS, as the SDK does: a class-body declaration exports only the vtable entry (`...Tj`),
//     while the symbol a client binds is the direct one (`...F`), which only an extension
//     declaration produces;
//   * `FieldKeySet` is a CLASS (the SDK's is too), nested in ArchiveHeader, with its inits in the
//     class body and its conformance members in an extension.
//
// SYSTEM ABI. FilePath and descriptor values use the genuine swift-system
// provider built by System/build.sh and installed as libswiftSystem.dylib.
// The focused rebuild imports the genuine SDK declarations and links that
// provider explicitly, including resilient FilePath metadata. No archive
// engine is inferred from the availability of these ordinary value types.

import System

/// Error thrown by every member that would need real Apple Archive work. Documented so a caller that
/// ever reaches one of them gets an honest "cannot", never a fabricated success. It is deliberately
/// NOT the module's public `ArchiveError`: that one means "the archive operation failed" (ioError) and
/// must not be used to describe an operation this runtime cannot perform at all.
internal enum UnimplementedAppleArchive: Error, CustomStringConvertible {
    case notSupported
    var description: String {
        "AppleArchive is not implemented in this runtime (see AppleArchive.swift; dar-vg6u)"
    }
}

/// The module's error type, declared as the SDK interface declares it. `ioError` is what every real
/// failing operation here throws (a failed file I/O system call, or an operation on a stream that was
/// cancelled or closed); `invalidValue` is for a value that cannot describe an operation.
public enum ArchiveError: Hashable, Error {
    case ioError
    case invalidValue
}

// MARK: - File I/O

// The file I/O system calls, declared by symbol.
//
// WHY NOT `import Darwin`: the SDK's Darwin overlay interface is a Swift module built by a
// different compiler than the one building this module, and importing it fails ("this SDK is not
// supported by the compiler"); the tree's own Darwin overlay (overlays/Darwin) is what the other
// modules here compile against, and this overlay deliberately has no such build step. The declarations
// below are the exact libSystem prototypes of the calls the AABI file stream maps to, and the symbols
// are resolved from libSystem.B.dylib, which this image already links (checked with llvm-nm on the
// built dylib: `_read`, `_write`, `_pread`, `_pwrite`, `_lseek`, `_close` bind to libSystem).
//
// Types are the Darwin ABI: ssize_t and size_t are pointer-sized (Int), off_t is Int64.

@_silgen_name("read")
private func aaRead(_ fd: Int32, _ buffer: UnsafeMutableRawPointer?, _ count: Int) -> Int
@_silgen_name("write")
private func aaWrite(_ fd: Int32, _ buffer: UnsafeRawPointer?, _ count: Int) -> Int
@_silgen_name("pread")
private func aaPRead(_ fd: Int32, _ buffer: UnsafeMutableRawPointer?, _ count: Int, _ offset: Int64) -> Int
@_silgen_name("pwrite")
private func aaPWrite(_ fd: Int32, _ buffer: UnsafeRawPointer?, _ count: Int, _ offset: Int64) -> Int
@_silgen_name("lseek")
private func aaLSeek(_ fd: Int32, _ offset: Int64, _ whence: Int32) -> Int64
@_silgen_name("close")
private func aaClose(_ fd: Int32) -> Int32

/// Flags for archive operations. OptionSet is what the SDK declares, and its SetAlgebra conformance
/// is one of the symbols the client binds. Its raw value is the AABI flag set: no member of this
/// module reads it to change behaviour, because no archive operation here reaches the engine.
public struct ArchiveFlags: OptionSet, Hashable {
    public let rawValue: UInt64
    public init(rawValue: UInt64) { self.rawValue = rawValue }

    /// Present so the static getter the client binds exists. No archive engine is behind it.
    public static let ignoreOperationNotPermitted = ArchiveFlags(rawValue: 1 << 0)
}

/// A compression algorithm. REAL: this is a codec identifier, and the raw values below are the AABI
/// `AACompressionAlgorithm` constants from the SDK's AppleArchive/AADefs.h (AA_COMPRESSION_ALGORITHM_*),
/// i.e. the values an Apple Archive stream carries and the values its C API takes. That header's own
/// "These constants match the values in compression.h" comment is only approximate for two of them
/// (AABI zlib is 0x505, level 5, and AABI lzbitmap is 0x702, while this tree's compression.h says
/// 0x205 and 0x703); the AABI values are the ones declared here, because AABI is what this type is.
public struct ArchiveCompression: Equatable, Hashable, RawRepresentable, CustomStringConvertible {
    public typealias RawValue = UInt32

    public var rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let none = ArchiveCompression(rawValue: 0x000)
    public static let lz4 = ArchiveCompression(rawValue: 0x100)
    public static let zlib = ArchiveCompression(rawValue: 0x505)
    public static let lzma = ArchiveCompression(rawValue: 0x306)
    public static let lzfse = ArchiveCompression(rawValue: 0x801)
    public static let lzbitmap = ArchiveCompression(rawValue: 0x702)

    /// The AABI name for the six declared algorithms, and the raw value for anything else (an
    /// algorithm this module has no name for must not be given one).
    public var description: String {
        switch self {
        case .none: return "none"
        case .lz4: return "lz4"
        case .zlib: return "zlib"
        case .lzma: return "lzma"
        case .lzfse: return "lzfse"
        case .lzbitmap: return "lzbitmap"
        default: return "unknown(0x" + String(rawValue, radix: 16) + ")"
        }
    }
}

/// A byte stream. A stream created here owns a real file descriptor and maps the whole read/write
/// surface onto the file I/O system calls, which is the AABI contract for a file stream
/// ("All protocol functions are mapped to the file I/O system calls" — SDK doc for fileStream(fd:)).
/// Every factory that would need the Apple Archive engine instead returns nil: no archive engine and
/// no compression container exists in this runtime, so "no stream" is the truth rather than a
/// placeholder object.
public class ArchiveByteStream {
    /// The descriptor this stream operates on, or -1 once the stream has been closed.
    internal var descriptor: Int32
    /// Whether closing the stream must also close `descriptor` (the stream owns it).
    internal let automaticClose: Bool
    /// Set by `cancel()`: every later operation fails, and `close()` still releases the descriptor.
    internal var cancelled: Bool
    /// Whether `close()` has run already (it is idempotent).
    internal var closed: Bool

    internal init(fd: Int32, automaticClose: Bool) {
        self.descriptor = fd
        self.automaticClose = automaticClose
        self.cancelled = false
        self.closed = false
    }

    deinit {
        // The AABI wrapper destroys its stream object on release, which closes the descriptor when the
        // stream owns it; dropping a stream without close() must not leak the descriptor.
        if automaticClose && !closed && descriptor >= 0 {
            _ = aaClose(descriptor)
        }
    }

    /// The descriptor to run an operation on, or `ArchiveError.ioError` if this stream can no longer
    /// be used. A cancelled stream keeps its descriptor ("After `cancel` is called, the stream still
    /// needs to be closed to release resources" — SDK doc) but every operation on it fails.
    ///
    /// The flags are plain properties, not atomics: `cancel()` is documented as asynchronous
    /// cancellation of stream OPERATIONS, and this module has no measured caller that races it.
    private func usableDescriptor() throws -> Int32 {
        guard !closed, !cancelled, descriptor >= 0 else { throw ArchiveError.ioError }
        return descriptor
    }

    private func checked(_ result: Int) throws -> Int {
        guard result >= 0 else { throw ArchiveError.ioError }
        return result
    }

    private func checkedOffset(_ result: Int64) throws -> Int64 {
        guard result >= 0 else { throw ArchiveError.ioError }
        return result
    }

    /// Sequential read. Returns the number of bytes read, 0 at end of file.
    public func read(into buffer: UnsafeMutableRawBufferPointer) throws -> Int {
        let fd = try usableDescriptor()
        return try checked(aaRead(fd, buffer.baseAddress, buffer.count))
    }

    /// Read at an absolute offset, without moving the stream position.
    public func read(into buffer: UnsafeMutableRawBufferPointer, atOffset offset: Int64) throws -> Int {
        let fd = try usableDescriptor()
        return try checked(aaPRead(fd, buffer.baseAddress, buffer.count, offset))
    }

    /// Sequential write. Returns the number of bytes written, which may be less than the buffer.
    public func write(from buffer: UnsafeRawBufferPointer) throws -> Int {
        let fd = try usableDescriptor()
        return try checked(aaWrite(fd, buffer.baseAddress, buffer.count))
    }

    /// Write at an absolute offset, without moving the stream position.
    public func write(from buffer: UnsafeRawBufferPointer, atOffset offset: Int64) throws -> Int {
        let fd = try usableDescriptor()
        return try checked(aaPWrite(fd, buffer.baseAddress, buffer.count, offset))
    }

    /// Move the stream position. The origin is `System.FileDescriptor.SeekOrigin`, whose raw value IS
    /// the `whence` the system call takes (SEEK_SET/SEEK_CUR/SEEK_END), so it is passed through.
    public func seek(toOffset offset: Int64, relativeTo origin: System.FileDescriptor.SeekOrigin) throws -> Int64 {
        let fd = try usableDescriptor()
        return try checkedOffset(aaLSeek(fd, offset, origin.rawValue))
    }

    /// Cancel all later operations on this stream. The descriptor is NOT released here: close() still
    /// has to run (SDK doc: "After `cancel` is called, the stream still needs to be closed to release
    /// resources"), which matters when the stream owns the descriptor.
    public func cancel() {
        cancelled = true
    }

    /// Close the stream. Idempotent. When the stream owns the descriptor (`automaticClose`), this
    /// closes it, and a failing `close(2)` is reported as `ArchiveError.ioError` rather than swallowed.
    public func close() throws {
        if closed { return }
        closed = true
        let fd = descriptor
        descriptor = -1
        if automaticClose && fd >= 0 {
            guard aaClose(fd) == 0 else { throw ArchiveError.ioError }
        }
    }

    /// Still "cannot": this would need the AABI decompression container (see the file header).
    public static func decompressionStream(readingFrom compressedStream: ArchiveByteStream,
                                           flags: ArchiveFlags = [],
                                           threadCount: Int = 0) -> ArchiveByteStream? {
        return nil
    }

    /// Still "cannot": this would need `open(2)` plus the AABI file-stream object, whose real value
    /// over withFileStream(fd:) is nil here (a caller can open the descriptor itself and hand it over).
    public static func fileStream(path: System.FilePath,
                                  mode: System.FileDescriptor.AccessMode,
                                  options: System.FileDescriptor.OpenOptions,
                                  permissions: System.FilePermissions) -> ArchiveByteStream? {
        return nil
    }
}

extension ArchiveByteStream {
    /// Create a stream over an already open file descriptor. REAL: the descriptor is taken as given
    /// (no dup), and when `automaticClose` is true the stream closes it when it is closed. An invalid
    /// descriptor is not detected here — as with the system calls it wraps, the first operation on it
    /// fails with `ArchiveError.ioError`.
    public static func fileStream(fd: System.FileDescriptor, automaticClose: Bool = true) -> ArchiveByteStream? {
        return ArchiveByteStream(fd: Int32(fd.rawValue), automaticClose: automaticClose)
    }

    /// Open a stream over a file descriptor, run `body`, and close the stream. REAL, and the close is
    /// not silent: if `body` returned and closing the descriptor failed, that failure is thrown, since
    /// reporting success for a close that failed would claim data that was never handed to the system.
    /// If `body` threw, its error is the one propagated (the close is then best-effort).
    public static func withFileStream<E>(fd: System.FileDescriptor,
                                         automaticClose: Bool = true,
                                         _ body: (ArchiveByteStream) throws -> E) throws -> E {
        let stream = ArchiveByteStream(fd: Int32(fd.rawValue), automaticClose: automaticClose)
        do {
            let result = try body(stream)
            try stream.close()
            return result
        } catch {
            try? stream.close()
            throw error
        }
    }

    /// Still "cannot": AAByteStream.h documents AACompressionOutputStreamOpen as a "block compression
    /// (pbz*) sequential output stream", and the pbz* container — not the raw codec stream — is what
    /// this returns. Nothing in this tree implements it (see the file header: no AABI engine, and the
    /// deployed libcompression is a do-nothing), and Apple's lzfse in src/external/lzfse is a raw
    /// buffer codec that is not even deployed. A stream of raw lzfse blocks under this name would be a
    /// fabricated Apple Archive stream, so this answers nil.
    public static func compressionStream(using compressionAlgorithm: ArchiveCompression,
                                         writingTo compressedStream: ArchiveByteStream,
                                         blockSize: Int = (1 << 20),
                                         flags: ArchiveFlags = [],
                                         threadCount: Int = 0) -> ArchiveByteStream? {
        return nil
    }

    /// Still "cannot", for the same reason, and one more: AAByteStream.h documents
    /// AACompressionOutputStreamOpenExisting as appending into an EXISTING pbz* stream, whose last
    /// block it may rewrite, so this needs the pbz* block layout for reading as well as writing.
    public static func compressionStream(appendingTo compressedStream: ArchiveByteStream,
                                         flags: ArchiveFlags = [],
                                         threadCount: Int = 0) -> ArchiveByteStream? {
        return nil
    }
}

/// An archive stream (an encoded archive being read or written). There is no archive engine here, so
/// no instance can be produced (every factory answers nil) and every member reports the documented
/// "cannot".
public class ArchiveStream {
    public static func decodeStream(readingFrom stream: ArchiveByteStream,
                                    selectUsing filter: AppleArchive.ArchiveHeader.EntryFilter? = nil,
                                    flags: ArchiveFlags = [],
                                    threadCount: Int = 0) -> ArchiveStream? {
        return nil
    }

    public static func extractStream(extractingTo directory: System.FilePath,
                                     selectUsing filter: AppleArchive.ArchiveHeader.EntryFilter? = nil,
                                     flags: ArchiveFlags = [],
                                     threadCount: Int = 0) -> ArchiveStream? {
        return nil
    }

    public static func process(readingFrom input: ArchiveStream,
                               writingTo output: ArchiveStream,
                               selectUsing filter: AppleArchive.ArchiveHeader.EntryFilter? = nil,
                               flags: ArchiveFlags = [],
                               threadCount: Int = 0) throws -> Int {
        throw UnimplementedAppleArchive.notSupported
    }

    public func readHeader() throws -> AppleArchive.ArchiveHeader? {
        throw UnimplementedAppleArchive.notSupported
    }

    public func close() throws {
        throw UnimplementedAppleArchive.notSupported
    }

    public func readBlob(key: AppleArchive.ArchiveHeader.FieldKey,
                         into buffer: UnsafeMutableRawBufferPointer) throws {
        throw UnimplementedAppleArchive.notSupported
    }
}

extension ArchiveStream {
    /// Still "cannot": an encode stream is the AABI archive WRITER (AAArchiveStream), which this tree
    /// does not have; the message/filter parameters only decide which entries it would take.
    public static func encodeStream(writingTo stream: ArchiveByteStream,
                                    selectUsing filter: AppleArchive.ArchiveHeader.EntryFilter? = nil,
                                    flags: ArchiveFlags = [],
                                    threadCount: Int = 0) -> ArchiveStream? {
        return nil
    }

    /// Declared in an extension (the SDK declares it there too) so that the direct symbol is exported
    /// rather than only a vtable entry. Still "cannot": walking a directory into archive HEADERS is
    /// engine work (TYP/PAT/LNK/DEV/… entries, see AppleArchive/AAHeader.h), so it throws the
    /// documented error instead of pretending an empty archive was written.
    public func writeDirectoryContents(archiveFrom directory: System.FilePath,
                                       path: System.FilePath? = nil,
                                       keySet: AppleArchive.ArchiveHeader.FieldKeySet,
                                       selectUsing filter: AppleArchive.ArchiveHeader.EntryFilter? = nil,
                                       flags: ArchiveFlags = [],
                                       threadCount: Int = 0) throws {
        throw UnimplementedAppleArchive.notSupported
    }
}

/// An archive header. A FieldKey honestly remembers the string it was given; a header holds no fields
/// because none can be parsed here.
public class ArchiveHeader {
    /// A 3-letter field key. The SDK interface documents the precondition implemented here: "Construct
    /// a FieldKey from a 3-letter ASCII string. The string must have length exactly 3, and characters
    /// must be in range 32..127, otherwise a fatal error will be raised." The stored value is the
    /// string as given; a key set canonicalises to upper case when it holds one (see FieldKeySet).
    public struct FieldKey: Equatable, Hashable, CustomStringConvertible {
        internal let key: String
        public init(_ key: String) {
            let bytes = Array(key.utf8)
            precondition(bytes.count == 3 && bytes.allSatisfy { $0 >= 32 && $0 <= 127 },
                         "FieldKey must be a 3-letter ASCII string")
            self.key = key
        }
        public var description: String { key }
    }

    /// The message identifier remains opaque without an archive engine.
    public struct EntryMessage {}

    /// Signed callback result from AAEntryMessage.h: zero continues, positive
    /// skips, negative cancels. The SDK exposes this as a non-frozen Int32 value,
    /// not an empty marker; constructing a status performs no archive operation.
    public struct EntryMessageStatus: Equatable, Hashable, RawRepresentable, CustomStringConvertible {
        public var rawValue: Int32
        public init(rawValue: Int32) { self.rawValue = rawValue }

        public static let ok = EntryMessageStatus(rawValue: 0)
        public static let skip = EntryMessageStatus(rawValue: 1)
        public static let cancel = EntryMessageStatus(rawValue: -1)

        public var description: String {
            switch self {
            case .ok: return "ok"
            case .skip: return "skip"
            case .cancel: return "cancel"
            default: return "unknown(\(rawValue))"
            }
        }
    }
    public enum EntryFilterData {
        case header(ArchiveHeader)
    }
    public typealias EntryFilter = (EntryMessage, System.FilePath, EntryFilterData?) -> EntryMessageStatus

    public enum Field {
        case blob(key: FieldKey, size: UInt64, offset: UInt64 = 0)
    }

    /// Answers with the real absence: this header carries no fields, because nothing here can parse
    /// an archive.
    public func field(forKey key: FieldKey) -> Field? {
        return nil
    }

    /// A set of field keys. REAL: it parses and serialises the key list the interface documents —
    /// "Create FieldKeySet from String, comma separated list of 3-letter keys. Example
    /// \"TYP,UID,GID,DAT\". Fails if the string can't be parsed" (SDK swiftdoc) — with the syntax the
    /// C API pins down (AppleArchive/AAFieldKeys.h, AAFieldKeySetCreateWithString): keys of exactly 3
    /// characters separated by single commas, i.e. a total length of exactly 4*N-1, "characters do not
    /// need to be uppercase". The set keeps the keys in insertion order, holds each key once, and
    /// canonicalises to the upper-case form an AAFieldKey stores ("skey[0,1,2] must be upper-case
    /// non-zero ASCII characters", same header), which is why a set holding PAT contains FieldKey("pat").
    ///
    /// `init?(_:)` rejects what that grammar rejects: a length that is not 4*N-1 for at least one key
    /// (a missing or doubled comma, a key of the wrong length), a character outside A-Z/a-z, and the
    /// empty string — the empty set is spelled by `init()`, and "" is not of the form 4*N-1 for any
    /// N >= 1. (For N == 0 the header's own length formula has no meaning, which is the one place the
    /// source documents leave open; the strict reading is the one implemented and documented here.)
    ///
    /// NOT DECLARED: `defaultForArchive` and `defaultForManifest`. The SDK documents only their
    /// meaning ("Default key set for `archive`" / "for `manifest`") and nothing in the SDK headers
    /// lists either composition, so any set invented here would be indistinguishable to a caller from
    /// the real default. No measured client binds them.
    final public class FieldKeySet: CustomStringConvertible, RandomAccessCollection, SetAlgebra {
        public typealias Index = Int
        public typealias Element = ArchiveHeader.FieldKey

        /// Canonical (upper-case) keys, insertion order, no duplicates. `internal` (not
        /// `@usableFromInline`) so that this module's own storage does not appear in its export trie:
        /// the SDK's FieldKeySet keeps the same information in its C object, and this build must not
        /// export a symbol Apple's library does not.
        internal var keys: [String]

        /// Create empty FieldKeySet.
        public required init() {
            self.keys = []
        }

        /// Create a copy of a FieldKeySet.
        public init(copying s: ArchiveHeader.FieldKeySet) {
            self.keys = s.keys
        }

        /// Parse "AAA,BBB,CCC" (see the class comment for the exact grammar).
        public init?(_ s: String) {
            let bytes = Array(s.utf8)
            guard !bytes.isEmpty, bytes.count % 4 == 3 else { return nil }
            var parsed = [String]()
            parsed.reserveCapacity((bytes.count + 1) / 4)
            var index = 0
            while index < bytes.count {
                if index > 0 {
                    guard bytes[index] == UInt8(ascii: ",") else { return nil }
                    index += 1
                }
                guard index + 3 <= bytes.count else { return nil }
                var keyBytes = [UInt8]()
                keyBytes.reserveCapacity(3)
                for offset in 0..<3 {
                    let byte = bytes[index + offset]
                    switch byte {
                    case UInt8(ascii: "A")...UInt8(ascii: "Z"): keyBytes.append(byte)
                    case UInt8(ascii: "a")...UInt8(ascii: "z"): keyBytes.append(byte - 32)
                    default: return nil
                    }
                }
                index += 3
                let key = String(decoding: keyBytes, as: UTF8.self)
                if !parsed.contains(key) { parsed.append(key) }
            }
            self.keys = parsed
        }

        /// The canonical key a set holds and compares: the upper-case form AAFieldKey stores.
        private func canonical(_ member: ArchiveHeader.FieldKey) -> String {
            member.description.uppercased()
        }

        // MARK: CustomStringConvertible

        /// The key set's string representation: the keys joined by commas, i.e. exactly the input the
        /// parsing initialiser accepts (AAFieldKeys.h, AAFieldKeySetSerialize).
        public var description: String {
            keys.joined(separator: ",")
        }

        // MARK: RandomAccessCollection

        public var startIndex: Int { return 0 }
        public var endIndex: Int { return keys.count }
        public subscript(i: Int) -> ArchiveHeader.FieldKey { return ArchiveHeader.FieldKey(keys[i]) }
        public var isEmpty: Bool { return keys.isEmpty }

        // MARK: SetAlgebra

        public func contains(_ member: ArchiveHeader.FieldKey) -> Bool {
            return keys.contains(canonical(member))
        }

        @discardableResult
        public func insert(_ newMember: __owned ArchiveHeader.FieldKey) -> (inserted: Bool, memberAfterInsert: ArchiveHeader.FieldKey) {
            let key = canonical(newMember)
            if let i = keys.firstIndex(of: key) {
                return (inserted: false, memberAfterInsert: ArchiveHeader.FieldKey(keys[i]))
            }
            keys.append(key)
            return (inserted: true, memberAfterInsert: ArchiveHeader.FieldKey(key))
        }

        @discardableResult
        public func remove(_ member: ArchiveHeader.FieldKey) -> ArchiveHeader.FieldKey? {
            let key = canonical(member)
            guard let i = keys.firstIndex(of: key) else { return nil }
            keys.remove(at: i)
            return ArchiveHeader.FieldKey(key)
        }

        @discardableResult
        public func update(with newMember: __owned ArchiveHeader.FieldKey) -> ArchiveHeader.FieldKey? {
            let key = canonical(newMember)
            guard let i = keys.firstIndex(of: key) else {
                keys.append(key)
                return nil
            }
            return ArchiveHeader.FieldKey(keys[i])
        }

        public func formUnion(_ other: ArchiveHeader.FieldKeySet) {
            for key in other.keys where !keys.contains(key) { keys.append(key) }
        }

        public func formIntersection(_ other: ArchiveHeader.FieldKeySet) {
            keys = keys.filter { other.keys.contains($0) }
        }

        public func formSymmetricDifference(_ other: __owned ArchiveHeader.FieldKeySet) {
            var kept = keys.filter { !other.keys.contains($0) }
            for key in other.keys where !keys.contains(key) { kept.append(key) }
            keys = kept
        }

        public func union(_ other: ArchiveHeader.FieldKeySet) -> ArchiveHeader.FieldKeySet {
            let result = ArchiveHeader.FieldKeySet(copying: self)
            result.formUnion(other)
            return result
        }

        public func intersection(_ other: ArchiveHeader.FieldKeySet) -> ArchiveHeader.FieldKeySet {
            let result = ArchiveHeader.FieldKeySet(copying: self)
            result.formIntersection(other)
            return result
        }

        public func symmetricDifference(_ other: __owned ArchiveHeader.FieldKeySet) -> ArchiveHeader.FieldKeySet {
            let result = ArchiveHeader.FieldKeySet(copying: self)
            result.formSymmetricDifference(other)
            return result
        }

        /// Set equality: the same keys, whatever order the two sets hold them in.
        public static func == (lhs: ArchiveHeader.FieldKeySet, rhs: ArchiveHeader.FieldKeySet) -> Bool {
            return lhs.keys.count == rhs.keys.count && lhs.keys.allSatisfy { rhs.keys.contains($0) }
        }
    }
}

/// Declared in an extension, as the SDK does, so the accessor is statically dispatched and the
/// direct `vg` symbol the client binds is exported (a class-body property would instead be reached
/// through a `Tj` thunk and its direct symbol hidden).
extension ArchiveHeader {
    /// Answers with the real absence: there is no decoded entry, so there is no path.
    public var entryPath: System.FilePath? {
        return nil
    }
}
