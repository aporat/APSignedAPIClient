# APSignedAPIClient

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Faporat%2FAPSignedAPIClient%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/aporat/APSignedAPIClient)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Faporat%2FAPSignedAPIClient%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/aporat/APSignedAPIClient)
![GitHub Actions Workflow Status](https://github.com/aporat/APSignedAPIClient/actions/workflows/ci.yml/badge.svg)
[![codecov](https://codecov.io/github/aporat/APSignedAPIClient/graph/badge.svg?token=OHF9AE0KMC)](https://codecov.io/github/aporat/APSignedAPIClient)

`APSignedAPIClient` is a Swift package for making signed API requests with HMAC-SHA256 authentication. It provides a flexible, reusable client for iOS applications, leveraging Alamofire for networking. This package is designed to simplify secure API communication by handling request signing, authentication tokens, and error handling out of the box.

## Features
- **Signed Requests**: Automatically signs requests with HMAC-SHA256 (CryptoKit) using a client key.
- **Authentication**: Supports account and user authentication tokens, device ID headers, and Firebase App Check tokens.
- **Configurable**: Set base URL, app name, client version, and more via a single setup call.
- **Typed Errors**: Maps API-specific status codes to `CoreAPIError` cases (session expired, rate limited, update required, and more).
- **Retry Logic**: Automatically retries transient network failures and retryable server errors once with a short delay.
- **Uploads**: Multipart file uploads with the same signing and error handling.

## Requirements
- iOS 18.0+
- Swift 6.0+
- Xcode 16.0+

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
Configure the client once at app startup with your API credentials and settings:

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

// Optional: attach auth tokens once you have them.
CoreAPIClient.setTokens(account: "account-token", user: "user-token", device: "device-id")

// Optional: wire up reachability so requests fail fast when offline
// (defaults to always reachable).
CoreAPIClient.Configuration.isReachable = { /* e.g. read from NWPathMonitor */ true }
```

Requests also carry a Firebase App Check token when available, so configure [App Check](https://firebase.google.com/docs/app-check) during your app's Firebase setup.

### Making a Request
Create an instance of `CoreAPIClient` and await a signed request. Responses are returned as SwiftyJSON `JSON`, and failures are thrown as `CoreAPIError`:

```swift
let client = CoreAPIClient()

do {
    let json = try await client.request(
        "/endpoint",
        method: .post,
        parameters: ["key": "value"]
    )
    print("Response: \(json)")
} catch {
    print("\(error.errorTitle): \(error.localizedDescription)")
}
```

### Uploading a File

```swift
let json = try await client.upload(
    "/photos",
    data: imageData,
    fileName: "photo.jpg",
    mimeType: "image/jpeg",
    parameters: ["caption": "Hello"]
)
```

### Handling Errors
`CoreAPIError` distinguishes the cases callers typically need to act on:

```swift
do {
    let json = try await client.request("/endpoint")
} catch CoreAPIError.sessionExpired {
    // Log the user out.
} catch CoreAPIError.updateRequired(let responseJSON) {
    // Prompt for an app update; responseJSON may contain an update URL.
} catch {
    guard !error.isIgnorableError else { return } // e.g. cancelled requests
    print("\(error.errorTitle): \(error.localizedDescription)")
}
```

### Cancelling
`client.cancel()` cancels all in-flight requests (they fail with `CoreAPIError.canceled`).

## Dependencies
- [Alamofire](https://github.com/Alamofire/Alamofire) (5.0.0+): Networking
- [SwiftyJSON](https://github.com/SwiftyJSON/SwiftyJSON) (5.0.0+): JSON parsing
- [firebase-ios-sdk](https://github.com/firebase/firebase-ios-sdk) (12.0.0+): Firebase App Check tokens
- [SwiftHTTPStatusCodes](https://github.com/rhodgkins/SwiftHTTPStatusCodes) (3.3.0+): HTTP status code handling

HMAC-SHA256 signing uses Apple's built-in [CryptoKit](https://developer.apple.com/documentation/cryptokit) — no third-party crypto dependency.
