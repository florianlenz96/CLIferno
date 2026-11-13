import Foundation

public struct Snippet: Codable, Identifiable, Equatable {
  public var id: UUID
  public var title: String
  public var trigger: String
  public var content: String

  public init(id: UUID = UUID(), title: String, trigger: String, content: String) {
    self.id = id
    self.title = title
    self.trigger = trigger
    self.content = content
  }

  public static let examples = [
    Snippet(title: "Terraform formatieren", trigger: ";tfmt", content: "terraform fmt -recursive"),
    Snippet(title: "Terraform validieren", trigger: ";tval", content: "terraform validate"),
    Snippet(title: "Git-Status", trigger: ";gst", content: "git status --short"),
  ]
}

public enum SnippetValidationError: LocalizedError, Equatable {
  case emptyTitle
  case invalidTrigger
  case emptyContent
  case duplicateID
  case conflictingTrigger(String)
  case unsafeCharacter(field: String, codePoint: String)

  public var errorDescription: String? {
    switch self {
    case .emptyTitle:
      return "Bitte einen Namen eingeben."
    case .invalidTrigger:
      return
        "Kürzel müssen mit ; beginnen, danach Buchstaben, Ziffern, - oder _ enthalten und 2 bis 64 Zeichen lang sein."
    case .emptyContent:
      return "Bitte einen einzufügenden Text eingeben."
    case .duplicateID:
      return "Die Datei enthält doppelte Eintrags-IDs."
    case .conflictingTrigger(let trigger):
      return
        "Das Kürzel überschneidet sich mit \(trigger). Kürzel dürfen nicht identisch oder der Anfang eines anderen Kürzels sein."
    case .unsafeCharacter(let field, let codePoint):
      return
        "\(field) enthält das unsichtbare Steuerzeichen \(codePoint). Solche Zeichen können eingefügte Befehle verschleiern und sind nicht erlaubt."
    }
  }
}

public enum SnippetRules {
  /// Invisible characters that can hide or reorder text (terminal escapes, Trojan-Source bidi
  /// overrides, zero-width spaces). Tab, line feed and carriage return stay allowed; U+200D
  /// (zero-width joiner) stays allowed because emoji sequences need it.
  static func firstUnsafeScalar(in text: String) -> Unicode.Scalar? {
    text.unicodeScalars.first { scalar in
      switch scalar.value {
      case 0x09, 0x0A, 0x0D: return false
      case 0x00...0x1F, 0x7F...0x9F: return true  // C0/C1 controls incl. ESC
      case 0x061C, 0x200E, 0x200F, 0x202A...0x202E, 0x2066...0x2069: return true  // bidi
      case 0x200B, 0x2060, 0xFEFF: return true  // zero-width / BOM
      default: return false
      }
    }
  }

  private static func checkCharacters(_ text: String, field: String) throws {
    if let scalar = firstUnsafeScalar(in: text) {
      throw SnippetValidationError.unsafeCharacter(
        field: field, codePoint: String(format: "U+%04X", scalar.value))
    }
  }

  public static func validate(_ snippet: Snippet, among snippets: [Snippet]) throws {
    guard !snippet.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw SnippetValidationError.emptyTitle
    }
    let scalars = Array(snippet.trigger.unicodeScalars)
    let allowed = CharacterSet(
      charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
    guard (2...64).contains(scalars.count), scalars.first == ";",
      scalars.dropFirst().allSatisfy({ allowed.contains($0) })
    else {
      throw SnippetValidationError.invalidTrigger
    }
    guard !snippet.content.isEmpty else { throw SnippetValidationError.emptyContent }
    try checkCharacters(snippet.title, field: "Der Name")
    try checkCharacters(snippet.content, field: "Der einzufügende Text")
    for other in snippets where other.id != snippet.id {
      if snippet.trigger.hasPrefix(other.trigger) || other.trigger.hasPrefix(snippet.trigger) {
        throw SnippetValidationError.conflictingTrigger(other.trigger)
      }
    }
  }

  public static func validateAll(_ snippets: [Snippet]) throws {
    guard Set(snippets.map(\.id)).count == snippets.count else {
      throw SnippetValidationError.duplicateID
    }
    for snippet in snippets {
      try validate(snippet, among: snippets)
    }
  }

  public static func search(_ snippets: [Snippet], query: String) -> [Snippet] {
    let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
    return snippets.filter { snippet in
      let fields = [snippet.title, snippet.trigger, snippet.content]
      return terms.allSatisfy { term in
        fields.contains {
          $0.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
      }
    }.sorted {
      $0.title.localizedStandardCompare($1.title) == .orderedAscending
    }
  }
}
