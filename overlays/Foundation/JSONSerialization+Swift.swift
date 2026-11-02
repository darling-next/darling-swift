//===----------------------------------------------------------------------===//
//
// This source file is part of the darling-swift project.
// Licensed under Apache License v2.0 with Runtime Library Exception
//
//===----------------------------------------------------------------------===//

// A JSON writer and parser (RFC 8259) for the Foundation object trees JSONEncoder and JSONDecoder build and read:
// NSDictionary with string keys, NSArray, NSString, NSNumber (the kCFBooleanTrue/kCFBooleanFalse singletons for
// booleans) and NSNull.
// Written for Darling, whose NSJSONSerialization ignores NSJSONWritingSortedKeys, pretty-prints with tabs, reports
// no error for unsupported values and has a fragile number parser. The output follows macOS's JSONSerialization:
// two-space indentation, " : " between keys and values when pretty-printed, and "/" escaped unless asked not to.
//
// The reader has two modes. The default is RFC 8259 exactly as before. `object(with:json5: true)` reads JSON5
// instead: comments, unquoted (ECMAScript IdentifierName) keys, single-quoted strings, trailing commas in objects
// and arrays, the extra string escapes (\v, \0, \xHH, line continuations), and the extra number spellings
// (+/-, hex, Infinity, NaN, leading and trailing decimal point, leading zeros). This is the parser behind
// JSONDecoder.allowsJSON5 (macOS 12). Everything the JSON5 mode cannot read throws `Error.invalidJSON`; it never
// falls back to JSON's grammar, so JSON5 input is either decoded to the value JSON5 defines or fails loudly.

@_exported import Foundation // Clang module

/// An integer above Int64.max in the boxed tree. Darling's NSNumber stores those as signed 64-bit values, so they
/// would read back negative; the writer and the decoder's numeric unboxing handle this box instead.
internal final class _JSONUnsignedNumber : NSObject {
    let value: UInt64

    init(_ value: UInt64) {
        self.value = value
        super.init()
    }
}

internal enum _JSONSerialization {
    struct WritingOptions {
        var prettyPrinted = false
        var sortedKeys = false
        var withoutEscapingSlashes = false
    }

    enum Error : Swift.Error, CustomStringConvertible {
        case invalidValue(String)
        case invalidJSON(String, offset: Int)

        var description: String {
            switch self {
            case .invalidValue(let reason): return reason
            case .invalidJSON(let reason, let offset): return "\(reason) around byte \(offset)."
            }
        }
    }

    static let trueNumber = unsafeBitCast(kCFBooleanTrue, to: NSNumber.self)
    static let falseNumber = unsafeBitCast(kCFBooleanFalse, to: NSNumber.self)

    // MARK: - Writing

    static func data(with object: Any, options: WritingOptions) throws -> Data {
        var writer = _Writer(options: options)
        try writer.write(object, depth: 0)
        return Data(writer.bytes)
    }

    private struct _Writer {
        let options: WritingOptions
        var bytes: [UInt8] = []

        init(options: WritingOptions) {
            self.options = options
        }

        mutating func append(_ string: String) {
            bytes.append(contentsOf: string.utf8)
        }

        mutating func indent(_ depth: Int) {
            bytes.append(contentsOf: repeatElement(UInt8(ascii: " "), count: 2 * depth))
        }

        mutating func write(_ object: Any, depth: Int) throws {
            switch object {
            case let number as NSNumber:
                try writeNumber(number)
            case let number as _JSONUnsignedNumber:
                append(String(number.value))
            case let string as String:
                writeString(string)
            case is NSNull:
                append("null")
            case let dictionary as NSDictionary:
                try writeDictionary(dictionary, depth: depth)
            case let array as NSArray:
                try writeArray(array, depth: depth)
            default:
                throw Error.invalidValue("Invalid type in JSON write (\(type(of: object))).")
            }
        }

        mutating func writeNumber(_ number: NSNumber) throws {
            if number === _JSONSerialization.trueNumber {
                append("true")
                return
            }
            if number === _JSONSerialization.falseNumber {
                append("false")
                return
            }
            switch number.objCType().map({ String(cString: $0) }) ?? "" {
            case "f":
                let float = number.floatValue()
                guard float.isFinite else {
                    throw Error.invalidValue("Invalid number value (\(float)) in JSON write.")
                }
                appendFloatingPoint(float.description)
            case "d":
                let double = number.doubleValue()
                guard double.isFinite else {
                    throw Error.invalidValue("Invalid number value (\(double)) in JSON write.")
                }
                appendFloatingPoint(double.description)
            default:
                append(String(number.longLongValue()))
            }
        }

        /// Writes a floating-point description without a trailing ".0", as macOS does ("1", "1e+16", "-0").
        mutating func appendFloatingPoint(_ description: String) {
            append(description.hasSuffix(".0") ? String(description.dropLast(2)) : description)
        }

        mutating func writeString(_ string: String) {
            bytes.append(UInt8(ascii: "\""))
            for scalar in string.unicodeScalars {
                switch scalar {
                case "\"": append("\\\"")
                case "\\": append("\\\\")
                case "/": append(options.withoutEscapingSlashes ? "/" : "\\/")
                case "\n": append("\\n")
                case "\r": append("\\r")
                case "\t": append("\\t")
                case "\u{8}": append("\\b")
                case "\u{C}": append("\\f")
                case _ where scalar.value < 0x20:
                    let hex = String(scalar.value, radix: 16)
                    append("\\u" + String(repeating: "0", count: 4 - hex.count) + hex)
                default:
                    bytes.append(contentsOf: String(scalar).utf8)
                }
            }
            bytes.append(UInt8(ascii: "\""))
        }

        mutating func writeDictionary(_ dictionary: NSDictionary, depth: Int) throws {
            var entries: [(key: String, value: Any)] = []
            for key in dictionary.allKeys() {
                let value: Any = dictionary.object(forKey: key)!
                guard let key = key as? String else {
                    throw Error.invalidValue("Invalid key in JSON write (\(type(of: key))).")
                }
                entries.append((key, value))
            }
            if options.sortedKeys {
                // The order JSONSerialization's sortedKeys uses for apps built against these SDKs.
                let order = NSStringCompareOptions([.numeric, .caseInsensitive, .forcedOrdering])
                entries.sort { $0.key.compare($1.key, options: order) == .orderedAscending }
            }
            guard !entries.isEmpty else {
                append(options.prettyPrinted ? "{\n\n" : "{")
                if options.prettyPrinted { indent(depth) }
                append("}")
                return
            }
            append("{")
            for (index, entry) in entries.enumerated() {
                if index > 0 { append(",") }
                if options.prettyPrinted {
                    append("\n")
                    indent(depth + 1)
                }
                writeString(entry.key)
                append(options.prettyPrinted ? " : " : ":")
                try write(entry.value, depth: depth + 1)
            }
            if options.prettyPrinted {
                append("\n")
                indent(depth)
            }
            append("}")
        }

        mutating func writeArray(_ array: NSArray, depth: Int) throws {
            guard array.count() > 0 else {
                append(options.prettyPrinted ? "[\n\n" : "[")
                if options.prettyPrinted { indent(depth) }
                append("]")
                return
            }
            append("[")
            for index in 0..<array.count() {
                if index > 0 { append(",") }
                if options.prettyPrinted {
                    append("\n")
                    indent(depth + 1)
                }
                try write(array.object(at: index) as Any, depth: depth + 1)
            }
            if options.prettyPrinted {
                append("\n")
                indent(depth)
            }
            append("]")
        }
    }

    // MARK: - Parsing

    /// Reads one JSON value from `data`. With `json5` true the JSON5 grammar is read instead of RFC 8259.
    static func object(with data: Data, json5: Bool = false) throws -> Any {
        var parser = _Parser(bytes: [UInt8](data), json5: json5)
        parser.skipByteOrderMark()
        try parser.skipWhitespace()
        let value = try parser.parseValue(depth: 0)
        try parser.skipWhitespace()
        guard parser.offset == parser.bytes.count else {
            throw Error.invalidJSON("Garbage at end", offset: parser.offset)
        }
        return value
    }

    private struct _Parser {
        let bytes: [UInt8]
        let json5: Bool
        var offset = 0

        init(bytes: [UInt8], json5: Bool) {
            self.bytes = bytes
            self.json5 = json5
        }

        var current: UInt8? {
            return offset < bytes.count ? bytes[offset] : nil
        }

        mutating func skipByteOrderMark() {
            if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
                offset = 3
            }
        }

        /// Skips whitespace, and in JSON5 mode also comments and the extra JSON5 whitespace (VT, FF, NBSP).
        mutating func skipWhitespace() throws {
            while let byte = current {
                if byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D {
                    offset += 1
                    continue
                }
                if json5 {
                    if byte == 0x0B || byte == 0x0C || byte == 0xA0 {
                        offset += 1
                        continue
                    }
                    if byte == UInt8(ascii: "/"), try skipComment() {
                        continue
                    }
                }
                break
            }
        }

        /// Skips a JSON5 `//` or `/* */` comment. Returns false when the bytes are not a comment; an
        /// unterminated `/* */` throws, and an unterminated `//` runs to end of input.
        private mutating func skipComment() throws -> Bool {
            guard offset + 1 < bytes.count else { return false }
            switch bytes[offset + 1] {
            case UInt8(ascii: "/"):
                offset += 2
                while let byte = current, byte != 0x0A && byte != 0x0D { offset += 1 }
                return true
            case UInt8(ascii: "*"):
                offset += 2
                while offset + 1 < bytes.count {
                    if bytes[offset] == UInt8(ascii: "*"), bytes[offset + 1] == UInt8(ascii: "/") {
                        offset += 2
                        return true
                    }
                    offset += 1
                }
                throw Error.invalidJSON("Unterminated block comment", offset: offset)
            default:
                return false
            }
        }

        mutating func expect(_ literal: String) throws {
            let utf8 = Array(literal.utf8)
            guard offset + utf8.count <= bytes.count, Array(bytes[offset..<offset + utf8.count]) == utf8 else {
                throw Error.invalidJSON("Invalid value", offset: offset)
            }
            offset += utf8.count
        }

        mutating func parseValue(depth: Int) throws -> Any {
            guard depth < 512 else {
                throw Error.invalidJSON("Too many nested arrays or dictionaries", offset: offset)
            }
            guard let byte = current else {
                throw Error.invalidJSON("Unexpected end of file", offset: offset)
            }
            switch byte {
            case UInt8(ascii: "{"): return try parseObject(depth: depth)
            case UInt8(ascii: "["): return try parseArray(depth: depth)
            case UInt8(ascii: "\""): return NSString(string: try parseString(quote: byte))
            case UInt8(ascii: "t"):
                try expect("true")
                return _JSONSerialization.trueNumber
            case UInt8(ascii: "f"):
                try expect("false")
                return _JSONSerialization.falseNumber
            case UInt8(ascii: "n"):
                try expect("null")
                return NSNull()
            case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"):
                return json5 ? try parseJSON5Number() : try parseNumber()
            case UInt8(ascii: "'") where json5:
                return NSString(string: try parseString(quote: byte))
            case UInt8(ascii: "+"), UInt8(ascii: "."), UInt8(ascii: "I"), UInt8(ascii: "N"):
                // JSON5-only value starts: a leading sign, a leading decimal point, or Infinity/NaN.
                guard json5 else { throw Error.invalidJSON("Invalid value", offset: offset) }
                return try parseJSON5Number()
            default:
                throw Error.invalidJSON("Invalid value", offset: offset)
            }
        }

        mutating func parseObject(depth: Int) throws -> NSDictionary {
            let result = NSMutableDictionary()
            offset += 1
            try skipWhitespace()
            if current == UInt8(ascii: "}") {
                offset += 1
                return result
            }
            while true {
                try skipWhitespace()
                let key: String
                switch current {
                case UInt8(ascii: "\""):
                    key = try parseString(quote: UInt8(ascii: "\""))
                case UInt8(ascii: "'") where json5:
                    key = try parseString(quote: UInt8(ascii: "'"))
                default:
                    // JSON5 object keys may be unquoted ECMAScript IdentifierNames.
                    guard json5 else {
                        throw Error.invalidJSON("No string key for value in object", offset: offset)
                    }
                    key = try parseUnquotedKey()
                }
                try skipWhitespace()
                guard current == UInt8(ascii: ":") else {
                    throw Error.invalidJSON("No value for key in object", offset: offset)
                }
                offset += 1
                try skipWhitespace()
                let value = try parseValue(depth: depth + 1)
                result.setObject(value, forKey: NSString(string: key))
                try skipWhitespace()
                switch current {
                case UInt8(ascii: ","):
                    offset += 1
                    if json5 {
                        // JSON5 allows a trailing comma before the closing brace.
                        try skipWhitespace()
                        if current == UInt8(ascii: "}") {
                            offset += 1
                            return result
                        }
                    }
                case UInt8(ascii: "}"):
                    offset += 1
                    return result
                default:
                    throw Error.invalidJSON("Badly formed object", offset: offset)
                }
            }
        }

        mutating func parseArray(depth: Int) throws -> NSArray {
            let result = NSMutableArray()!
            offset += 1
            try skipWhitespace()
            if current == UInt8(ascii: "]") {
                offset += 1
                return result
            }
            while true {
                try skipWhitespace()
                result.add(try parseValue(depth: depth + 1))
                try skipWhitespace()
                switch current {
                case UInt8(ascii: ","):
                    offset += 1
                    if json5 {
                        // JSON5 allows a trailing comma before the closing bracket.
                        try skipWhitespace()
                        if current == UInt8(ascii: "]") {
                            offset += 1
                            return result
                        }
                    }
                case UInt8(ascii: "]"):
                    offset += 1
                    return result
                default:
                    throw Error.invalidJSON("Badly formed array", offset: offset)
                }
            }
        }

        mutating func parseHex4() throws -> UInt32 {
            guard offset + 4 <= bytes.count else {
                throw Error.invalidJSON("Invalid unicode escape sequence", offset: offset)
            }
            var value: UInt32 = 0
            for byte in bytes[offset..<offset + 4] {
                let digit: UInt8
                switch byte {
                case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = byte - UInt8(ascii: "0")
                case UInt8(ascii: "a")...UInt8(ascii: "f"): digit = byte - UInt8(ascii: "a") + 10
                case UInt8(ascii: "A")...UInt8(ascii: "F"): digit = byte - UInt8(ascii: "A") + 10
                default: throw Error.invalidJSON("Invalid unicode escape sequence", offset: offset)
                }
                value = value * 16 + UInt32(digit)
            }
            offset += 4
            return value
        }

        /// Parses a quoted string. `quote` is the delimiter: `"` in both dialects, `'` in JSON5 only.
        mutating func parseString(quote: UInt8) throws -> String {
            offset += 1
            var utf8: [UInt8] = []
            while true {
                guard let byte = current else {
                    throw Error.invalidJSON("Unexpected end of file during string parse", offset: offset)
                }
                offset += 1
                if byte == quote {
                    guard let string = String(validating: utf8, as: UTF8.self) else {
                        throw Error.invalidJSON("Unable to convert data to a string using UTF-8", offset: offset)
                    }
                    return string
                }
                switch byte {
                case UInt8(ascii: "\\"):
                    guard let escaped = current else {
                        throw Error.invalidJSON("Unexpected end of file during string parse", offset: offset)
                    }
                    offset += 1
                    switch escaped {
                    case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"): utf8.append(escaped)
                    case UInt8(ascii: "'") where json5: utf8.append(escaped)
                    case UInt8(ascii: "b"): utf8.append(0x08)
                    case UInt8(ascii: "f"): utf8.append(0x0C)
                    case UInt8(ascii: "n"): utf8.append(0x0A)
                    case UInt8(ascii: "r"): utf8.append(0x0D)
                    case UInt8(ascii: "t"): utf8.append(0x09)
                    case UInt8(ascii: "v") where json5: utf8.append(0x0B)
                    case UInt8(ascii: "0") where json5:
                        // \0 is NUL, unless a decimal digit follows it (which JSON5 forbids).
                        if let next = current, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(next) {
                            throw Error.invalidJSON("Invalid escape sequence", offset: offset)
                        }
                        utf8.append(0x00)
                    case UInt8(ascii: "x") where json5:
                        guard let value = try parseHex2() else {
                            throw Error.invalidJSON("Invalid escape sequence", offset: offset)
                        }
                        utf8.append(value)
                    case 0x0A, 0x0D:
                        // A JSON5 line continuation (backslash before a line terminator) produces
                        // nothing; JSON rejects the escape.
                        guard json5 else { throw Error.invalidJSON("Invalid escape sequence", offset: offset) }
                        if escaped == 0x0D, current == 0x0A { offset += 1 }
                    case UInt8(ascii: "u"):
                        var value = try parseHex4()
                        if (0xD800..<0xDC00).contains(value) {
                            // A high surrogate must be followed by an escaped low surrogate.
                            guard current == UInt8(ascii: "\\"), offset + 1 < bytes.count, bytes[offset + 1] == UInt8(ascii: "u") else {
                                throw Error.invalidJSON("Unable to convert hex escape sequence (no low character) to UTF8-encoded character", offset: offset)
                            }
                            offset += 2
                            let low = try parseHex4()
                            guard (0xDC00..<0xE000).contains(low) else {
                                throw Error.invalidJSON("Unable to convert hex escape sequence (invalid low character) to UTF8-encoded character", offset: offset)
                            }
                            value = 0x10000 + ((value - 0xD800) << 10) + (low - 0xDC00)
                        } else if (0xDC00..<0xE000).contains(value) {
                            throw Error.invalidJSON("Unable to convert hex escape sequence (no high character) to UTF8-encoded character", offset: offset)
                        }
                        guard let scalar = Unicode.Scalar(value) else {
                            throw Error.invalidJSON("Invalid unicode escape sequence", offset: offset)
                        }
                        utf8.append(contentsOf: String(scalar).utf8)
                    default:
                        // A JSON5 line continuation may also escape U+2028 or U+2029.
                        if json5, escaped == 0xE2, current == 0x80, offset + 1 < bytes.count,
                           bytes[offset + 1] == 0xA8 || bytes[offset + 1] == 0xA9 {
                            offset += 2
                        } else {
                            throw Error.invalidJSON("Invalid escape sequence", offset: offset)
                        }
                    }
                case 0x0A, 0x0D:
                    // Unescaped line terminators are not legal in a string in either dialect.
                    throw Error.invalidJSON("Unescaped control character", offset: offset)
                case 0x00..<0x20 where !json5:
                    throw Error.invalidJSON("Unescaped control character", offset: offset)
                default:
                    // JSON5 additionally forbids unescaped U+2028 and U+2029 in a string.
                    if json5, byte == 0xE2, current == 0x80, offset + 1 < bytes.count,
                       bytes[offset + 1] == 0xA8 || bytes[offset + 1] == 0xA9 {
                        throw Error.invalidJSON("Unescaped control character", offset: offset)
                    }
                    utf8.append(byte)
                }
            }
        }

        /// Reads the two hex digits of a JSON5 `\xHH` string escape, or nil if they are not hex digits.
        mutating func parseHex2() throws -> UInt8? {
            guard offset + 2 <= bytes.count else { return nil }
            var value: UInt8 = 0
            for byte in bytes[offset..<offset + 2] {
                let digit: UInt8
                switch byte {
                case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = byte - UInt8(ascii: "0")
                case UInt8(ascii: "a")...UInt8(ascii: "f"): digit = byte - UInt8(ascii: "a") + 10
                case UInt8(ascii: "A")...UInt8(ascii: "F"): digit = byte - UInt8(ascii: "A") + 10
                default: return nil
                }
                value = value &* 16 &+ digit
            }
            offset += 2
            return value
        }

        /// Parses a JSON5 unquoted object key: an ECMAScript IdentifierName.
        mutating func parseUnquotedKey() throws -> String {
            var scalars: [Unicode.Scalar] = []
            var isStart = true
            loop: while let byte = current {
                if byte == UInt8(ascii: "\\") {
                    // An escaped code point, which JSON5 allows in an unquoted key.
                    guard offset + 1 < bytes.count, bytes[offset + 1] == UInt8(ascii: "u") else {
                        throw Error.invalidJSON("Invalid identifier escape in object key", offset: offset)
                    }
                    offset += 2
                    let value = try parseHex4()
                    guard let scalar = Unicode.Scalar(value) else {
                        throw Error.invalidJSON("Invalid identifier escape in object key", offset: offset)
                    }
                    scalars.append(scalar)
                    isStart = false
                    continue
                }
                if byte < 0x80 {
                    let letter = (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
                        || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
                    if isStart {
                        guard letter || byte == UInt8(ascii: "$") || byte == UInt8(ascii: "_") else { break loop }
                    } else {
                        guard letter || byte == UInt8(ascii: "$") || byte == UInt8(ascii: "_")
                            || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) else { break loop }
                    }
                    scalars.append(Unicode.Scalar(byte))
                    offset += 1
                    isStart = false
                    continue
                }
                // A non-ASCII code point must be a letter to be an identifier character.
                guard let (scalar, length) = decodeScalar(at: offset), scalar.properties.isAlphabetic else { break loop }
                scalars.append(scalar)
                offset += length
                isStart = false
            }
            guard !scalars.isEmpty else {
                throw Error.invalidJSON("No string key for value in object", offset: offset)
            }
            return String(String.UnicodeScalarView(scalars))
        }

        /// Decodes one UTF-8 code point at `index`, returning it with its byte length, or nil if invalid.
        func decodeScalar(at index: Int) -> (Unicode.Scalar, Int)? {
            let first = bytes[index]
            if first < 0x80 { return (Unicode.Scalar(first), 1) }
            var value: UInt32
            let length: Int
            switch first {
            case 0xC2...0xDF: value = UInt32(first & 0x1F); length = 2
            case 0xE0...0xEF: value = UInt32(first & 0x0F); length = 3
            case 0xF0...0xF4: value = UInt32(first & 0x07); length = 4
            default: return nil
            }
            guard index + length <= bytes.count else { return nil }
            for i in 1..<length {
                let byte = bytes[index + i]
                guard byte & 0xC0 == 0x80 else { return nil }
                value = (value << 6) | UInt32(byte & 0x3F)
            }
            guard let scalar = Unicode.Scalar(value) else { return nil }
            return (scalar, length)
        }

        static func isHexDigit(_ byte: UInt8) -> Bool {
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"),
                 UInt8(ascii: "a")...UInt8(ascii: "f"),
                 UInt8(ascii: "A")...UInt8(ascii: "F"):
                return true
            default:
                return false
            }
        }

        /// Parses a JSON5 number: `+`/`-`, hex, `Infinity`/`NaN`, a leading or trailing decimal point, and
        /// leading zeros are all legal in addition to the JSON forms.
        mutating func parseJSON5Number() throws -> NSObject {
            let start = offset
            var negative = false
            if current == UInt8(ascii: "+") {
                offset += 1
            } else if current == UInt8(ascii: "-") {
                negative = true
                offset += 1
            }

            if current == UInt8(ascii: "I") {
                try expect("Infinity")
                return NSNumber(value: negative ? -Double.infinity : Double.infinity)
            }
            if current == UInt8(ascii: "N") {
                try expect("NaN")
                return NSNumber(value: Double.nan)
            }

            if current == UInt8(ascii: "0"), offset + 1 < bytes.count,
               bytes[offset + 1] == UInt8(ascii: "x") || bytes[offset + 1] == UInt8(ascii: "X") {
                offset += 2
                let digits = offset
                while let byte = current, Self.isHexDigit(byte) { offset += 1 }
                guard offset > digits else { throw Error.invalidJSON("Invalid number", offset: start) }
                let text = String(decoding: bytes[digits..<offset], as: UTF8.self)
                guard let magnitude = UInt64(text, radix: 16) else {
                    throw Error.invalidJSON("Number \(text) is not representable", offset: start)
                }
                if negative {
                    if magnitude <= UInt64(Int64.max) + 1 {
                        return NSNumber(value: magnitude == UInt64(Int64.max) + 1 ? Int64.min : -Int64(magnitude))
                    }
                    return NSNumber(value: -Double(magnitude))
                }
                if magnitude <= UInt64(Int64.max) { return NSNumber(value: Int64(magnitude)) }
                return _JSONUnsignedNumber(magnitude)
            }

            var sawDigit = false
            while let byte = current, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) {
                offset += 1
                sawDigit = true
            }
            var isInteger = true
            if current == UInt8(ascii: ".") {
                isInteger = false
                offset += 1
                while let byte = current, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) {
                    offset += 1
                    sawDigit = true
                }
            }
            guard sawDigit else { throw Error.invalidJSON("Invalid number", offset: start) }
            if current == UInt8(ascii: "e") || current == UInt8(ascii: "E") {
                isInteger = false
                offset += 1
                if current == UInt8(ascii: "+") || current == UInt8(ascii: "-") { offset += 1 }
                let digits = offset
                while let byte = current, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) { offset += 1 }
                guard offset > digits else { throw Error.invalidJSON("Invalid number", offset: start) }
            }
            let text = String(decoding: bytes[start..<offset], as: UTF8.self)
            // "-0" and "+0" stay a Double so their sign survives; integer decoding still gets 0.
            if isInteger && text != "-0" && text != "+0" {
                if let value = Int64(text) { return NSNumber(value: value) }
                if !negative, let value = UInt64(text) { return _JSONUnsignedNumber(value) }
            }
            guard let value = Double(text), value.isFinite else {
                throw Error.invalidJSON("Number \(text) is not representable", offset: start)
            }
            return NSNumber(value: value)
        }

        mutating func parseNumber() throws -> NSObject {
            let start = offset
            var isInteger = true
            if current == UInt8(ascii: "-") { offset += 1 }
            guard let first = current, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(first) else {
                throw Error.invalidJSON("Invalid number", offset: start)
            }
            if first == UInt8(ascii: "0") {
                offset += 1
            } else {
                while let byte = current, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) { offset += 1 }
            }
            if current == UInt8(ascii: ".") {
                isInteger = false
                offset += 1
                let digits = offset
                while let byte = current, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) { offset += 1 }
                guard offset > digits else { throw Error.invalidJSON("Invalid number", offset: start) }
            }
            if current == UInt8(ascii: "e") || current == UInt8(ascii: "E") {
                isInteger = false
                offset += 1
                if current == UInt8(ascii: "+") || current == UInt8(ascii: "-") { offset += 1 }
                let digits = offset
                while let byte = current, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) { offset += 1 }
                guard offset > digits else { throw Error.invalidJSON("Invalid number", offset: start) }
            }
            let text = String(decoding: bytes[start..<offset], as: UTF8.self)
            // "-0" stays a Double so its sign survives; integer decoding still gets 0.
            if isInteger && text != "-0" {
                if let value = Int64(text) { return NSNumber(value: value) }
                if let value = UInt64(text) { return _JSONUnsignedNumber(value) }
            }
            guard let value = Double(text), value.isFinite else {
                throw Error.invalidJSON("Number \(text) is not representable", offset: start)
            }
            return NSNumber(value: value)
        }
    }
}
