//
//  RequestInterceptor.swift
//
//  Copyright (c) 2019 Alamofire Software Foundation (http://alamofire.org/)
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import Foundation

/// Stores all state associated with a `URLRequest` being adapted.
public struct RequestAdapterState {
    /// The `UUID` of the `Request` associated with the `URLRequest` to adapt.
    public let requestID: UUID

    /// The `Session` associated with the `URLRequest` to adapt.
    public let session: Session
}

// MARK: -

/// A type that can inspect and optionally adapt a `URLRequest` in some manner if necessary.
public protocol RequestAdapter {
    /// Inspects and adapts the specified `URLRequest` in some manner and calls the completion handler with the Result.
    ///
    /// - Parameters:
    ///   - urlRequest: The `URLRequest` to adapt.
    ///   - session:    The `Session` that will execute the `URLRequest`.
    ///   - completion: The completion handler that must be called when adaptation is complete.
    func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping (Result<URLRequest, Error>) -> Void)

    /// Inspects and adapts the specified `URLRequest` in some manner and calls the completion handler with the Result.
    ///
    /// - Parameters:
    ///   - urlRequest: The `URLRequest` to adapt.
    ///   - state:      The `RequestAdapterState` associated with the `URLRequest`.
    ///   - completion: The completion handler that must be called when adaptation is complete.
    func adapt(_ urlRequest: URLRequest, using state: RequestAdapterState, completion: @escaping (Result<URLRequest, Error>) -> Void)
}

extension RequestAdapter {
    public func adapt(_ urlRequest: URLRequest, using state: RequestAdapterState, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        adapt(urlRequest, for: state.session, completion: completion)
    }
}

// MARK: -

/// Outcome of determination whether retry is necessary.
public enum RetryResult {
    /// Retry should be attempted immediately.
    case retry
    /// Retry should be attempted after the associated `TimeInterval`.
    case retryWithDelay(TimeInterval)
    /// Do not retry.
    case doNotRetry
    /// Do not retry due to the associated `Error`.
    case doNotRetryWithError(Error)
}

extension RetryResult {
    var retryRequired: Bool {
        switch self {
        case .retry, .retryWithDelay: return true
        default: return false
        }
    }

    var delay: TimeInterval? {
        switch self {
        case let .retryWithDelay(delay): return delay
        default: return nil
        }
    }

    var error: Error? {
        guard case let .doNotRetryWithError(error) = self else { return nil }
        return error
    }
}

/// A type that determines whether a request should be retried after being executed by the specified session manager
/// and encountering an error.
public protocol RequestRetrier {
    /// Determines whether the `Request` should be retried by calling the `completion` closure.
    ///
    /// This operation is fully asynchronous. Any amount of time can be taken to determine whether the request needs
    /// to be retried. The one requirement is that the completion closure is called to ensure the request is properly
    /// cleaned up after.
    ///
    /// - Parameters:
    ///   - request:    `Request` that failed due to the provided `Error`.
    ///   - session:    `Session` that produced the `Request`.
    ///   - error:      `Error` encountered while executing the `Request`.
    ///   - completion: Completion closure to be executed when a retry decision has been determined.
    func retry(_ request: Request, for session: Session, dueTo error: Error, completion: @escaping (RetryResult) -> Void)
}

// MARK: -

/// Type that provides both `RequestAdapter` and `RequestRetrier` functionality.
public protocol RequestInterceptor: RequestAdapter, RequestRetrier {}

extension RequestInterceptor {
    public func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        completion(.success(urlRequest))
    }

    public func retry(_ request: Request,
                      for session: Session,
                      dueTo error: Error,
                      completion: @escaping (RetryResult) -> Void) {
        completion(.doNotRetry)
    }
}

/// `RequestAdapter` closure definition.
public typealias AdaptHandler = (URLRequest, Session, _ completion: @escaping (Result<URLRequest, Error>) -> Void) -> Void
/// `RequestRetrier` closure definition.
public typealias RetryHandler = (Request, Session, Error, _ completion: @escaping (RetryResult) -> Void) -> Void

// MARK: -

/// Closure-based `RequestAdapter`.
open class Adapter: RequestInterceptor {
    private let adaptHandler: AdaptHandler

    /// Creates an instance using the provided closure.
    ///
    /// - Parameter adaptHandler: `AdaptHandler` closure to be executed when handling request adaptation.
    public init(_ adaptHandler: @escaping AdaptHandler) {
        self.adaptHandler = adaptHandler
    }

    open func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        adaptHandler(urlRequest, session, completion)
    }

    open func adapt(_ urlRequest: URLRequest, using state: RequestAdapterState, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        adaptHandler(urlRequest, state.session, completion)
    }
}

extension RequestAdapter where Self == Adapter {
    /// Creates an `Adapter` using the provided `AdaptHandler` closure.
    ///
    /// - Parameter closure: `AdaptHandler` to use to adapt the request.
    /// - Returns:           The `Adapter`.
    public static func adapter(using closure: @escaping AdaptHandler) -> Adapter {
        Adapter(closure)
    }
}

// MARK: -

/// Closure-based `RequestRetrier`.
open class Retrier: RequestInterceptor {
    private let retryHandler: RetryHandler

    /// Creates an instance using the provided closure.
    ///
    /// - Parameter retryHandler: `RetryHandler` closure to be executed when handling request retry.
    public init(_ retryHandler: @escaping RetryHandler) {
        self.retryHandler = retryHandler
    }

    open func retry(_ request: Request,
                    for session: Session,
                    dueTo error: Error,
                    completion: @escaping (RetryResult) -> Void) {
        retryHandler(request, session, error, completion)
    }
}

extension RequestRetrier where Self == Retrier {
    /// Creates a `Retrier` using the provided `RetryHandler` closure.
    ///
    /// - Parameter closure: `RetryHandler` to use to retry the request.
    /// - Returns:           The `Retrier`.
    public static func retrier(using closure: @escaping RetryHandler) -> Retrier {
        Retrier(closure)
    }
}

// MARK: -

/// `RequestInterceptor` which can use multiple `RequestAdapter` and `RequestRetrier` values.
open class Interceptor: RequestInterceptor {
    /// All `RequestAdapter`s associated with the instance. These adapters will be run until one fails.
    public let adapters: [RequestAdapter]
    /// All `RequestRetrier`s associated with the instance. These retriers will be run one at a time until one triggers retry.
    public let retriers: [RequestRetrier]

    /// Creates an instance from `AdaptHandler` and `RetryHandler` closures.
    ///
    /// - Parameters:
    ///   - adaptHandler: `AdaptHandler` closure to be used.
    ///   - retryHandler: `RetryHandler` closure to be used.
    public init(adaptHandler: @escaping AdaptHandler, retryHandler: @escaping RetryHandler) {
        adapters = [Adapter(adaptHandler)]
        retriers = [Retrier(retryHandler)]
    }

    /// Creates an instance from `RequestAdapter` and `RequestRetrier` values.
    ///
    /// - Parameters:
    ///   - adapter: `RequestAdapter` value to be used.
    ///   - retrier: `RequestRetrier` value to be used.
    public init(adapter: RequestAdapter, retrier: RequestRetrier) {
        adapters = [adapter]
        retriers = [retrier]
    }

    /// Creates an instance from the arrays of `RequestAdapter` and `RequestRetrier` values.
    ///
    /// - Parameters:
    ///   - adapters:     `RequestAdapter` values to be used.
    ///   - retriers:     `RequestRetrier` values to be used.
    ///   - interceptors: `RequestInterceptor`s to be used.
    public init(adapters: [RequestAdapter] = [], retriers: [RequestRetrier] = [], interceptors: [RequestInterceptor] = []) {
        self.adapters = adapters + interceptors
        self.retriers = retriers + interceptors
    }

    open func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        adapt(urlRequest, for: session, using: adapters, completion: completion)
    }

    private func adapt(_ urlRequest: URLRequest,
                       for session: Session,
                       using adapters: [RequestAdapter],
                       completion: @escaping (Result<URLRequest, Error>) -> Void) {
        var pendingAdapters = adapters

        guard !pendingAdapters.isEmpty else { completion(.success(urlRequest)); return }

        pendingAdapters.first!.adapt(urlRequest, for: session) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case let .success(urlRequest):
                self.adapt(urlRequest, for: session, using: pendingAdapters, completion: completion)
                pendingAdapters.removeAll()

            case .failure:
                completion(result)
                pendingAdapters.removeAll()
            }
        }
    }

    open func adapt(_ urlRequest: URLRequest, using state: RequestAdapterState, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        adapt(urlRequest, using: state, adapters: adapters, completion: completion)
    }

    private func adapt(_ urlRequest: URLRequest,
                       using state: RequestAdapterState,
                       adapters: [RequestAdapter],
                       completion: @escaping (Result<URLRequest, Error>) -> Void) {
        var pendingAdapters = adapters

        guard !pendingAdapters.isEmpty else { completion(.success(urlRequest)); return }

        pendingAdapters.first!.adapt(urlRequest, using: state) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case let .success(urlRequest):
                self.adapt(urlRequest, using: state, adapters: pendingAdapters, completion: completion)
                pendingAdapters.removeAll()

            case .failure:
                completion(result)
                pendingAdapters.removeAll()
            }
        }
    }

    open func retry(_ request: Request,
                    for session: Session,
                    dueTo error: Error,
                    completion: @escaping (RetryResult) -> Void) {
        retry(request, for: session, dueTo: error, using: retriers, completion: completion)
    }

    private func retry(_ request: Request,
                       for session: Session,
                       dueTo error: Error,
                       using retriers: [RequestRetrier],
                       completion: @escaping (RetryResult) -> Void) {
        var pendingRetriers = retriers

        guard !pendingRetriers.isEmpty else { completion(.doNotRetry); return }

        pendingRetriers.first!.retry(request, for: session, dueTo: error) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .retry, .retryWithDelay, .doNotRetryWithError:
                completion(result)
                pendingRetriers.removeAll()

            case .doNotRetry:
                // Only continue to the next retrier if retry was not triggered and no error was encountered
                self.retry(request, for: session, dueTo: error, using: pendingRetriers, completion: completion)
                pendingRetriers.removeAll()
            }
        }
    }
}

extension RequestInterceptor where Self == Interceptor {
    /// Creates an `Interceptor` using the provided `AdaptHandler` and `RetryHandler` closures.
    ///
    /// - Parameters:
    ///   - adapter: `AdapterHandler`to use to adapt the request.
    ///   - retrier: `RetryHandler` to use to retry the request.
    /// - Returns:   The `Interceptor`.
    public static func interceptor(adapter: @escaping AdaptHandler, retrier: @escaping RetryHandler) -> Interceptor {
        Interceptor(adaptHandler: adapter, retryHandler: retrier)
    }

    /// Creates an `Interceptor` using the provided `RequestAdapter` and `RequestRetrier` instances.
    /// - Parameters:
    ///   - adapter: `RequestAdapter` to use to adapt the request
    ///   - retrier: `RequestRetrier` to use to retry the request.
    /// - Returns:   The `Interceptor`.
    public static func interceptor(adapter: RequestAdapter, retrier: RequestRetrier) -> Interceptor {
        Interceptor(adapter: adapter, retrier: retrier)
    }

    /// Creates an `Interceptor` using the provided `RequestAdapter`s, `RequestRetrier`s, and `RequestInterceptor`s.
    /// - Parameters:
    ///   - adapters:     `RequestAdapter`s to use to adapt the request. These adapters will be run until one fails.
    ///   - retriers:     `RequestRetrier`s to use to retry the request. These retriers will be run one at a time until
    ///                   a retry is triggered.
    ///   - interceptors: `RequestInterceptor`s to use to intercept the request.
    /// - Returns:        The `Interceptor`.
    public static func interceptor(adapters: [RequestAdapter] = [],
                                   retriers: [RequestRetrier] = [],
                                   interceptors: [RequestInterceptor] = []) -> Interceptor {
        Interceptor(adapters: adapters, retriers: retriers, interceptors: interceptors)
    }
}
