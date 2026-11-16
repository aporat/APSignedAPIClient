import Alamofire
import Foundation
import HTTPStatusCodes
import os

/// Retries requests once on transient network failures (timeouts, DNS, dropped
/// connections) and on retryable 5xx responses. A failure that proves the request
/// never left the device (no connection, no DNS answer) is retried for every method.
/// One that leaves it open whether the server got the request (a timeout, a connection
/// dropped mid-flight, a 5xx) is retried for idempotent methods only: the server may
/// have processed a POST already, so replaying it risks doing the work twice (a
/// second charge, or a "duplicate" error for the row the first attempt created).
final class TransientNetworkRetrier: RequestRetrier, Sendable {

    private let maxRetryCount: UInt

    /// `maxRetryCount` 0 installs the retrier without ever replaying a request, for sessions
    /// whose calls are expensive or non-idempotent enough that a retry must be the user's call.
    init(maxRetryCount: UInt = 1) {
        self.maxRetryCount = maxRetryCount
    }

    private let isReloadingCancelledLock = OSAllocatedUnfairLock(initialState: false)

    var isReloadingCancelled: Bool {
        get { isReloadingCancelledLock.withLock { $0 } }
        set { isReloadingCancelledLock.withLock { $0 = newValue } }
    }

    /// The request never reached a server, so replaying it cannot repeat anything.
    private let unsentURLErrorCodes: Set<URLError.Code> = [
        .dnsLookupFailed,
        .notConnectedToInternet,
        .cannotFindHost
    ]

    /// The request may have reached the server before the failure.
    private let ambiguousURLErrorCodes: Set<URLError.Code> = [
        .timedOut,
        .networkConnectionLost
    ]

    func retry(_ request: Request, for session: Session, dueTo error: any Error, completion: @escaping (RetryResult) -> Void) {
        guard request.retryCount < maxRetryCount, !isReloadingCancelled else {
            completion(.doNotRetry)
            return
        }

        if shouldRetry(error: error, statusCode: request.response?.statusCode, method: request.request?.method) {
            // Single 0.5s delay before the one retry — keeps the overall failure window
            // inside the resource timeout so users get a prompt error.
            completion(.retryWithDelay(0.5))
        } else {
            completion(.doNotRetry)
        }
    }

    func shouldRetry(error: (any Error)?, statusCode: Int?, method: HTTPMethod?) -> Bool {
        if maxRetryCount == 0 || isReloadingCancelled { return false }

        if let urlErr = extractURLError(from: error) {
            if unsentURLErrorCodes.contains(urlErr.code) { return true }
            if ambiguousURLErrorCodes.contains(urlErr.code) { return isIdempotent(method) }
        }

        // Software caused connection abort: the connection went away mid-request.
        if let nsError = error as? NSError, nsError.domain == NSPOSIXErrorDomain, nsError.code == 53 {
            return isIdempotent(method)
        }

        if let statusCode {
            switch HTTPStatusCode(rawValue: statusCode) {
            case .internalServerError, .notImplemented, .badGateway, .serviceUnavailable, .gatewayTimeout: // 5xx
                return isIdempotent(method)
            default:
                break
            }
        }

        return false
    }

    private func isIdempotent(_ method: HTTPMethod?) -> Bool {
        switch method {
        case .get, .head, .options, .trace, .put, .delete:
            return true
        default:
            return false
        }
    }

    private func extractURLError(from error: (any Error)?) -> URLError? {
        if let urlError = error as? URLError { return urlError }

        if let afError = error as? AFError {
            if case let .sessionTaskFailed(underlyingError) = afError, let urlError = underlyingError as? URLError {
                return urlError
            }
            if let urlError = afError.underlyingError as? URLError {
                return urlError
            }
        }
        return nil
    }
}
