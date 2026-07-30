import AppKit
import Combine
import DexCore
import Foundation

enum ActionExecutionError: LocalizedError {
  case invalidApplication(String)
  case invalidURL(String)
  case emptyCommand
  case emptyShortcutName
  case terminalUnavailable
  case invalidWorkingDirectory(String)
  case invalidDirectory(String)
  case finderUnavailable

  var errorDescription: String? {
    switch self {
    case .invalidApplication(let target): "Could not find application '\(target)'."
    case .invalidURL(let url): "'\(url)' is not a valid URL."
    case .emptyCommand: "The command is empty."
    case .emptyShortcutName: "The Apple Shortcut name is empty."
    case .terminalUnavailable: "Terminal.app could not be found."
    case .invalidWorkingDirectory(let path): "Working directory '\(path)' does not exist."
    case .invalidDirectory(let path): "Directory '\(path)' does not exist."
    case .finderUnavailable: "Finder.app could not be found."
    }
  }
}

@MainActor
final class ActionExecutor: ObservableObject {
  @Published private(set) var lastResult: String?

  private let history: ExecutionHistoryStore
  private let applicationWindowCycler = ApplicationWindowCycler()
  private var runningProcesses: [UUID: Process] = [:]

  init(history: ExecutionHistoryStore) {
    self.history = history
  }

  func execute(_ shortcut: DexShortcut) {
    history.record(shortcut)
    do {
      switch shortcut.action {
      case .launchApplication(let target):
        try launchApplication(target, shortcutName: shortcut.name)
      case .openFinder(let directory):
        try openFinder(directory, shortcutName: shortcut.name)
      case .openURL(let url):
        try openURL(url, shortcutName: shortcut.name)
      case .runCommand(
        let command,
        let workingDirectory,
        let inTerminal,
        let closeTerminalOnCompletion
      ):
        if inTerminal {
          try runCommandInTerminal(
            command,
            workingDirectory: workingDirectory,
            closeOnCompletion: closeTerminalOnCompletion,
            shortcut: shortcut
          )
        } else {
          try runCommandInBackground(
            command,
            workingDirectory: workingDirectory,
            shortcut: shortcut
          )
        }
      case .runAppleShortcut(let name):
        try runAppleShortcut(name, shortcut: shortcut)
      }
    } catch {
      lastResult = "\(shortcut.name): \(error.localizedDescription)"
      NSSound.beep()
    }
  }

  private func launchApplication(_ target: String, shortcutName: String) throws {
    let expandedTarget = (target as NSString).expandingTildeInPath
    let applicationURL =
      FileManager.default.fileExists(atPath: expandedTarget)
      ? URL(fileURLWithPath: expandedTarget)
      : NSWorkspace.shared.urlForApplication(withBundleIdentifier: target)
    guard let applicationURL else { throw ActionExecutionError.invalidApplication(target) }

    if
      let bundleIdentifier = Bundle(url: applicationURL)?.bundleIdentifier,
      let runningApplication = NSRunningApplication.runningApplications(
        withBundleIdentifier: bundleIdentifier
      ).first,
      applicationWindowCycler.activateNextWindow(in: runningApplication)
    {
      lastResult = "Opened \(shortcutName)."
      return
    }

    NSWorkspace.shared.openApplication(
      at: applicationURL,
      configuration: NSWorkspace.OpenConfiguration()
    ) { [weak self] _, error in
      Task { @MainActor in
        if let error {
          self?.lastResult = "\(shortcutName): \(error.localizedDescription)"
        } else {
          self?.lastResult = "Opened \(shortcutName)."
        }
      }
    }
  }

  private func openURL(_ value: String, shortcutName: String) throws {
    guard let url = URL(string: value), url.scheme != nil else {
      throw ActionExecutionError.invalidURL(value)
    }
    guard NSWorkspace.shared.open(url) else {
      throw ActionExecutionError.invalidURL(value)
    }
    lastResult = "Opened \(shortcutName)."
  }

  private func openFinder(_ directory: String?, shortcutName: String) throws {
    if let directory, !directory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      let directoryURL = try validatedDirectory(directory)
      guard NSWorkspace.shared.open(directoryURL) else {
        throw ActionExecutionError.invalidDirectory(directoryURL.path)
      }
    } else {
      guard
        let finderURL = NSWorkspace.shared.urlForApplication(
          withBundleIdentifier: "com.apple.finder")
      else {
        throw ActionExecutionError.finderUnavailable
      }
      NSWorkspace.shared.openApplication(
        at: finderURL,
        configuration: NSWorkspace.OpenConfiguration()
      ) { [weak self] _, error in
        Task { @MainActor in
          if let error {
            self?.lastResult = "\(shortcutName): \(error.localizedDescription)"
          } else {
            self?.lastResult = "Opened \(shortcutName)."
          }
        }
      }
      return
    }
    lastResult = "Opened \(shortcutName)."
  }

  private func runCommandInTerminal(
    _ command: String,
    workingDirectory: String?,
    closeOnCompletion: Bool,
    shortcut: DexShortcut
  ) throws {
    guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ActionExecutionError.emptyCommand
    }
    let directory = try validatedWorkingDirectory(workingDirectory)
    try FileManager.default.createDirectory(
      at: DexPaths.generatedCommandsDirectory,
      withIntermediateDirectories: true
    )
    let scriptURL = DexPaths.generatedCommandsDirectory
      .appendingPathComponent("\(shortcut.id.uuidString).command")
    var closeScriptURL: URL?
    if closeOnCompletion {
      let generatedCloseScriptURL = DexPaths.generatedCommandsDirectory
        .appendingPathComponent("\(shortcut.id.uuidString)-close-terminal.applescript")
      closeScriptURL = generatedCloseScriptURL
      try TerminalCommandScripts.closeTerminal.write(
        to: generatedCloseScriptURL,
        atomically: true,
        encoding: .utf8
      )
    }
    let script = TerminalCommandScripts.command(
      command,
      workingDirectory: directory,
      closeScriptURL: closeScriptURL
    )
    try script.write(to: scriptURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o700],
      ofItemAtPath: scriptURL.path
    )

    guard
      let terminalURL = NSWorkspace.shared.urlForApplication(
        withBundleIdentifier: "com.apple.Terminal")
    else {
      throw ActionExecutionError.terminalUnavailable
    }
    NSWorkspace.shared.open(
      [scriptURL],
      withApplicationAt: terminalURL,
      configuration: NSWorkspace.OpenConfiguration()
    ) { [weak self] _, error in
      Task { @MainActor in
        if let error {
          self?.lastResult = "\(shortcut.name): \(error.localizedDescription)"
        } else {
          self?.lastResult = "Started \(shortcut.name) in Terminal."
        }
      }
    }
  }

  private func runCommandInBackground(
    _ command: String,
    workingDirectory: String?,
    shortcut: DexShortcut
  ) throws {
    guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ActionExecutionError.emptyCommand
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-lc", command]
    process.currentDirectoryURL = try validatedWorkingDirectory(workingDirectory)
    try launchLoggedProcess(process, shortcut: shortcut)
    lastResult = "Started \(shortcut.name) in the background."
  }

  private func runAppleShortcut(_ name: String, shortcut: DexShortcut) throws {
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ActionExecutionError.emptyShortcutName
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
    process.arguments = ["run", name]
    process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
    try launchLoggedProcess(process, shortcut: shortcut)
    lastResult = "Started Apple Shortcut '\(name)'."
  }

  private func launchLoggedProcess(_ process: Process, shortcut: DexShortcut) throws {
    try FileManager.default.createDirectory(
      at: DexPaths.applicationSupportDirectory,
      withIntermediateDirectories: true
    )
    if !FileManager.default.fileExists(atPath: DexPaths.logFile.path) {
      FileManager.default.createFile(atPath: DexPaths.logFile.path, contents: nil)
    }
    let logHandle = try FileHandle(forWritingTo: DexPaths.logFile)
    try logHandle.seekToEnd()
    let timestamp = ISO8601DateFormatter().string(from: Date())
    logHandle.write(Data("\n[\(timestamp)] Starting \(shortcut.name)\n".utf8))
    process.standardOutput = logHandle
    process.standardError = logHandle
    process.terminationHandler = { [weak self] process in
      try? logHandle.close()
      Task { @MainActor in
        self?.runningProcesses.removeValue(forKey: shortcut.id)
        self?.lastResult = "\(shortcut.name) exited with status \(process.terminationStatus)."
      }
    }
    try process.run()
    runningProcesses[shortcut.id] = process
  }

  private func validatedWorkingDirectory(_ value: String?) throws -> URL {
    let path: String
    if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      path = (value as NSString).expandingTildeInPath
    } else {
      path = FileManager.default.homeDirectoryForCurrentUser.path
    }
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      throw ActionExecutionError.invalidWorkingDirectory(path)
    }
    return URL(fileURLWithPath: path, isDirectory: true)
  }

  private func validatedDirectory(_ value: String) throws -> URL {
    switch DirectoryPathValidation(value) {
    case .valid(let path):
      return URL(fileURLWithPath: path, isDirectory: true)
    case .missing(let path), .notDirectory(let path):
      throw ActionExecutionError.invalidDirectory(path)
    case .empty:
      throw ActionExecutionError.invalidDirectory(value)
    }
  }
}
