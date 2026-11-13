import AppKit
import SnippetCore

final class SearchController: NSObject, NSSearchFieldDelegate, NSTableViewDataSource,
  NSTableViewDelegate, NSWindowDelegate
{
  let panel: NSPanel
  let searchField = NSSearchField()
  private let table = NSTableView()
  private let hint = NSTextField(labelWithString: "")
  private let actionButton = NSButton(title: "Einfügen", target: nil, action: nil)
  private let model: AppModel
  private var results: [Snippet] = []
  private var target: NSRunningApplication?
  private var activationWork: DispatchWorkItem?
  private var activationGeneration = UUID()

  init(model: AppModel) {
    self.model = model
    panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 620, height: 420),
      styleMask: [.titled, .closable, .fullSizeContentView],
      backing: .buffered, defer: false)
    super.init()
    panel.title = "Atext – Text suchen"
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.hidesOnDeactivate = true
    panel.isReleasedWhenClosed = false
    panel.delegate = self
    panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

    let content = NSView()
    panel.contentView = content
    searchField.placeholderString = "Name, Kürzel oder Text suchen"
    searchField.delegate = self
    searchField.font = .systemFont(ofSize: 20)
    searchField.sendsSearchStringImmediately = true
    table.headerView = nil
    table.rowHeight = 58
    table.allowsEmptySelection = false
    table.dataSource = self
    table.delegate = self
    table.target = self
    table.doubleAction = #selector(choose)
    table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("snippet")))
    let scroll = NSScrollView()
    scroll.documentView = table
    scroll.hasVerticalScroller = true
    scroll.borderType = .bezelBorder
    hint.font = .systemFont(ofSize: 11)
    hint.textColor = .secondaryLabelColor
    hint.maximumNumberOfLines = 2
    actionButton.target = self
    actionButton.action = #selector(choose)
    actionButton.bezelStyle = .rounded
    actionButton.keyEquivalent = "\r"
    for view in [searchField, scroll, hint, actionButton] {
      view.translatesAutoresizingMaskIntoConstraints = false
      content.addSubview(view)
    }
    NSLayoutConstraint.activate([
      searchField.topAnchor.constraint(
        equalTo: content.safeAreaLayoutGuide.topAnchor, constant: 18),
      searchField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
      searchField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
      scroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 14),
      scroll.leadingAnchor.constraint(equalTo: searchField.leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: searchField.trailingAnchor),
      scroll.bottomAnchor.constraint(equalTo: actionButton.topAnchor, constant: -14),
      actionButton.trailingAnchor.constraint(equalTo: searchField.trailingAnchor),
      actionButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
      hint.leadingAnchor.constraint(equalTo: searchField.leadingAnchor),
      hint.trailingAnchor.constraint(lessThanOrEqualTo: actionButton.leadingAnchor, constant: -12),
      hint.centerYAnchor.constraint(equalTo: actionButton.centerYAnchor),
    ])
  }

  func show(target: NSRunningApplication?) {
    cancelActivation()
    self.target =
      target?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : target
    searchField.stringValue = ""
    refreshResults()
    let canInsert = self.target != nil && AXIsProcessTrusted()
    actionButton.title = canInsert ? "Einfügen" : "Kopieren"
    hint.stringValue =
      canInsert
      ? "↑↓ auswählen · Enter einfügen · Esc schließen\nZiel: \(self.target?.localizedName ?? "Anwendung")"
      : "↑↓ auswählen · Enter kopieren · Esc schließen\nZum Einfügen im Zielprogramm die globale Tastenkombination verwenden."
    panel.center()
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
    panel.makeFirstResponder(searchField)
  }

  func controlTextDidChange(_ notification: Notification) { refreshResults() }

  private func refreshResults() {
    results = SnippetRules.search(model.snippets, query: searchField.stringValue)
    table.reloadData()
    if !results.isEmpty {
      table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    }
    actionButton.isEnabled = !results.isEmpty
  }

  func numberOfRows(in tableView: NSTableView) -> Int { results.count }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    let snippet = results[row]
    let title = NSTextField(labelWithString: "\(snippet.title)   \(snippet.trigger)")
    title.font = .systemFont(ofSize: 14, weight: .semibold)
    title.lineBreakMode = .byTruncatingTail
    let preview = NSTextField(
      labelWithString: snippet.content.replacingOccurrences(of: "\n", with: " ↵ "))
    preview.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
    preview.textColor = .secondaryLabelColor
    preview.lineBreakMode = .byTruncatingTail
    let stack = NSStackView(views: [title, preview])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 4
    stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
    title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    preview.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return stack
  }

  func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector)
    -> Bool
  {
    switch commandSelector {
    case #selector(NSResponder.moveDown(_:)):
      moveSelection(1)
    case #selector(NSResponder.moveUp(_:)):
      moveSelection(-1)
    case #selector(NSResponder.insertNewline(_:)):
      choose()
    case #selector(NSResponder.cancelOperation(_:)):
      dismiss()
    default:
      return false
    }
    return true
  }

  private func moveSelection(_ offset: Int) {
    guard !results.isEmpty else { return }
    let row = min(max(table.selectedRow + offset, 0), results.count - 1)
    table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    table.scrollRowToVisible(row)
  }

  @objc private func choose() {
    guard results.indices.contains(table.selectedRow) else { return }
    let snippet = results[table.selectedRow]
    guard let target, AXIsProcessTrusted() else {
      dismiss()
      model.copy(snippet)
      return
    }
    panel.orderOut(nil)
    if !SnippetTemplate(snippet.content).placeholders.isEmpty {
      model.insert(snippet, targetPID: target.processIdentifier)
      return
    }
    let generation = UUID()
    activationGeneration = generation
    activate(target: target, attempts: 12, generation: generation) { [weak self] in
      self?.model.insert(snippet, targetPID: target.processIdentifier)
    }
  }

  private func activate(
    target: NSRunningApplication, attempts: Int, generation: UUID,
    ready: @escaping () -> Void
  ) {
    guard generation == activationGeneration else { return }
    guard !target.isTerminated, attempts > 0 else {
      model.error = InsertionError.noTarget.localizedDescription
      return
    }
    if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier {
      ready()
      return
    }
    if attempts == 12 { target.activate(options: []) }
    let work = DispatchWorkItem { [weak self] in
      self?.activate(target: target, attempts: attempts - 1, generation: generation, ready: ready)
    }
    activationWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
  }

  private func cancelActivation() {
    activationGeneration = UUID()
    activationWork?.cancel()
    activationWork = nil
  }

  private func dismiss() {
    cancelActivation()
    panel.orderOut(nil)
    target?.activate(options: [])
  }

  func windowWillClose(_ notification: Notification) { dismiss() }
}
