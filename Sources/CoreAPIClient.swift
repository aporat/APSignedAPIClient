import Alamofire
import CryptoKit
import SwiftyJSON
import Foundation
import APWebAuthentication

private enum APIStatusCode: Int {
    case badRequest = 400
    case clientError = 403
    case notFound = 404
    case invalidAPIToken = 406
    case notice = 407
    case fatalClientError = 410
    case appUpdateRequired = 411
    case checkPointRequired = 422
    case downloadNewApp = 430
    case rateLimit = 429
    case internalServerError = 500
}

public final class CoreAPIClient {
    public var accountAuthToken: String? {
        get {
            requestAdapter.accountAuthToken
        }
        set {
            requestAdapter.accountAuthToken = newValue
        }
    }
    
    public var userAuthToken: String? {
        get {
            requestAdapter.userAuthToken
        }
        set {
            requestAdapter.userAuthToken = newValue
        }
    }
    
    public var deviceId: String? {
        get {
            requestAdapter.deviceId
        }
        set {
            requestAdapter.deviceId = newValue
        }
    }
    
    public static var baseURLString = ""

    private static var appName = ""
    public static var clientVersion = ""
    private static var clientId = ""
    private static var clientKey = ""
    private static var userAgent = ""
    
    private var requestAdapter: CoreAPIRequestAdapter
    private var requestRetrier: CoreAPIRequestRetrier
    
    private lazy var sessionManager: Session = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        
        return Session(configuration: configuration, delegate: SessionDelegate(), interceptor: Interceptor(adapter: self.requestAdapter, retrier: self.requestRetrier))
    }()
    
    public init() {
        requestAdapter = CoreAPIRequestAdapter()
        requestRetrier = CoreAPIRequestRetrier()
    }
    
    public class func setup(baseURLString: String, appName: String, clientVersion: String, clientId: String, clientKey: String, userAgent: String) {
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
    
    @discardableResult
    public class func request(
        _ path: String,
        method: HTTPMethod = .get,
        parameters: Parameters = Parameters()
    )
    throws -> DataRequest
    {
        let urlRequest = try CoreAPIClient.asURLRequest(method: method, path: path, parameters: parameters)
        return AF.request(urlRequest)
    }
    
    @discardableResult
    public func request(
        _ path: String,
        method: HTTPMethod = .get,
        parameters: Parameters = Parameters()
    )
    throws -> DataRequest
    {
        let urlRequest = try CoreAPIClient.asURLRequest(method: method, path: path, parameters: parameters)
        return sessionManager.request(urlRequest)
    }
    
    private class func asURLRequest(method: HTTPMethod, path: String, parameters: Parameters) throws -> URLRequest {
        let url = URL(string: CoreAPIClient.baseURLString)!
        
        var urlRequest = URLRequest(url: url.appendingPathComponent(path))
        urlRequest.method = method
        urlRequest = CoreAPIClient.addSignatureHeaders(urlRequest, params: parameters)
        
        if method == .get {
            return try URLEncoding.default.encode(urlRequest, with: parameters)
        }
        
        return try JSONEncoding.default.encode(urlRequest, with: parameters)
    }
    
    public class func addSignatureHeaders(_ urlRequest: URLRequest, params: Parameters) -> URLRequest {
        var urlRequest = urlRequest
        
        guard let currentMethod = urlRequest.method, let url = urlRequest.url, let bundleId = Bundle.main.bundleIdentifier else {
            return urlRequest
        }
        
        let timestamp = String(format: "%d", Int(Date().timeIntervalSince1970))
        
        let components: [String] = [
            bundleId,
            timestamp,
            clientId,
            clientVersion,
            currentMethod.rawValue,
            combinedParameters(params),
            url.path,
        ]
        
        let signatureParam = components.joined(separator: "")
        let data = Data(signatureParam.utf8)
        guard let keyData = clientKey.data(using: .utf8) else { return urlRequest }
        let key = SymmetricKey(data: keyData)
        let signature = HMAC<SHA256>.authenticationCode(for: data, using: key)
        let hexSignature = signature.map { String(format: "%02x", $0) }.joined()
        urlRequest.headers.add(HTTPHeader(name: "X-Auth-Signature", value: hexSignature))
        
        urlRequest.headers.add(HTTPHeader(name: "X-Auth-Timestamp", value: timestamp))
        urlRequest.headers.add(HTTPHeader(name: "X-Auth-Version", value: clientVersion))
        urlRequest.headers.add(HTTPHeader(name: "X-Auth-Client-ID", value: clientId))
        urlRequest.headers.add(HTTPHeader(name: "X-App-Name", value: appName))
        
        if !userAgent.isEmpty {
            urlRequest.headers.add(.userAgent(userAgent))
        }
        
        return urlRequest
    }
    
    private class func combinedParameters(_ params: Parameters) -> String {
        var lowerCaseParams = [String: Any?]()
        
        for (key, value) in params {
            lowerCaseParams[key.lowercased()] = value
        }
        
        let keys = lowerCaseParams.keys
        let sortedKeys = keys.sorted { $0 < $1 }
        
        let encodedParamerers = NSMutableArray()
        for (_, key) in sortedKeys.enumerated() {
            if let value = lowerCaseParams[key] {
                let encodedParamerer = encode(key, value: value)
                
                if !encodedParamerer.isEmpty {
                    encodedParamerers.add(encodedParamerer)
                }
            } else {
                let encodedParamerer = encode(key, value: "")
                
                if !encodedParamerer.isEmpty {
                    encodedParamerers.add(encodedParamerer)
                }
            }
        }
        
        return encodedParamerers.componentsJoined(by: "&")
    }
    
    private class func encode(_ key: String, value: Any?) -> String {
        if let currentValue = value as? [String: Any] {
            if currentValue.count == 0 {
                return String(format: "%@=%@", key.urlEscaped, "")
            }
            
            if let jsonString = JSON(currentValue).rawString(options: []) {
                return String(format: "%@=%@", key.urlEscaped, jsonString.urlEscaped)
            }
        } else if let currentValue = value as? [Any] {
            if currentValue.count == 0 {
                return String(format: "%@=%@", key.urlEscaped, "")
            }
            
            if let jsonString = JSON(currentValue).rawString(options: []) {
                return String(format: "%@=%@", key.urlEscaped, jsonString.urlEscaped)
            }
        } else if let currentValue = value as? String {
            return String(format: "%@=%@", key.urlEscaped, currentValue.urlEscaped)
        } else if let currentValue = value as? Int {
            return String(format: "%@=%@", key.urlEscaped, currentValue.string)
        } else if let currentValue = value as? Int32 {
            return String(format: "%@=%@", key.urlEscaped, currentValue.string)
        } else if let currentValue = value as? Double {
            return String(format: "%@=%@", key.urlEscaped, currentValue.string)
        } else if let currentValue = value as? Bool {
            return String(format: "%@=%d", key.urlEscaped, currentValue.int)
        } else {
            return String(format: "%@=%@", key.urlEscaped, "")
        }
        
        return ""
    }
    
    // MARK: - API Errors
    
    public func generateError(_ dataResponse: DataResponse<JSON, AFError>?) -> APWebAuthenticationError {
        var response: JSON?
        if let jsonResponse = dataResponse?.value {
            response = jsonResponse
        } else if let responseData = dataResponse?.data {
            response = JSON(responseData)
        }
        
        if response == nil, dataResponse?.error == nil {
            return APWebAuthenticationError.canceled
        }
        
        var errorMessage = NSLocalizedString("Session Expired", comment: "")
        
        if let message = response?["error_message"].string {
            errorMessage = message
        } else if let message = dataResponse?.error?.asAFError?.underlyingError?.localizedDescription {
            errorMessage = message
        } else if let message = dataResponse?.error?.localizedDescription {
            errorMessage = message
        }
        
        var errorCode: APIStatusCode = .badRequest
        if let value = response?["error_code"].int, let currentErrorCode = APIStatusCode(rawValue: value) {
            errorCode = currentErrorCode
        }
        
        if errorCode == .appUpdateRequired {
            return APWebAuthenticationError.appUpdateRequired(content: response)
        } else if errorCode == .downloadNewApp {
            return APWebAuthenticationError.appDownloadNewAppRequired(content: response)
        } else if errorCode == .checkPointRequired {
            return APWebAuthenticationError.appCheckPointRequired(content: response)
        } else if errorCode == .fatalClientError || errorCode == .invalidAPIToken {
            return APWebAuthenticationError.appSessionExpired(reason: errorMessage)
        } else if errorCode == .rateLimit {
            return APWebAuthenticationError.rateLimit(reason: errorMessage)
        } else if errorCode == .notFound || errorCode == .internalServerError {
            return APWebAuthenticationError.serverError(reason: errorMessage)
        } else if errorCode == .notice || errorCode == .clientError {
            return APWebAuthenticationError.failed(reason: errorMessage)
        }
        
        if let error = dataResponse?.error, error.isCancelledError {
            return APWebAuthenticationError.canceled
        } else if let error = dataResponse?.error, error.isConnectionError {
            return APWebAuthenticationError.connectionError(reason: "Check your network connection. Server could also be down.")
        } else if let error = dataResponse?.error, !error.isIgnorableError {
            return APWebAuthenticationError.failed(reason: errorMessage)
        }
        
        return APWebAuthenticationError.unknown
    }
}
