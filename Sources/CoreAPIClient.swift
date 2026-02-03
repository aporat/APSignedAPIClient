import Alamofire
import CryptoKit
@preconcurrency import SwiftyJSON
import Foundation
import HTTPStatusCodes
import os

// MARK: - CoreAPIError

/// Errors returned by `CoreAPIClient`.
///
/// Every case carries exactly the information a caller needs to react —
/// nothing more, nothing less.  Cases that include a `responseJSON` payload
/// do so because the server body contains structured data (e.g. update URLs)
/// that the caller may need to act on.
public enum CoreAPIError: Error, LocalizedError {
    
    /// The request was explicitly cancelled (e.g. the owning object was deallocated).
    case canceled
    /// A network-level failure prevented the request from completing.
    case connectionError(reason: String)
    /// The server responded with an error the client does not handle specially.
    case failed(reason: String)
    /// The server requires the app to be updated before continuing.
    case updateRequired(responseJSON: JSON?)
    /// The server requires the user to download a replacement app.
    case downloadNewAppRequired(responseJSON: JSON?)
    /// The server requires a checkpoint/challenge before the request can succeed.
    case checkPointRequired(responseJSON: JSON?)
    /// The session is no longer valid (fatal client error or invalid API token).
    case sessionExpired(reason: String)
    /// The client has been rate-limited by the server.
    case rateLimit(reason: String)
    /// The requested resource was not found or the server encountered an internal error.
    case serverError(reason: String)
    
    // MARK: - LocalizedError
    
    public var errorDescription: String? {
        switch self {
        case .canceled:
            return "Request was cancelled."
        case .connectionError(let reason),
             .failed(let reason),
             .sessionExpired(let reason),
             .rateLimit(let reason),
             .serverError(let reason):
            return reason
        case .updateRequired(let json):
            return json?["error_message"].string ?? "An app update is required."
        case .downloadNewAppRequired(let json):
            return json?["error_message"].string ?? "Please download the latest version of the app."
        case .checkPointRequired(let json):
            return json?["error_message"].string ?? "Additional verification is required."
        }
    }
    
    // MARK: - DisplayableError
    
    public var errorTitle: String {
        switch self {
        case .canceled:                      return "Cancelled"
        case .connectionError:               return "Connection Error"
        case .failed:                        return "Error"
        case .updateRequired:                return "Update Required"
        case .downloadNewAppRequired:        return "New Version Available"
        case .checkPointRequired:            return "Verification Required"
        case .sessionExpired:                return "Session Expired"
        case .rateLimit:                     return "Rate Limited"
        case .serverError:                   return "Server Error"
        }
    }
    
    public var isIgnorableError: Bool {
        if case .canceled = self { return true }
        return false
    }
    
    // MARK: - Helpers
    
    /// The raw JSON body returned by the server, when available.
    public var responseJSON: JSON? {
        switch self {
        case .updateRequired(let json),
             .downloadNewAppRequired(let json),
             .checkPointRequired(let json):
            return json
        default:
            return nil
        }
    }
}

// MARK: - CoreAPIClient

public final class CoreAPIClient: Sendable {
    
    // MARK: - Configuration
    
    public struct Configuration {
        nonisolated(unsafe) public static var baseURLString = ""
        nonisolated(unsafe) public static var appName = ""
        nonisolated(unsafe) public static var clientVersion = ""
        nonisolated(unsafe) public static var clientId = ""
        nonisolated(unsafe) public static var clientKey = ""
        nonisolated(unsafe) public static var userAgent = ""
        
        private static let tokenLock = OSAllocatedUnfairLock(initialState: (account: String?.none, user: String?.none, device: String?.none))
        
        public static var accountAuthToken: String? {
            get { tokenLock.withLock { $0.account } }
            set { tokenLock.withLock { $0.account = newValue } }
        }
        
        public static var userAuthToken: String? {
            get { tokenLock.withLock { $0.user } }
            set { tokenLock.withLock { $0.user = newValue } }
        }
        
        public static var deviceId: String? {
            get { tokenLock.withLock { $0.device } }
            set { tokenLock.withLock { $0.device = newValue } }
        }
        
        public static func reset() {
            tokenLock.withLock { state in
                state.account = nil
                state.user = nil
            }
        }
    }
    
    // MARK: - Setup
    
    public static func setup(
        baseURLString: String,
        appName: String,
        clientVersion: String,
        clientId: String,
        clientKey: String,
        userAgent: String
    ) {
        Configuration.baseURLString = baseURLString
        Configuration.appName = appName
        Configuration.clientVersion = clientVersion
        Configuration.clientId = clientId
        Configuration.clientKey = clientKey
        Configuration.userAgent = userAgent
    }
    
    public static func setTokens(account: String?, user: String?, device: String?) {
        if let account { Configuration.accountAuthToken = account }
        if let user { Configuration.userAuthToken = user }
        if let device { Configuration.deviceId = device }
    }
    
    // MARK: - Initialization
    
    private let sessionManager: Session
    private let interceptor = CoreAPIInterceptor()
    
    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        
        self.sessionManager = Session(
            configuration: configuration,
            delegate: SessionDelegate(),
            interceptor: interceptor // Pass directly
        )
    }
    
    public func cancel() {
        sessionManager.cancelAllRequests()
        interceptor.isReloadingCancelled = true
    }
    
    // MARK: - Request
    
    @discardableResult
    public func request(
        _ path: String,
        method: HTTPMethod = .get,
        parameters: Parameters = [:]
    ) async throws(CoreAPIError) -> JSON {
        
        let urlRequest: URLRequest
        do {
            urlRequest = try CoreAPIClient.buildURLRequest(method: method, path: path, parameters: parameters)
        } catch {
            throw CoreAPIError.failed(reason: "Failed to create URLRequest: \(error.localizedDescription)")
        }
        
        let dataTask = sessionManager.request(urlRequest)
            .validate()
            .serializingDecodable(JSON.self)
        
        let response = await dataTask.response
        
        switch response.result {
        case .success(let value):
            return value
        case .failure:
            throw generateError(from: response)
        }
    }
    
    // MARK: - Helpers (Signature & Encoding)
    
    private enum BuildError: Error { case invalidBaseURL }
    
    private static func buildURLRequest(method: HTTPMethod, path: String, parameters: Parameters) throws -> URLRequest {
        guard let baseURL = URL(string: Configuration.baseURLString) else {
            throw BuildError.invalidBaseURL
        }
        
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent(path))
        urlRequest.method = method
        
        urlRequest = addSignatureHeaders(urlRequest, params: parameters)
        
        if method == .get {
            return try URLEncoding.default.encode(urlRequest, with: parameters)
        } else {
            return try JSONEncoding.default.encode(urlRequest, with: parameters)
        }
    }
    
    static func addSignatureHeaders(_ urlRequest: URLRequest, params: Parameters) -> URLRequest {
        var req = urlRequest
        
        guard
            let method = req.method,
            let url = req.url
        else { return req }

        let bundleId = Bundle.main.bundleIdentifier ?? ""
        
        let timestamp = String(Int(Date().timeIntervalSince1970))
        
        let components: [String] = [
            timestamp,
            bundleId,
            Configuration.clientId,
            Configuration.clientVersion,
            method.rawValue,
            combinedParameters(params),
            url.path
        ]
        
        let signatureParam = components.joined()
        
        if let keyData = Configuration.clientKey.data(using: .utf8) {
            let key = SymmetricKey(data: keyData)
            let signature = HMAC<SHA256>.authenticationCode(for: Data(signatureParam.utf8), using: key)
            let hex = signature.map { String(format: "%02x", $0) }.joined()
            req.headers.add(name: "X-Auth-Signature", value: hex)
        }
        
        req.headers.add(name: "X-Auth-Timestamp", value: timestamp)
        req.headers.add(name: "X-Auth-Version", value: Configuration.clientVersion)
        req.headers.add(name: "X-Auth-Client-ID", value: Configuration.clientId)
        req.headers.add(name: "X-App-Name", value: Configuration.appName)
        
        if !Configuration.userAgent.isEmpty {
            req.headers.add(.userAgent(Configuration.userAgent))
        }
        
        return req
    }
    
    private static func combinedParameters(_ params: Parameters) -> String {
        var lowered: [String: Any?] = [:]
        for (k, v) in params { lowered[k.lowercased()] = v }
        let sortedKeys = lowered.keys.sorted()
        
        var parts: [String] = []
        for key in sortedKeys {
            let value = lowered[key] ?? ""
            let encoded = encode(key, value: value)
            if !encoded.isEmpty { parts.append(encoded) }
        }
        return parts.joined(separator: "&")
    }
    
    private static func encode(_ key: String, value: Any?) -> String {
        let k = key.urlEscaped
        switch value {
        case let dict as [String: Any]:
            if dict.isEmpty { return "\(k)=" }
            if let json = JSON(dict).rawString(options: [.sortedKeys]) { return "\(k)=\(json.urlEscaped)" }
            return "\(k)="
        case let array as [Any]:
            if array.isEmpty { return "\(k)=" }
            if let json = JSON(array).rawString(options: [.sortedKeys]) { return "\(k)=\(json.urlEscaped)" }
            return "\(k)="
        case let s as String: return "\(k)=\(s.urlEscaped)"
        case let i as Int: return "\(k)=\(i)"
        case let i32 as Int32: return "\(k)=\(i32)"
        case let d as Double: return "\(k)=\(String(d))"
        case let b as Bool: return "\(k)=\(b ? 1 : 0)"
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return "\(k)=\(n.boolValue ? 1 : 0)" }
            else { return "\(k)=\(n.stringValue)" }
        case .none: return "\(k)="
        default: return "\(k)="
        }
    }
    
    private func generateError<T>(from response: DataResponse<T, AFError>) -> CoreAPIError {
        if let afError = response.error {
            if afError.isExplicitlyCancelledError { return .canceled }
            if afError.isSessionTaskError { return .connectionError(reason: "Please check your network connection.") }
        }
        
        var responseJSON: JSON?
        if let data = response.data { responseJSON = try? JSON(data: data) }
        
        let errorMessage: String = (
            responseJSON?["error_message"].string ??
            response.error?.localizedDescription ??
            HTTPURLResponse.localizedString(forStatusCode: response.response?.statusCode ?? 0)
        )
        
        var code: APIStatusCode = .badRequest
        if let intCode = responseJSON?["error_code"].int, let mapped = APIStatusCode(rawValue: intCode) {
            code = mapped
        } else if let statusCode = response.response?.statusCode, let mapped = APIStatusCode(rawValue: statusCode) {
            code = mapped
        }
        
        switch code {
        case .updateRequired: return .updateRequired(responseJSON: responseJSON)
        case .downloadNewApp: return .downloadNewAppRequired(responseJSON: responseJSON)
        case .checkPointRequired: return .checkPointRequired(responseJSON: responseJSON)
        case .fatalClientError, .invalidAPIToken: return .sessionExpired(reason: errorMessage)
        case .rateLimit: return .rateLimit(reason: errorMessage)
        case .notFound, .internalServerError: return .serverError(reason: errorMessage)
        case .notice, .clientError: return .failed(reason: errorMessage)
        default: return .failed(reason: errorMessage)
        }
    }
    
    private enum APIStatusCode: Int {
        case badRequest = 400
        case clientError = 403
        case notFound = 404
        case invalidAPIToken = 406
        case notice = 407
        case fatalClientError = 410
        case updateRequired = 411
        case checkPointRequired = 422
        case rateLimit = 429
        case downloadNewApp = 430
        case internalServerError = 500
    }
}

extension String {
    var urlEscaped: String {
        let unreserved = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        let allowed = CharacterSet(charactersIn: unreserved)
        
        return self.addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
