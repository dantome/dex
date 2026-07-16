import Combine
import DexCore
import Foundation
import SwiftUI

@MainActor
final class ShortcutStore: ObservableObject {
  @Published var configuration: DexConfiguration {
    didSet {
      guard !isApplyingExternalChange else { return }
      save()
      onConfigurationChanged?(configuration)
    }
  }
  @Published private(set) var lastError: String?

  var onConfigurationChanged: ((DexConfiguration) -> Void)?

  private let repository: ConfigurationRepository
  private var isApplyingExternalChange = false

  init(repository: ConfigurationRepository = ConfigurationRepository()) {
    self.repository = repository
    do {
      configuration = try repository.load()
    } catch {
      configuration = DexConfiguration()
      lastError = "Could not read shortcuts: \(error.localizedDescription)"
    }
  }

  func reload() {
    do {
      let loaded = try repository.load()
      guard loaded != configuration else { return }
      isApplyingExternalChange = true
      configuration = loaded
      isApplyingExternalChange = false
      lastError = nil
      onConfigurationChanged?(configuration)
    } catch {
      isApplyingExternalChange = false
      lastError = "Could not reload shortcuts: \(error.localizedDescription)"
    }
  }

  func configurationJSON() throws -> String {
    let data = try repository.encode(configuration)
    guard let json = String(data: data, encoding: .utf8) else {
      throw CocoaError(.fileReadInapplicableStringEncoding)
    }
    return json
  }

  func replaceConfiguration(withJSON json: String) throws {
    let configuration = try repository.decode(Data(json.utf8))
    try repository.save(configuration)

    isApplyingExternalChange = true
    self.configuration = configuration
    isApplyingExternalChange = false
    lastError = nil
    onConfigurationChanged?(configuration)
  }

  @discardableResult
  func saveCurrentConfiguration() -> Bool {
    do {
      try repository.save(configuration)
      lastError = nil
      return true
    } catch {
      lastError = "Could not save shortcuts: \(error.localizedDescription)"
      return false
    }
  }

  @discardableResult
  func addShortcut() -> UUID {
    let usedCodes = Set(configuration.shortcuts.filter(\.isEnabled).map(\.binding.keyCode))
    let key = KeyCatalog.all.first { !usedCodes.contains($0.keyCode) } ?? KeyCatalog.all[0]
    let action = ShortcutAction.launchApplication(target: "")
    let shortcut = DexShortcut(
      name: action.suggestedName,
      binding: KeyBinding(keyCode: key.keyCode, keyLabel: key.label),
      action: action
    )
    configuration.shortcuts.append(shortcut)
    return shortcut.id
  }

  func update(_ shortcut: DexShortcut) {
    guard let index = configuration.shortcuts.firstIndex(where: { $0.id == shortcut.id }) else {
      return
    }
    configuration.shortcuts[index] = shortcut
  }

  func remove(id: UUID) {
    configuration.removeShortcut(id: id)
  }

  @discardableResult
  func restoreDeletedShortcut(id: UUID) -> DexShortcut? {
    configuration.restoreDeletedShortcut(id: id)
  }

  func permanentlyDeleteShortcut(id: UUID) {
    configuration.permanentlyDeleteShortcut(id: id)
  }

  func deleteAllRecentlyDeletedShortcuts() {
    configuration.recentlyDeletedShortcuts.removeAll()
  }

  func purgeExpiredDeletedShortcuts() {
    var updatedConfiguration = configuration
    updatedConfiguration.purgeExpiredDeletedShortcuts()
    guard updatedConfiguration != configuration else { return }
    configuration = updatedConfiguration
  }

  func moveShortcuts(fromOffsets source: IndexSet, toOffset destination: Int) {
    configuration.shortcuts.move(fromOffsets: source, toOffset: destination)
  }

  func shortcut(id: UUID) -> DexShortcut? {
    configuration.shortcuts.first { $0.id == id }
  }

  func conflictingShortcut(for shortcut: DexShortcut) -> DexShortcut? {
    guard shortcut.isEnabled else { return nil }
    let trigger = configuration.trigger
    return configuration.shortcuts.first {
      $0.id != shortcut.id
        && $0.isEnabled
        && $0.binding.keyCode == shortcut.binding.keyCode
        && $0.binding.effectiveModifiers(using: trigger)
          == shortcut.binding.effectiveModifiers(using: trigger)
    }
  }

  private func save() {
    do {
      try repository.save(configuration)
      lastError = nil
    } catch {
      lastError = "Could not save shortcuts: \(error.localizedDescription)"
    }
  }
}
