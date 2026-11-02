import Foundation

private struct Failure: Error { let message: String }
private func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw Failure(message: message) }
}

private func run() throws {
    let text = "α β\r\n\r\n雪\u{2028}last"
    var lines: [String] = []
    text.enumerateLines { line, _ in lines.append(line) }
    try require(lines == ["α β", "", "雪", "last"], "Hard lines lost whitespace, empty lines or Unicode separators")
    var stopped: [String] = []
    text.enumerateLines { line, stop in stopped.append(line); stop = true }
    try require(stopped == ["α β"], "Line enumeration ignored stop")
    var called = false
    "".enumerateLines { _, _ in called = true }
    try require(!called, "An empty string produced a line")

    let original = "prefix:🦊 tail\r\nnext:suffix"
    let lower = original.index(original.startIndex, offsetBy: 7)
    let upper = original.index(original.endIndex, offsetBy: -7)
    let slice = original[lower..<upper]
    var start = original.startIndex, end = original.startIndex, contents = original.startIndex
    slice.getLineStart(&start, end: &end, contentsEnd: &contents, for: slice.startIndex..<slice.startIndex)
    try require(start == slice.startIndex && String(slice[start..<contents]) == "🦊 tail", "Substring line bounds lost the original index base")
    try require(String(slice[contents..<end]) == "\r\n", "CRLF was not one line terminator")
    slice.getLineStart(&start, end: &end, contentsEnd: &contents, for: slice.endIndex..<slice.endIndex)
    try require(String(slice[start..<contents]) == "next" && end == slice.endIndex && contents == end, "Unterminated final-line bounds are incorrect")

    let encoded = URL(string: "custom://alpha%2Fbeta:8443/base/")!
    let relative = URL(string: "../child", relativeTo: encoded)!
    try require(relative.host(percentEncoded: true) == "alpha%2Fbeta", "Encoded host failed base resolution")
    try require(relative.host(percentEncoded: false) == "alpha/beta", "Host percent decoding is incorrect")
    let ipv6 = URL(string: "https://[2001:db8::1]:8443/path")!
    try require(ipv6.host(percentEncoded: true) == "2001:db8::1" && ipv6.host(percentEncoded: false) == "2001:db8::1", "IPv6 host leaked URI brackets")
    let idn = URL(string: "https://xn--bcher-kva.example/path")!
    try require(idn.host(percentEncoded: true) == "b%C3%BCcher.example", "IDNA Unicode host was not percent encoded")
    try require(idn.host(percentEncoded: false) == "xn--bcher-kva.example", "Unescaped IDNA host lost its ASCII representation")
    try require(URL(string: "mailto:user@example.com")!.host(percentEncoded: true) == nil, "An opaque URL fabricated a host")

    let oldURL = URL(fileURLWithPath: "/old")
    let explicitURL = URL(fileURLWithPath: "/explicit")
    let error = CocoaError.error(.fileReadInvalidFileName, userInfo: [NSURLErrorKey: oldURL], url: explicitURL)
    guard let cocoa = error as? CocoaError else { throw Failure(message: "Factory error did not bridge as CocoaError") }
    try require(cocoa.code.rawValue == 258, "Factory lost the Cocoa file-name failure code")
    try require(cocoa.errorUserInfo[NSURLErrorKey] as? URL == explicitURL, "Explicit factory URL did not override userInfo URL")

    var template = Array("/private/var/tmp/foundation-values.XXXXXX".utf8CString)
    let base = try template.withUnsafeMutableBufferPointer { buffer -> String in
        guard let created = mkdtemp(buffer.baseAddress!) else { throw Failure(message: "mkdtemp failed") }
        return String(cString: created)
    }
    let real = base + "/real"
    let link = base + "/link"
    let file = real + "/payload"
    defer { unlink(file); unlink(link); rmdir(real); rmdir(base) }
    try require(mkdir(real, 0o700) == 0, "Cannot create fixture directory")
    let fd = open(file, O_CREAT | O_EXCL | O_WRONLY, 0o600)
    try require(fd >= 0, "Cannot create fixture file")
    close(fd)
    try require(symlink("real", link) == 0, "Cannot create relative symlink")
    let aliased = URL(fileURLWithPath: link + "/./payload", isDirectory: false, relativeTo: nil)
    let values = try aliased.resourceValues(forKeys: [.canonicalPathKey])
    try require(values.canonicalPath == file, "Canonical path did not resolve the real symlink target")
    let unrequested = try aliased.resourceValues(forKeys: [.isRegularFileKey])
    try require(unrequested.canonicalPath == nil, "Resource lookup populated an unrequested canonical path")
}

do {
    try run()
    print("FOUNDATION_VALUE_SEMANTICS_PASS")
} catch {
    print("FOUNDATION_VALUE_SEMANTICS_FAIL: \(error)")
    exit(1)
}
