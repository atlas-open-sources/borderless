// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "BorderlessAudio", platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "BorderlessAudio", targets: ["BorderlessAudio"])],
    targets: [.target(name: "BorderlessAudio"),
              .testTarget(name: "BorderlessAudioTests", dependencies: ["BorderlessAudio"])])
