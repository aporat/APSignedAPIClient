import Testing
import Foundation
import Alamofire
import CryptoKit
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
    
    @Test("Setup Configures Properties Correctly")
    func setupConfiguration() {
        #expect(CoreAPIClient.Configuration.baseURLString == "https://api.example.com")
        #expect(CoreAPIClient.Configuration.clientVersion == "400")
    }
    
    @Test("Add Signature Headers")
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
}
