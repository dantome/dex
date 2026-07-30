import DexCore
import XCTest

final class WindowDrillHistoryTests: XCTestCase {
  func testSessionCalculatesRoundAndFamilyAverages() {
    let session = WindowDrillSession(
      score: 2_500,
      rounds: [
        DrillRoundResult(
          succeeded: true,
          elapsed: 12,
          placements: [
            DrillPlacementResult(family: .halves, zone: .leftHalf, elapsed: 4),
            DrillPlacementResult(family: .halves, zone: .rightHalf, elapsed: 8),
          ]
        ),
        DrillRoundResult(
          succeeded: false,
          elapsed: 30,
          placements: [
            DrillPlacementResult(family: .thirds, zone: .leftThird, elapsed: 10)
          ]
        ),
        DrillRoundResult(
          succeeded: true,
          elapsed: 18,
          placements: [
            DrillPlacementResult(family: .halves, zone: .topHalf, elapsed: 12)
          ]
        ),
      ]
    )

    XCTAssertEqual(session.successfulRoundCount, 2)
    XCTAssertEqual(session.averageRoundTime, 15)
    XCTAssertEqual(session.averagePlacementTime(for: .halves), 8)
    XCTAssertEqual(session.averagePlacementTime(for: .thirds), 10)
    XCTAssertNil(session.averagePlacementTime(for: .quarters))
  }

  func testRepositoryRetainsNewestSessionsAndUsesPrivatePermissions() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("drills.json")
    let repository = WindowDrillHistoryRepository(
      fileURL: fileURL,
      maximumSessionCount: 2
    )
    let sessions = (1...3).map { index in
      WindowDrillSession(score: index * 100, rounds: [])
    }

    try repository.save(sessions)

    XCTAssertEqual(try repository.load().map(\.score), [200, 300])
    let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    XCTAssertEqual(attributes[.posixPermissions] as? NSNumber, NSNumber(value: 0o600))
  }

  func testStatsCompareAcrossPriorSessions() {
    let sessions = [
      WindowDrillSession(
        score: 1_000,
        rounds: [
          DrillRoundResult(
            succeeded: true,
            elapsed: 20,
            placements: [
              DrillPlacementResult(family: .fullScreen, zone: .full, elapsed: 6)
            ]
          )
        ]
      ),
      WindowDrillSession(
        score: 1_200,
        rounds: [
          DrillRoundResult(
            succeeded: true,
            elapsed: 10,
            placements: [
              DrillPlacementResult(family: .fullScreen, zone: .full, elapsed: 4)
            ]
          )
        ]
      ),
    ]

    XCTAssertEqual(WindowDrillStats.averageRoundTime(in: sessions), 15)
    XCTAssertEqual(
      WindowDrillStats.averagePlacementTime(for: .fullScreen, in: sessions),
      5
    )
  }
}
