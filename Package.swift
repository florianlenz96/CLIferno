// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "CLIferno",
  platforms: [.macOS(.v14)],
  products: [.executable(name: "CLIferno", targets: ["CLIferno"])],
  targets: [
    .target(name: "SnippetCore"),
    .executableTarget(name: "CLIferno", dependencies: ["SnippetCore"]),
    .testTarget(name: "SnippetCoreTests", dependencies: ["SnippetCore"]),
  ],
  swiftLanguageModes: [.v5]
)
