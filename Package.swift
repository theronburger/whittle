// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WhittleCore",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [.library(name: "WhittleCore", targets: ["WhittleCore"])],
    targets: [
        .target(name: "WhittleCore"),
        .testTarget(name: "WhittleCoreTests", dependencies: ["WhittleCore"])
    ],
    swiftLanguageModes: [.v5]
)
