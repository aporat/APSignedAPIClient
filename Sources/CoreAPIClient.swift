import Alamofire
import CryptoKit
@preconcurrency import SwiftyJSON
import Foundation
import APWebAuthentication
import HTTPStatusCodes

private enum APIStatusCode: Int {
    case badRequest = 400
    case clientError = 403
    case notFound = 404
    case invalidAPIToken = 406
    case notice = 407
    case fatalClientError = 410
    case appUpdateRequired = 411
    case checkPointRequired = 422
    case rateLimit = 429
    case downloadNewApp = 430
    case internalServerError = 500
}

public final class CoreAPIClient {
    // MARK: Public tokens passthrough
    public var accountAuthToken: String? {
        get { requestAdapter.accountAuthToken }
        set { requestAdapter.accountAuthToken = newValue }
    }
    public var userAuthToken: String? {
        get { requestAdapter.userAuthToken }
        set { requestAdapter.userAuthToken = newValue }
    }
    public var deviceId: String? {
        get { requestAdapter.deviceId }
        set { requestAdapter.deviceId = newValue }
    }
    
    // MARK: Static config
    public nonisolated(unsafe) static var baseURLString = ""
    private nonisolated(unsafe) static var appName = ""
    public nonisolated(unsafe) static var clientVersion = ""
    private nonisolated(unsafe) static var clientId = ""
    private nonisolated(unsafe) static var clientKey = ""
    private nonisolated(unsafe) static var userAgent = ""
    
    // MARK: Infra
    private let requestAdapter: CoreAPIRequestAdapter
    private let requestRetrier: CoreAPIRequestRetrier
    
    private lazy var sessionManager: Session = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        return Session(
            configuration: configuration,
            delegate: SessionDelegate(),
            interceptor: Interceptor(adapter: self.requestAdapter, retrier: self.requestRetrier)
        )
    }()
    
    public init() {
        requestAdapter = CoreAPIRequestAdapter()
        requestRetrier  = CoreAPIRequestRetrier()
    }
    
    // MARK: Setup / lifecycle
    
    public class func setup(
        baseURLString: String,
        appName: String,
        clientVersion: String,
        clientId: String,
        clientKey: String,
        userAgent: String
    ) {
        self.baseURLString = baseURLString
        self.appName = appName
        self.clientVersion = clientVersion
        self.clientId = clientId
        self.clientKey = clientKey
        self.userAgent = userAgent
    }
    
    public func reset() {
        requestAdapter.reset()
    }
    
    public func cancel() {
        sessionManager.cancelAllRequests()
        requestRetrier.isReloadingCancelled = true
    }
    
    // MARK: - Request
    
    @discardableResult
    public func request(
        _ path: String,
        method: HTTPMethod = .get,
        parameters: Parameters = [:]
    ) async throws(APWebAuthenticationError) -> JSON {
        let urlRequest: URLRequest
        
        do {
            urlRequest = try CoreAPIClient.asURLRequest(method: method, path: path, parameters: parameters)
        } catch {
            throw APWebAuthenticationError.failed(reason: "Failed to create URLRequest: \(error.localizedDescription)")
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
    
    // MARK: URLRequest building
    
    private enum BuildError: Error {
        case invalidBaseURL
        case missingMethodOrURL
        case missingBundleId
    }
    
    private class func asURLRequest(
        method: HTTPMethod,
        path: String,
        parameters: Parameters
    ) throws -> URLRequest {
        guard let baseURL = URL(string: CoreAPIClient.baseURLString) else {
            throw BuildError.invalidBaseURL
        }
        
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent(path))
        urlRequest.method = method
        urlRequest = CoreAPIClient.addSignatureHeaders(urlRequest, params: parameters)
        
        if method == .get {
            return try URLEncoding.default.encode(urlRequest, with: parameters)
        } else {
            return try JSONEncoding.default.encode(urlRequest, with: parameters)
        }
    }
    
    public class func addSignatureHeaders(
        _ urlRequest: URLRequest,
        params: Parameters
    ) -> URLRequest {
        var req = urlRequest
        
        guard
            let method = req.method,
            let url = req.url,
            let bundleId = Bundle.main.bundleIdentifier
        else { return req }
        
        let timestamp = String(Int(Date().timeIntervalSince1970))
        
        // Build signature components in a deterministic way
        let components: [String] = [
            timestamp,
            bundleId,
            clientId,
            clientVersion,
            method.rawValue,
            combinedParameters(params),
            url.path
        ]
        
        let signatureParam = components.joined()
        let data = Data(signatureParam.utf8)
        
        if let keyData = clientKey.data(using: .utf8) {
            let key = SymmetricKey(data: keyData)
            let signature = HMAC<SHA256>.authenticationCode(for: data, using: key)
            let hex = signature.map { String(format: "%02x", $0) }.joined()
            req.headers.add(name: "X-Auth-Signature", value: hex)
        }
        
        req.headers.add(name: "X-Auth-Timestamp", value: timestamp)
        req.headers.add(name: "X-Auth-Version", value: clientVersion)
        req.headers.add(name: "X-Auth-Client-ID", value: clientId)
        req.headers.add(name: "X-App-Name", value: appName)
        
        if !userAgent.isEmpty {
            req.headers.add(.userAgent(userAgent))
        }
        
        return req
    }
    
    // MARK: Param encoding for signature
    
    private class func combinedParameters(_ params: Parameters) -> String {
        // Lowercase keys and keep values
        var lowered: [String: Any?] = [:]
        for (k, v) in params { lowered[k.lowercased()] = v }
        
        // Stable sort by key
        let sortedKeys = lowered.keys.sorted()
        
        var parts: [String] = []
        parts.reserveCapacity(sortedKeys.count)
        
        for key in sortedKeys {
            let value = lowered[key] ?? ""
            let encoded = encode(key, value: value)
            if !encoded.isEmpty {
                parts.append(encoded)
            }
        }
        
        return parts.joined(separator: "&")
    }
    
    private class func encode(_ key: String, value: Any?) -> String {
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
            
        case let s as String:
            return "\(k)=\(s.urlEscaped)"
            
        case let i as Int:
            return "\(k)=\(i)"
            
        case let i32 as Int32:
            return "\(k)=\(i32)"
            
        case let d as Double:
            // Avoid scientific notation by formatting via String(describing:)
            return "\(k)=\(String(d))"
            
        case let b as Bool:
            // Preserve your original 1/0 convention
            return "\(k)=\(b ? 1 : 0)"
            
        case let n as NSNumber:
            // Fallback for bridged numeric types
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                return "\(k)=\(n.boolValue ? 1 : 0)"
            } else {
                return "\(k)=\(n.stringValue)"
            }
            
        case .none:
            return "\(k)="
            
        default:
            // Unknown—encode empty to preserve key presence
            return "\(k)="
        }
    }
    
    // MARK: - API Errors
    private func generateError<T>(from response: DataResponse<T, AFError>) -> APWebAuthenticationError {
        if let afError = response.error {
            if afError.isExplicitlyCancelledError {
                return .canceled
            }
            if afError.isSessionTaskError {
                return .connectionError(reason: "Please check your network connection.")
            }
        }
        
        var responseJSON: JSON?
        if let data = response.data {
            responseJSON = try? JSON(data: data)
        }
        
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
        case .appUpdateRequired:
            return .appUpdateRequired(content: responseJSON)
        case .downloadNewApp:
            return .appDownloadNewAppRequired(content: responseJSON)
        case .checkPointRequired:
            return .appCheckPointRequired(content: responseJSON)
        case .fatalClientError, .invalidAPIToken:
            return .appSessionExpired(reason: errorMessage)
        case .rateLimit:
            return .rateLimit(reason: errorMessage)
        case .notFound, .internalServerError:
            return .serverError(reason: errorMessage)
        case .notice, .clientError:
            return .failed(reason: errorMessage)
        default:
            return .failed(reason: errorMessage)
        }
    }
}
