import AppKit
import CoreGraphics
import DexCore
import SwiftUI
import UniformTypeIdentifiers

struct DexSettingsView: View {
  private enum SettingsTab: Hashable {
    case shortcuts
    case general
    case history
    case recentlyDeleted
  }

  private let model: DexApplicationModel
  @State private var selectedTab: SettingsTab = .shortcuts

  init(model: DexApplicationModel) {
    self.model = model
  }

  var body: some View {
    TabView(selection: $selectedTab) {
      ShortcutManagerView(
        store: model.store,
        executor: model.executor,
        monitor: model.monitor
      )
      .tabItem { Label("Shortcuts", systemImage: "command") }
      .tag(SettingsTab.shortcuts)

      GeneralSettingsView(model: model)
        .tabItem { Label("General", systemImage: "gear") }
        .tag(SettingsTab.general)

      ExecutionHistoryView(history: model.history)
        .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
        .tag(SettingsTab.history)

      RecentlyDeletedShortcutsView(store: model.store)
        .tabItem { Label("Recently Deleted", systemImage: "trash") }
        .tag(SettingsTab.recentlyDeleted)
    }
    .frame(minWidth: 900, minHeight: 580)
    .onAppear { model.startIfNeeded() }
  }
}

private struct ShortcutManagerView: View {
  @ObservedObject var store: ShortcutStore
  @ObservedObject var executor: ActionExecutor
  @ObservedObject var monitor: GlobalShortcutMonitor
  @State private var selection: UUID?
  @State private var shortcutPendingDeletion: DexShortcut?

  var body: some View {
    HSplitView {
      VStack(spacing: 0) {
        HStack {
          Text("Shortcuts")
            .font(.headline)
          Spacer()
          Text("\(store.configuration.shortcuts.count)")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)

        Divider()

        List(selection: $selection) {
          ForEach(store.configuration.shortcuts) { shortcut in
            HStack(spacing: 10) {
              ShortcutActionIcon(action: shortcut.action, size: 26)

              Text(shortcut.name.isEmpty ? shortcut.action.suggestedName : shortcut.name)
                .lineLimit(1)
              Spacer(minLength: 4)
              Text(shortcut.binding.display(using: store.configuration.trigger))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.vertical, 4)
            .opacity(shortcut.isEnabled ? 1 : 0.5)
            .tag(shortcut.id)
            .contextMenu {
              Button(role: .destructive) {
                requestDeletion(of: shortcut.id)
              } label: {
                Label("Delete", systemImage: "trash")
              }
            }
          }
          .onMove(perform: store.moveShortcuts)
        }
        .listStyle(.sidebar)

        Divider()

        HStack(spacing: 2) {
          Button {
            selection = store.addShortcut()
          } label: {
            Image(systemName: "plus")
              .frame(width: 22, height: 20)
          }
          .buttonStyle(.borderless)
          .keyboardShortcut("n", modifiers: .command)
          .help("Add Shortcut")

          Button {
            guard let selection else { return }
            requestDeletion(of: selection)
          } label: {
            Image(systemName: "minus")
              .frame(width: 22, height: 20)
          }
          .buttonStyle(.borderless)
          .keyboardShortcut(.delete, modifiers: .command)
          .disabled(selection == nil)
          .help("Remove Shortcut (⌘⌫)")

          Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
      }
      .frame(minWidth: 280, idealWidth: 280, maxWidth: 480)
      .background(Color(nsColor: .controlBackgroundColor))

      Group {
        if let selection, let currentShortcut = store.shortcut(id: selection) {
          ShortcutEditorView(
            shortcut: Binding(
              get: { store.shortcut(id: selection) ?? currentShortcut },
              set: { store.update($0) }
            ),
            defaultTerminal: store.configuration.defaultTerminal,
            trigger: store.configuration.trigger,
            conflict: store.conflictingShortcut(for: currentShortcut),
            recordingChanged: { isRecording in
              if isRecording {
                monitor.stop()
              } else {
                monitor.start()
              }
            },
            execute: { executor.execute($0) }
          )
          .id(selection)
        } else {
          ContentUnavailableView(
            "No Shortcut Selected",
            systemImage: "command",
            description: Text("Add or select a shortcut to configure it.")
          )
        }
      }
      .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
      .layoutPriority(1)
    }
    .onAppear {
      if selection == nil { selection = store.configuration.shortcuts.first?.id }
    }
    .alert(item: $shortcutPendingDeletion) { shortcut in
      Alert(
        title: Text("Delete \(displayName(for: shortcut))?"),
        message: Text(deletionMessage),
        primaryButton: .destructive(Text(deletionButtonTitle)) {
          deleteShortcut(withID: shortcut.id)
        },
        secondaryButton: .cancel()
      )
    }
    .overlay(alignment: .bottom) {
      if let error = store.lastError {
        Text(error)
          .font(.caption)
          .foregroundStyle(.red)
          .padding(8)
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
          .padding()
      }
    }
  }

  private func requestDeletion(of id: UUID) {
    shortcutPendingDeletion = store.shortcut(id: id)
  }

  private func deleteShortcut(withID id: UUID) {
    let deletedIndex = store.configuration.shortcuts.firstIndex { $0.id == id }
    store.remove(id: id)

    guard selection == id, let deletedIndex else { return }
    let remainingShortcuts = store.configuration.shortcuts
    if remainingShortcuts.indices.contains(deletedIndex) {
      selection = remainingShortcuts[deletedIndex].id
    } else {
      selection = remainingShortcuts.last?.id
    }
  }

  private func displayName(for shortcut: DexShortcut) -> String {
    let name = shortcut.name.trimmingCharacters(in: .whitespacesAndNewlines)
    return "“\(name.isEmpty ? shortcut.action.suggestedName : name)”"
  }

  private var deletionMessage: String {
    if store.configuration.archivesDeletedShortcuts {
      return "You can restore this shortcut from Recently Deleted for 30 days."
    }
    return "This shortcut will be deleted immediately. This action cannot be undone."
  }

  private var deletionButtonTitle: String {
    store.configuration.archivesDeletedShortcuts ? "Move to Recently Deleted" : "Delete"
  }
}

private struct ExecutionHistoryView: View {
  @ObservedObject var history: ExecutionHistoryStore
  @State private var isConfirmingClear = false

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("Shortcut History")
            .font(.headline)
          Text("The most recent 1,000 shortcut runs are kept on this Mac.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Text("\(history.entries.count)")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)

      Divider()

      if history.entries.isEmpty {
        ContentUnavailableView(
          "No Shortcut History",
          systemImage: "clock.arrow.circlepath",
          description: Text("Shortcuts you run will appear here in newest-first order.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        List(history.entries) { entry in
          HStack(spacing: 12) {
            Image(systemName: systemImage(for: entry.actionKind))
              .foregroundStyle(.secondary)
              .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
              Text(entry.shortcutName)
                .lineLimit(1)
              Text(entry.actionKind.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            Text(
              entry.timestamp,
              format: .dateTime.month(.abbreviated).day().hour().minute()
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
          }
          .padding(.vertical, 5)
        }
        .listStyle(.inset)
      }

      Divider()

      HStack {
        if let error = history.lastError {
          Label(error, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.red)
            .lineLimit(2)
        }
        Spacer()
        Button("Clear History…", role: .destructive) {
          isConfirmingClear = true
        }
        .disabled(history.entries.isEmpty)
      }
      .padding(10)
    }
    .alert("Clear Shortcut History?", isPresented: $isConfirmingClear) {
      Button("Clear History", role: .destructive) { history.clear() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This permanently removes all shortcut run history from this Mac.")
    }
  }

  private func systemImage(for kind: ShortcutActionKind) -> String {
    switch kind {
    case .launchApplication: "app"
    case .openFinder: "folder"
    case .runCommand: "terminal"
    case .openURL: "link"
    case .runAppleShortcut: "square.stack.3d.up.fill"
    }
  }
}

private struct RecentlyDeletedShortcutsView: View {
  @ObservedObject var store: ShortcutStore
  @State private var shortcutPendingPermanentDeletion: DeletedShortcut?
  @State private var isConfirmingDeleteAll = false
  @State private var disabledRestorationName: String?

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("Recently Deleted")
            .font(.headline)
          Text("Shortcuts are permanently deleted 30 days after removal.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Text("\(store.configuration.recentlyDeletedShortcuts.count)")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)

      Divider()

      if store.configuration.recentlyDeletedShortcuts.isEmpty {
        ContentUnavailableView(
          "No Recently Deleted Shortcuts",
          systemImage: "trash",
          description: Text("Deleted shortcuts that can still be restored will appear here.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        List(store.configuration.recentlyDeletedShortcuts) { deletedShortcut in
          HStack(spacing: 12) {
            ShortcutActionIcon(action: deletedShortcut.shortcut.action, size: 28)

            VStack(alignment: .leading, spacing: 2) {
              Text(displayName(for: deletedShortcut.shortcut))
                .lineLimit(1)
              Text(
                "Available until \(deletedShortcut.expiresAt(), format: .dateTime.month(.abbreviated).day().year())"
              )
              .font(.caption)
              .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            Text(
              deletedShortcut.shortcut.binding.display(using: store.configuration.trigger)
            )
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(.secondary)

            Button("Restore") {
              restore(deletedShortcut)
            }
            .buttonStyle(.bordered)

            Button(role: .destructive) {
              shortcutPendingPermanentDeletion = deletedShortcut
            } label: {
              Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete Permanently")
          }
          .padding(.vertical, 5)
        }
        .listStyle(.inset)
      }

      Divider()

      HStack {
        Text("Restored shortcuts return to the end of your Shortcuts list.")
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        Button("Delete All…", role: .destructive) {
          isConfirmingDeleteAll = true
        }
        .disabled(store.configuration.recentlyDeletedShortcuts.isEmpty)
      }
      .padding(10)
    }
    .alert(item: $shortcutPendingPermanentDeletion) { deletedShortcut in
      Alert(
        title: Text("Permanently delete \(displayName(for: deletedShortcut.shortcut))?"),
        message: Text("This action cannot be undone."),
        primaryButton: .destructive(Text("Delete Permanently")) {
          store.permanentlyDeleteShortcut(id: deletedShortcut.id)
        },
        secondaryButton: .cancel()
      )
    }
    .alert("Delete All Recently Deleted Shortcuts?", isPresented: $isConfirmingDeleteAll) {
      Button("Delete All", role: .destructive) {
        store.deleteAllRecentlyDeletedShortcuts()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This permanently deletes every shortcut in Recently Deleted.")
    }
    .alert(
      "Restored but Disabled",
      isPresented: Binding(
        get: { disabledRestorationName != nil },
        set: { if !$0 { disabledRestorationName = nil } }
      )
    ) {
      Button("OK") { disabledRestorationName = nil }
    } message: {
      Text(
        "\(disabledRestorationName ?? "This shortcut") was restored, but its keyboard shortcut is already in use. Choose a new binding before enabling it."
      )
    }
    .onAppear {
      store.purgeExpiredDeletedShortcuts()
    }
  }

  private func restore(_ deletedShortcut: DeletedShortcut) {
    guard let restored = store.restoreDeletedShortcut(id: deletedShortcut.id) else { return }
    if !restored.isEnabled && deletedShortcut.shortcut.isEnabled {
      disabledRestorationName = displayName(for: restored)
    }
  }

  private func displayName(for shortcut: DexShortcut) -> String {
    let name = shortcut.name.trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? shortcut.action.suggestedName : name
  }
}

private struct ShortcutEditorView: View {
  @Binding var shortcut: DexShortcut
  let defaultTerminal: TerminalApplication
  let trigger: TriggerKey
  let conflict: DexShortcut?
  let recordingChanged: (Bool) -> Void
  let execute: (DexShortcut) -> Void

  var body: some View {
    Form {
      Section("Action") {
        Picker("Type", selection: actionKindBinding) {
          ForEach(ShortcutActionKind.allCases) { kind in
            Text(kind.displayName).tag(kind)
          }
        }

        actionFields

        Button("Run Now") {
          execute(shortcut)
        }
        .disabled(!shortcut.isEnabled || !canRunAction)
      }

      Section("Keyboard Shortcut") {
        LabeledContent("Keyboard shortcut") {
          ShortcutRecorderView(
            binding: $shortcut.binding,
            trigger: trigger,
            recordingChanged: recordingChanged
          )
        }

        LabeledContent("Result") {
          Text(shortcut.binding.display(using: trigger))
            .font(.system(.body, design: .monospaced))
        }

        if let conflict {
          Label(
            "This binding is also assigned to \(conflict.name).",
            systemImage: "exclamationmark.triangle"
          )
          .foregroundStyle(.orange)
        }

        Toggle("Enabled", isOn: $shortcut.isEnabled)
      }

      Section("Name") {
        TextField("Name", text: $shortcut.name)
      }
    }
    .formStyle(.grouped)
  }

  @ViewBuilder
  private var actionFields: some View {
    switch shortcut.action {
    case .launchApplication(let target):
      ApplicationSelectionRow(target: target, chooseApplication: chooseApplication)

    case .openFinder:
      FinderDirectoryField(
        directory: finderDirectoryBinding,
        validation: finderDirectoryValidation,
        chooseDirectory: chooseFinderDirectory
      )

    case .runCommand:
      TextField("Command", text: commandBinding, axis: .vertical)
        .lineLimit(2...5)
      WorkingDirectoryField(
        directory: workingDirectoryBinding,
        chooseDirectory: chooseWorkingDirectory
      )
      Toggle("Open in terminal", isOn: terminalBinding)
      if terminalBinding.wrappedValue {
        Toggle("Close terminal on completion", isOn: closeTerminalOnCompletionBinding)
        Text("Uses \(defaultTerminal.displayName). Change the default terminal in General.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      BackgroundCommandLogRow(openLog: openCommandLog)

    case .openURL:
      TextField("URL", text: urlBinding)

    case .runAppleShortcut:
      AppleShortcutPicker(name: appleShortcutNameBinding)
    }
  }

  private var actionKindBinding: Binding<ShortcutActionKind> {
    Binding(
      get: { shortcut.action.kind },
      set: { updateAction(.empty(for: $0)) }
    )
  }

  private var commandBinding: Binding<String> {
    Binding(
      get: {
        if case .runCommand(let command, _, _, _) = shortcut.action { return command }
        return ""
      },
      set: { value in
        if case .runCommand(_, let directory, let terminal, let closeTerminal) = shortcut.action {
          updateAction(
            .runCommand(
              command: value,
              workingDirectory: directory,
              inTerminal: terminal,
              closeTerminalOnCompletion: closeTerminal
            )
          )
        }
      }
    )
  }

  private var workingDirectoryBinding: Binding<String> {
    Binding(
      get: {
        if case .runCommand(_, let directory, _, _) = shortcut.action {
          return directory ?? FileManager.default.homeDirectoryForCurrentUser.path
        }
        return ""
      },
      set: { value in
        if case .runCommand(let command, _, let terminal, let closeTerminal) = shortcut.action {
          updateAction(
            .runCommand(
              command: command,
              workingDirectory: value,
              inTerminal: terminal,
              closeTerminalOnCompletion: closeTerminal
            )
          )
        }
      }
    )
  }

  private var finderDirectoryBinding: Binding<String> {
    Binding(
      get: {
        if case .openFinder(let directory) = shortcut.action { return directory ?? "" }
        return ""
      },
      set: { value in
        updateAction(.openFinder(directory: value.isEmpty ? nil : value))
      }
    )
  }

  private var finderDirectoryValidation: DirectoryPathValidation {
    DirectoryPathValidation(finderDirectoryBinding.wrappedValue)
  }

  private var canRunAction: Bool {
    switch shortcut.action {
    case .openFinder:
      return finderDirectoryValidation.canOpenInFinder
    case .runAppleShortcut(let name):
      return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    default:
      return true
    }
  }

  private var terminalBinding: Binding<Bool> {
    Binding(
      get: {
        if case .runCommand(_, _, let terminal, _) = shortcut.action { return terminal }
        return true
      },
      set: { value in
        if case .runCommand(let command, let directory, _, let closeTerminal) = shortcut.action {
          updateAction(
            .runCommand(
              command: command,
              workingDirectory: directory,
              inTerminal: value,
              closeTerminalOnCompletion: closeTerminal
            )
          )
        }
      }
    )
  }

  private var closeTerminalOnCompletionBinding: Binding<Bool> {
    Binding(
      get: {
        if case .runCommand(_, _, _, let closeTerminal) = shortcut.action {
          return closeTerminal
        }
        return false
      },
      set: { value in
        if case .runCommand(let command, let directory, let terminal, _) = shortcut.action {
          updateAction(
            .runCommand(
              command: command,
              workingDirectory: directory,
              inTerminal: terminal,
              closeTerminalOnCompletion: value
            )
          )
        }
      }
    )
  }

  private var urlBinding: Binding<String> {
    Binding(
      get: {
        if case .openURL(let url) = shortcut.action { return url }
        return ""
      },
      set: { updateAction(.openURL(url: $0)) }
    )
  }

  private var appleShortcutNameBinding: Binding<String> {
    Binding(
      get: {
        if case .runAppleShortcut(let name) = shortcut.action { return name }
        return ""
      },
      set: { updateAction(.runAppleShortcut(name: $0)) }
    )
  }

  private var suggestedShortcutName: String {
    if let applicationIdentity {
      return "Open \(applicationIdentity.name)"
    }
    return shortcut.action.suggestedName
  }

  private func updateAction(_ action: ShortcutAction) {
    let previousSuggestion = suggestedShortcutName
    let trimmedName = shortcut.name.trimmingCharacters(in: .whitespacesAndNewlines)
    let shouldUpdateName =
      trimmedName.isEmpty
      || trimmedName == "New Shortcut"
      || trimmedName == previousSuggestion

    shortcut.action = action
    if shouldUpdateName {
      shortcut.name = suggestedShortcutName
    }
  }

  private func chooseApplication() {
    let panel = NSOpenPanel()
    panel.title = "Choose an Application"
    panel.message = "Choose the application this shortcut should open."
    panel.prompt = "Choose"
    panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
    panel.allowedContentTypes = [.applicationBundle]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    if panel.runModal() == .OK, let url = panel.url {
      updateAction(.launchApplication(target: url.path))
    }
  }

  private var applicationIdentity: ApplicationIdentity? {
    guard case .launchApplication(let target) = shortcut.action else { return nil }
    return ApplicationIdentity(target: target)
  }

  private func chooseWorkingDirectory() {
    let panel = NSOpenPanel()
    panel.title = "Choose a Working Directory"
    panel.message = "Choose the folder where this command should run."
    panel.prompt = "Choose"
    panel.directoryURL = URL(
      fileURLWithPath: (workingDirectoryBinding.wrappedValue as NSString).expandingTildeInPath,
      isDirectory: true
    )
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    if panel.runModal() == .OK, let url = panel.url,
      case .runCommand(let command, _, let terminal, let closeTerminal) = shortcut.action
    {
      updateAction(
        .runCommand(
          command: command,
          workingDirectory: url.path,
          inTerminal: terminal,
          closeTerminalOnCompletion: closeTerminal
        )
      )
    }
  }

  private func openCommandLog() {
    try? FileManager.default.createDirectory(
      at: DexPaths.applicationSupportDirectory,
      withIntermediateDirectories: true
    )
    if !FileManager.default.fileExists(atPath: DexPaths.logFile.path) {
      FileManager.default.createFile(atPath: DexPaths.logFile.path, contents: nil)
    }
    NSWorkspace.shared.open(DexPaths.logFile)
  }

  private func chooseFinderDirectory() {
    let panel = NSOpenPanel()
    panel.title = "Choose a Directory"
    panel.message = "Choose the directory this shortcut should open in Finder."
    panel.prompt = "Choose"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    if panel.runModal() == .OK, let url = panel.url {
      updateAction(.openFinder(directory: url.path))
    }
  }
}

private struct AppleShortcutPicker: View {
  @Binding var name: String
  @StateObject private var store = AppleShortcutsStore()

  private var selectedShortcutIsMissing: Bool {
    !name.isEmpty && !store.names.contains(name)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      LabeledContent("Apple Shortcut") {
        HStack(spacing: 8) {
          Picker("Apple Shortcut", selection: $name) {
            Text("Choose a Shortcut").tag("")

            if selectedShortcutIsMissing {
              Text("\(name) (not found)").tag(name)
            }

            ForEach(store.names, id: \.self) { shortcutName in
              Text(shortcutName).tag(shortcutName)
            }
          }
          .labelsHidden()
          .frame(maxWidth: 360)

          Button {
            store.reload()
          } label: {
            Image(systemName: "arrow.clockwise")
          }
          .disabled(store.isLoading)
          .help("Refresh Apple Shortcuts")
          .accessibilityLabel("Refresh Apple Shortcuts")
        }
      }

      if store.isLoading {
        HStack(spacing: 6) {
          ProgressView()
            .controlSize(.small)
          Text("Loading Apple Shortcuts…")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      } else if let errorMessage = store.errorMessage {
        Label(errorMessage, systemImage: "exclamationmark.triangle")
          .font(.caption)
          .foregroundStyle(.orange)
      } else if store.names.isEmpty {
        Text("No Apple Shortcuts were found. Create one in Apple's Shortcuts app, then refresh.")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        Text("Choose a shortcut saved in Apple's Shortcuts app.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .task {
      store.loadIfNeeded()
    }
  }
}

private struct WorkingDirectoryField: View {
  @Binding var directory: String
  let chooseDirectory: () -> Void

  private var homeDirectory: String {
    FileManager.default.homeDirectoryForCurrentUser.path
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("Working directory", systemImage: "folder")
        .font(.headline)

      HStack(spacing: 10) {
        TextField(
          "Working directory",
          text: $directory,
          prompt: Text(homeDirectory)
        )
        .labelsHidden()
        .font(.system(.body, design: .monospaced))
        .textFieldStyle(.roundedBorder)
        .controlSize(.large)
        .frame(maxWidth: .infinity)
        .accessibilityHint("Type or paste the folder where the command should run.")

        Button(action: chooseDirectory) {
          Label("Browse…", systemImage: "folder")
        }
        .controlSize(.large)
      }

      Text("Enter a folder path or browse to choose where the command runs.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(.vertical, 4)
  }
}

private struct BackgroundCommandLogRow: View {
  let openLog: () -> Void

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      Text("Background command output")
        .font(.headline)

      Spacer(minLength: 12)

      Button(action: openLog) {
        Label("Open Log", systemImage: "doc.text")
      }
    }
    .padding(.vertical, 4)
  }
}

private struct FinderDirectoryField: View {
  @Binding var directory: String
  let validation: DirectoryPathValidation
  let chooseDirectory: () -> Void

  private static let placeholderInterval: TimeInterval = 7
  private static let suggestedDirectories: [String] = {
    let fileManager = FileManager.default
    let homeDirectory = fileManager.homeDirectoryForCurrentUser
    let candidates: [URL?] = [
      homeDirectory,
      fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first,
      fileManager.urls(for: .documentDirectory, in: .userDomainMask).first,
      fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first,
      homeDirectory.appendingPathComponent(
        "Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true),
    ]
    let availableCandidates: [URL] = candidates.compactMap { $0 }

    var seenPaths: Set<String> = []
    return availableCandidates.compactMap { url in
      var isDirectory: ObjCBool = false
      guard
        fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
        isDirectory.boolValue,
        seenPaths.insert(url.path).inserted
      else {
        return nil
      }
      return url.path
    }
  }()

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        Label("Folder path", systemImage: "folder")
          .font(.headline)
      }

      HStack(spacing: 10) {
        TimelineView(.periodic(from: .now, by: Self.placeholderInterval)) { context in
          TextField(
            "Folder path",
            text: $directory,
            prompt: Text(placeholder(at: context.date))
          )
          .labelsHidden()
          .font(.system(.body, design: .monospaced))
          .textFieldStyle(.roundedBorder)
          .controlSize(.large)
          .frame(maxWidth: .infinity)
          .accessibilityHint("Type or paste a folder path to open in Finder.")
        }

        Button(action: chooseDirectory) {
          Label("Browse…", systemImage: "folder")
        }
        .controlSize(.large)
      }

      validationMessage
        .font(.caption)
    }
    .padding(.vertical, 4)
  }

  @ViewBuilder
  private var validationMessage: some View {
    switch validation {
    case .empty:
      Label(
        "Leave blank to activate Finder without opening a specific folder.",
        systemImage: "info.circle"
      )
      .foregroundStyle(.secondary)
    case .valid:
      Label("Directory verified.", systemImage: "checkmark.circle.fill")
        .foregroundStyle(.green)
    case .missing:
      Label("That path does not exist.", systemImage: "exclamationmark.triangle.fill")
        .foregroundStyle(.red)
    case .notDirectory:
      Label(
        "That path points to a file, not a folder.",
        systemImage: "exclamationmark.triangle.fill"
      )
      .foregroundStyle(.red)
    }
  }

  private func placeholder(at date: Date) -> String {
    guard !Self.suggestedDirectories.isEmpty else {
      return FileManager.default.homeDirectoryForCurrentUser.path
    }
    let interval = Int(date.timeIntervalSinceReferenceDate / Self.placeholderInterval)
    return Self.suggestedDirectories[interval % Self.suggestedDirectories.count]
  }
}

private struct ApplicationSelectionRow: View {
  let target: String
  let chooseApplication: () -> Void

  private var identity: ApplicationIdentity? {
    ApplicationIdentity(target: target)
  }

  var body: some View {
    HStack(spacing: 12) {
      if let identity {
        Image(nsImage: identity.icon)
          .resizable()
          .scaledToFit()
          .frame(width: 42, height: 42)
          .accessibilityHidden(true)

        Text("Open \(identity.name)")
          .font(.headline)
      } else {
        Image(systemName: target.isEmpty ? "app.dashed" : "exclamationmark.app")
          .font(.system(size: 24))
          .foregroundStyle(.secondary)
          .frame(width: 42, height: 42)
          .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: 2) {
          Text(target.isEmpty ? "Choose an application" : "Application unavailable")
            .font(.headline)
          Text(
            target.isEmpty
              ? "Select the app this shortcut should open."
              : "Choose the application again to repair this shortcut."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      }

      Spacer(minLength: 12)

      Button(identity == nil ? "Choose…" : "Change…", action: chooseApplication)
    }
    .padding(.vertical, 4)
  }
}

private struct ShortcutActionIcon: View {
  let action: ShortcutAction
  let size: CGFloat

  var body: some View {
    Group {
      if case .launchApplication(let target) = action,
        let identity = ApplicationIdentity(target: target)
      {
        Image(nsImage: identity.icon)
          .resizable()
          .scaledToFit()
      } else {
        Image(systemName: fallbackSystemImage)
          .resizable()
          .scaledToFit()
          .padding(size * 0.18)
          .foregroundStyle(.secondary)
      }
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }

  private var fallbackSystemImage: String {
    switch action {
    case .launchApplication: "app.dashed"
    case .openFinder(let directory): FinderDirectoryLocation(directory: directory).systemImage
    case .runCommand: "terminal"
    case .openURL: "link"
    case .runAppleShortcut: "square.stack.3d.up.fill"
    }
  }
}

extension FinderDirectoryLocation {
  fileprivate var systemImage: String {
    switch self {
    case .applications: "pencil.and.ruler"
    case .desktop: "menubar.dock.rectangle"
    case .documents: "doc"
    case .downloads: "arrow.down.circle"
    case .iCloudDrive: "icloud"
    case .home: "house"
    case .movies: "film"
    case .music: "music.note"
    case .pictures: "photo"
    case .publicFolder, .shared: "folder.badge.person.crop"
    case .trash: "trash"
    case .startupDisk: "internaldrive"
    case .mountedVolume: "externaldrive"
    case .other: "folder"
    }
  }
}

private struct ApplicationIdentity {
  let name: String
  let icon: NSImage

  init?(target: String) {
    guard let url = Self.applicationURL(for: target) else { return nil }

    let bundle = Bundle(url: url)
    name =
      bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
      ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
      ?? url.deletingPathExtension().lastPathComponent
    icon = NSWorkspace.shared.icon(forFile: url.path)
  }

  private static func applicationURL(for target: String) -> URL? {
    guard !target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

    let expandedTarget = (target as NSString).expandingTildeInPath
    if FileManager.default.fileExists(atPath: expandedTarget) {
      return URL(fileURLWithPath: expandedTarget)
    }
    return NSWorkspace.shared.urlForApplication(withBundleIdentifier: target)
  }
}

private struct ShortcutRecorderView: View {
  @Binding var binding: KeyBinding
  let trigger: TriggerKey
  let recordingChanged: (Bool) -> Void

  @State private var isRecording = false
  @State private var validationMessage: String?

  var body: some View {
    VStack(alignment: .trailing, spacing: 5) {
      Button {
        validationMessage = nil
        isRecording.toggle()
      } label: {
        HStack(spacing: 8) {
          Circle()
            .fill(isRecording ? Color.red : Color.secondary.opacity(0.45))
            .frame(width: 8, height: 8)
          Text(isRecording ? "Listening…" : binding.display(using: trigger))
            .font(.system(.body, design: .rounded))
            .fontWeight(.medium)
          Spacer(minLength: 12)
          Image(systemName: isRecording ? "keyboard.fill" : "keyboard")
            .foregroundStyle(.secondary)
        }
        .frame(minWidth: 210, alignment: .leading)
      }
      .buttonStyle(.bordered)
      .controlSize(.large)

      Text(recorderHelp)
        .font(.caption)
        .foregroundStyle(validationMessage == nil ? Color.secondary : Color.red)
        .multilineTextAlignment(.trailing)
        .frame(maxWidth: 300, alignment: .trailing)
    }
    .background {
      ShortcutRecorderEventMonitor(
        isRecording: $isRecording,
        binding: $binding,
        trigger: trigger,
        validationMessage: $validationMessage
      )
      .frame(width: 0, height: 0)
    }
    .onChange(of: isRecording) { _, newValue in
      recordingChanged(newValue)
    }
    .onDisappear {
      guard isRecording else { return }
      isRecording = false
      recordingChanged(false)
    }
  }

  private var recorderHelp: String {
    if let validationMessage { return validationMessage }
    if isRecording {
      return "Press \(trigger.shortcutDisplayName) and the key you want. Escape cancels."
    }
    return "Click to record a shortcut by typing it."
  }
}

private struct ShortcutRecorderEventMonitor: NSViewRepresentable {
  @Binding var isRecording: Bool
  @Binding var binding: KeyBinding
  let trigger: TriggerKey
  @Binding var validationMessage: String?

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeNSView(context: Context) -> NSView {
    NSView(frame: .zero)
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    context.coordinator.update(
      isRecording: isRecording,
      trigger: trigger,
      record: { newBinding in
        binding = newBinding
        validationMessage = nil
        isRecording = false
      },
      cancel: {
        validationMessage = nil
        isRecording = false
      },
      reportValidation: { message in
        validationMessage = message
      }
    )
  }

  static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
    coordinator.stop()
  }

  @MainActor
  final class Coordinator {
    private var eventMonitor: Any?
    private var triggerState = PhysicalTriggerState()
    private var trigger: TriggerKey = .rightCommand
    private var record: (KeyBinding) -> Void = { _ in }
    private var cancel: () -> Void = {}
    private var reportValidation: (String) -> Void = { _ in }

    deinit {
      if let eventMonitor {
        NSEvent.removeMonitor(eventMonitor)
      }
    }

    func update(
      isRecording: Bool,
      trigger: TriggerKey,
      record: @escaping (KeyBinding) -> Void,
      cancel: @escaping () -> Void,
      reportValidation: @escaping (String) -> Void
    ) {
      self.trigger = trigger
      self.record = record
      self.cancel = cancel
      self.reportValidation = reportValidation

      if isRecording {
        startIfNeeded()
      } else {
        stop()
      }
    }

    func stop() {
      if let eventMonitor {
        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
      }
      triggerState.reset()
    }

    private func startIfNeeded() {
      guard eventMonitor == nil else { return }
      triggerState.reset()
      eventMonitor = NSEvent.addLocalMonitorForEvents(
        matching: [.keyDown, .flagsChanged]
      ) { [weak self] event in
        guard let self else { return event }
        return self.handle(event)
      }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
      if event.type == .flagsChanged {
        updateTriggerState(
          keyCode: event.keyCode,
          flags: event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        )
        return event
      }

      let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      let isTriggerPressed = triggerIsPressed(flags: flags)

      if event.keyCode == 53 && !isTriggerPressed {
        cancel()
        return nil
      }

      guard isTriggerPressed else {
        reportValidation("Include \(trigger.shortcutDisplayName) when you type the shortcut.")
        NSSound.beep()
        return nil
      }

      guard let key = KeyCatalog.key(forCode: event.keyCode) else {
        reportValidation("That key is not available for a Dex shortcut.")
        NSSound.beep()
        return nil
      }

      record(
        KeyBinding(
          keyCode: key.keyCode,
          keyLabel: key.label,
          modifiers: auxiliaryModifiers(flags: flags)
        ).normalized(using: trigger)
      )
      return nil
    }

    private func updateTriggerState(keyCode: UInt16, flags: NSEvent.ModifierFlags) {
      triggerState.update(
        keyCode: keyCode,
        familyIsActive: triggerFlagIsActive(in: flags),
        trigger: trigger
      )
    }

    private func triggerIsPressed(flags: NSEvent.ModifierFlags) -> Bool {
      if triggerState.isPressed(trigger) { return true }

      if triggerState.hasTrackedKey(inFamilyOf: trigger) { return false }

      if isPressed(trigger.keyCode) { return true }

      // The generic modifier flag cannot tell the left and right keys apart.
      // The physical key-state query above also covers a trigger that was held
      // before recording began, so a generic fallback is never appropriate.
      return false
    }

    private func triggerFlagIsActive(in flags: NSEvent.ModifierFlags) -> Bool {
      switch trigger {
      case .rightCommand, .leftCommand: flags.contains(.command)
      case .rightOption, .leftOption: flags.contains(.option)
      case .rightControl, .leftControl: flags.contains(.control)
      case .function: flags.contains(.function)
      }
    }

    private func auxiliaryModifiers(flags: NSEvent.ModifierFlags) -> Set<AuxiliaryModifier> {
      var modifiers: Set<AuxiliaryModifier> = []

      if trigger.correspondingModifier != .shift && flags.contains(.shift) {
        modifiers.insert(.shift)
      }
      if trigger.correspondingModifier != .control && flags.contains(.control) {
        modifiers.insert(.control)
      }
      if trigger.correspondingModifier != .option && flags.contains(.option) {
        modifiers.insert(.option)
      }
      if trigger.correspondingModifier != .command && flags.contains(.command) {
        modifiers.insert(.command)
      }

      return modifiers
    }

    private func isPressed(_ keyCode: UInt16) -> Bool {
      CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(keyCode))
    }

  }
}

private struct GeneralSettingsView: View {
  @ObservedObject private var model: DexApplicationModel
  @ObservedObject private var store: ShortcutStore
  @ObservedObject private var monitor: GlobalShortcutMonitor

  init(model: DexApplicationModel) {
    _model = ObservedObject(wrappedValue: model)
    _store = ObservedObject(wrappedValue: model.store)
    _monitor = ObservedObject(wrappedValue: model.monitor)
  }

  var body: some View {
    Form {
      Section("Keyboard") {
        Picker("Default trigger", selection: triggerBinding) {
          ForEach(TriggerKey.allCases) { trigger in
            Text(trigger.displayName).tag(trigger)
          }
        }

        LabeledContent("Global shortcuts") {
          HStack {
            Circle()
              .fill(monitor.status == .active ? Color.green : Color.orange)
              .frame(width: 8, height: 8)
            Text(monitor.status.label)
          }
        }

        if monitor.status != .active {
          HStack {
            Button("Request Access") { monitor.requestAccess() }
            Button("Open Privacy Settings") { monitor.openPrivacySettings() }
            Button("Try Again") { monitor.start() }
          }
          Text(
            "Dex needs Accessibility access to distinguish the physical modifier keys and consume matched shortcuts."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      }

      Section("Commands") {
        Picker("Default terminal", selection: $store.configuration.defaultTerminal) {
          ForEach(TerminalApplication.allCases) { terminal in
            Text(terminal.displayName).tag(terminal)
          }
        }
        Text("Used by every shortcut with Open in terminal enabled.")
          .font(.caption)
          .foregroundStyle(.secondary)
        if NSWorkspace.shared.urlForApplication(
          withBundleIdentifier: store.configuration.defaultTerminal.bundleIdentifier
        ) == nil {
          Text("\(store.configuration.defaultTerminal.displayName) is not installed. Install it or choose another terminal.")
            .font(.caption)
            .foregroundStyle(.red)
        }
      }

      Section("App") {
        Toggle("Launch Dex at login", isOn: launchAtLoginBinding)
        if let error = model.launchAtLoginError {
          Text(error)
            .font(.caption)
            .foregroundStyle(.red)
        }

        Toggle("Show Dex in the menu bar", isOn: menuBarItemBinding)
        Text(
          "When hidden, Dex and its shortcuts keep running. Reopen Dex from Applications or Spotlight to return to Settings."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Section("Deleted Shortcuts") {
        Toggle(
          "Keep deleted shortcuts for 30 days",
          isOn: archiveDeletedShortcutsBinding
        )
        Text(
          store.configuration.archivesDeletedShortcuts
            ? "Deleted shortcuts can be restored from Recently Deleted before they expire."
            : "Newly deleted shortcuts are removed immediately. Anything already in Recently Deleted remains available until it expires."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Section("Configuration") {
        LabeledContent("Configuration file") {
          Button("Open File") {
            openConfigurationFile()
          }
        }

        ConfigurationJSONEditor(store: store)

        Text(
          "This JSON contains your complete Dex setup. Copy it to move your shortcuts to another Mac; paths to apps and folders may need updating."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Section("Data") {
        LabeledContent("Logs") {
          Text(DexPaths.logFile.path)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
        }

        HStack {
          Button("Reveal Configuration File") {
            revealConfigurationFile()
          }
          Button("Open Dex Data Folder") {
            openDataFolder()
          }
        }

        Text(
          "Command actions execute with your user permissions, so review commands before saving them."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .padding()
  }

  private var triggerBinding: Binding<TriggerKey> {
    Binding(
      get: { store.configuration.trigger },
      set: { trigger in
        var configuration = store.configuration
        configuration.trigger = trigger
        configuration.normalizeBindings()
        store.configuration = configuration
      }
    )
  }

  private var launchAtLoginBinding: Binding<Bool> {
    Binding(
      get: { model.launchAtLoginEnabled },
      set: { model.setLaunchAtLogin($0) }
    )
  }

  private var menuBarItemBinding: Binding<Bool> {
    Binding(
      get: { model.isMenuBarItemVisible },
      set: { model.setMenuBarItemVisible($0) }
    )
  }

  private var archiveDeletedShortcutsBinding: Binding<Bool> {
    Binding(
      get: { store.configuration.archivesDeletedShortcuts },
      set: { store.configuration.archivesDeletedShortcuts = $0 }
    )
  }

  private func revealConfigurationFile() {
    guard store.saveCurrentConfiguration() else { return }
    NSWorkspace.shared.activateFileViewerSelecting([DexPaths.configurationFile])
  }

  private func openConfigurationFile() {
    guard store.saveCurrentConfiguration() else { return }
    NSWorkspace.shared.open(DexPaths.configurationFile)
  }

  private func openDataFolder() {
    try? FileManager.default.createDirectory(
      at: DexPaths.applicationSupportDirectory,
      withIntermediateDirectories: true
    )
    NSWorkspace.shared.activateFileViewerSelecting([DexPaths.applicationSupportDirectory])
  }
}

private struct ConfigurationJSONEditor: View {
  @ObservedObject var store: ShortcutStore
  @State private var json = ""
  @State private var loadedJSON = ""
  @State private var message: String?
  @State private var messageIsError = false
  @State private var editorHeight: CGFloat = 150
  @GestureState private var editorResizeOffset: CGFloat = 0

  private var hasUnsavedChanges: Bool {
    json != loadedJSON
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      TextEditor(text: $json)
        .font(.system(.caption, design: .monospaced))
        .scrollContentBackground(.hidden)
        .padding(5)
        .padding(.bottom, 10)
        .frame(height: max(150, editorHeight + editorResizeOffset))
        .background(Color(nsColor: .textBackgroundColor))
        .overlay {
          RoundedRectangle(cornerRadius: 6)
            .stroke(Color(nsColor: .separatorColor))
        }
        .overlay(alignment: .bottomTrailing) {
          Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.tertiary)
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
            .gesture(editorResizeGesture)
            .help("Drag to resize the JSON editor")
        }
        .accessibilityLabel("Dex configuration JSON")

      HStack {
        Button("Save Changes") {
          save()
        }
        .keyboardShortcut("s", modifiers: .command)
        .disabled(!hasUnsavedChanges)

        Button("Reload from Disk") {
          loadFromDisk()
        }

        Button("Copy JSON") {
          copyJSON()
        }

        Spacer()

        if hasUnsavedChanges {
          Text("Unsaved changes")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      if let message {
        Text(message)
          .font(.caption)
          .foregroundStyle(messageIsError ? Color.red : Color.secondary)
          .textSelection(.enabled)
      }
    }
    .onAppear {
      if json.isEmpty { loadFromStore() }
    }
    .onChange(of: store.configuration) { _, _ in
      if !hasUnsavedChanges { loadFromStore() }
    }
  }

  private var editorResizeGesture: some Gesture {
    DragGesture(minimumDistance: 1, coordinateSpace: .global)
      .updating($editorResizeOffset) { value, offset, transaction in
        transaction.animation = nil
        offset = value.translation.height
      }
      .onEnded { value in
        editorHeight = max(150, editorHeight + value.translation.height)
      }
  }

  private func loadFromStore() {
    do {
      let currentJSON = try store.configurationJSON()
      json = currentJSON
      loadedJSON = currentJSON
      message = nil
      messageIsError = false
    } catch {
      show(error: error)
    }
  }

  private func loadFromDisk() {
    do {
      let currentConfigurationJSON = try store.configurationJSON()
      let currentJSON: String
      if FileManager.default.fileExists(atPath: DexPaths.configurationFile.path) {
        currentJSON = try String(contentsOf: DexPaths.configurationFile, encoding: .utf8)
      } else {
        currentJSON = currentConfigurationJSON
      }
      json = currentJSON
      loadedJSON = currentConfigurationJSON
      message =
        currentJSON == currentConfigurationJSON
        ? "Configuration is up to date."
        : "Loaded changes from disk. Review them, then save to apply."
      messageIsError = false
    } catch {
      show(error: error)
    }
  }

  private func save() {
    do {
      try store.replaceConfiguration(withJSON: json)
      let savedJSON = try store.configurationJSON()
      json = savedJSON
      loadedJSON = savedJSON
      message = "Configuration saved and applied."
      messageIsError = false
    } catch {
      show(error: error)
    }
  }

  private func copyJSON() {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(json, forType: .string)
    message = "Configuration copied."
    messageIsError = false
  }

  private func show(error: Error) {
    message = "Could not use this configuration: \(error.localizedDescription)"
    messageIsError = true
  }
}
