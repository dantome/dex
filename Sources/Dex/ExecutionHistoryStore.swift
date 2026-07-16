import Combine
import DexCore
import Foundation

@MainActor
final class ExecutionHistoryStore: ObservableObject {
  @Published private(set) var entries: [ExecutionHistoryEntry] = []
  @Published private(set) var lastError: String?

  private let repository: ExecutionHistoryRepository

  init(repository: ExecutionHistoryRepository = ExecutionHistoryRepository()) {
    self.repository = repository
    reload()
  }

  func reload() {
    do {
      entries = Array(try repository.load().reversed())
      lastError = nil
    } catch {
      lastError = "Could not read shortcut history: \(error.localizedDescription)"
    }
  }

  func record(_ shortcut: DexShortcut) {
    let entry = ExecutionHistoryEntry(
      shortcutID: shortcut.id,
      shortcutName: displayName(for: shortcut),
      actionKind: shortcut.action.kind
    )
    do {
      try repository.append(entry)
      entries.insert(entry, at: 0)
      if entries.count > repository.maximumEntryCount {
        entries.removeLast(entries.count - repository.maximumEntryCount)
      }
      lastError = nil
    } catch {
      lastError = "Could not save shortcut history: \(error.localizedDescription)"
    }
  }

  func clear() {
    do {
      try repository.clear()
      entries = []
      lastError = nil
    } catch {
      lastError = "Could not clear shortcut history: \(error.localizedDescription)"
    }
  }

  private func displayName(for shortcut: DexShortcut) -> String {
    let name = shortcut.name.trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? shortcut.action.suggestedName : name
  }
}
