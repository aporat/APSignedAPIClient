import Alamofire
import Foundation
import os
@preconcurrency import FirebaseAppCheck

final class CoreAPIInterceptor: RequestAdapter, Sendable {

    // MARK: - Headers (Adapter)

    private enum Header {
        static let accountToken = "X-Account-Auth-Token"
        static let userToken = "X-User-Auth-Token"
        static let deviceID = "X-Device-ID"
        static let appCheck = "X-Firebase-AppCheck"
    }

    nonisolated func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping @Sendable (Result<URLRequest, any Error>) -> Void) {
        Task { @MainActor in
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

            do {
                let token = try await AppCheck.appCheck().token(forcingRefresh: false)
                req.headers.update(.init(name: Header.appCheck, value: token.token))
            } catch {
            //    print("Failed to get App Check token: \(error)")
            }

            completion(.success(req))
        }
    }
}
