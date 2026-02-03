// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "APSignedAPIClient",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "APSignedAPIClient",
            targets: ["APSignedAPIClient"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.0.0"),
        .package(url: "https://github.com/SwiftyJSON/SwiftyJSON.git", from: "5.0.0"),
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: "12.0.0")
    ],
    targets: [
        .target(
            name: "APSignedAPIClient",
            dependencies: [
                "Alamofire",
                .product(name: "FirebaseAppCheck", package: "firebase-ios-sdk"),
                "SwiftyJSON"
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        ),
        .testTarget(
            name: "APSignedAPIClientTests",
            dependencies: ["APSignedAPIClient"]
        )
    ]
)
