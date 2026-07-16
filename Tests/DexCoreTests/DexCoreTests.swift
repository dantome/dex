import XCTest

@testable import DexCore

final class DexCoreTests: XCTestCase {
  func testConfigurationRoundTripsEveryActionType() throws {
    let shortcuts = [
      DexShortcut(
        name: "Calendar",
        binding: KeyBinding(keyCode: 8, keyLabel: "C"),
        action: .launchApplication(target: "/Applications/Calendar.app")
      ),
      DexShortcut(
        name: "Dev server",
        binding: KeyBinding(keyCode: 2, keyLabel: "D", modifiers: [.shift]),
        action: .runCommand(
          command: "npm run dev",
          workingDirectory: "/tmp/project",
          inTerminal: true,
          closeTerminalOnCompletion: true
        )
      ),
      DexShortcut(
        name: "Downloads",
        binding: KeyBinding(keyCode: 3, keyLabel: "F"),
        action: .openFinder(directory: "~/Downloads")
      ),
      DexShortcut(
        name: "GitHub",
        binding: KeyBinding(keyCode: 5, keyLabel: "G"),
        action: .openURL(url: "https://github.com")
      ),
      DexShortcut(
        name: "Focus",
        binding: KeyBinding(keyCode: 3, keyLabel: "F"),
        action: .runAppleShortcut(name: "Start Focus")
      ),
    ]
    let original = DexConfiguration(trigger: .rightOption, shortcuts: shortcuts)

    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(DexConfiguration.self, from: data)

    XCTAssertEqual(decoded, original)
  }

  func testOlderConfigurationDefaultsToShowingMenuBarItem() throws {
    let data = Data(
      #"{"version":1,"trigger":"rightCommand","launchAtLogin":false,"shortcuts":[]}"#.utf8
    )

    let configuration = try JSONDecoder().decode(DexConfiguration.self, from: data)

    XCTAssertTrue(configuration.showsMenuBarItem)
  }

  func testMenuBarVisibilityRoundTrips() throws {
    let original = DexConfiguration(showsMenuBarItem: false)

    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(DexConfiguration.self, from: data)

    XCTAssertFalse(decoded.showsMenuBarItem)
    XCTAssertEqual(decoded, original)
  }

  func testOlderConfigurationDefaultsToArchivingDeletedShortcuts() throws {
    let data = Data(
      #"{"version":1,"trigger":"rightCommand","launchAtLogin":false,"shortcuts":[]}"#.utf8
    )

    let configuration = try JSONDecoder().decode(DexConfiguration.self, from: data)

    XCTAssertTrue(configuration.archivesDeletedShortcuts)
    XCTAssertTrue(configuration.recentlyDeletedShortcuts.isEmpty)
    XCTAssertEqual(configuration.version, DexConfiguration.currentVersion)
  }

  func testRemovingAndRestoringShortcutUsesRecentlyDeletedArchive() {
    let shortcut = DexShortcut(
      name: "Calendar",
      binding: KeyBinding(keyCode: 8, keyLabel: "C"),
      action: .launchApplication(target: "/Applications/Calendar.app")
    )
    let deletionDate = Date(timeIntervalSince1970: 1_000)
    var configuration = DexConfiguration(shortcuts: [shortcut])

    configuration.removeShortcut(id: shortcut.id, deletedAt: deletionDate)

    XCTAssertTrue(configuration.shortcuts.isEmpty)
    XCTAssertEqual(
      configuration.recentlyDeletedShortcuts,
      [DeletedShortcut(shortcut: shortcut, deletedAt: deletionDate)]
    )

    let restored = configuration.restoreDeletedShortcut(id: shortcut.id)

    XCTAssertEqual(restored, shortcut)
    XCTAssertEqual(configuration.shortcuts, [shortcut])
    XCTAssertTrue(configuration.recentlyDeletedShortcuts.isEmpty)
  }

  func testImmediateDeletionDoesNotArchiveShortcut() {
    let shortcut = DexShortcut(
      name: "Calendar",
      binding: KeyBinding(keyCode: 8, keyLabel: "C"),
      action: .launchApplication(target: "/Applications/Calendar.app")
    )
    var configuration = DexConfiguration(
      archivesDeletedShortcuts: false,
      shortcuts: [shortcut]
    )

    configuration.removeShortcut(id: shortcut.id)

    XCTAssertTrue(configuration.shortcuts.isEmpty)
    XCTAssertTrue(configuration.recentlyDeletedShortcuts.isEmpty)
  }

  func testExpiredDeletedShortcutsArePurged() {
    let now = Date(timeIntervalSince1970: 5_000_000)
    let expired = DeletedShortcut(
      shortcut: DexShortcut(
        name: "Old",
        binding: KeyBinding(keyCode: 31, keyLabel: "O"),
        action: .openURL(url: "https://example.com")
      ),
      deletedAt: now.addingTimeInterval(-DexConfiguration.deletedShortcutRetentionInterval - 1)
    )
    let retained = DeletedShortcut(
      shortcut: DexShortcut(
        name: "Recent",
        binding: KeyBinding(keyCode: 15, keyLabel: "R"),
        action: .openURL(url: "https://example.com")
      ),
      deletedAt: now.addingTimeInterval(-DexConfiguration.deletedShortcutRetentionInterval + 1)
    )
    var configuration = DexConfiguration(recentlyDeletedShortcuts: [expired, retained])

    configuration.purgeExpiredDeletedShortcuts(now: now)

    XCTAssertEqual(configuration.recentlyDeletedShortcuts, [retained])
  }

  func testRestoredShortcutIsDisabledWhenBindingIsAlreadyInUse() {
    let active = DexShortcut(
      name: "Active",
      binding: KeyBinding(keyCode: 8, keyLabel: "C"),
      action: .openURL(url: "https://example.com")
    )
    let deleted = DexShortcut(
      name: "Deleted",
      binding: active.binding,
      action: .launchApplication(target: "/Applications/Calendar.app")
    )
    var configuration = DexConfiguration(
      shortcuts: [active],
      recentlyDeletedShortcuts: [DeletedShortcut(shortcut: deleted)]
    )

    let restored = configuration.restoreDeletedShortcut(id: deleted.id)

    XCTAssertEqual(restored?.isEnabled, false)
    XCTAssertEqual(configuration.shortcuts.last?.id, deleted.id)
  }

  func testFinderActionWithoutDirectoryRoundTrips() throws {
    let action = ShortcutAction.openFinder(directory: nil)

    let data = try JSONEncoder().encode(action)
    let decoded = try JSONDecoder().decode(ShortcutAction.self, from: data)

    XCTAssertEqual(decoded, action)
  }

  func testNewRunCommandDefaultsToHomeDirectory() {
    XCTAssertEqual(
      ShortcutAction.empty(for: .runCommand),
      .runCommand(
        command: "",
        workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path,
        inTerminal: true,
        closeTerminalOnCompletion: false
      )
    )
  }

  func testOlderRunCommandDefaultsToKeepingTerminalOpen() throws {
    let data = Data(
      #"{"kind":"runCommand","command":"echo hello","inTerminal":true}"#.utf8
    )

    let action = try JSONDecoder().decode(ShortcutAction.self, from: data)

    XCTAssertEqual(
      action,
      .runCommand(
        command: "echo hello",
        workingDirectory: nil,
        inTerminal: true,
        closeTerminalOnCompletion: false
      )
    )
  }

  func testActionsSuggestUsefulNames() {
    XCTAssertEqual(
      ShortcutAction.launchApplication(target: "/Applications/Spotify.app").suggestedName,
      "Open Spotify"
    )
    XCTAssertEqual(
      ShortcutAction.openFinder(directory: "~/Downloads").suggestedName,
      "Open Downloads"
    )
    XCTAssertEqual(
      ShortcutAction.openFinder(directory: nil).suggestedName,
      "Open Finder"
    )
    XCTAssertEqual(
      ShortcutAction.openURL(url: "https://www.github.com/openai").suggestedName,
      "Open github.com"
    )
    XCTAssertEqual(
      ShortcutAction.runAppleShortcut(name: "Start Focus").suggestedName,
      "Run Start Focus"
    )
    XCTAssertEqual(
      ShortcutAction.runCommand(
        command: "npm run dev",
        workingDirectory: nil,
        inTerminal: true,
        closeTerminalOnCompletion: false
      )
      .suggestedName,
      "Run Command"
    )
  }

  func testDirectoryPathValidationDistinguishesCommonStates() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let file = root.appendingPathComponent("file.txt")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data().write(to: file)

    let empty = DirectoryPathValidation("  ")
    let valid = DirectoryPathValidation("  \(root.path)  ")
    let filePath = DirectoryPathValidation(file.path)
    let missingPath = root.appendingPathComponent("missing").path
    let missing = DirectoryPathValidation(missingPath)

    XCTAssertEqual(empty, .empty)
    XCTAssertEqual(valid, .valid(expandedPath: root.path))
    XCTAssertEqual(filePath, .notDirectory(expandedPath: file.path))
    XCTAssertEqual(missing, .missing(expandedPath: missingPath))
    XCTAssertTrue(empty.canOpenInFinder)
    XCTAssertTrue(valid.canOpenInFinder)
    XCTAssertFalse(filePath.canOpenInFinder)
    XCTAssertFalse(missing.canOpenInFinder)
  }

  func testDirectoryPathValidationExpandsHomeDirectory() {
    XCTAssertEqual(
      DirectoryPathValidation("~"),
      .valid(expandedPath: FileManager.default.homeDirectoryForCurrentUser.path)
    )
  }

  func testFinderDirectoryLocationRecognizesFinderSidebarDirectories() {
    let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
    let locations: [(String, FinderDirectoryLocation)] = [
      ("~", .home),
      ("~/Applications", .applications),
      ("~/Desktop", .desktop),
      ("~/Documents", .documents),
      ("~/Downloads", .downloads),
      ("~/Library/Mobile Documents/com~apple~CloudDocs", .iCloudDrive),
      ("~/Movies", .movies),
      ("~/Music", .music),
      ("~/Pictures", .pictures),
      ("~/Public", .publicFolder),
      ("~/.Trash", .trash),
      ("/Applications", .applications),
      ("/Users/Shared", .shared),
      ("/", .startupDisk),
      ("/Volumes/Backup", .mountedVolume),
      ("~/Projects", .other),
      ("~/Downloads/Archive", .other),
    ]

    for (directory, expectedLocation) in locations {
      XCTAssertEqual(
        FinderDirectoryLocation(directory: directory, homeDirectory: home),
        expectedLocation,
        directory
      )
    }
  }

  func testRepositoryCreatesAndLoadsPrivateConfigurationFile() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("nested/shortcuts.json")
    let repository = ConfigurationRepository(fileURL: url)
    let configuration = DexConfiguration(trigger: .function)

    try repository.save(configuration)

    XCTAssertEqual(try repository.load(), configuration)
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
  }

  func testShortcutDisplayUsesReadableTriggerAndSeparators() {
    XCTAssertEqual(
      KeyBinding(keyCode: 8, keyLabel: "C").display(using: .rightCommand),
      "Right ⌘ + C"
    )
    XCTAssertEqual(
      KeyBinding(keyCode: 8, keyLabel: "C", modifiers: [.shift, .option])
        .display(using: .leftControl),
      "Left ⌃ + ⇧ + ⌥ + C"
    )
  }

  func testTriggerModifierIsImplicitAndRemovedDuringNormalization() {
    let contaminated = KeyBinding(
      keyCode: 2,
      keyLabel: "D",
      modifiers: [.command, .shift]
    )

    XCTAssertEqual(contaminated.display(using: .rightCommand), "Right ⌘ + ⇧ + D")
    XCTAssertEqual(contaminated.effectiveModifiers(using: .rightCommand), [.shift])
    XCTAssertEqual(
      contaminated.normalized(using: .rightCommand).modifiers,
      [.shift]
    )
    XCTAssertEqual(
      contaminated.effectiveModifiers(using: .function),
      [.command, .shift]
    )
  }

  func testRepositoryRepairsRedundantTriggerModifiers() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let repository = ConfigurationRepository(fileURL: root.appendingPathComponent("shortcuts.json"))
    let shortcut = DexShortcut(
      name: "Dictionary",
      binding: KeyBinding(keyCode: 2, keyLabel: "D", modifiers: [.command]),
      action: .launchApplication(target: "/System/Applications/Dictionary.app")
    )

    try repository.save(DexConfiguration(trigger: .rightCommand, shortcuts: [shortcut]))
    let repaired = try repository.load()

    XCTAssertEqual(repaired.shortcuts.first?.binding.modifiers, [])
  }

  func testPhysicalRightCommandStateTracksPressAndRelease() {
    var state = PhysicalTriggerState()

    state.update(keyCode: 54, familyIsActive: true, trigger: .rightCommand)
    XCTAssertTrue(state.isPressed(.rightCommand))
    XCTAssertFalse(state.isPressed(.leftCommand))

    state.update(keyCode: 54, familyIsActive: false, trigger: .rightCommand)
    XCTAssertFalse(state.hasTrackedKey(inFamilyOf: .rightCommand))
  }

  func testPhysicalTriggerStateHandlesReleaseAfterMonitorRestart() {
    var state = PhysicalTriggerState()

    // Recording stops and the global monitor starts while Right Command is
    // still held, so the first event the new monitor sees is its release.
    state.update(keyCode: 54, familyIsActive: false, trigger: .rightCommand)

    XCTAssertFalse(state.isPressed(.rightCommand))
    XCTAssertFalse(state.hasTrackedKey(inFamilyOf: .rightCommand))
  }

  func testPhysicalTriggerStateDistinguishesCommandSides() {
    var state = PhysicalTriggerState()

    state.update(keyCode: 55, familyIsActive: true, trigger: .rightCommand)

    XCTAssertFalse(state.isPressed(.rightCommand))
    XCTAssertTrue(state.hasTrackedKey(inFamilyOf: .rightCommand))
  }

  func testShellSingleQuoteEscaping() {
    XCTAssertEqual(ShellEscaping.singleQuoted("it's ready"), "'it'\"'\"'s ready'")
  }

  func testTerminalCommandWithoutCloseScriptKeepsTerminalOpen() {
    let script = TerminalCommandScripts.command(
      "echo hello",
      workingDirectory: URL(fileURLWithPath: "/tmp/project"),
      closeScriptURL: nil
    )

    XCTAssertTrue(script.contains("cd -- '/tmp/project'"))
    XCTAssertTrue(script.contains("/bin/zsh -lc 'echo hello'"))
    XCTAssertFalse(script.contains("osascript"))
  }

  func testTerminalCommandWithCloseScriptPreservesExitStatusAndRequestsClose() {
    let script = TerminalCommandScripts.command(
      "exit 7",
      workingDirectory: URL(fileURLWithPath: "/tmp/project"),
      closeScriptURL: URL(fileURLWithPath: "/tmp/close terminal.applescript")
    )

    XCTAssertTrue(script.contains("exit_status=$?"))
    XCTAssertTrue(script.contains("terminal_tty=$(/usr/bin/tty)"))
    XCTAssertTrue(script.contains("/usr/bin/osascript '/tmp/close terminal.applescript'"))
    XCTAssertTrue(script.contains("exit \"$exit_status\""))
  }

  func testTerminalCloseScriptClosesSingleTabWindowAndPollsUntilIdle() {
    let script = TerminalCommandScripts.closeTerminal

    XCTAssertTrue(script.contains("if busy of terminalTab then return false"))
    XCTAssertTrue(script.contains("if (count tabs of terminalWindow) is 1 then"))
    XCTAssertTrue(script.contains("close terminalWindow"))
    XCTAssertTrue(script.contains("close terminalTab"))
    XCTAssertTrue(script.contains("repeat 50 times"))
  }

  func testTerminalCloseScriptCompilesAsAppleScript() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let sourceURL = root.appendingPathComponent("close-terminal.applescript")
    let compiledURL = root.appendingPathComponent("close-terminal.scpt")
    try TerminalCommandScripts.closeTerminal.write(
      to: sourceURL,
      atomically: true,
      encoding: .utf8
    )

    let compiler = Process()
    compiler.executableURL = URL(fileURLWithPath: "/usr/bin/osacompile")
    compiler.arguments = ["-o", compiledURL.path, sourceURL.path]
    let errors = Pipe()
    compiler.standardError = errors
    try compiler.run()
    compiler.waitUntilExit()

    let errorOutput =
      String(
        data: errors.fileHandleForReading.readDataToEndOfFile(),
        encoding: .utf8
      ) ?? ""
    XCTAssertEqual(compiler.terminationStatus, 0, errorOutput)
  }
}
