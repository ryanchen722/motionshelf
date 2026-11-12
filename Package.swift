// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MotionShelf",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "MotionShelf", path: "Sources/MotionShelf")
    ]
)
