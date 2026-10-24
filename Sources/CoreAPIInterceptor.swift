import Alamofire
import Foundation
import os
@preconcurrency import FirebaseAppCheck

final class CoreAPIInterceptor: RequestAdapter, Sendable {

    // MARK: - Headers (Adapter)

    private enum Header {
        static let accountToken = "X-Account-Auth-Token"
        static let deviceID = "X-Device-ID"
        static let appCheck = "X-Firebase-AppCheck"
    }

    nonisolated func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping @Sendable (Result<URLRequest, any Error>) -> Void) {
        Task { @MainActor in
            var req = urlRequest

            if let token = CoreAPIClient.Configuration.accountAuthToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
                req.headers.update(.init(name: Header.accountToken, value: token))
            }

            if let id = CoreAPIClient.Configuration.deviceId?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
                req.headers.update(.init(name: Header.deviceID, value: id))
            }

            if let token = await Self.appCheckToken() {
                req.headers.update(.init(name: Header.appCheck, value: token))
            }

            completion(.success(req))
        }
    }

    // MARK: - App Check

    /// How long a request waits for an App Check token before it goes out without the header.
    private static let appCheckTimeout: Duration = .seconds(3)

    /// The App Check token, or `nil` on failure or after `appCheckTimeout`. When Firebase can't be
    /// reached the fetch hangs for minutes and ignores cancellation, so it is raced against a
    /// sleep rather than run in a task group (which would wait for it anyway).
    @MainActor
    private static func appCheckToken() async -> String? {
        @MainActor final class Once { var resumed = false }
        let once = Once()
        return await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            @MainActor func resume(_ token: String?) {
                guard !once.resumed else { return }
                once.resumed = true
                continuation.resume(returning: token)
            }
            Task { @MainActor in resume(try? await AppCheck.appCheck().token(forcingRefresh: false).token) }
            Task { @MainActor in try? await Task.sleep(for: appCheckTimeout); resume(nil) }
        }
    }
}
