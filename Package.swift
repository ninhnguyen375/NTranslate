// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "translate",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "translate", targets: ["translate"]),
    ],
    targets: [
        .executableTarget(name: "translate"),
    ]
)
