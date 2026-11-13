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
    if !template.placeholders.isEmpty {
      guard let target = NSRunningApplication(processIdentifier: targetPID) else {
        error = InsertionError.noTarget.localizedDescription
        return
      }
      prepare(snippet, target: target, actionTitle: "Einfügen") { [weak self] text in
        guard let self, let text else { return }
        self.insertRendered(text, title: snippet.title, deleting: count, targetPID: targetPID)
      }
    } else if let text = try? template.render(values: [:]) {
      insertRendered(text, title: snippet.title, deleting: count, targetPID: targetPID)
    }
  }

  private func insertRendered(_ text: String, title: String, deleting count: Int, targetPID: pid_t)
  {
    inserter.insert(text, deleting: count, into: targetPID) { [weak self] result in
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
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    status = "Kopiert: \(title)"
  }

  func exportSnippets() {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.json]
    panel.nameFieldStringValue = "atext-snippets.json"
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
        "Die \(snippets.count) vorhandenen Einträge werden durch \(incoming.count) Einträge ersetzt. Exportiere sie zuerst, wenn du sie behalten möchtest."
      alert.addButton(withTitle: "Ersetzen")
      alert.addButton(withTitle: "Abbrechen")
      guard alert.runModal() == .alertFirstButtonReturn else { return }
      _ = persist(incoming, selection: incoming.first?.id)
    } catch {
      self.error = error.localizedDescription
    }
  }

  func shutdown() {
    permissionTimer?.invalidate()
    monitor.stop()
    inserter.restoreClipboard()
  }
}
