// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CleanQuit",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CleanQuit", targets: ["CleanQuit"])
    ],
    targets: [
        .executableTarget(
            name: "CleanQuit",
            path: "Sources/CleanQuit"
        ),
        .testTarget(
            name: "CleanQuitTests",
            dependencies: ["CleanQuit"],
            path: "Tests/CleanQuitTests"
        )
    ]
)
