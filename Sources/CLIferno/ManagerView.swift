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
    return "Version \(version) (Build \(build))"
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
          TextField("Einträge suchen", text: $query)
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
            Button(action: newSnippet) { Label("Neu", systemImage: "plus") }
              .keyboardShortcut("n", modifiers: .command)
              .disabled(!model.storageAvailable)
            Spacer()
            Button(action: deleteSnippet) { Image(systemName: "trash") }
              .help("Ausgewählten Eintrag löschen")
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
            "Deine häufigsten Texte", systemImage: "text.badge.plus",
            description: Text("Lege einen Eintrag an oder wähle einen aus der Liste.")
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
        Button("Importieren", action: model.importSnippets).disabled(!model.storageAvailable)
        Button("Exportieren", action: model.exportSnippets).disabled(!model.storageAvailable)
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
        Picker("Darstellung", selection: $model.appearance) {
          ForEach(AppearanceMode.allCases) { mode in
            Label(mode.title, systemImage: mode.symbolName).tag(mode)
          }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .help("Darstellung: Hell, Dunkel oder wie macOS")
        Toggle("Ersetzung pausieren", isOn: $model.paused).toggleStyle(.switch)
      }
      Text("Kürzel direkt tippen oder Ctrl + Option + Leertaste zum Suchen drücken.")
        .foregroundStyle(.secondary)
      if !model.storageAvailable {
        HStack {
          Label(
            "Speicherfehler: Änderungen sind gesperrt.", systemImage: "exclamationmark.triangle"
          )
          .foregroundStyle(.red)
          Button("Erneut laden", action: model.reload)
        }
      }
      if !model.monitorRunning {
        HStack(alignment: .top, spacing: 12) {
          Image(systemName: "lock.shield").font(.title2)
          VStack(alignment: .leading, spacing: 6) {
            Text(
              model.accessibilityGranted
                ? "Bedienungshilfen sind freigegeben, aber der Tastaturmonitor konnte nicht starten."
                : "macOS hat Bedienungshilfen für diese App-Version noch nicht freigegeben."
            )
            .font(.callout.bold())
            HStack {
              permissionButton(
                "Bedienungshilfen", granted: model.accessibilityGranted,
                pane: "Privacy_Accessibility")
              permissionButton(
                "Eingabeüberwachung", granted: model.inputMonitoringGranted,
                pane: "Privacy_ListenEvent")
              Button("Anfordern", action: model.requestPermissions)
              Button("Erneut prüfen", action: model.refreshPermissions)
            }
            Text(
              "Nach einem Signaturwechsel kann der alte Eintrag aktiviert aussehen: CLIferno in den Bedienungshilfen entfernen und diese App neu hinzufügen. Bei Bedarf auch die Eingabeüberwachung erneuern und CLIferno neu starten. Gespeicherte Texte bleiben erhalten."
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
            ? "Automatische Ersetzung pausiert; Suche bleibt verfügbar."
            : "Systemweite Kürzel aktiv",
          systemImage: model.paused ? "pause.circle" : "checkmark.circle"
        )
        .font(.caption)
        .foregroundStyle(model.paused ? Color.secondary : Color.green)
      }
    }
    .padding(18)
    .background(.bar)
  }

  private func permissionButton(_ title: String, granted: Bool, pane: String) -> some View {
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
            ? "Eintrag bearbeiten" : "Neuer Eintrag"
        )
        .font(.title2.bold())
        Spacer()
        if isDirty { Text("Nicht gespeichert").font(.caption).foregroundStyle(.secondary) }
      }
      VStack(alignment: .leading, spacing: 6) {
        Text("Name").font(.headline)
        TextField("Zum Beispiel: Terraform formatieren", text: draftBinding(\.title))
          .textFieldStyle(.roundedBorder)
      }
      VStack(alignment: .leading, spacing: 6) {
        Text("Kürzel").font(.headline)
        TextField(";tfmt", text: draftBinding(\.trigger))
          .textFieldStyle(.roundedBorder)
          .font(.system(.body, design: .monospaced))
        Text(
          "Beginnt mit ; und wird sofort nach dem letzten Zeichen ersetzt. Groß-/Kleinschreibung zählt."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      VStack(alignment: .leading, spacing: 6) {
        Text("Einzufügender Text").font(.headline)
        TextEditor(text: draftBinding(\.content))
          .font(.system(.body, design: .monospaced))
          .padding(6)
          .background(Color(nsColor: .textBackgroundColor))
          .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
          .frame(minHeight: 140)
        Text(
          "Platzhalter: $1, $2 usw. werden vor dem Einfügen abgefragt. $$1 fügt wörtlich $1 ein; $$ ergibt ein Dollarzeichen."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      Text(
        "CLIferno sendet keine Eingabetaste. Zeilenumbrüche in eingefügten Texten können im Terminal trotzdem Befehle auslösen. Sichere Felder sind ausgenommen."
      )
      .font(.caption).foregroundStyle(.secondary)
      HStack {
        Button("Text kopieren") { model.copy(snippet) }.disabled(snippet.content.isEmpty)
        Spacer()
        Button("Verwerfen") {
          creatingNew = false
          loadDraft()
        }.disabled(!isDirty)
        Button("Speichern") { _ = model.save(snippet) }
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
    alert.messageText = "Ungespeicherte Änderungen verwerfen?"
    alert.addButton(withTitle: "Weiter bearbeiten")
    alert.addButton(withTitle: "Verwerfen")
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
    alert.messageText = "„\(snippet.title)“ löschen?"
    alert.informativeText = "Der Eintrag und ungespeicherte Änderungen daran werden entfernt."
    alert.addButton(withTitle: "Abbrechen")
    alert.addButton(withTitle: "Löschen")
    if alert.runModal() == .alertSecondButtonReturn {
      creatingNew = false
      model.delete(id)
    }
  }
}
