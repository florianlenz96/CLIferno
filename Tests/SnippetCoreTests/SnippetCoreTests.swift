import Foundation
import XCTest

@testable import SnippetCore

final class SnippetCoreTests: XCTestCase {
  private let snippet = Snippet(
    title: "Terraform", trigger: ";tfmt", content: "terraform fmt -recursive")

  func testMatchSuppressesFinalCharacterAndDeletesOnlyPreviouslyTypedTrigger() {
    var matcher = ExpansionMatcher()
    for character in "hello ;tfm" {
      XCTAssertNil(matcher.consume(String(character), snippets: [snippet]))
    }
    XCTAssertEqual(
      matcher.consume("t", snippets: [snippet]),
      ExpansionMatch(snippet: snippet, deletionCount: 4)
    )
    XCTAssertNil(matcher.consume("t", snippets: [snippet]))
  }

  func testBackspaceAndResetDoNotMatchStaleInput() {
    var matcher = ExpansionMatcher()
    for character in ";tfx" {
      _ = matcher.consume(String(character), snippets: [snippet])
    }
    XCTAssertNil(matcher.consume("t", snippets: [snippet]))
    for character in ";tf" {
      _ = matcher.consume(String(character), snippets: [snippet])
    }
    matcher.backspace()
    for character in "fm" {
      XCTAssertNil(matcher.consume(String(character), snippets: [snippet]))
    }
    XCTAssertNotNil(matcher.consume("t", snippets: [snippet]))
    for character in ";tfm" {
      _ = matcher.consume(String(character), snippets: [snippet])
    }
    matcher.reset()
    XCTAssertNil(matcher.consume("t", snippets: [snippet]))
  }

  func testWhitespaceAndComposedInputClearCandidate() {
    var matcher = ExpansionMatcher()
    for character in ";tfm " {
      XCTAssertNil(matcher.consume(String(character), snippets: [snippet]))
    }
    XCTAssertNil(matcher.consume("t", snippets: [snippet]))
    _ = matcher.consume(";", snippets: [snippet])
    XCTAssertNil(matcher.consume("tfmt", snippets: [snippet]))
    XCTAssertNil(matcher.consume("t", snippets: [snippet]))
  }

  func testPrefixConflictsAreRejectedInBothDirectionsButEditingSameEntryWorks() throws {
    let shorter = Snippet(title: "Other", trigger: ";tf", content: "other")
    XCTAssertThrowsError(try SnippetRules.validate(shorter, among: [snippet]))
    XCTAssertThrowsError(try SnippetRules.validate(snippet, among: [shorter]))
    let duplicate = Snippet(title: "Duplicate", trigger: ";tfmt", content: "other")
    XCTAssertThrowsError(try SnippetRules.validate(duplicate, among: [snippet]))
    var edited = snippet
    edited.content = "new"
    XCTAssertNoThrow(try SnippetRules.validate(edited, among: [snippet]))
  }

  func testInvalidTriggersAndDuplicateIDsAreRejected() {
    for trigger in [
      "tfmt", ";", ";tf mt", ";ümlaut", ";tf\n", ";" + String(repeating: "a", count: 64),
    ] {
      let invalid = Snippet(title: "Test", trigger: trigger, content: "test")
      XCTAssertThrowsError(try SnippetRules.validate(invalid, among: []), trigger)
    }
    XCTAssertThrowsError(try SnippetRules.validateAll([snippet, snippet]))
  }

  func testSearchFindsTermsAcrossTitleTriggerAndMultilineContent() {
    let multiline = Snippet(
      title: "Übersicht", trigger: ";info", content: "first line\nsecond line")
    XCTAssertEqual(
      SnippetRules.search([multiline, snippet], query: "terraform recursive"), [snippet])
    XCTAssertEqual(SnippetRules.search([multiline], query: "ubersicht SECOND"), [multiline])
    XCTAssertEqual(SnippetRules.search([snippet], query: ";tf"), [snippet])
    XCTAssertTrue(SnippetRules.search([snippet], query: "missing").isEmpty)
  }

  func testPersistenceRoundTripsMultilineContentAndEmptyCollection() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = SnippetRepository(fileURL: directory.appendingPathComponent("snippets.json"))
    XCTAssertNil(try repository.load())
    let multiline = Snippet(title: "Text", trigger: ";text", content: "ä\nsecond line\n")
    try repository.save([snippet, multiline])
    XCTAssertEqual(try repository.load(), [snippet, multiline])
    try repository.save([])
    XCTAssertEqual(try repository.load(), [])
  }

  func testInvalidSaveDoesNotOverwriteExistingData() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = SnippetRepository(fileURL: directory.appendingPathComponent("snippets.json"))
    try repository.save([snippet])
    let invalid = Snippet(title: "", trigger: ";bad", content: "bad")
    XCTAssertThrowsError(try repository.save([invalid]))
    XCTAssertEqual(try repository.load(), [snippet])
  }

  func testCorruptOrFutureDocumentsAreNotSilentlyReplaced() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("snippets.json")
    let repository = SnippetRepository(fileURL: url)
    let corrupt = Data("not json".utf8)
    try corrupt.write(to: url)
    XCTAssertThrowsError(try repository.load())
    XCTAssertEqual(try Data(contentsOf: url), corrupt)
    try Data(#"{"version":2,"snippets":[]}"#.utf8).write(to: url)
    XCTAssertThrowsError(try repository.load()) { error in
      guard case RepositoryError.unsupportedVersion(2) = error else {
        return XCTFail("Unexpected error: \(error)")
      }
    }
  }

  func testHiddenControlAndBidiCharactersAreRejected() {
    for content in [
      "ls\u{1B}[201~\nrm -rf ~",  // ESC: breaks out of bracketed paste
      "echo ok\u{202E}txt.hs",  // right-to-left override (Trojan Source)
      "git\u{200B}status",  // zero-width space
      "a\u{0007}b",  // BEL
      "a\u{0085}b",  // C1 control
    ] {
      let unsafe = Snippet(title: "Test", trigger: ";test", content: content)
      XCTAssertThrowsError(try SnippetRules.validate(unsafe, among: []), content) { error in
        guard case SnippetValidationError.unsafeCharacter = error else {
          return XCTFail("Unexpected error: \(error)")
        }
      }
    }
    let hiddenTitle = Snippet(title: "Harmlos\u{2066}", trigger: ";test", content: "ok")
    XCTAssertThrowsError(try SnippetRules.validate(hiddenTitle, among: []))
    let allowed = Snippet(
      title: "Erlaubt", trigger: ";ok", content: "a\tb\r\nc\nÄ 👨\u{200D}💻 €")
    XCTAssertNoThrow(try SnippetRules.validate(allowed, among: []))
  }

  func testImportOfUnsafeOrOversizedFilesIsRejected() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("import.json")
    let id = UUID().uuidString
    try Data(
      #"{"version":1,"snippets":[{"id":"\#(id)","title":"x","trigger":";x","content":"ls\u001b[201~"}]}"#
        .utf8
    ).write(to: url)
    XCTAssertThrowsError(try SnippetRepository(fileURL: url).load())
    try Data(count: SnippetRepository.maxFileSize + 1).write(to: url)
    XCTAssertThrowsError(try SnippetRepository(fileURL: url).load()) { error in
      guard case RepositoryError.fileTooLarge = error else {
        return XCTFail("Unexpected error: \(error)")
      }
    }
  }

  func testLocalStorageFolderIsRestrictedEvenIfItExisted() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
    let repository = SnippetRepository(
      fileURL: directory.appendingPathComponent("snippets.json"), restrictsDirectory: true)
    try repository.save([snippet])
    let folder = try FileManager.default.attributesOfItem(atPath: directory.path)
    let file = try FileManager.default.attributesOfItem(atPath: repository.fileURL.path)
    XCTAssertEqual((folder[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    XCTAssertEqual((file[.posixPermissions] as? NSNumber)?.intValue, 0o600)
  }

  func testStorageDirectoryMigratesLegacyFolderOnce() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("migration-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let legacy = root.appendingPathComponent("Atext", isDirectory: true)
    let current = root.appendingPathComponent("CLIferno", isDirectory: true)
    try SnippetRepository(fileURL: legacy.appendingPathComponent("snippets.json")).save([snippet])

    XCTAssertEqual(SnippetRepository.storageDirectory(current: current, legacy: legacy), current)
    XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
    XCTAssertEqual(
      try SnippetRepository(fileURL: current.appendingPathComponent("snippets.json")).load(),
      [snippet])

    // An existing current folder always wins; a reappearing legacy folder is left alone.
    try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
    XCTAssertEqual(SnippetRepository.storageDirectory(current: current, legacy: legacy), current)
    XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path))
  }

  func testStorageDirectoryWithoutLegacyFolderUsesCurrent() {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("migration-\(UUID().uuidString)", isDirectory: true)
    let current = root.appendingPathComponent("CLIferno", isDirectory: true)
    let legacy = root.appendingPathComponent("Atext", isDirectory: true)
    XCTAssertEqual(SnippetRepository.storageDirectory(current: current, legacy: legacy), current)
  }
}
