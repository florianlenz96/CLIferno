import Foundation

public enum RepositoryError: LocalizedError {
  case unsupportedVersion(Int)

  public var errorDescription: String? {
    switch self {
    case .unsupportedVersion(let version):
      return "Das Dateiformat \(version) wird von dieser App nicht unterstützt."
    }
  }
}

public struct SnippetRepository {
  private struct Document: Codable {
    let version: Int
    let snippets: [Snippet]
  }

  public let fileURL: URL

  public init(fileURL: URL) {
    self.fileURL = fileURL
  }

  public static var local: SnippetRepository {
    let directory = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Atext", isDirectory: true)
    return SnippetRepository(fileURL: directory.appendingPathComponent("snippets.json"))
  }

  public func load() throws -> [Snippet]? {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
    let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: fileURL))
    guard document.version == 1 else { throw RepositoryError.unsupportedVersion(document.version) }
    try SnippetRules.validateAll(document.snippets)
    return document.snippets
  }

  public func save(_ snippets: [Snippet]) throws {
    try SnippetRules.validateAll(snippets)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(Document(version: 1, snippets: snippets))
    let directory = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    try data.write(to: fileURL, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
  }
}
