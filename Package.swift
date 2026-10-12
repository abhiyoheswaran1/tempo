// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "TempoCore", platforms: [.macOS(.v14), .iOS("26.0")], products: [.library(name: "TempoCore", targets: ["TempoCore"])], targets: [.systemLibrary(name: "CSQLite"), .target(name: "TempoCore", dependencies: ["CSQLite"]), .testTarget(name: "TempoCoreTests", dependencies: ["TempoCore"])])
