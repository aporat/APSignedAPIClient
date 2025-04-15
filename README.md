# APSignedAPIClient

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Faporat%2FAAPSignedAPIClient%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/aporat/APSignedAPIClient)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Faporat%2FAPSignedAPIClient%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/aporat/APSignedAPIClient)
![GitHub Actions Workflow Status](https://github.com/aporat/APSignedAPIClient/actions/workflows/ci.yml/badge.svg)
[![codecov](https://codecov.io/github/aporat/APSignedAPIClient/graph/badge.svg?token=OHF9AE0KMC)](https://codecov.io/github/aporat/APSignedAPIClient)

`APSignedAPIClient` is a Swift package for making signed API requests with HMAC-SHA256 authentication. It provides a flexible, reusable client for iOS applications, leveraging Alamofire for networking. This package is designed to simplify secure API communication by handling request signing, authentication tokens, and error handling out of the box.

## Features
- **Signed Requests**: Automatically signs requests with HMAC-SHA256 using a client key.
- **Authentication**: Supports account and user authentication tokens, plus device ID headers.
- **Configurable**: Set base URL, app name, client version, and more via a single setup call.
- **Error Handling**: Maps API-specific status codes to meaningful errors using `APWebAuthentication`.
- **Retry Logic**: Includes a retrier for transient network failures and server errors.

## Requirements
- iOS 16.0+
- Swift 5.9+
- Xcode 15.0+

## Installation

### Swift Package Manager
Add `APSignedAPIClient` to your project via Swift Package Manager:

1. In Xcode, go to **File > Add Packages**.
2. Enter the repository URL:
   ```
   https://github.com/aporat/APSignedAPIClient.git
   ```
3. Specify the version (e.g., `1.0.0`) or use the latest commit.
4. Add the package to your target.

Alternatively, add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/aporat/APSignedAPIClient.git", from: "1.0.0")
]
```

Then, include it in your target:

```swift
.target(
    name: "YourApp",
    dependencies: ["APSignedAPIClient"]
)
```

## Usage

### Setup
Configure the client with your API credentials and settings:

```swift
import APSignedAPIClient

CoreAPIClient.setup(
    baseURLString: "https://api.example.com",
    appName: "MyApp",
    clientVersion: "400",
    clientId: "your-client-id",
    clientKey: "your-client-key",
    userAgent: "MyApp/1.0"
)
```

### Making a Request
Create an instance of `CoreAPIClient` and send a signed request:

```swift
let client = CoreAPIClient()

do {
    let request = try client.request(
    "/endpoint",
    method: .post,
    parameters: ["key": "value"]
)

request.responseData { response in
    switch response.result {
        case .success(let data):
            print("Response: \(data)")
        case .failure(let error):
            print("Error: \(client.generateError(response))")
        }
    }
} catch {
    print("Request creation failed: \(error)")
}
```

## Dependencies
- [Alamofire](https://github.com/Alamofire/Alamofire) (5.0.0+): Networking
- [CryptoSwift](https://github.com/krzyzanowskim/CryptoSwift) (1.8.0+): HMAC-SHA256 signing
- [APWebAuthentication](https://github.com/aporat/APWebAuthentication): Error types
- [SwiftyUserDefaults](https://github.com/sunshinejr/SwiftyUserDefaults) (5.0.0+): User defaults (optional)
- [SwiftyJSON](https://github.com/SwiftyJSON/SwiftyJSON) (5.0.0+): JSON parsing
