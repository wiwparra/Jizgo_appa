// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "HogarFinanzas", platforms: [.iOS(.v17), .macOS(.v14)], products: [.library(name: "HogarCore", targets: ["HogarCore"])], targets: [.target(name: "HogarCore"), .testTarget(name: "HogarCoreTests", dependencies: ["HogarCore"])])
