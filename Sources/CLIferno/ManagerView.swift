import AppKit
import SnippetCore
import SwiftUI

struct ManagerView: View {
  @ObservedObject var model: AppModel
  @State private var query = ""
  @State private var draft: Snippet?
  @State private var creatingNew = false

  private static let versionText: String = {
    let info = Bundle.main.infoDictionary
    let version = info?["CFBundleShortVersionString"] as? String ?? "dev"
    let build = info?["CFBundleVersion"] as? String ?? "–"
    return String(localized: "Version \(version) (Build \(build))")
  }()

  private var results: [Snippet] { SnippetRules.search(model.snippets, query: query) }
  private var isDirty: Bool {
    guard let draft else { return false }
    if let saved = model.snippets.first(where: { $0.id == draft.id }) { return draft != saved }
    return !draft.title.isEmpty || draft.trigger != ";" || !draft.content.isEmpty
  }

  var body: some View {
    VStack(spacing: 0) {
      permissions
      HSplitView {
        VStack(spacing: 10) {
          TextField("Search snippets", text: $query)
            .textFieldStyle(.roundedBorder)
            .padding([.horizontal, .top], 12)
          List(selection: Binding(get: { model.selectedID }, set: select)) {
            ForEach(results) { snippet in
              VStack(alignment: .leading, spacing: 4) {
                Text(snippet.title).font(.headline)
                Text(snippet.trigger).font(.system(.caption, design: .monospaced))
                  .foregroundStyle(.secondary)
              }
              .padding(.vertical, 4)
              .tag(snippet.id)
            }
          }
          HStack {
            Button(action: newSnippet) { Label("New", systemImage: "plus") }
              .keyboardShortcut("n", modifiers: .command)
              .disabled(!model.storageAvailable)
            Spacer()
            Button(action: deleteSnippet) { Image(systemName: "trash") }
              .help("Delete selected snippet")
              .disabled(model.selectedID == nil || !model.storageAvailable)
          }
          .padding(12)
        }
        .frame(minWidth: 210, idealWidth: 240, maxWidth: 320)

        if let draft {
          editor(draft)
            .frame(minWidth: 430, maxWidth: .infinity, maxHeight: .infinity)
        } else {
          ContentUnavailableView(
            "Your most-used texts", systemImage: "text.badge.plus",
            description: Text("Create a snippet or pick one from the list.")
          )
          .frame(minWidth: 430, maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      Divider()
      HStack {
        Text(model.status).font(.caption).foregroundStyle(.secondary)
        Spacer()
        Text(Self.versionText).font(.caption).foregroundStyle(.tertiary)
          .textSelection(.enabled)
        Button("Import", action: model.importSnippets).disabled(!model.storageAvailable)
        Button("Export", action: model.exportSnippets).disabled(!model.storageAvailable)
      }
      .padding(12)
    }
    .frame(minWidth: 760, minHeight: 570)
    .onAppear { loadDraft() }
    .onChange(of: model.selectedID) { _, _ in loadDraft() }
    .onChange(of: model.snippets) { _, _ in loadDraft() }
    .onChange(of: isDirty) { _, dirty in model.hasUnsavedChanges = dirty }
    .alert(
      "CLIferno",
      isPresented: Binding(
        get: { model.error != nil }, set: { if !$0 { model.error = nil } }
      )
    ) {
      Button("OK") { model.error = nil }
    } message: {
      Text(model.error ?? "")
    }
  }

  private var permissions: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Label("CLIferno", systemImage: "flame").font(.title2.bold())
        Spacer()
        Picker("Appearance", selection: $model.appearance) {
          ForEach(AppearanceMode.allCases) { mode in
            Label(mode.title, systemImage: mode.symbolName).tag(mode)
          }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .help("Appearance: light, dark or match macOS")
        Toggle("Pause Expansion", isOn: $model.paused).toggleStyle(.switch)
      }
      Text("Type a trigger directly, or press Control + Option + Space to search.")
        .foregroundStyle(.secondary)
      if !model.storageAvailable {
        HStack {
          Label(
            "Storage error: changes are locked.", systemImage: "exclamationmark.triangle"
          )
          .foregroundStyle(.red)
          Button("Reload", action: model.reload)
        }
      }
      if !model.monitorRunning {
        HStack(alignment: .top, spacing: 12) {
          Image(systemName: "lock.shield").font(.title2)
          VStack(alignment: .leading, spacing: 6) {
            Text(
              model.accessibilityGranted
                ? String(
                  localized: "Accessibility is granted, but the keyboard monitor could not start.")
                : String(
                  localized: "macOS has not yet granted Accessibility to this version of the app.")
            )
            .font(.callout.bold())
            HStack {
              permissionButton(
                "Accessibility", granted: model.accessibilityGranted,
                pane: "Privacy_Accessibility")
              permissionButton(
                "Input Monitoring", granted: model.inputMonitoringGranted,
                pane: "Privacy_ListenEvent")
              Button("Request", action: model.requestPermissions)
              Button("Check Again", action: model.refreshPermissions)
            }
            Text(
              "After a signature change, the old entry may still look enabled: remove CLIferno from Accessibility and add this app again. If needed, renew Input Monitoring as well and restart CLIferno. Saved texts are kept."
            )
            .font(.caption).foregroundStyle(.secondary)
            Text(Bundle.main.bundleURL.path)
              .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
          }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
      } else {
        Label(
          model.paused
            ? String(localized: "Automatic expansion paused; search stays available.")
            : String(localized: "System-wide triggers active"),
          systemImage: model.paused ? "pause.circle" : "checkmark.circle"
        )
        .font(.caption)
        .foregroundStyle(model.paused ? Color.secondary : Color.green)
      }
    }
    .padding(18)
    .background(.bar)
  }

  private func permissionButton(_ title: LocalizedStringKey, granted: Bool, pane: String) -> some View {
    Button {
      model.openPermissionSettings(pane)
    } label: {
      Label(title, systemImage: granted ? "checkmark.circle.fill" : "circle")
    }
  }

  private func editor(_ snippet: Snippet) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text(
          model.snippets.contains(where: { $0.id == snippet.id })
            ? String(localized: "Edit Snippet") : String(localized: "New Snippet")
        )
        .font(.title2.bold())
        Spacer()
        if isDirty { Text("Not saved").font(.caption).foregroundStyle(.secondary) }
      }
      VStack(alignment: .leading, spacing: 6) {
        Text("Name").font(.headline)
        TextField("For example: Format Terraform", text: draftBinding(\.title))
          .textFieldStyle(.roundedBorder)
      }
      VStack(alignment: .leading, spacing: 6) {
        Text("Trigger").font(.headline)
        TextField(";tfmt", text: draftBinding(\.trigger))
          .textFieldStyle(.roundedBorder)
          .font(.system(.body, design: .monospaced))
        Text(
          "Starts with ; and is replaced as soon as you type its last character. Case-sensitive."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      VStack(alignment: .leading, spacing: 6) {
        Text("Text to Insert").font(.headline)
        PlainTextEditor(text: draftBinding(\.content))
          .padding(6)
          .background(Color(nsColor: .textBackgroundColor))
          .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
          .frame(minHeight: 140)
        Text(
          "Placeholders: $1, $2 etc. are asked for before inserting. $$1 inserts a literal $1; $$ gives a dollar sign."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      Text(
        "CLIferno never presses Return. Line breaks in inserted texts can still run commands in a terminal. Secure fields are excluded."
      )
      .font(.caption).foregroundStyle(.secondary)
      HStack {
        Button("Copy Text") { model.copy(snippet) }.disabled(snippet.content.isEmpty)
        Spacer()
        Button("Discard") {
          creatingNew = false
          loadDraft()
        }.disabled(!isDirty)
        Button("Save") { _ = model.save(snippet) }
          .keyboardShortcut("s", modifiers: .command)
          .buttonStyle(.borderedProminent)
          .disabled(!isDirty || !model.storageAvailable)
      }
    }
    .padding(24)
  }

  private func draftBinding(_ keyPath: WritableKeyPath<Snippet, String>) -> Binding<String> {
    Binding(
      get: { draft?[keyPath: keyPath] ?? "" },
      set: { draft?[keyPath: keyPath] = $0 })
  }

  private func loadDraft() {
    if model.selectedID == nil && creatingNew { return }
    creatingNew = false
    draft = model.snippets.first(where: { $0.id == model.selectedID })
  }

  private func allowDiscard() -> Bool {
    guard isDirty else { return true }
    let alert = NSAlert()
    alert.messageText = String(localized: "Discard unsaved changes?")
    alert.addButton(withTitle: String(localized: "Keep Editing"))
    alert.addButton(withTitle: String(localized: "Discard"))
    return alert.runModal() == .alertSecondButtonReturn
  }

  private func select(_ id: UUID?) {
    guard id != model.selectedID, allowDiscard() else { return }
    creatingNew = false
    model.selectedID = id
  }

  private func newSnippet() {
    guard allowDiscard() else { return }
    creatingNew = true
    model.selectedID = nil
    draft = Snippet(title: "", trigger: ";", content: "")
  }

  private func deleteSnippet() {
    guard let id = model.selectedID,
      let snippet = model.snippets.first(where: { $0.id == id })
    else { return }
    let alert = NSAlert()
    alert.messageText = String(localized: "Delete “\(snippet.title)”?")
    alert.informativeText = String(
      localized: "The snippet and any unsaved changes to it will be removed.")
    alert.addButton(withTitle: String(localized: "Cancel"))
    alert.addButton(withTitle: String(localized: "Delete"))
    if alert.runModal() == .alertSecondButtonReturn {
      creatingNew = false
      model.delete(id)
    }
  }
}
