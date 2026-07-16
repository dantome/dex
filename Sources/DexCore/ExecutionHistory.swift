import Foundation

extension DexPaths {
  public static var executionHistoryFile: URL {
    applicationSupportDirectory.appendingPathComponent("history.json")
  }
}

/// A snapshot of one shortcut execution.
///
/// The shortcut name is captured at execution time so history remains useful
/// after the shortcut is renamed or deleted. The shortcut identifier and
/// action kind make the records suitable for future usage analytics.
public struct ExecutionHistoryEntry: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let timestamp: Date
  public let shortcutID: UUID
  public let shortcutName: String
  public let actionKind: ShortcutActionKind

  public init(
    id: UUID = UUID(),
    timestamp: Date = Date(),
    shortcutID: UUID,
    shortcutName: String,
    actionKind: ShortcutActionKind
  ) {
    self.id = id
    self.timestamp = timestamp
    self.shortcutID = shortcutID
    self.shortcutName = shortcutName
    self.actionKind = actionKind
  }
}

/// Persists shortcut execution history in chronological (oldest-first) order.
public struct ExecutionHistoryRepository {
  public static let defaultMaximumEntryCount = 1_000

  public let fileURL: URL
  public let maximumEntryCount: Int

  public init(
    fileURL: URL = DexPaths.executionHistoryFile,
    maximumEntryCount: Int = ExecutionHistoryRepository.defaultMaximumEntryCount
  ) {
    precondition(maximumEntryCount > 0, "Execution history retention must be positive")
    self.fileURL = fileURL
    self.maximumEntryCount = maximumEntryCount
  }

  public func load() throws -> [ExecutionHistoryEntry] {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return []
    }

    let data = try Data(contentsOf: fileURL)
    return try JSONDecoder().decode([ExecutionHistoryEntry].self, from: data)
  }

  /// Replaces the stored history, retaining the newest configured number of entries.
  public func save(_ entries: [ExecutionHistoryEntry]) throws {
    let retainedEntries = Array(entries.suffix(maximumEntryCount))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(retainedEntries)

    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try data.write(to: fileURL, options: .atomic)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: fileURL.path
    )
  }

  /// Adds an execution to the end of the history and applies bounded retention.
  public func append(_ entry: ExecutionHistoryEntry) throws {
    var entries = try load()
    entries.append(entry)
    try save(entries)
  }

  /// Persists an empty history while preserving the repository file's privacy guarantees.
  public func clear() throws {
    try save([])
  }
}
