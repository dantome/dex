import Foundation

public enum DirectoryPathValidation: Equatable, Sendable {
  case empty
  case valid(expandedPath: String)
  case missing(expandedPath: String)
  case notDirectory(expandedPath: String)

  public init(_ value: String) {
    let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedValue.isEmpty else {
      self = .empty
      return
    }

    let expandedPath = (trimmedValue as NSString).expandingTildeInPath
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDirectory) else {
      self = .missing(expandedPath: expandedPath)
      return
    }

    self =
      isDirectory.boolValue
      ? .valid(expandedPath: expandedPath)
      : .notDirectory(expandedPath: expandedPath)
  }

  public var canOpenInFinder: Bool {
    switch self {
    case .empty, .valid: true
    case .missing, .notDirectory: false
    }
  }
}
