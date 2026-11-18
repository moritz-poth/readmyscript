// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ReadMyScript",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    targets: [
        // PDF → screenplay elements → VoiceStudio render plan; no UI, fully tested
        .target(name: "ScriptCore", path: "Sources/ScriptCore"),
        .executableTarget(name: "ReadMyScript", dependencies: ["ScriptCore"], path: "Sources/ReadMyScript"),
        // prints what the parser makes of a PDF – for checking real scripts
        .executableTarget(name: "rms-dump", dependencies: ["ScriptCore"], path: "Sources/rms-dump"),
        .testTarget(name: "ScriptCoreTests", dependencies: ["ScriptCore"], path: "Tests/ScriptCoreTests"),
    ]
)
