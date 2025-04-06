// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "APSignedAPIClient",
    platforms: [
        .iOS(.v16),
        .macOS(.v12),
        .tvOS(.v16),
        .watchOS(.v9),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "APSignedAPIClient",
            targets: ["APSignedAPIClient"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.0.0"),
        .package(url: "https://github.com/aporat/APWebAuthentication.git", branch: "main"),
        .package(url: "https://github.com/SwiftyJSON/SwiftyJSON.git", from: "5.0.0")
    ],
    targets: [
        .target(
            name: "APSignedAPIClient",
            dependencies: [
                "Alamofire",
                "APWebAuthentication",
                "SwiftyJSON"
            ]
        ),
        .testTarget(
            name: "APSignedAPIClientTests",
            dependencies: ["APSignedAPIClient"]
        )
    ]
)
