import Foundation

extension DexPaths {
  public static var windowDrillHistoryFile: URL {
    applicationSupportDirectory.appendingPathComponent("window-drill-history.json")
  }
}

public struct DrillPlacementResult: Codable, Equatable, Sendable {
  public let family: DrillLayoutFamily
  public let zone: DrillZone
  public let elapsed: TimeInterval

  public init(family: DrillLayoutFamily, zone: DrillZone, elapsed: TimeInterval) {
    self.family = family
    self.zone = zone
    self.elapsed = elapsed
  }
}

public struct DrillRoundResult: Codable, Equatable, Sendable {
  public let succeeded: Bool
  public let elapsed: TimeInterval
  public let placements: [DrillPlacementResult]

  public init(
    succeeded: Bool,
    elapsed: TimeInterval,
    placements: [DrillPlacementResult]
  ) {
    self.succeeded = succeeded
    self.elapsed = elapsed
    self.placements = placements
  }
}

public struct WindowDrillSession: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  public let completedAt: Date
  public let score: Int
  public let rounds: [DrillRoundResult]

  public init(
    id: UUID = UUID(),
    completedAt: Date = Date(),
    score: Int,
    rounds: [DrillRoundResult]
  ) {
    self.id = id
    self.completedAt = completedAt
    self.score = score
    self.rounds = rounds
  }

  public var successfulRoundCount: Int {
    rounds.count(where: \.succeeded)
  }

  public var averageRoundTime: TimeInterval? {
    Self.average(rounds.filter(\.succeeded).map(\.elapsed))
  }

  public func averagePlacementTime(for family: DrillLayoutFamily) -> TimeInterval? {
    Self.average(
      rounds.flatMap(\.placements)
        .filter { $0.family == family }
        .map(\.elapsed)
    )
  }

  private static func average(_ values: [TimeInterval]) -> TimeInterval? {
    guard !values.isEmpty else { return nil }
    return values.reduce(0, +) / Double(values.count)
  }
}

public enum WindowDrillStats {
  public static func averageRoundTime(in sessions: [WindowDrillSession]) -> TimeInterval? {
    average(sessions.flatMap(\.rounds).filter(\.succeeded).map(\.elapsed))
  }

  public static func averagePlacementTime(
    for family: DrillLayoutFamily,
    in sessions: [WindowDrillSession]
  ) -> TimeInterval? {
    average(
      sessions.flatMap(\.rounds).flatMap(\.placements)
        .filter { $0.family == family }
        .map(\.elapsed)
    )
  }

  private static func average(_ values: [TimeInterval]) -> TimeInterval? {
    guard !values.isEmpty else { return nil }
    return values.reduce(0, +) / Double(values.count)
  }
}

public struct WindowDrillHistoryRepository {
  public static let defaultMaximumSessionCount = 250

  public let fileURL: URL
  public let maximumSessionCount: Int

  public init(
    fileURL: URL = DexPaths.windowDrillHistoryFile,
    maximumSessionCount: Int = WindowDrillHistoryRepository.defaultMaximumSessionCount
  ) {
    precondition(maximumSessionCount > 0, "Window Drill history retention must be positive")
    self.fileURL = fileURL
    self.maximumSessionCount = maximumSessionCount
  }

  public func load() throws -> [WindowDrillSession] {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
    return try JSONDecoder().decode(
      [WindowDrillSession].self,
      from: Data(contentsOf: fileURL)
    )
  }

  public func save(_ sessions: [WindowDrillSession]) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(Array(sessions.suffix(maximumSessionCount)))
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

  public func append(_ session: WindowDrillSession) throws {
    var sessions = try load()
    sessions.append(session)
    try save(sessions)
  }
}
