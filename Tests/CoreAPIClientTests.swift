import XCTest
@testable import APSignedAPIClient
import Alamofire
import CryptoSwift

final class CoreAPIClientTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Configure CoreAPIClient before each test
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
        // Clean up after each test if needed
        super.tearDown()
    }
    
    // Test that setup configures public static properties correctly
    func testSetupConfiguresProperties() {
        XCTAssertEqual(CoreAPIClient.baseURLString, "https://api.example.com")
        XCTAssertEqual(CoreAPIClient.clientVersion, "400")
    }
    
    // Test signature header generation
    func testAddSignatureHeaders() throws {
        // Mock a URLRequest
        let url = URL(string: "https://api.example.com/test")!
        var urlRequest = URLRequest(url: url)
        urlRequest.method = .get
        
        // Mock parameters
        let params: Parameters = ["key": "value"]
        
        // Add signature headers
        let signedRequest = CoreAPIClient.addSignatureHeaders(urlRequest, params: params)
        
        // Verify headers are added
        XCTAssertNotNil(signedRequest.value(forHTTPHeaderField: "X-Auth-Signature"))
        XCTAssertNotNil(signedRequest.value(forHTTPHeaderField: "X-Auth-Timestamp"))
        XCTAssertEqual(signedRequest.value(forHTTPHeaderField: "X-Auth-Version"), "400")
        XCTAssertEqual(signedRequest.value(forHTTPHeaderField: "X-Auth-Client-ID"), "testClientId")
        XCTAssertEqual(signedRequest.value(forHTTPHeaderField: "X-App-Name"), "TestApp")
        XCTAssertEqual(signedRequest.value(forHTTPHeaderField: "User-Agent"), "TestApp/1.0")
        
        // Verify signature
        let timestamp = signedRequest.value(forHTTPHeaderField: "X-Auth-Timestamp")!
        let bundleId = Bundle.main.bundleIdentifier ?? "com.test" // Fallback for test environment
        let components = [
            bundleId,
            timestamp.extendToLength(10),
            "testClientId",
            "400",
            "GET",
            "key=value",
            "/test"
        ]
        let signatureParam = components.joined(separator: "")
        let expectedSignature = try HMAC(key: "testClientKey", variant: .sha2(.sha256))
            .authenticate(Array(signatureParam.utf8))
            .toHexString()
        XCTAssertEqual(signedRequest.value(forHTTPHeaderField: "X-Auth-Signature"), expectedSignature)
    }
    
}

// Helper extension for consistent timestamp length in tests
extension String {
    func extendToLength(_ length: Int) -> String {
        guard count < length else { return self }
        return String(repeating: "0", count: length - count) + self
    }
}
