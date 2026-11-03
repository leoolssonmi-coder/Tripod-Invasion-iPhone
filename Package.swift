// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "TripodCore", platforms: [.macOS(.v13)], products: [.library(name: "TripodCore", targets: ["TripodCore"])], targets: [.target(name: "TripodCore", path: "Sources/Core"), .testTarget(name: "TripodCoreTests", dependencies: ["TripodCore"], path: "Tests")])
