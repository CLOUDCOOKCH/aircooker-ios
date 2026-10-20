// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "AirCookerCore",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [.library(name: "AirCookerCore", targets: ["AirCookerCore"])],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
        .target(name: "AirCookerCore", dependencies: ["CSQLite"]),
        .testTarget(name: "AirCookerCoreTests", dependencies: ["AirCookerCore", "CSQLite"], resources: [.copy("Fixtures")])
    ]
)
