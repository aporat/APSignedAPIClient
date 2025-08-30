// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "APSignedAPIClient",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "APSignedAPIClient",
            targets: ["APSignedAPIClient"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.0.0"),
        .package(path: "../APWebAuthentication"),
        .package(url: "https://github.com/SwiftyJSON/SwiftyJSON.git", from: "5.0.0")
    ],
    targets: [
        .target(
            name: "APSignedAPIClient",
            dependencies: [
                "Alamofire",
                "APWebAuthentication",
                "SwiftyJSON"
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "APSignedAPIClientTests",
            dependencies: ["APSignedAPIClient"],
            path: "Tests"
        )
    ],
    swiftLanguageVersions: [.v5, .v6]
)
