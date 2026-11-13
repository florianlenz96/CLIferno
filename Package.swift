// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Atext",
  platforms: [.macOS(.v14)],
  products: [.executable(name: "Atext", targets: ["Atext"])],
  targets: [
    .target(name: "SnippetCore"),
    .executableTarget(name: "Atext", dependencies: ["SnippetCore"]),
    .testTarget(name: "SnippetCoreTests", dependencies: ["SnippetCore"]),
  ],
  swiftLanguageModes: [.v5]
)
