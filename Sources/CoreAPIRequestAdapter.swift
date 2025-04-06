import Alamofire
import UIKit

final class CoreAPIRequestAdapter: RequestAdapter {
    var accountAuthToken: String?
    var userAuthToken: String?
    var deviceId: String?
    
    func reset() {
        accountAuthToken = nil
        userAuthToken = nil
    }
    
    func adapt(_ urlRequest: URLRequest, for _: Session, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        var urlRequest = urlRequest
        
        if let currentToken = accountAuthToken, !currentToken.isEmpty {
            urlRequest.headers.add(HTTPHeader(name: "X-Account-Auth-Token", value: currentToken))
        }
        
        if let currentToken = userAuthToken, !currentToken.isEmpty {
            urlRequest.headers.add(HTTPHeader(name: "X-User-Auth-Token", value: currentToken))
        }
        
        if let currentDeviceId = deviceId, !currentDeviceId.isEmpty {
            urlRequest.headers.add(HTTPHeader(name: "X-Device-ID", value: currentDeviceId))
        }
        
        completion(.success(urlRequest))
    }
}
