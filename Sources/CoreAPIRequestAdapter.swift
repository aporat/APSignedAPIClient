import Alamofire
import Foundation

final class CoreAPIRequestAdapter: RequestAdapter {
    // MARK: - Header Keys
    private enum Header {
        static let accountToken = "X-Account-Auth-Token"
        static let userToken    = "X-User-Auth-Token"
        static let deviceID     = "X-Device-ID"
    }

    var accountAuthToken: String?
    var userAuthToken: String?
    var deviceId: String?

    func reset() {
        accountAuthToken = nil
        userAuthToken = nil
        // intentionally keep deviceId; remove here if you want it reset too
        // deviceId = nil
    }

    func adapt(
        _ urlRequest: URLRequest,
        for _: Session,
        completion: @escaping (Result<URLRequest, Error>) -> Void
    ) {
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
