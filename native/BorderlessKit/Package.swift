// swift-tools-version: 6.1
import Foundation
import PackageDescription

// even-companion (prior work, MIT, not yet public) pinned by revision; see the README, "Display kits".
let evenCompanion: Package.Dependency = .package(
    url: "https://github.com/local-ai-cat/even-companion.git", revision: "527efbf4cb9c30c510640c919415125d98eb7cf5")
let package = Package(
    name: "BorderlessKit", platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "BorderlessCore", targets: ["BorderlessCore"]),
               .library(name: "BorderlessDisplay", targets: ["BorderlessDisplay"]),
               .library(name: "BorderlessRelay", targets: ["BorderlessRelay"])],
    dependencies: [evenCompanion],
    targets: [
        .target(name: "BorderlessCore"),
        .target(name: "BorderlessRelay", dependencies: ["BorderlessCore"]),
        .target(name: "BorderlessDisplay", dependencies: ["BorderlessCore", .product(name: "GlassesSceneKit", package: "even-companion"), .product(name: "GlassesTextKit", package: "even-companion"), .product(name: "MetaDisplayKit", package: "even-companion")]),
        .testTarget(name: "BorderlessKitTests", dependencies: ["BorderlessCore", "BorderlessDisplay", "BorderlessRelay",
                                                           .product(name: "GlassesSceneKit", package: "even-companion"), .product(name: "GlassesTextKit", package: "even-companion"), .product(name: "MetaDisplayKit", package: "even-companion")],
                    resources: [.copy("Fixtures")])
    ]
)
