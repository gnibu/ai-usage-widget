// swift-tools-version: 5.9
import PackageDescription

// Built as a plain SwiftPM executable and wrapped into an .app bundle by
// build.sh, so the whole thing compiles with Command Line Tools — no Xcode.
let package = Package(
    name: "AIUsage",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "AIUsage", path: "Sources/AIUsage")
    ]
)
