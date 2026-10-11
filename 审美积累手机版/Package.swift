// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "AestheticApp",
    platforms: [.iOS(.v17)],
    products: [
        .executable(name: "AestheticApp", targets: ["AestheticApp"])
    ],
    targets: [
        .executableTarget(
            name: "AestheticApp",
            path: "Sources/AestheticApp"
        )
    ]
)
