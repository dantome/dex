import Foundation

public enum TriggerKey: String, Codable, CaseIterable, Identifiable, Sendable {
  case rightCommand
  case rightOption
  case function
  case leftCommand
  case leftOption
  case rightControl
  case leftControl

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .rightCommand: "Right Command"
    case .rightOption: "Right Option"
    case .function: "Fn / Globe"
    case .leftCommand: "Left Command"
    case .leftOption: "Left Option"
    case .rightControl: "Right Control"
    case .leftControl: "Left Control"
    }
  }

  public var symbol: String {
    switch self {
    case .rightCommand, .leftCommand: "⌘"
    case .rightOption, .leftOption: "⌥"
    case .function: "fn"
    case .rightControl, .leftControl: "⌃"
    }
  }

  public var shortcutDisplayName: String {
    switch self {
    case .rightCommand, .rightOption, .rightControl: "Right \(symbol)"
    case .function: "Fn / Globe"
    case .leftCommand, .leftOption, .leftControl: "Left \(symbol)"
    }
  }

  public var keyCode: UInt16 {
    switch self {
    case .rightCommand: 54
    case .rightOption: 61
    case .function: 63
    case .leftCommand: 55
    case .leftOption: 58
    case .rightControl: 62
    case .leftControl: 59
    }
  }

  /// The generic modifier represented by this physical trigger.
  ///
  /// Dex treats this modifier as implicit in every binding. For example, a
  /// Right Command trigger plus D is stored as just D, not Command + D.
  public var correspondingModifier: AuxiliaryModifier? {
    switch self {
    case .rightCommand, .leftCommand: .command
    case .rightOption, .leftOption: .option
    case .rightControl, .leftControl: .control
    case .function: nil
    }
  }

  public var familyKeyCodes: Set<UInt16> {
    switch self {
    case .rightCommand, .leftCommand: [54, 55]
    case .rightOption, .leftOption: [58, 61]
    case .rightControl, .leftControl: [59, 62]
    case .function: [63]
    }
  }

}

public enum AuxiliaryModifier: String, Codable, CaseIterable, Hashable, Sendable {
  case shift
  case control
  case option
  case command

  public var displayName: String { rawValue.capitalized }

  public var symbol: String {
    switch self {
    case .shift: "⇧"
    case .control: "⌃"
    case .option: "⌥"
    case .command: "⌘"
    }
  }
}

public struct KeyBinding: Codable, Equatable, Hashable, Sendable {
  public var keyCode: UInt16
  public var keyLabel: String
  public var modifiers: Set<AuxiliaryModifier>

  public init(
    keyCode: UInt16,
    keyLabel: String,
    modifiers: Set<AuxiliaryModifier> = []
  ) {
    self.keyCode = keyCode
    self.keyLabel = keyLabel
    self.modifiers = modifiers
  }

  public func display(using trigger: TriggerKey) -> String {
    let modifierSymbols = AuxiliaryModifier.allCases
      .filter(effectiveModifiers(using: trigger).contains)
      .map(\.symbol)
    return ([trigger.shortcutDisplayName] + modifierSymbols + [keyLabel]).joined(separator: " + ")
  }

  public func effectiveModifiers(using trigger: TriggerKey) -> Set<AuxiliaryModifier> {
    guard let triggerModifier = trigger.correspondingModifier else { return modifiers }
    return modifiers.subtracting([triggerModifier])
  }

  public func normalized(using trigger: TriggerKey) -> KeyBinding {
    var binding = self
    binding.removeRedundantTriggerModifier(using: trigger)
    return binding
  }

  public mutating func removeRedundantTriggerModifier(using trigger: TriggerKey) {
    modifiers = effectiveModifiers(using: trigger)
  }
}

public enum ShortcutActionKind: String, Codable, CaseIterable, Identifiable, Sendable {
  case launchApplication
  case openFinder
  case runCommand
  case openURL
  case runAppleShortcut

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .launchApplication: "Open Application"
    case .openFinder: "Open Finder"
    case .runCommand: "Run Command"
    case .openURL: "Open URL"
    case .runAppleShortcut: "Run Apple Shortcut"
    }
  }
}

public enum ShortcutAction: Equatable, Sendable {
  case launchApplication(target: String)
  case openFinder(directory: String?)
  case runCommand(
    command: String,
    workingDirectory: String?,
    inTerminal: Bool,
    closeTerminalOnCompletion: Bool
  )
  case openURL(url: String)
  case runAppleShortcut(name: String)

  public var kind: ShortcutActionKind {
    switch self {
    case .launchApplication: .launchApplication
    case .openFinder: .openFinder
    case .runCommand: .runCommand
    case .openURL: .openURL
    case .runAppleShortcut: .runAppleShortcut
    }
  }

  public static func empty(for kind: ShortcutActionKind) -> ShortcutAction {
    switch kind {
    case .launchApplication: .launchApplication(target: "")
    case .openFinder: .openFinder(directory: nil)
    case .runCommand:
      .runCommand(
        command: "",
        workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path,
        inTerminal: true,
        closeTerminalOnCompletion: false
      )
    case .openURL: .openURL(url: "https://")
    case .runAppleShortcut: .runAppleShortcut(name: "")
    }
  }

  public var suggestedName: String {
    switch self {
    case .launchApplication(let target):
      let trimmedTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmedTarget.isEmpty else { return "Open Application" }

      let applicationName = URL(fileURLWithPath: (trimmedTarget as NSString).expandingTildeInPath)
        .deletingPathExtension()
        .lastPathComponent
      return applicationName.isEmpty ? "Open Application" : "Open \(applicationName)"

    case .openFinder(let directory):
      guard let directory else { return "Open Finder" }
      let trimmedDirectory = directory.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmedDirectory.isEmpty else { return "Open Finder" }

      let directoryName = URL(fileURLWithPath: (trimmedDirectory as NSString).expandingTildeInPath)
        .lastPathComponent
      return directoryName.isEmpty ? "Open Finder" : "Open \(directoryName)"

    case .runCommand:
      return "Run Command"

    case .openURL(let value):
      let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
      guard
        let host = URL(string: trimmedValue)?.host(percentEncoded: false),
        !host.isEmpty
      else {
        return "Open URL"
      }
      let displayHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
      return "Open \(displayHost)"

    case .runAppleShortcut(let name):
      let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmedName.isEmpty ? "Run Apple Shortcut" : "Run \(trimmedName)"
    }
  }
}

extension ShortcutAction: Codable {
  private enum CodingKeys: String, CodingKey {
    case kind
    case target
    case command
    case workingDirectory
    case inTerminal
    case closeTerminalOnCompletion
    case url
    case name
    case directory
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try values.decode(ShortcutActionKind.self, forKey: .kind)
    switch kind {
    case .launchApplication:
      self = .launchApplication(target: try values.decode(String.self, forKey: .target))
    case .openFinder:
      self = .openFinder(directory: try values.decodeIfPresent(String.self, forKey: .directory))
    case .runCommand:
      self = .runCommand(
        command: try values.decode(String.self, forKey: .command),
        workingDirectory: try values.decodeIfPresent(String.self, forKey: .workingDirectory),
        inTerminal: try values.decodeIfPresent(Bool.self, forKey: .inTerminal) ?? true,
        closeTerminalOnCompletion:
          try values.decodeIfPresent(Bool.self, forKey: .closeTerminalOnCompletion) ?? false
      )
    case .openURL:
      self = .openURL(url: try values.decode(String.self, forKey: .url))
    case .runAppleShortcut:
      self = .runAppleShortcut(name: try values.decode(String.self, forKey: .name))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(kind, forKey: .kind)
    switch self {
    case .launchApplication(let target):
      try values.encode(target, forKey: .target)
    case .openFinder(let directory):
      try values.encodeIfPresent(directory, forKey: .directory)
    case .runCommand(
      let command,
      let workingDirectory,
      let inTerminal,
      let closeTerminalOnCompletion
    ):
      try values.encode(command, forKey: .command)
      try values.encodeIfPresent(workingDirectory, forKey: .workingDirectory)
      try values.encode(inTerminal, forKey: .inTerminal)
      try values.encode(closeTerminalOnCompletion, forKey: .closeTerminalOnCompletion)
    case .openURL(let url):
      try values.encode(url, forKey: .url)
    case .runAppleShortcut(let name):
      try values.encode(name, forKey: .name)
    }
  }
}

public struct DexShortcut: Codable, Identifiable, Equatable, Sendable {
  public var id: UUID
  public var name: String
  public var binding: KeyBinding
  public var action: ShortcutAction
  public var isEnabled: Bool

  public init(
    id: UUID = UUID(),
    name: String,
    binding: KeyBinding,
    action: ShortcutAction,
    isEnabled: Bool = true
  ) {
    self.id = id
    self.name = name
    self.binding = binding
    self.action = action
    self.isEnabled = isEnabled
  }
}

public struct DeletedShortcut: Codable, Identifiable, Equatable, Sendable {
  public var shortcut: DexShortcut
  public var deletedAt: Date

  public var id: UUID { shortcut.id }

  public init(shortcut: DexShortcut, deletedAt: Date = Date()) {
    self.shortcut = shortcut
    self.deletedAt = deletedAt
  }

  public func expiresAt(
    retentionInterval: TimeInterval = DexConfiguration.deletedShortcutRetentionInterval
  ) -> Date {
    deletedAt.addingTimeInterval(retentionInterval)
  }
}

public struct DexConfiguration: Codable, Equatable, Sendable {
  public static let currentVersion = 2
  public static let deletedShortcutRetentionInterval: TimeInterval = 30 * 24 * 60 * 60

  public var version: Int
  public var trigger: TriggerKey
  public var launchAtLogin: Bool
  public var defaultTerminal: TerminalApplication
  public var showsMenuBarItem: Bool
  public var archivesDeletedShortcuts: Bool
  public var shortcuts: [DexShortcut]
  public var recentlyDeletedShortcuts: [DeletedShortcut]

  public init(
    version: Int = currentVersion,
    trigger: TriggerKey = .rightCommand,
    launchAtLogin: Bool = false,
    defaultTerminal: TerminalApplication = .terminal,
    showsMenuBarItem: Bool = true,
    archivesDeletedShortcuts: Bool = true,
    shortcuts: [DexShortcut] = [],
    recentlyDeletedShortcuts: [DeletedShortcut] = []
  ) {
    self.version = version
    self.trigger = trigger
    self.launchAtLogin = launchAtLogin
    self.defaultTerminal = defaultTerminal
    self.showsMenuBarItem = showsMenuBarItem
    self.archivesDeletedShortcuts = archivesDeletedShortcuts
    self.shortcuts = shortcuts
    self.recentlyDeletedShortcuts = recentlyDeletedShortcuts
  }

  public mutating func normalizeBindings() {
    for index in shortcuts.indices {
      shortcuts[index].binding.removeRedundantTriggerModifier(using: trigger)
    }
    for index in recentlyDeletedShortcuts.indices {
      recentlyDeletedShortcuts[index].shortcut.binding.removeRedundantTriggerModifier(
        using: trigger
      )
    }
  }

  @discardableResult
  public mutating func removeShortcut(id: UUID, deletedAt: Date = Date()) -> DexShortcut? {
    guard let index = shortcuts.firstIndex(where: { $0.id == id }) else { return nil }
    let shortcut = shortcuts.remove(at: index)
    if archivesDeletedShortcuts {
      recentlyDeletedShortcuts.removeAll { $0.id == id }
      recentlyDeletedShortcuts.insert(
        DeletedShortcut(shortcut: shortcut, deletedAt: deletedAt),
        at: 0
      )
    }
    return shortcut
  }

  @discardableResult
  public mutating func restoreDeletedShortcut(id: UUID) -> DexShortcut? {
    guard let index = recentlyDeletedShortcuts.firstIndex(where: { $0.id == id }) else {
      return nil
    }
    var shortcut = recentlyDeletedShortcuts.remove(at: index).shortcut
    shortcut.binding.removeRedundantTriggerModifier(using: trigger)
    let hasConflict =
      shortcut.isEnabled
      && shortcuts.contains {
        $0.isEnabled
          && $0.binding.keyCode == shortcut.binding.keyCode
          && $0.binding.effectiveModifiers(using: trigger)
            == shortcut.binding.effectiveModifiers(using: trigger)
      }
    if hasConflict {
      shortcut.isEnabled = false
    }
    shortcuts.append(shortcut)
    return shortcut
  }

  public mutating func permanentlyDeleteShortcut(id: UUID) {
    recentlyDeletedShortcuts.removeAll { $0.id == id }
  }

  public mutating func purgeExpiredDeletedShortcuts(now: Date = Date()) {
    recentlyDeletedShortcuts.removeAll {
      $0.expiresAt() <= now
    }
  }

  private enum CodingKeys: String, CodingKey {
    case version
    case trigger
    case launchAtLogin
    case defaultTerminal
    case showsMenuBarItem
    case archivesDeletedShortcuts
    case shortcuts
    case recentlyDeletedShortcuts
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    version = max(
      try values.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion,
      Self.currentVersion
    )
    trigger = try values.decodeIfPresent(TriggerKey.self, forKey: .trigger) ?? .rightCommand
    launchAtLogin = try values.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
    defaultTerminal =
      try values.decodeIfPresent(TerminalApplication.self, forKey: .defaultTerminal) ?? .terminal
    showsMenuBarItem = try values.decodeIfPresent(Bool.self, forKey: .showsMenuBarItem) ?? true
    archivesDeletedShortcuts =
      try values.decodeIfPresent(Bool.self, forKey: .archivesDeletedShortcuts) ?? true
    shortcuts = try values.decodeIfPresent([DexShortcut].self, forKey: .shortcuts) ?? []
    recentlyDeletedShortcuts =
      try values.decodeIfPresent([DeletedShortcut].self, forKey: .recentlyDeletedShortcuts) ?? []
    purgeExpiredDeletedShortcuts()
  }
}
