import XCTest
@testable import APSignedAPIClient
import Alamofire
import CryptoKit

final class CoreAPIClientTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        CoreAPIClient.setup(
            baseURLString: "https://api.example.com",
            appName: "TestApp",
            clientVersion: "400",
            clientId: "testClientId",
            clientKey: "testClientKey",
            userAgent: "TestApp/1.0"
        )
    }
    
    override func tearDown() {
        super.tearDown()
    }
    
    func testSetupConfiguresProperties() {
        XCTAssertEqual(CoreAPIClient.baseURLString, "https://api.example.com", "baseURLString should match the setup value")
        XCTAssertEqual(CoreAPIClient.clientVersion, "400", "clientVersion should match the setup value")
    }
    
    func testAddSignatureHeaders() throws {
        let url = URL(string: "https://api.example.com/test")!
        var urlRequest = URLRequest(url: url)
        urlRequest.method = .get
        let params: Parameters = ["key": "value"]
        
        let signedRequest = CoreAPIClient.addSignatureHeaders(urlRequest, params: params)
        
        XCTAssertNotNil(signedRequest.value(forHTTPHeaderField: "X-Auth-Signature"), "Signature header should be present")
        XCTAssertNotNil(signedRequest.value(forHTTPHeaderField: "X-Auth-Timestamp"), "Timestamp header should be present")
        XCTAssertEqual(signedRequest.value(forHTTPHeaderField: "X-Auth-Version"), "400", "Version header should match clientVersion")
        XCTAssertEqual(signedRequest.value(forHTTPHeaderField: "X-Auth-Client-ID"), "testClientId", "Client ID header should match setup value")
        XCTAssertEqual(signedRequest.value(forHTTPHeaderField: "X-App-Name"), "TestApp", "App name header should match setup value")
        XCTAssertEqual(signedRequest.value(forHTTPHeaderField: "User-Agent"), "TestApp/1.0", "User-Agent header should match setup value")
        
        let timestamp = signedRequest.value(forHTTPHeaderField: "X-Auth-Timestamp")!
        let bundleId = Bundle.main.bundleIdentifier ?? "com.test"
        let components = [
            bundleId,
            timestamp,
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
        XCTAssertEqual(
            signedRequest.value(forHTTPHeaderField: "X-Auth-Signature"),
            expectedSignature,
            "Signature should match the expected HMAC-SHA256 value"
        )
    }
}
