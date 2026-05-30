import Alamofire
import Foundation
import HTTPStatusCodes
import os

/// Retries requests on transient network failures (timeouts, DNS, dropped
/// connections) and select retryable HTTP responses. Uses exponential backoff
/// so retries span real-world network handoffs (e.g. WiFi ↔ cellular).
final class TransientNetworkRetrier: RequestRetrier, Sendable {

    private let maxRetryCount: UInt = 5

    private let isReloadingCancelledLock = OSAllocatedUnfairLock(initialState: false)

    var isReloadingCancelled: Bool {
        get { isReloadingCancelledLock.withLock { $0 } }
        set { isReloadingCancelledLock.withLock { $0 = newValue } }
    }

    private let transientURLErrorCodes: Set<URLError.Code> = [
        .timedOut,
        .dnsLookupFailed,
        .notConnectedToInternet,
        .cannotFindHost,
        .networkConnectionLost
    ]

    func retry(_ request: Request, for session: Session, dueTo error: any Error, completion: @escaping (RetryResult) -> Void) {
        guard request.retryCount < maxRetryCount, !isReloadingCancelled else {
            completion(.doNotRetry)
            return
        }

        if shouldRetryRequest(error, request: request) {
            // Exponential backoff: 0.5, 1, 2, 4, 8 — spans ~15s to cover WiFi↔cell handoffs.
            let delay = min(pow(2.0, Double(request.retryCount)) * 0.5, 8.0)
            completion(.retryWithDelay(delay))
        } else {
            completion(.doNotRetry)
        }
    }

    private func shouldRetryRequest(_ error: (any Error)?, request: Request?) -> Bool {
        if isReloadingCancelled { return false }

        if let urlErr = extractURLError(from: error), transientURLErrorCodes.contains(urlErr.code) {
            return true
        }

        if let nsError = error as? NSError, nsError.domain == NSPOSIXErrorDomain, nsError.code == 53 {
            return true
        }

        if let status = request?.response?.statusCodeValue {
            switch HTTPStatusCode(rawValue: status.rawValue) {
            case .notFound, .gone: // 404, 410
                return true
            case .internalServerError, .notImplemented, .badGateway, .serviceUnavailable, .gatewayTimeout: // 5xx
                return true
            default:
                break
            }
        }

        return false
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
