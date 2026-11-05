// swift-tools-version: 6.1
import Foundation
import PackageDescription

// even-companion (prior work, MIT, not yet public) pinned by revision; see the README, "Display kits".
let evenCompanion: Package.Dependency = .package(
    url: "https://github.com/local-ai-cat/even-companion.git", revision: "527efbf4cb9c30c510640c919415125d98eb7cf5")
let package = Package(
    name: "BorderlessG2", platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "BorderlessG2", targets: ["BorderlessG2"])],
    dependencies: [
        .package(path: "../BorderlessKit"),
        evenCompanion,
        .package(url: "https://github.com/httpswift/swifter", exact: "1.5.0")
    ],
    targets: [
        .target(name: "BorderlessG2", dependencies: [
            .product(name: "BorderlessCore", package: "BorderlessKit"),
            .product(name: "BorderlessDisplay", package: "BorderlessKit"),
            .product(name: "EvenCompanionKit", package: "even-companion"), .product(name: "GlassesSceneKit", package: "even-companion"), .product(name: "Swifter", package: "swifter")]),
        .testTarget(name: "BorderlessG2Tests", dependencies: ["BorderlessG2", .product(name: "BorderlessCore", package: "BorderlessKit"), .product(name: "EvenCompanionKit", package: "even-companion")])
    ])
