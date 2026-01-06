import Alamofire
import Foundation
import HTTPStatusCodes

final class CoreAPIInterceptor: RequestInterceptor, @unchecked Sendable {
    
    // MARK: - Properties
    
    private let maxRetryCount: UInt = 5
    
    var isReloadingCancelled = false
    
    private let transientURLErrorCodes: Set<URLError.Code> = [
        .timedOut,
        .dnsLookupFailed,
        .notConnectedToInternet,
        .cannotFindHost,
        .networkConnectionLost
    ]
    
    // MARK: - Headers (Adapter)
    
    private enum Header {
        static let accountToken = "X-Account-Auth-Token"
        static let userToken = "X-User-Auth-Token"
        static let deviceID = "X-Device-ID"
    }
    
    func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping (Result<URLRequest, any Error>) -> Void) {
        var req = urlRequest
        
        if let token = CoreAPIClient.Configuration.accountAuthToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            req.headers.update(.init(name: Header.accountToken, value: token))
        }
        
        if let token = CoreAPIClient.Configuration.userAuthToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            req.headers.update(.init(name: Header.userToken, value: token))
        }
        
        if let id = CoreAPIClient.Configuration.deviceId?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            req.headers.update(.init(name: Header.deviceID, value: id))
        }
        
        completion(.success(req))
    }
    
    // MARK: - Retry Logic
    
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
