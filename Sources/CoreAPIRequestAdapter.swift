import Alamofire
import Foundation

final class CoreAPIRequestAdapter: RequestAdapter, Sendable {
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
}
