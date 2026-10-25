// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "MeshCoreServicer", platforms: [.macOS(.v14)], products: [.library(name: "MeshCoreKit", targets: ["MeshCoreKit"]), .executable(name: "MeshCoreServicer", targets: ["MeshCoreServicer"])], targets: [.target(name: "MeshCoreKit"), .executableTarget(name: "MeshCoreServicer", dependencies: ["MeshCoreKit"]), .testTarget(name: "MeshCoreKitTests", dependencies: ["MeshCoreKit"]), .testTarget(name: "AppModelTests", dependencies: ["MeshCoreServicer", "MeshCoreKit"])])
