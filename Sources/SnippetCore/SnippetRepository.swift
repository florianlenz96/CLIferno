import Foundation

public enum RepositoryError: LocalizedError {
  case unsupportedVersion(Int)
  case fileTooLarge(Int)

  public var errorDescription: String? {
    switch self {
    case .unsupportedVersion(let version):
      return "Das Dateiformat \(version) wird von dieser App nicht unterstützt."
    case .fileTooLarge(let bytes):
      return
        "Die Datei ist mit \(bytes / 1_048_576) MB zu groß (maximal \(SnippetRepository.maxFileSize / 1_048_576) MB)."
    }
  }
}

public struct SnippetRepository {
  private struct Document: Codable {
    let version: Int
    let snippets: [Snippet]
  }

  public static let maxFileSize = 10 * 1_048_576

  public let fileURL: URL
  /// Only for the app's own storage folder: enforce 0700 even if the folder already existed.
  let restrictsDirectory: Bool

  public init(fileURL: URL) {
    self.init(fileURL: fileURL, restrictsDirectory: false)
  }

  init(fileURL: URL, restrictsDirectory: Bool) {
    self.fileURL = fileURL
    self.restrictsDirectory = restrictsDirectory
  }

  public static var local: SnippetRepository {
    let support = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let directory = storageDirectory(
      current: support.appendingPathComponent("CLIferno", isDirectory: true),
      legacy: support.appendingPathComponent("Atext", isDirectory: true))
    return SnippetRepository(
      fileURL: directory.appendingPathComponent("snippets.json"), restrictsDirectory: true)
  }

  /// Moves the folder from the app's former name (Atext) to the current one, once.
  /// If the move fails, the legacy folder keeps being used so no entries get lost.
  static func storageDirectory(current: URL, legacy: URL) -> URL {
    let files = FileManager.default
    guard !files.fileExists(atPath: current.path), files.fileExists(atPath: legacy.path) else {
      return current
    }
    do {
      try files.moveItem(at: legacy, to: current)
      return current
    } catch {
      return legacy
    }
  }

  public func load() throws -> [Snippet]? {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
    let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    let size = (attributes[.size] as? NSNumber)?.intValue ?? Int.max
    guard size <= Self.maxFileSize else { throw RepositoryError.fileTooLarge(size) }
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
    if restrictsDirectory {
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }
    try data.write(to: fileURL, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
  }
}
