import AppKit
import XCTest
import DexCore

@testable import Dex

@MainActor
final class GhosttyExecutionTests: XCTestCase {
  func testGhosttyExecutesCommandsAndHonorsCompletionPreference() async throws {
    guard ProcessInfo.processInfo.environment["DEX_TEST_GHOSTTY"] == "1" else {
      throw XCTSkip("Set DEX_TEST_GHOSTTY=1 to run the installed Ghostty integration test.")
    }
    XCTAssertNotNil(NSWorkspace.shared.urlForApplication(
      withBundleIdentifier: TerminalApplication.ghostty.bundleIdentifier
    ))
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("DEX's Ghostty test \(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ShortcutStore(repository: ConfigurationRepository(
      fileURL: root.appendingPathComponent("shortcuts.json")
    ))
    let history = ExecutionHistoryStore(repository: ExecutionHistoryRepository(
      fileURL: root.appendingPathComponent("history.jsonl")
    ))
    let executor = ActionExecutor(history: history, store: store)
    // Updating the setting after executor creation must affect the next run.
    store.configuration.defaultTerminal = .ghostty
    let originalPIDs = Set(ghosttyApplications.map(\.processIdentifier))
    defer {
      for app in ghosttyApplications where !originalPIDs.contains(app.processIdentifier) {
        app.forceTerminate()
      }
    }

    for closeOnCompletion in [false, true] {
      let output = root.appendingPathComponent("output-\(closeOnCompletion).txt")
      let literal = "quotes '\" and $HOME; $(echo untouched)"
      let command = """
        { printf '%s\\n' "$TERM_PROGRAM" "$PWD" \(ShellEscaping.singleQuoted(literal)); } > \(ShellEscaping.singleQuoted(output.path))
        sleep 1
        exit 17
        """
      let beforePIDs = Set(ghosttyApplications.map(\.processIdentifier))
      let shortcut = DexShortcut(
        name: "DEX Ghostty integration test",
        binding: KeyBinding(keyCode: 0, keyLabel: "A"),
        action: .runCommand(
          command: command,
          workingDirectory: root.path,
          inTerminal: true,
          closeTerminalOnCompletion: closeOnCompletion
        )
      )
      executor.execute(shortcut)
      for _ in 0..<100 {
        if FileManager.default.fileExists(atPath: output.path) { break }
        try await Task.sleep(for: .milliseconds(100))
      }
      XCTAssertEqual(executor.lastResult, "Started \(shortcut.name) in Ghostty.")
      let contents = try String(contentsOf: output, encoding: .utf8)
      XCTAssertEqual(contents, "ghostty\n\(root.resolvingSymlinksInPath().path)\n\(literal)\n")
      let launched = try XCTUnwrap(ghosttyApplications.first {
        !beforePIDs.contains($0.processIdentifier)
      })
      XCTAssertGreaterThan(windowCount(for: launched), 0, "The command should open a visible window.")
      try await Task.sleep(for: .seconds(2))
      if closeOnCompletion {
        for _ in 0..<50 {
          if windowCount(for: launched) == 0 { break }
          try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(windowCount(for: launched), 0, "Ghostty should close even after a nonzero exit.")
      } else {
        XCTAssertGreaterThan(windowCount(for: launched), 0, "Ghostty should keep command output visible.")
      }
    }
  }

  private var ghosttyApplications: [NSRunningApplication] {
    NSRunningApplication.runningApplications(
      withBundleIdentifier: TerminalApplication.ghostty.bundleIdentifier
    )
  }

  private func windowCount(for app: NSRunningApplication) -> Int {
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], 0)
      as? [[String: Any]] ?? []
    return windows.filter {
      ($0[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier
        && ($0[kCGWindowLayer as String] as? Int) == 0
    }.count
  }
}
