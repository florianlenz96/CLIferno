import AppKit
import Combine
import SnippetCore
import UniformTypeIdentifiers

final class AppModel: ObservableObject {
  @Published private(set) var snippets: [Snippet] = []
  @Published var selectedID: UUID?
  @Published var error: String?
  @Published private(set) var storageAvailable = true
  @Published private(set) var accessibilityGranted = false
  @Published private(set) var inputMonitoringGranted = false
  @Published private(set) var monitorRunning = false
  @Published var paused = false {
    didSet { monitor.isPaused = paused }
  }
  @Published var status = "Bereit"
  var hasUnsavedChanges = false
  private(set) var isPreparingTemplate = false

  let repository: SnippetRepository
  let monitor = KeyboardMonitor()
  let inserter = TextInserter()
  var openSearch: ((NSRunningApplication?) -> Void)?
  var openTemplate: ((Snippet, NSRunningApplication?, String, @escaping (String?) -> Void) -> Void)?
  private var permissionTimer: Timer?

  init(repository: SnippetRepository = .local, monitorPermissions: Bool = true) {
    self.repository = repository
    reload()
    monitor.isInsertionBusy = { [weak self] in
      guard let self else { return true }
      return self.inserter.isBusy || self.isPreparingTemplate
    }
    monitor.onExpansion = { [weak self] snippet, count, pid in
      self?.insert(snippet, deleting: count, targetPID: pid)
    }
    monitor.onSearch = { [weak self] target in self?.openSearch?(target) }
    monitor.onTapStateChange = { [weak self] running in self?.monitorRunning = running }
    if monitorPermissions {
      refreshPermissions()
      permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
        self?.refreshPermissions()
      }
    }
  }

  func reload() {
    do {
      if let loaded = try repository.load() {
        snippets = loaded
      } else {
        try repository.save(Snippet.examples)
        snippets = Snippet.examples
      }
      storageAvailable = true
      error = nil
      selectedID = snippets.first?.id
      monitor.snippets = snippets
    } catch {
      storageAvailable = false
      self.error =
        "Einträge konnten nicht geladen werden. Die Datei wird nicht überschrieben.\n\(repository.fileURL.path)\n\(error.localizedDescription)"
    }
  }

  @discardableResult
  func save(_ snippet: Snippet) -> Bool {
    guard storageAvailable else { return false }
    var updated = snippets
    if let index = updated.firstIndex(where: { $0.id == snippet.id }) {
      updated[index] = snippet
    } else {
      updated.append(snippet)
    }
    return persist(updated, selection: snippet.id)
  }

  func delete(_ id: UUID) {
    let updated = snippets.filter { $0.id != id }
    _ = persist(updated, selection: updated.first?.id)
  }

  private func persist(_ updated: [Snippet], selection: UUID?) -> Bool {
    guard storageAvailable else { return false }
    do {
      try repository.save(updated)
      snippets = updated
      selectedID = selection
      monitor.snippets = updated
      status = "Gespeichert"
      return true
    } catch {
      self.error = error.localizedDescription
      return false
    }
  }

  func requestPermissions() {
    let options =
      [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
    _ = CGRequestListenEventAccess()
    refreshPermissions()
  }

  func refreshPermissions() {
    accessibilityGranted = AXIsProcessTrusted()
    inputMonitoringGranted = CGPreflightListenEventAccess()
    // A modifying event tap uses Accessibility; listen-only permission is not a prerequisite.
    if accessibilityGranted {
      monitor.start()
      monitorRunning = monitor.isRunning
    } else {
      monitor.stop()
    }
  }

  func openPermissionSettings(_ pane: String) {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
      NSWorkspace.shared.open(url)
    }
  }

  func insert(_ snippet: Snippet, deleting count: Int = 0, targetPID: pid_t) {
    guard !isPreparingTemplate, !inserter.isBusy else { return }
    let template = SnippetTemplate(snippet.content)
    // Remember the field the trigger was typed in; insertion is refused if focus moved.
    let focus = TextInserter.focusedElement(of: targetPID)
    if !template.placeholders.isEmpty {
      guard let target = NSRunningApplication(processIdentifier: targetPID) else {
        error = InsertionError.noTarget.localizedDescription
        return
      }
      prepare(snippet, target: target, actionTitle: "Einfügen") { [weak self] text in
        guard let self, let text else { return }
        self.insertRendered(
          text, title: snippet.title, deleting: count, targetPID: targetPID, focus: focus)
      }
    } else if let text = try? template.render(values: [:]) {
      insertRendered(text, title: snippet.title, deleting: count, targetPID: targetPID, focus: focus)
    }
  }

  private func insertRendered(
    _ text: String, title: String, deleting count: Int, targetPID: pid_t, focus: AXUIElement?
  ) {
    inserter.insert(text, deleting: count, into: targetPID, expectedFocus: focus) {
      [weak self] result in
      switch result {
      case .success: self?.status = "Einfügen gesendet: \(title)"
      case .failure(let error): self?.error = error.localizedDescription
      }
    }
  }

  func copy(_ snippet: Snippet) {
    guard !inserter.isBusy, !isPreparingTemplate else { return }
    let template = SnippetTemplate(snippet.content)
    if !template.placeholders.isEmpty {
      prepare(snippet, target: nil, actionTitle: "Kopieren") { [weak self] text in
        guard let text else { return }
        self?.copyRendered(text, title: snippet.title)
      }
    } else if let text = try? template.render(values: [:]) {
      copyRendered(text, title: snippet.title)
    }
  }

  private func prepare(
    _ snippet: Snippet, target: NSRunningApplication?, actionTitle: String,
    completion: @escaping (String?) -> Void
  ) {
    guard let openTemplate else {
      error = "Das Platzhalterfenster ist nicht verfügbar."
      return
    }
    isPreparingTemplate = true
    openTemplate(snippet, target, actionTitle) { [weak self] text in
      self?.isPreparingTemplate = false
      if text == nil { self?.status = "Platzhalter-Eingabe abgebrochen; nichts eingefügt." }
      completion(text)
    }
  }

  private func copyRendered(_ text: String, title: String) {
    guard TextInserter.writeConcealed(text, transient: false) else {
      error = InsertionError.clipboard.localizedDescription
      return
    }
    status = "Kopiert: \(title)"
  }

  func exportSnippets() {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.json]
    panel.nameFieldStringValue = "atext-snippets.json"
    panel.message =
      "Der Export ist unverschlüsselt. Enthält ein Eintrag Zugangsdaten, die Datei nicht weitergeben."
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do { try SnippetRepository(fileURL: url).save(snippets) } catch {
      self.error = error.localizedDescription
    }
  }

  func importSnippets() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      guard let incoming = try SnippetRepository(fileURL: url).load() else { return }
      let alert = NSAlert()
      alert.messageText = "Einträge aus Sicherung übernehmen?"
      alert.informativeText =
        "Die \(snippets.count) vorhandenen Einträge werden durch \(incoming.count) Einträge ersetzt. Exportiere sie zuerst, wenn du sie behalten möchtest.\n\nPrüfe den vollständigen Inhalt unten: Importierte Texte werden später ungeprüft eingefügt, Zeilenumbrüche (↵) können im Terminal Befehle ausführen."
      alert.accessoryView = Self.importPreview(incoming)
      alert.addButton(withTitle: "Ersetzen")
      alert.addButton(withTitle: "Abbrechen")
      guard alert.runModal() == .alertFirstButtonReturn else { return }
      _ = persist(incoming, selection: incoming.first?.id)
    } catch {
      self.error = error.localizedDescription
    }
  }

  /// Full, untruncated listing so hidden commands in imported snippets are visible.
  private static func importPreview(_ snippets: [Snippet]) -> NSView {
    let listing = snippets.map { snippet in
      let lines = snippet.content.components(separatedBy: "\n")
      let marker = lines.count > 1 ? "  ⚠︎ \(lines.count) Zeilen" : ""
      let body = lines.map { "    " + $0 }.joined(separator: " ↵\n")
      return "\(snippet.trigger)  –  \(snippet.title)\(marker)\n\(body)"
    }.joined(separator: "\n\n")
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 460, height: 240))
    scroll.hasVerticalScroller = true
    scroll.borderType = .bezelBorder
    let text = NSTextView(frame: NSRect(origin: .zero, size: scroll.contentSize))
    text.isEditable = false
    text.isVerticallyResizable = true
    text.minSize = NSSize(width: 0, height: scroll.contentSize.height)
    text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
    text.textContainer?.widthTracksTextView = true
    text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
    text.string = listing
    text.autoresizingMask = [.width]
    scroll.documentView = text
    return scroll
  }

  func shutdown() {
    permissionTimer?.invalidate()
    monitor.stop()
    inserter.restoreClipboard()
  }
}
