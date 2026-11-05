// swift-tools-version: 6.1
import Foundation
import PackageDescription

// even-companion (prior work, MIT, not yet public) pinned by revision; see the README, "Display kits".
let evenCompanion: Package.Dependency = .package(
    url: "https://github.com/local-ai-cat/even-companion.git", revision: "527efbf4cb9c30c510640c919415125d98eb7cf5")

// Default is the exact reviewed SDK release. Offline build override points at
// an existing checkout of that revision; no SDK binaries are copied into this package.
let cachedSDK = ProcessInfo.processInfo.environment["BORDERLESS_DAT_PACKAGE_PATH"]
let dat: Package.Dependency = cachedSDK.map {
    .package(name: "meta-wearables-dat-ios", path: $0)
} ?? .package(url: "https://github.com/facebook/meta-wearables-dat-ios", exact: "1.0.0")
let experimentalInputs = ProcessInfo.processInfo.environment["BORDERLESS_EXPERIMENTAL_INPUTS"] == "1"
var adapterDependencies: [Target.Dependency] = [
    "MetaConnectionPolicy", .product(name: "MetaDisplayKit", package: "even-companion"),
    .product(name: "MWDATCore", package: "meta-wearables-dat-ios", condition: .when(platforms: [.iOS])),
    .product(name: "MWDATDisplay", package: "meta-wearables-dat-ios", condition: .when(platforms: [.iOS]))
]
if experimentalInputs {
    adapterDependencies.append(.product(name: "MWDATInputs", package: "meta-wearables-dat-ios", condition: .when(platforms: [.iOS])))
}
let package = Package(
    name: "MetaDATAdapter", platforms: [.iOS("17.2"), .macOS(.v14)],
    products: [.library(name: "MetaDATAdapter", targets: ["MetaDATAdapter"]),
               .library(name: "MetaConnectionPolicy", targets: ["MetaConnectionPolicy"])],
    dependencies: [evenCompanion, dat],
    targets: [
        .target(name: "MetaConnectionPolicy"),
        .target(name: "MetaDATAdapter", dependencies: adapterDependencies,
                swiftSettings: experimentalInputs ? [.define("BORDERLESS_EXPERIMENTAL_INPUTS")] : []),
        .testTarget(name: "MetaConnectionPolicyTests", dependencies: ["MetaConnectionPolicy"])
    ])
