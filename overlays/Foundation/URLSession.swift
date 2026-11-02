//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

@_exported import Foundation
import Combine

// The Objective-C class cluster is served by CFNetwork's native session worker.
// The public signatures and WebSocket Message bridge follow the vendored
// swift-corelibs-foundation Darwin/Foundation-swiftoverlay/URLSession.swift and
// Apple's Foundation SDK interface. Newer upstream FoundationNetworking async
// methods target its distinct Swift/curl classes, so the cancellation bridge
// below instead owns the actual imported NSURLSessionTask. No surrogate session.
private final class _DarlingSessionCancellation: @unchecked Sendable {
  private let lock = NSLock()
  private var task: URLSessionTask?
  private var cancelled = false

  func start(_ task: URLSessionTask) {
    lock.lock()
    self.task = task
    let cancelled = self.cancelled
    lock.unlock()
    if cancelled { task.cancel() } else { task.resume() }
  }

  func cancel() {
    lock.lock()
    cancelled = true
    let task = self.task
    lock.unlock()
    task?.cancel()
  }

  func complete() {
    lock.lock()
    task = nil
    lock.unlock()
  }
}

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
extension URLSession {
  public func data(for request: URLRequest, delegate: (any NSURLSessionTaskDelegate)? = nil) async throws -> (Data, URLResponse) {
    let cancellation = _DarlingSessionCancellation()
    return try await withTaskCancellationHandler(operation: {
      try await withCheckedThrowingContinuation { continuation in
        let task = dataTask(with: request) { data, response, error in
          cancellation.complete()
          if let error = error { continuation.resume(throwing: error) }
          else if let data = data, let response = response { continuation.resume(returning: (data, response)) }
          else { continuation.resume(throwing: URLError(.badServerResponse)) }
        }
        task.delegate = delegate
        cancellation.start(task)
      }
    }, onCancel: { cancellation.cancel() })
  }

  /// The native callback owns its temporary file only until it returns. Move it
  /// before resuming Swift: the returned URL belongs to the async caller, who
  /// must move or remove the file when finished (including after cancellation).
  public func download(for request: URLRequest, delegate: (any NSURLSessionTaskDelegate)? = nil) async throws -> (URL, URLResponse) {
    let cancellation = _DarlingSessionCancellation()
    return try await withTaskCancellationHandler(operation: {
      try await withCheckedThrowingContinuation { continuation in
        let task = downloadTask(with: request) { location, response, error in
          cancellation.complete()
          if let error = error { continuation.resume(throwing: error); return }
          guard let location = location, let response = response else {
            continuation.resume(throwing: URLError(.badServerResponse)); return
          }
          do {
            let owned = location.deletingLastPathComponent().appendingPathComponent("NSURLSession-" + UUID().uuidString)
            try FileManager.default.moveItem(at: location, to: owned)
            continuation.resume(returning: (owned, response))
          } catch { continuation.resume(throwing: error) }
        }
        task.delegate = delegate
        cancellation.start(task)
      }
    }, onCancel: { cancellation.cancel() })
  }
}

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
extension URLSessionWebSocketTask {
  public enum Message {
    case data(Data)
    case string(String)
  }

  public func send(_ message: Message, completionHandler: @escaping (Error?) -> Void) {
    switch message {
    case .data(let data):
      __send(__NSURLSessionWebSocketMessage(data: data), completionHandler: completionHandler)
    case .string(let string):
      __send(__NSURLSessionWebSocketMessage(string: string), completionHandler: completionHandler)
    }
  }

  public func receive(completionHandler: @escaping (Result<Message, Error>) -> Void) {
    __receiveMessage { message, error in
      if let error = error { completionHandler(.failure(error)); return }
      guard let message = message else { completionHandler(.failure(URLError(.badServerResponse))); return }
      switch message.type {
      case .data:
        guard let data = message.data else { completionHandler(.failure(URLError(.badServerResponse))); return }
        completionHandler(.success(.data(data)))
      case .string:
        guard let string = message.string else { completionHandler(.failure(URLError(.badServerResponse))); return }
        completionHandler(.success(.string(string)))
      @unknown default:
        completionHandler(.failure(URLError(.badServerResponse)))
      }
    }
  }
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension URLSession {
  public func dataTaskPublisher(for url: URL) -> DataTaskPublisher {
    return dataTaskPublisher(for: URLRequest(url: url))
  }

  public func dataTaskPublisher(for request: URLRequest) -> DataTaskPublisher {
    return DataTaskPublisher(request: request, session: self)
  }

  public struct DataTaskPublisher: Combine.Publisher {
    public typealias Output = (data: Data, response: URLResponse)
    public typealias Failure = URLError
    public let request: URLRequest
    public let session: URLSession

    public init(request: URLRequest, session: URLSession) {
      self.request = request
      self.session = session
    }

    public func receive<S>(subscriber: S) where S: Subscriber, S.Failure == URLError, S.Input == Output {
      subscriber.receive(subscription: _DarlingDataTaskSubscription(subscriber, request: request, session: session))
    }
  }
}

// One network task per subscription, started by the first positive demand.
// Locking protects state only; downstream code and session methods run outside
// the lock so demand/cancellation and synchronous subscriber reentrancy are safe.
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
private final class _DarlingDataTaskSubscription<S: Subscriber>: Subscription
where S.Input == (data: Data, response: URLResponse), S.Failure == URLError {
  private let lock = NSLock()
  private var downstream: S?
  private var task: URLSessionDataTask?
  private var started = false
  private var cancelled = false
  private let requestValue: URLRequest
  private let session: URLSession

  init(_ downstream: S, request: URLRequest, session: URLSession) {
    self.downstream = downstream
    self.requestValue = request
    self.session = session
  }

  func request(_ demand: Subscribers.Demand) {
    guard demand > .none else { return }
    lock.lock()
    guard !started, downstream != nil else { lock.unlock(); return }
    started = true
    let task = session.dataTask(with: requestValue) { [self] data, response, error in
      finish(data: data, response: response, error: error)
    }
    self.task = task
    lock.unlock()
    task.resume()
  }

  func cancel() {
    lock.lock()
    cancelled = true
    downstream = nil
    let task = self.task
    self.task = nil
    lock.unlock()
    task?.cancel()
  }

  private func finish(data: Data?, response: URLResponse?, error: Error?) {
    lock.lock()
    let downstream = self.downstream
    self.downstream = nil
    task = nil
    lock.unlock()
    guard let downstream = downstream else { return }
    if let error = error { downstream.receive(completion: .failure(URLError(_nsError: error as NSError))) }
    else if let data = data, let response = response {
      _ = downstream.receive((data: data, response: response))
      lock.lock()
      let cancelled = self.cancelled
      lock.unlock()
      if !cancelled { downstream.receive(completion: .finished) }
    } else { downstream.receive(completion: .failure(URLError(.badServerResponse))) }
  }
}
