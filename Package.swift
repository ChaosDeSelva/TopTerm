// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TopTerm",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "TopTerm", targets: ["TopTerm"])],
    dependencies: [.package(path: "Vendor/SwiftTerm")],
    targets: [
        .target(name: "TopTermCore"),
        .executableTarget(name: "TopTerm", dependencies: ["TopTermCore", "SwiftTerm"],
                          linkerSettings: [.linkedFramework("Carbon")]),
        .executableTarget(name: "TopTermGeometryChecks", dependencies: ["TopTermCore"], path: "Tests/TopTermCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
