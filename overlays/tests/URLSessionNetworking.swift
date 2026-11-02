// Guest consumer regression; compile against the built Foundation overlay.
// Arguments: HTTP download URL, WS echo URL, WS invalid-upgrade URL, WSS URL
// signed by an untrusted/self-signed CA. The download body is "download-payload".
// The echo server must handle RFC6455 ping/pong, text, binary and close frames.
import Foundation

@available(macOS 12.0, *)
@main struct URLSessionNetworking {
  static func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw NSError(domain: "URLSessionNetworking", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
  }

  static func requireURLFailure(_ error: NSError, _ code: URLError.Code, _ message: String) throws {
    try require(error._domain == NSURLErrorDomain && error._code == code.rawValue,
                "\(message): \(error._domain):\(error._code)")
  }

  static func certificateValidationFailure(_ root: NSError) -> Bool {
    // Security/base/SecBase.h defines these certificate-validation statuses.
    // CFNetwork's SharedCode/CFError.c preserves SSL status codes under "SSL";
    // other providers may retain NSOSStatusErrorDomain or wrap in NSUnderlyingErrorKey.
    // Generic TLS negotiation, EOF, connection refusal and timeouts do not qualify.
    let certificateStatuses = [
      Int(errSSLXCertChainInvalid), Int(errSSLUnknownRootCert), Int(errSSLNoRootCert),
      Int(errSSLCertExpired), Int(errSSLCertNotYetValid), Int(errSSLHostNameMismatch)
    ]
    let urlCertificateStatuses = [
      URLError.Code.serverCertificateUntrusted.rawValue,
      URLError.Code.serverCertificateHasUnknownRoot.rawValue,
      URLError.Code.serverCertificateHasBadDate.rawValue,
      URLError.Code.serverCertificateNotYetValid.rawValue
    ]
    var next: NSError? = root
    var seen = Set<ObjectIdentifier>()
    while let error = next, seen.insert(ObjectIdentifier(error)).inserted {
      let domain = error._domain
      if (domain == "SSL" || domain == NSOSStatusErrorDomain || domain == "MacOSStatus") &&
          certificateStatuses.contains(error._code) { return true }
      if domain == NSURLErrorDomain && urlCertificateStatuses.contains(error._code) { return true }
      next = (error._userInfo as? [String: Any])?[NSUnderlyingErrorKey] as? NSError
    }
    return false
  }

  static func receive(_ task: URLSessionWebSocketTask) async throws -> URLSessionWebSocketTask.Message {
    try await withCheckedThrowingContinuation { continuation in
      task.receive { continuation.resume(with: $0) }
    }
  }

  static func send(_ message: URLSessionWebSocketTask.Message, _ task: URLSessionWebSocketTask) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      task.send(message) { error in
        if let error = error { continuation.resume(throwing: error) }
        else { continuation.resume(returning: ()) }
      }
    }
  }

  static func mustFail(_ task: URLSessionWebSocketTask) async throws -> NSError {
    task.resume()
    do { _ = try await receive(task) }
    catch { return error as NSError }
    throw NSError(domain: "URLSessionNetworking", code: 2, userInfo: [NSLocalizedDescriptionKey: "A rejected connection delivered a message"])
  }

  static func main() async throws {
    try require(CommandLine.arguments.count == 5, "Expected download, echo, invalid-upgrade and untrusted-TLS URLs")
    let session = URLSession(configuration: .default)
    defer { session.invalidateAndCancel() }
    let request = URLRequest(url: URL(string: CommandLine.arguments[1])!)
    let (location, response) = try await session.download(for: request)
    defer { try? FileManager.default.removeItem(at: location) }
    // This read happens after the native completion callback returned; it catches
    // temporary-file deletion before the async consumer acquires ownership.
    let body = try Data(contentsOf: location)
    try require(body == Data("download-payload".utf8), "Download bytes/temporary-file ownership are incorrect")
    try require((response as? HTTPURLResponse)?.statusCode == 200, "Download response is not HTTP 200")
    let (data, _) = try await session.data(for: request)
    try require(data == body, "data(for:) and download(for:) disagree")

    let socket = session.webSocketTask(with: URL(string: CommandLine.arguments[2])!)
    socket.resume()
    try await send(.string("Darling ☃"), socket)
    guard case .string(let text) = try await receive(socket) else { throw NSError(domain: "URLSessionNetworking", code: 3) }
    try require(text == "Darling ☃", "Text/UTF-8 echo mismatch")
    let bytes = Data([0, 1, 127, 128, 255])
    try await send(.data(bytes), socket)
    guard case .data(let binary) = try await receive(socket) else { throw NSError(domain: "URLSessionNetworking", code: 4) }
    try require(binary == bytes, "Binary echo mismatch")
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      socket.sendPing { error in
        if let error = error { continuation.resume(throwing: error) }
        else { continuation.resume(returning: ()) }
      }
    }
    // Register a pending receive, then cancel. It must fail once, not hang or
    // deliver a fabricated frame. Cancellation before first resume is tested too.
    let cancelled: NSError = await withCheckedContinuation { continuation in
      socket.receive { result in
        switch result {
        case .failure(let error): continuation.resume(returning: error as NSError)
        case .success: continuation.resume(returning: NSError(domain: "URLSessionNetworking", code: 5))
        }
      }
      socket.cancel()
    }
    try requireURLFailure(cancelled, .cancelled, "Pending receive did not report cancellation")
    let neverStarted = session.webSocketTask(with: URL(string: CommandLine.arguments[2])!)
    neverStarted.cancel()
    let cancelledBeforeResume = try await mustFail(neverStarted)
    try requireURLFailure(cancelledBeforeResume, .cancelled, "Cancellation before resume was lost")
    let closing = session.webSocketTask(with: URL(string: CommandLine.arguments[2])!)
    closing.resume()
    try await send(.string("close-handshake"), closing)
    _ = try await receive(closing)
    closing.cancel(with: .normalClosure, reason: Data("bye".utf8))
    let closed = try await mustFail(closing)
    try requireURLFailure(closed, .networkConnectionLost, "Closed WebSocket receive did not report closure")
    try require(closing.closeCode == .normalClosure, "Graceful close code was lost")
    var injected = URLRequest(url: URL(string: CommandLine.arguments[2])!)
    injected.setValue("x\r\nSec-WebSocket-Key: forged\r\n\r\n", forHTTPHeaderField: "X-Test")
    let injection = try await mustFail(session.webSocketTask(with: injected))
    try requireURLFailure(injection, .badURL, "HTTP request header injection was not rejected")
    let invalid = try await mustFail(session.webSocketTask(with: URL(string: CommandLine.arguments[3])!))
    try requireURLFailure(invalid, .badServerResponse, "Invalid upgrade was not rejected")
    let tls = try await mustFail(session.webSocketTask(with: URL(string: CommandLine.arguments[4])!))
    try require(certificateValidationFailure(tls), "Expected certificate-validation rejection, got \(tls._domain):\(tls._code)")
    print("URLSessionNetworking PASS: download ownership, data, text, binary, ping, close, cancellation, header rejection, invalid upgrade and untrusted TLS")
  }
}
