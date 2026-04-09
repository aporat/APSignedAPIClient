import Testing
import Foundation
import Alamofire
import CryptoKit
@preconcurrency import SwiftyJSON
@testable import APSignedAPIClient

@Suite("Core API Client Tests")
struct CoreAPIClientTests {

    init() {
        CoreAPIClient.setup(
            baseURLString: "https://api.example.com",
            appName: "TestApp",
            clientVersion: "400",
            clientId: "testClientId",
            clientKey: "testClientKey",
            userAgent: "TestApp/1.0"
        )
    }

    // MARK: - Setup & Configuration

    @Test("Setup configures all properties correctly")
    func setupConfiguration() {
        #expect(CoreAPIClient.Configuration.baseURLString == "https://api.example.com")
        #expect(CoreAPIClient.Configuration.appName == "TestApp")
        #expect(CoreAPIClient.Configuration.clientVersion == "400")
        #expect(CoreAPIClient.Configuration.clientId == "testClientId")
        #expect(CoreAPIClient.Configuration.clientKey == "testClientKey")
        #expect(CoreAPIClient.Configuration.userAgent == "TestApp/1.0")
    }

    @Test("setTokens sets account, user, and device tokens")
    func setTokens() {
        CoreAPIClient.setTokens(account: "acct-token", user: "user-token", device: "device-123")
        #expect(CoreAPIClient.Configuration.accountAuthToken == "acct-token")
        #expect(CoreAPIClient.Configuration.userAuthToken == "user-token")
        #expect(CoreAPIClient.Configuration.deviceId == "device-123")
    }

    @Test("setTokens with nil values does not overwrite existing tokens")
    func setTokensNilPreservesExisting() {
        CoreAPIClient.Configuration.accountAuthToken = "existing-acct"
        CoreAPIClient.Configuration.userAuthToken = "existing-user"
        CoreAPIClient.Configuration.deviceId = "existing-device"

        CoreAPIClient.setTokens(account: nil, user: nil, device: nil)

        #expect(CoreAPIClient.Configuration.accountAuthToken == "existing-acct")
        #expect(CoreAPIClient.Configuration.userAuthToken == "existing-user")
        #expect(CoreAPIClient.Configuration.deviceId == "existing-device")
    }

    @Test("reset clears account and user tokens")
    func resetTokens() {
        CoreAPIClient.Configuration.accountAuthToken = "acct"
        CoreAPIClient.Configuration.userAuthToken = "user"
        CoreAPIClient.Configuration.deviceId = "device"

        CoreAPIClient.Configuration.reset()

        #expect(CoreAPIClient.Configuration.accountAuthToken == nil)
        #expect(CoreAPIClient.Configuration.userAuthToken == nil)
        // reset does not clear deviceId
        #expect(CoreAPIClient.Configuration.deviceId == "device")
    }

    @Test("CoreAPIClient initializes without error")
    func clientInit() {
        let client = CoreAPIClient()
        // Verify cancel does not crash on a fresh client
        client.cancel()
    }

    // MARK: - Signature Headers

    @Test("Add signature headers with GET request")
    func signatureHeaders() throws {
        let url = try #require(URL(string: "https://api.example.com/test"))
        var urlRequest = URLRequest(url: url)
        urlRequest.method = .get
        let params: Parameters = ["key": "value"]

        let signedRequest = CoreAPIClient.addSignatureHeaders(urlRequest, params: params)

        #expect(signedRequest.value(forHTTPHeaderField: "X-Auth-Signature") != nil)
        #expect(signedRequest.value(forHTTPHeaderField: "X-Auth-Timestamp") != nil)
        #expect(signedRequest.value(forHTTPHeaderField: "X-Auth-Version") == "400")
        #expect(signedRequest.value(forHTTPHeaderField: "X-Auth-Client-ID") == "testClientId")
        #expect(signedRequest.value(forHTTPHeaderField: "X-App-Name") == "TestApp")
        #expect(signedRequest.value(forHTTPHeaderField: "User-Agent") == "TestApp/1.0")

        let timestamp = try #require(signedRequest.value(forHTTPHeaderField: "X-Auth-Timestamp"))

        let bundleId = Bundle.main.bundleIdentifier ?? ""

        let components = [
            timestamp,
            bundleId,
            "testClientId",
            "400",
            "GET",
            "key=value",
            "/test"
        ]

        let signatureParam = components.joined(separator: "")
        let data = Data(signatureParam.utf8)
        let key = SymmetricKey(data: Data("testClientKey".utf8))

        let expectedSignature = HMAC<SHA256>.authenticationCode(for: data, using: key)
            .map { String(format: "%02x", $0) }
            .joined()

        #expect(signedRequest.value(forHTTPHeaderField: "X-Auth-Signature") == expectedSignature)
    }

    @Test("Add signature headers with POST request")
    func signatureHeadersPost() throws {
        let url = try #require(URL(string: "https://api.example.com/v1/submit"))
        var urlRequest = URLRequest(url: url)
        urlRequest.method = .post
        let params: Parameters = ["name": "test"]

        let signedRequest = CoreAPIClient.addSignatureHeaders(urlRequest, params: params)

        let timestamp = try #require(signedRequest.value(forHTTPHeaderField: "X-Auth-Timestamp"))
        let bundleId = Bundle.main.bundleIdentifier ?? ""

        let components = [
            timestamp,
            bundleId,
            "testClientId",
            "400",
            "POST",
            "name=test",
            "/v1/submit"
        ]

        let signatureParam = components.joined()
        let key = SymmetricKey(data: Data("testClientKey".utf8))
        let expectedSignature = HMAC<SHA256>.authenticationCode(for: Data(signatureParam.utf8), using: key)
            .map { String(format: "%02x", $0) }
            .joined()

        #expect(signedRequest.value(forHTTPHeaderField: "X-Auth-Signature") == expectedSignature)
    }

    @Test("Add signature headers with empty parameters")
    func signatureHeadersEmptyParams() throws {
        let url = try #require(URL(string: "https://api.example.com/health"))
        var urlRequest = URLRequest(url: url)
        urlRequest.method = .get

        let signedRequest = CoreAPIClient.addSignatureHeaders(urlRequest, params: [:])

        #expect(signedRequest.value(forHTTPHeaderField: "X-Auth-Signature") != nil)
        #expect(signedRequest.value(forHTTPHeaderField: "X-Auth-Timestamp") != nil)
    }

    @Test("Add signature headers with multiple sorted parameters")
    func signatureHeadersMultipleParams() throws {
        let url = try #require(URL(string: "https://api.example.com/search"))
        var urlRequest = URLRequest(url: url)
        urlRequest.method = .get
        let params: Parameters = ["Zebra": "last", "Apple": "first", "middle": "mid"]

        let signedRequest = CoreAPIClient.addSignatureHeaders(urlRequest, params: params)

        let timestamp = try #require(signedRequest.value(forHTTPHeaderField: "X-Auth-Timestamp"))
        let bundleId = Bundle.main.bundleIdentifier ?? ""

        // Keys are lowercased and sorted: apple, middle, zebra
        let combinedParams = "apple=first&middle=mid&zebra=last"
        let components = [
            timestamp,
            bundleId,
            "testClientId",
            "400",
            "GET",
            combinedParams,
            "/search"
        ]

        let signatureParam = components.joined()
        let key = SymmetricKey(data: Data("testClientKey".utf8))
        let expectedSignature = HMAC<SHA256>.authenticationCode(for: Data(signatureParam.utf8), using: key)
            .map { String(format: "%02x", $0) }
            .joined()

        #expect(signedRequest.value(forHTTPHeaderField: "X-Auth-Signature") == expectedSignature)
    }


    @Test("Signature headers uses default GET method when none is explicitly set")
    func signatureHeadersDefaultMethod() throws {
        let url = try #require(URL(string: "https://api.example.com/test"))
        let urlRequest = URLRequest(url: url)
        // URLRequest defaults to GET

        let result = CoreAPIClient.addSignatureHeaders(urlRequest, params: ["key": "value"])

        // Should still sign the request since default method is GET
        #expect(result.value(forHTTPHeaderField: "X-Auth-Signature") != nil)
        #expect(result.value(forHTTPHeaderField: "X-Auth-Timestamp") != nil)
    }

    // MARK: - Parameter Encoding via Signature

    @Test("Parameters with integer values")
    func signatureWithIntParams() throws {
        let url = try #require(URL(string: "https://api.example.com/api"))
        var urlRequest = URLRequest(url: url)
        urlRequest.method = .get
        let params: Parameters = ["count": 42]

        let signedRequest = CoreAPIClient.addSignatureHeaders(urlRequest, params: params)

        let timestamp = try #require(signedRequest.value(forHTTPHeaderField: "X-Auth-Timestamp"))
        let bundleId = Bundle.main.bundleIdentifier ?? ""

        let components = [
            timestamp, bundleId, "testClientId", "400", "GET", "count=42", "/api"
        ]
        let signatureParam = components.joined()
        let key = SymmetricKey(data: Data("testClientKey".utf8))
        let expectedSignature = HMAC<SHA256>.authenticationCode(for: Data(signatureParam.utf8), using: key)
            .map { String(format: "%02x", $0) }
            .joined()

        #expect(signedRequest.value(forHTTPHeaderField: "X-Auth-Signature") == expectedSignature)
    }

    @Test("Parameters with boolean values encode as 0/1")
    func signatureWithBoolParams() throws {
        let url = try #require(URL(string: "https://api.example.com/api"))
        var urlRequest = URLRequest(url: url)
        urlRequest.method = .get
        let params: Parameters = ["active": true, "deleted": false]

        let signedRequest = CoreAPIClient.addSignatureHeaders(urlRequest, params: params)

        let timestamp = try #require(signedRequest.value(forHTTPHeaderField: "X-Auth-Timestamp"))
        let bundleId = Bundle.main.bundleIdentifier ?? ""

        // Keys sorted: active, deleted
        let combinedParams = "active=1&deleted=0"
        let components = [
            timestamp, bundleId, "testClientId", "400", "GET", combinedParams, "/api"
        ]
        let signatureParam = components.joined()
        let key = SymmetricKey(data: Data("testClientKey".utf8))
        let expectedSignature = HMAC<SHA256>.authenticationCode(for: Data(signatureParam.utf8), using: key)
            .map { String(format: "%02x", $0) }
            .joined()

        #expect(signedRequest.value(forHTTPHeaderField: "X-Auth-Signature") == expectedSignature)
    }

    @Test("Parameters with special characters are URL-escaped")
    func signatureWithSpecialCharParams() throws {
        let url = try #require(URL(string: "https://api.example.com/api"))
        var urlRequest = URLRequest(url: url)
        urlRequest.method = .get
        let params: Parameters = ["query": "hello world&foo=bar"]

        let signedRequest = CoreAPIClient.addSignatureHeaders(urlRequest, params: params)

        #expect(signedRequest.value(forHTTPHeaderField: "X-Auth-Signature") != nil)
    }

    // MARK: - CoreAPIError

    @Test("CoreAPIError.canceled errorDescription")
    func canceledErrorDescription() {
        let error = CoreAPIError.canceled
        #expect(error.errorDescription == "Request was cancelled.")
    }

    @Test("CoreAPIError.connectionError errorDescription")
    func connectionErrorDescription() {
        let error = CoreAPIError.connectionError(reason: "No network")
        #expect(error.errorDescription == "No network")
    }

    @Test("CoreAPIError.failed errorDescription")
    func failedErrorDescription() {
        let error = CoreAPIError.failed(reason: "Something went wrong")
        #expect(error.errorDescription == "Something went wrong")
    }

    @Test("CoreAPIError.sessionExpired errorDescription")
    func sessionExpiredErrorDescription() {
        let error = CoreAPIError.sessionExpired(reason: "Token invalid")
        #expect(error.errorDescription == "Token invalid")
    }

    @Test("CoreAPIError.rateLimit errorDescription")
    func rateLimitErrorDescription() {
        let error = CoreAPIError.rateLimit(reason: "Too many requests")
        #expect(error.errorDescription == "Too many requests")
    }

    @Test("CoreAPIError.serverError errorDescription")
    func serverErrorDescription() {
        let error = CoreAPIError.serverError(reason: "Internal error")
        #expect(error.errorDescription == "Internal error")
    }

    @Test("CoreAPIError.updateRequired errorDescription with JSON")
    func updateRequiredErrorDescriptionWithJSON() {
        let json = JSON(["error_message": "Please update to v2.0"])
        let error = CoreAPIError.updateRequired(responseJSON: json)
        #expect(error.errorDescription == "Please update to v2.0")
    }

    @Test("CoreAPIError.updateRequired errorDescription without JSON")
    func updateRequiredErrorDescriptionNilJSON() {
        let error = CoreAPIError.updateRequired(responseJSON: nil)
        #expect(error.errorDescription == "An app update is required.")
    }

    @Test("CoreAPIError.downloadNewAppRequired errorDescription with JSON")
    func downloadNewAppErrorDescriptionWithJSON() {
        let json = JSON(["error_message": "Download from App Store"])
        let error = CoreAPIError.downloadNewAppRequired(responseJSON: json)
        #expect(error.errorDescription == "Download from App Store")
    }

    @Test("CoreAPIError.downloadNewAppRequired errorDescription without JSON")
    func downloadNewAppErrorDescriptionNilJSON() {
        let error = CoreAPIError.downloadNewAppRequired(responseJSON: nil)
        #expect(error.errorDescription == "Please download the latest version of the app.")
    }

    @Test("CoreAPIError.checkPointRequired errorDescription with JSON")
    func checkPointRequiredErrorDescriptionWithJSON() {
        let json = JSON(["error_message": "Verify your identity"])
        let error = CoreAPIError.checkPointRequired(responseJSON: json)
        #expect(error.errorDescription == "Verify your identity")
    }

    @Test("CoreAPIError.checkPointRequired errorDescription without JSON")
    func checkPointRequiredErrorDescriptionNilJSON() {
        let error = CoreAPIError.checkPointRequired(responseJSON: nil)
        #expect(error.errorDescription == "Additional verification is required.")
    }

    // MARK: - CoreAPIError errorTitle

    @Test("CoreAPIError errorTitle for all cases")
    func errorTitles() {
        #expect(CoreAPIError.canceled.errorTitle == "Cancelled")
        #expect(CoreAPIError.connectionError(reason: "").errorTitle == "Connection Error")
        #expect(CoreAPIError.failed(reason: "").errorTitle == "Error")
        #expect(CoreAPIError.updateRequired(responseJSON: nil).errorTitle == "Update Required")
        #expect(CoreAPIError.downloadNewAppRequired(responseJSON: nil).errorTitle == "New Version Available")
        #expect(CoreAPIError.checkPointRequired(responseJSON: nil).errorTitle == "Verification Required")
        #expect(CoreAPIError.sessionExpired(reason: "").errorTitle == "Session Expired")
        #expect(CoreAPIError.rateLimit(reason: "").errorTitle == "Rate Limited")
        #expect(CoreAPIError.serverError(reason: "").errorTitle == "Server Error")
    }

    // MARK: - CoreAPIError isIgnorableError

    @Test("Only canceled error is ignorable")
    func isIgnorableError() {
        #expect(CoreAPIError.canceled.isIgnorableError == true)
        #expect(CoreAPIError.connectionError(reason: "").isIgnorableError == false)
        #expect(CoreAPIError.failed(reason: "").isIgnorableError == false)
        #expect(CoreAPIError.updateRequired(responseJSON: nil).isIgnorableError == false)
        #expect(CoreAPIError.downloadNewAppRequired(responseJSON: nil).isIgnorableError == false)
        #expect(CoreAPIError.checkPointRequired(responseJSON: nil).isIgnorableError == false)
        #expect(CoreAPIError.sessionExpired(reason: "").isIgnorableError == false)
        #expect(CoreAPIError.rateLimit(reason: "").isIgnorableError == false)
        #expect(CoreAPIError.serverError(reason: "").isIgnorableError == false)
    }

    // MARK: - CoreAPIError responseJSON

    @Test("responseJSON returns JSON for applicable cases")
    func responseJSONPresent() {
        let json = JSON(["key": "value"])
        #expect(CoreAPIError.updateRequired(responseJSON: json).responseJSON != nil)
        #expect(CoreAPIError.downloadNewAppRequired(responseJSON: json).responseJSON != nil)
        #expect(CoreAPIError.checkPointRequired(responseJSON: json).responseJSON != nil)
    }

    @Test("responseJSON returns nil for non-applicable cases")
    func responseJSONNil() {
        #expect(CoreAPIError.canceled.responseJSON == nil)
        #expect(CoreAPIError.connectionError(reason: "err").responseJSON == nil)
        #expect(CoreAPIError.failed(reason: "err").responseJSON == nil)
        #expect(CoreAPIError.sessionExpired(reason: "err").responseJSON == nil)
        #expect(CoreAPIError.rateLimit(reason: "err").responseJSON == nil)
        #expect(CoreAPIError.serverError(reason: "err").responseJSON == nil)
    }

    @Test("responseJSON returns nil when case has nil JSON")
    func responseJSONNilValue() {
        #expect(CoreAPIError.updateRequired(responseJSON: nil).responseJSON == nil)
        #expect(CoreAPIError.downloadNewAppRequired(responseJSON: nil).responseJSON == nil)
        #expect(CoreAPIError.checkPointRequired(responseJSON: nil).responseJSON == nil)
    }

    // MARK: - CoreAPIError conforms to Error and LocalizedError

    @Test("CoreAPIError localizedDescription uses errorDescription")
    func errorLocalizedDescription() {
        let error: Error = CoreAPIError.failed(reason: "Custom reason")
        #expect(error.localizedDescription == "Custom reason")
    }

    // MARK: - CoreAPIError errorType

    @Test("errorType returns token when present on failed")
    func errorTypePresent() {
        let error = CoreAPIError.failed(reason: "You must connect your X account before using this feature.", errorType: "x_account_connection_required")
        #expect(error.errorType == "x_account_connection_required")
    }

    @Test("errorType returns nil when not provided on failed")
    func errorTypeAbsent() {
        let error = CoreAPIError.failed(reason: "Something went wrong")
        #expect(error.errorType == nil)
    }

    @Test("errorType returns nil for non-failed cases")
    func errorTypeNonFailed() {
        #expect(CoreAPIError.canceled.errorType == nil)
        #expect(CoreAPIError.connectionError(reason: "err").errorType == nil)
        #expect(CoreAPIError.sessionExpired(reason: "err").errorType == nil)
        #expect(CoreAPIError.rateLimit(reason: "err").errorType == nil)
        #expect(CoreAPIError.serverError(reason: "err").errorType == nil)
        #expect(CoreAPIError.updateRequired(responseJSON: nil).errorType == nil)
        #expect(CoreAPIError.downloadNewAppRequired(responseJSON: nil).errorType == nil)
        #expect(CoreAPIError.checkPointRequired(responseJSON: nil).errorType == nil)
    }

    @Test("failed with errorType still surfaces correct errorDescription")
    func errorTypeDoesNotAffectDescription() {
        let error = CoreAPIError.failed(reason: "You must connect your X account before using this feature.", errorType: "x_account_connection_required")
        #expect(error.errorDescription == "You must connect your X account before using this feature.")
        #expect(error.errorTitle == "Error")
    }

    // MARK: - String.urlEscaped

    @Test("urlEscaped preserves unreserved characters")
    func urlEscapedUnreserved() {
        #expect("abcXYZ0123456789-._~".urlEscaped == "abcXYZ0123456789-._~")
    }

    @Test("urlEscaped encodes spaces")
    func urlEscapedSpaces() {
        #expect("hello world".urlEscaped == "hello%20world")
    }

    @Test("urlEscaped encodes special characters")
    func urlEscapedSpecialChars() {
        #expect("a&b=c".urlEscaped == "a%26b%3Dc")
        #expect("foo/bar".urlEscaped == "foo%2Fbar")
        #expect("key+value".urlEscaped == "key%2Bvalue")
    }

    @Test("urlEscaped handles empty string")
    func urlEscapedEmpty() {
        #expect("".urlEscaped == "")
    }

    @Test("urlEscaped encodes unicode characters")
    func urlEscapedUnicode() {
        let escaped = "café".urlEscaped
        #expect(escaped.contains("caf"))
        #expect(escaped.contains("%"))
    }

    @Test("urlEscaped encodes at-sign and hash")
    func urlEscapedAtAndHash() {
        #expect("user@host".urlEscaped == "user%40host")
        #expect("#fragment".urlEscaped == "%23fragment")
    }
}
