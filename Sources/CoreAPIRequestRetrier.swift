import Alamofire
import HTTPStatusCodes
import Foundation

final class CoreAPIRequestRetrier: RequestRetrier {
    fileprivate var maxRetryCount: UInt = 5
    var isReloadingCancelled = false

    func retry(
        _ request: Request,
        for _: Session,
        dueTo error: Error,
        completion: @escaping (RetryResult) -> Void
    ) {
        // Stop if we've hit the cap or if a cancel was requested
        guard request.retryCount < maxRetryCount, !isReloadingCancelled else {
            completion(.doNotRetry)
            return
        }

        if shouldRetryRequest(error, request: request) {
            completion(.retryWithDelay(0.2))
        } else {
            completion(.doNotRetry)
        }
    }

    func shouldRetryRequest(_ error: Error?, request: Request?) -> Bool {
        if isReloadingCancelled { return false }

        // Transient networking errors (direct or wrapped by AFError)
        if let urlErr = extractURLError(from: error),
           transientURLErrorCodes.contains(urlErr.code) {
            return true
        }

        // POSIX ENETDOWN (Darwin code 53) — treat as transient
        if let nsError = error as NSError?, nsError.domain == NSPOSIXErrorDomain, nsError.code == 53 {
            return true
        }

        // HTTP status–based retries
        if let status = request?.response?.statusCodeValue {
            // 4xx we retry (your existing choices)
            if status == HTTPStatusCode.notFound || status == HTTPStatusCode.gone {
                return true
            }
            // 5xx we retry (your existing choices)
            if status == HTTPStatusCode.internalServerError ||
               status == HTTPStatusCode.notImplemented ||
               status == HTTPStatusCode.badGateway ||
               status == HTTPStatusCode.serviceUnavailable ||
               status == HTTPStatusCode.gatewayTimeout {
                return true
            }
        }

        return false
    }

    // MARK: - Private

    private let transientURLErrorCodes: Set<URLError.Code> = [
        .timedOut,
        .dnsLookupFailed,
        .notConnectedToInternet,
        .cannotFindHost,
        .networkConnectionLost
    ]

    private func extractURLError(from error: Error?) -> URLError? {
        if let urlError = error as? URLError { return urlError }
        if let afError = error as? AFError,
           case let .sessionTaskFailed(underlyingError) = afError,
           let urlError = underlyingError as? URLError {
            return urlError
        }
        if let afError = error as? AFError,
           let urlError = afError.underlyingError as? URLError {
            return urlError
        }
        return nil
    }
}
