import Foundation
import XCTest

@testable import DexCore

final class ExecutionHistoryTests: XCTestCase {
  func testEntryRoundTripsAllAnalyticsFields() throws {
    let entry = ExecutionHistoryEntry(
      id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
      timestamp: Date(timeIntervalSince1970: 1_700_000_000),
      shortcutID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
      shortcutName: "Open Calendar",
      actionKind: .launchApplication
    )

    let data = try JSONEncoder().encode(entry)
    let decoded = try JSONDecoder().decode(ExecutionHistoryEntry.self, from: data)

    XCTAssertEqual(decoded, entry)
  }

  func testMissingHistoryLoadsAsEmpty() throws {
    let repository = makeRepository()

    XCTAssertEqual(try repository.load(), [])
  }

  func testAppendPersistsInChronologicalOrderWithPrivatePermissions() throws {
    let repository = makeRepository()
    let first = makeEntry(index: 1)
    let second = makeEntry(index: 2)

    try repository.append(first)
    try repository.append(second)

    XCTAssertEqual(try repository.load(), [first, second])
    let attributes = try FileManager.default.attributesOfItem(atPath: repository.fileURL.path)
    XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
  }

  func testSaveAndAppendRetainOnlyNewestEntries() throws {
    let repository = makeRepository(maximumEntryCount: 3)
    let entries = (1...5).map(makeEntry(index:))

    try repository.save(Array(entries.prefix(4)))
    XCTAssertEqual(try repository.load(), Array(entries[1...3]))

    try repository.append(entries[4])
    XCTAssertEqual(try repository.load(), Array(entries[2...4]))
  }

  func testClearPersistsEmptyPrivateHistory() throws {
    let repository = makeRepository()
    try repository.append(makeEntry(index: 1))

    try repository.clear()

    XCTAssertEqual(try repository.load(), [])
    XCTAssertTrue(FileManager.default.fileExists(atPath: repository.fileURL.path))
    let attributes = try FileManager.default.attributesOfItem(atPath: repository.fileURL.path)
    XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
  }

  private func makeRepository(
    maximumEntryCount: Int = ExecutionHistoryRepository.defaultMaximumEntryCount
  ) -> ExecutionHistoryRepository {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: root) }
    return ExecutionHistoryRepository(
      fileURL: root.appendingPathComponent("nested/history.json"),
      maximumEntryCount: maximumEntryCount
    )
  }

  private func makeEntry(index: Int) -> ExecutionHistoryEntry {
    ExecutionHistoryEntry(
      timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
      shortcutID: UUID(),
      shortcutName: "Shortcut \(index)",
      actionKind: .runCommand
    )
  }
}
