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
}
