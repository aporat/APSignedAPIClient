import Alamofire
import HTTPStatusCodes
import Foundation

/// A request retrier that handles transient network and HTTP status errors.
final class CoreAPIRequestRetrier: RequestRetrier {
    nonisolated(unsafe) private var maxRetryCount: UInt = 5
    nonisolated(unsafe) var isReloadingCancelled = false
    
    /// Determines whether a failed request should be retried.
    func retry(_ request: Request, for session: Session, dueTo error: any Error, completion: @escaping (RetryResult) -> Void) {
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
            case .notFound, .gone:
                return true
            case .internalServerError, .notImplemented, .badGateway, .serviceUnavailable, .gatewayTimeout:
                return true
            default:
                break
            }
        }
        
        return false
    }
    
    private let transientURLErrorCodes: Set<URLError.Code> = [
        .timedOut,
        .dnsLookupFailed,
        .notConnectedToInternet,
        .cannotFindHost,
        .networkConnectionLost
    ]
    
    private func extractURLError(from error: (any Error)?) -> URLError? {
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
