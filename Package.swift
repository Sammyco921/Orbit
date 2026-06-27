// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Orbit",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Orbit", targets: ["OrbitApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0")
    ],
    targets: [
        .target(
            name: "Orbit",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/Orbit"
        ),
        .executableTarget(
            name: "OrbitApp",
            dependencies: ["Orbit"],
            path: "Sources/OrbitApp"
        ),
        .testTarget(
            name: "OrbitTests",
            dependencies: ["Orbit"],
            path: "Tests/OrbitTests"
        )
    ]
)
