// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "MealfCore",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [.library(name: "MealfCore", targets: ["MealfCore"])],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
        .target(name: "MealfCore", dependencies: ["CSQLite"]),
        .testTarget(name: "MealfCoreTests", dependencies: ["MealfCore", "CSQLite"], resources: [.copy("Fixtures")])
    ]
)
