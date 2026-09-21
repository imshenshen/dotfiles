// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "SpaceBar", platforms: [.macOS(.v13)], products: [.executable(name: "SpaceBar", targets: ["SpaceBar"])], targets: [.executableTarget(name: "SpaceBar"), .testTarget(name: "SpaceBarTests", dependencies: ["SpaceBar"])])
