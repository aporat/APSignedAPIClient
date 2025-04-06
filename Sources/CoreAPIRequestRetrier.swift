import Alamofire
import HTTPStatusCodes
import Foundation

final class CoreAPIRequestRetrier: RequestRetrier {
    fileprivate var maxRetryCount: UInt = 5
    var isReloadingCancelled = false
    
    func retry(_ request: Request, for _: Session, dueTo error: Error, completion: @escaping (RetryResult) -> Void) {
        if request.retryCount >= maxRetryCount || isReloadingCancelled {
            completion(.doNotRetry)
            return
        }
        
        if shouldRetryRequest(error, request: request) {
            completion(.retryWithDelay(0.2))
            return
        }
        
        completion(.doNotRetry)
    }
    
    func shouldRetryRequest(_ error: Error?, request: Request?) -> Bool {
        if isReloadingCancelled {
            return false
        }
        
        if let currentError = error as? URLError {
            if currentError.code == URLError.timedOut ||
                currentError.code == URLError.dnsLookupFailed ||
                currentError.code == URLError.notConnectedToInternet ||
                currentError.code == URLError.cannotFindHost ||
                currentError.code == URLError.networkConnectionLost
            {
                return true
            }
        }
        
        if let afError = error as? AFError, let currentError = afError.underlyingError as? URLError {
            if currentError.code == URLError.timedOut ||
                currentError.code == URLError.dnsLookupFailed ||
                currentError.code == URLError.notConnectedToInternet ||
                currentError.code == URLError.cannotFindHost ||
                currentError.code == URLError.networkConnectionLost
            {
                return true
            }
        }
        
        if let currentError = error {
            if (currentError as NSError).domain == "NSPOSIXErrorDomain", (currentError as NSError).code == 53 {
                return true
            }
        }
        
        if let httpResponse = request?.response {
            // 4xx
            if httpResponse.statusCodeValue == HTTPStatusCode.notFound ||
                httpResponse.statusCodeValue == HTTPStatusCode.gone
            {
                return true
            }
            
            // 5xx
            if httpResponse.statusCodeValue == HTTPStatusCode.internalServerError ||
                httpResponse.statusCodeValue == HTTPStatusCode.notImplemented ||
                httpResponse.statusCodeValue == HTTPStatusCode.badGateway ||
                httpResponse.statusCodeValue == HTTPStatusCode.serviceUnavailable ||
                httpResponse.statusCodeValue == HTTPStatusCode.gatewayTimeout
            {
                return true
            }
        }
        
        return false
    }
}
