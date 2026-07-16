import Foundation

public enum FinderDirectoryLocation: Equatable, Sendable {
  case applications
  case desktop
  case documents
  case downloads
  case iCloudDrive
  case home
  case movies
  case music
  case pictures
  case publicFolder
  case shared
  case trash
  case startupDisk
  case mountedVolume
  case other

  public init(
    directory: String?,
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
  ) {
    guard let directory else {
      self = .other
      return
    }

    let trimmedDirectory = directory.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedDirectory.isEmpty else {
      self = .other
      return
    }

    let normalizedHome = Self.normalizedPath(homeDirectory)
    let normalizedDirectory = Self.normalizedPath(
      URL(
        fileURLWithPath: Self.expandingTilde(
          in: trimmedDirectory,
          homeDirectory: homeDirectory
        ),
        isDirectory: true
      )
    )

    let knownLocations: [(String, FinderDirectoryLocation)] = [
      (normalizedHome, .home),
      (Self.path("Applications", relativeTo: homeDirectory), .applications),
      (Self.path("Desktop", relativeTo: homeDirectory), .desktop),
      (Self.path("Documents", relativeTo: homeDirectory), .documents),
      (Self.path("Downloads", relativeTo: homeDirectory), .downloads),
      (
        Self.path(
          "Library/Mobile Documents/com~apple~CloudDocs",
          relativeTo: homeDirectory
        ),
        .iCloudDrive
      ),
      (Self.path("Library/CloudStorage/iCloud Drive", relativeTo: homeDirectory), .iCloudDrive),
      (Self.path("Movies", relativeTo: homeDirectory), .movies),
      (Self.path("Music", relativeTo: homeDirectory), .music),
      (Self.path("Pictures", relativeTo: homeDirectory), .pictures),
      (Self.path("Public", relativeTo: homeDirectory), .publicFolder),
      (Self.path(".Trash", relativeTo: homeDirectory), .trash),
      (Self.normalizedPath(URL(fileURLWithPath: "/Applications")), .applications),
      (Self.normalizedPath(URL(fileURLWithPath: "/System/Applications")), .applications),
      (Self.normalizedPath(URL(fileURLWithPath: "/Users/Shared")), .shared),
      (Self.normalizedPath(URL(fileURLWithPath: "/")), .startupDisk),
    ]

    if let location = knownLocations.first(where: { $0.0 == normalizedDirectory })?.1 {
      self = location
      return
    }

    let directoryURL = URL(fileURLWithPath: normalizedDirectory, isDirectory: true)
    if Self.normalizedPath(directoryURL.deletingLastPathComponent())
      == Self.normalizedPath(URL(fileURLWithPath: "/Volumes"))
    {
      self = .mountedVolume
      return
    }

    self = .other
  }

  private static func expandingTilde(in path: String, homeDirectory: URL) -> String {
    if path == "~" {
      return homeDirectory.path
    }
    if path.hasPrefix("~/") {
      return homeDirectory.appendingPathComponent(String(path.dropFirst(2))).path
    }
    return (path as NSString).expandingTildeInPath
  }

  private static func path(_ path: String, relativeTo homeDirectory: URL) -> String {
    normalizedPath(homeDirectory.appendingPathComponent(path, isDirectory: true))
  }

  private static func normalizedPath(_ url: URL) -> String {
    url.standardizedFileURL.path
  }
}
