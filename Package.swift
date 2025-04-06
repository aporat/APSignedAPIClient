// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

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
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", from: "1.8.0"),
        .package(url: "https://github.com/aporat/APWebAuthentication.git", branch: "main"),
        .package(url: "https://github.com/sunshinejr/SwiftyUserDefaults.git", from: "5.0.0"),
        .package(url: "https://github.com/SwiftyJSON/SwiftyJSON.git", from: "5.0.0")
   ],
    targets: [
        .target(
            name: "APSignedAPIClient",
            dependencies: [
                "Alamofire",
                "CryptoSwift",
                "APWebAuthentication",
                "SwiftyUserDefaults",
                "SwiftyJSON"
            ]
        ),
        .testTarget(
            name: "APSignedAPIClientTests",
            dependencies: ["APSignedAPIClient"]
        )
    ]
)
