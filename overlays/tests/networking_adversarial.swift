// Native guest Swift 6.2 + real macOS 15 SDK source consumer.
// Argument: http://127.0.0.1:50591. Run with an external finite workload deadline.
// /slow intentionally leaves receive uncalled for 5s, then drains 256 MiB.
// RSS/TCP plateau is a separate host diagnostic, not inferred from this PASS.
import Foundation

@available(macOS 12.0, *)
@main struct NetworkingAdversarial {
  static func require(_ value: Bool, _ message: String) throws {
    if !value { throw NSError(domain: "NetworkingAdversarial", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: message]) }
  }
  static func receive(_ task: URLSessionWebSocketTask) async throws -> URLSessionWebSocketTask.Message {
    try await withCheckedThrowingContinuation { continuation in
      task.receive { continuation.resume(with: $0) }
    }
  }
  static func failed(_ task: URLSessionWebSocketTask) async throws -> NSError {
    task.resume()
    do { _ = try await receive(task) }
    catch { return error as NSError }
    throw NSError(domain: "NetworkingAdversarial", code: 2,
                  userInfo: [NSLocalizedDescriptionKey: "Rejected input delivered a message"])
  }
  static func stats(_ session: URLSession, _ base: String) async throws -> [String: Int] {
    var request = URLRequest(url: URL(string: base + "/stats")!)
    request.setValue("close", forHTTPHeaderField: "Connection")
    let (data, _) = try await session.data(for: request)
    return try JSONSerialization.jsonObject(with: data) as! [String: Int]
  }
  final class CompletionCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    func value() -> Int { lock.lock(); defer { lock.unlock() }; return count }
  }
  static func main() async throws {
    try require(CommandLine.arguments.count == 2, "Expected HTTP base URL")
    let base = CommandLine.arguments[1]
    let wsBase = base.replacingOccurrences(of: "http://", with: "ws://")
    let session = URLSession(configuration: .ephemeral)
    defer { session.invalidateAndCancel() }
    func socket(_ path: String) -> URLSessionWebSocketTask {
      session.webSocketTask(with: URL(string: wsBase + path)!)
    }
    let protocolError = try await failed(session.webSocketTask(with: URL(string: wsBase + "/protocol")!, protocols: ["chat"]))
    try require(protocolError._domain == NSURLErrorDomain && protocolError._code == URLError.badServerResponse.rawValue,
                "Unoffered case-mismatched CHAT accepted/wrong error: \(protocolError._domain):\(protocolError._code)")
    let fragmented = socket("/fragment")
    fragmented.resume()
    guard case .string(let text) = try await receive(fragmented) else {
      throw NSError(domain: "NetworkingAdversarial", code: 3)
    }
    try require(text == "split ☃", "Fragmented UTF-8 corrupted")
    fragmented.cancel(with: .normalClosure, reason: nil)
    let invalidBefore = try await stats(session, base)["utf8_close"] ?? 0
    let invalid = try await failed(socket("/utf8"))
    print("invalid UTF8 public error \(invalid._domain):\(invalid._code)")
    // Wire 1007 is separately checked by the strict peer; no invented public code.
    try await Task.sleep(nanoseconds: 200_000_000)
    let wire = try await stats(session, base)
    try require((wire["utf8_close"] ?? 0) == invalidBefore + 1, "Invalid UTF-8 did not produce a fresh wire close 1007")

    // Every stats request asks for Connection: close, hence one TCP accept.
    let beforeControl = try await stats(session, base)["connections"]!
    let afterControl = try await stats(session, base)["connections"]!
    let controlDelta = afterControl - beforeControl
    try require(controlDelta == 1, "Stats connection-count control is not isolated")
    for additional in [false, true] {
      for badName in [false, true] {
        let configuration = URLSessionConfiguration.ephemeral
        let field = badName ? "X-Test\r\nInjected" : "X-Test"
        let value = badName ? "value" : "value\r\nInjected: true"
        var request = URLRequest(url: URL(string: wsBase + "/echo")!)
        if additional { configuration.httpAdditionalHeaders = [field: value] }
        else { request.setValue(value, forHTTPHeaderField: field) }
        let testSession = URLSession(configuration: configuration)
        let before = try await stats(session, base)["connections"]!
        let error = try await failed(testSession.webSocketTask(with: request))
        testSession.invalidateAndCancel()
        try require(error._domain == NSURLErrorDomain && error._code == URLError.badURL.rawValue,
                    "CRLF header not rejected as badURL")
        let after = try await stats(session, base)["connections"]!
        try require(after - before == controlDelta, "CRLF header reached peer TCP accept")
      }
    }
    let slow = socket("/slow")
    slow.resume()
    print("slow receiver hold begins (5 seconds); sample guest RSS/TCP now")
    try await Task.sleep(nanoseconds: 5_000_000_000)
    var bytes = 0
    for _ in 0..<4096 {
      guard case .data(let data) = try await receive(slow) else {
        throw NSError(domain: "NetworkingAdversarial", code: 4)
      }
      try require(data.count == 65536 && data.first == 115 && data.last == 115, "Slow drain corrupted")
      bytes += data.count
    }
    guard case .string(let drained) = try await receive(slow) else {
      throw NSError(domain: "NetworkingAdversarial", code: 5)
    }
    try require(bytes == 268435456 && drained == "drained", "Slow drain truncated")
    try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
      slow.sendPing { error in
        if let error = error { c.resume(throwing: error) } else { c.resume() }
      }
    }
    slow.cancel(with: .normalClosure, reason: nil)
    let flood = socket("/flood")
    flood.resume()
    guard case .string(let final) = try await receive(flood) else {
      throw NSError(domain: "NetworkingAdversarial", code: 6)
    }
    try require(final == "final-pong-observed", "Final uniquely numbered Ping payload lost")
    flood.cancel()
    let cancel = socket("/floodcancel")
    cancel.resume()
    let completions = CompletionCount()
    // Avoid a single-use checked continuation: duplicate completion must be
    // reported by the oracle, not trap before the count can be inspected.
    let (done, completion) = AsyncStream<Bool>.makeStream(bufferingPolicy: .bufferingNewest(1))
    let errors = CompletionCount()
    cancel.receive { result in
      completions.increment()
      if case .failure(let error) = result {
        let native = error as NSError
        if native._domain == NSURLErrorDomain && native._code == URLError.cancelled.rawValue { errors.increment() }
      }
      completion.yield(true)
    }
    try await Task.sleep(nanoseconds: 500_000_000)
    cancel.cancel()
    let completed = await withTaskGroup(of: Bool.self) { group in
      group.addTask {
        for await event in done { return event }
        return false
      }
      group.addTask {
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        return false
      }
      let first = await group.next()!
      group.cancelAll()
      return first
    }
    completion.finish()
    try require(completed, "Cancellation hung during Ping flood")
    try await Task.sleep(nanoseconds: 1_000_000_000)
    try require(completions.value() == 1 && errors.value() == 1, "Cancellation did not complete exactly once")
    print("NetworkingAdversarial PASS: protocol case, fragmented/invalid UTF8, prewire CRLF, slow drain/control, final Pong, flood cancellation; RSS plateau requires independent measurement")
  }
}
