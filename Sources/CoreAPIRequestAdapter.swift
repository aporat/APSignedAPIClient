import Alamofire
import Foundation

/// A request adapter that adds required authentication headers.
final class CoreAPIRequestAdapter: RequestAdapter {
    private enum Header {
        static let accountToken = "X-Account-Auth-Token"
        static let userToken = "X-User-Auth-Token"
        static let deviceID = "X-Device-ID"
    }
    
    nonisolated(unsafe) var accountAuthToken: String?
    nonisolated(unsafe) var userAuthToken: String?
    nonisolated(unsafe) var deviceId: String?
    
    func reset() {
        accountAuthToken = nil
        userAuthToken = nil
    }
    
    func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping (Result<URLRequest, any Error>) -> Void) {
        var req = urlRequest
        
        if let token = accountAuthToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            req.headers.update(.init(name: Header.accountToken, value: token))
        }
        
        if let token = userAuthToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            req.headers.update(.init(name: Header.userToken, value: token))
        }
        
        if let id = deviceId?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            req.headers.update(.init(name: Header.deviceID, value: id))
        }
        
        completion(.success(req))
    }
}
