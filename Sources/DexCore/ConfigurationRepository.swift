import Foundation

public enum DexPaths {
  public static var applicationSupportDirectory: URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return base.appendingPathComponent("Dex", isDirectory: true)
  }

  public static var configurationFile: URL {
    return applicationSupportDirectory.appendingPathComponent("shortcuts.json")
  }

  public static var logFile: URL {
    applicationSupportDirectory.appendingPathComponent("dex.log")
  }

  public static var generatedCommandsDirectory: URL {
    applicationSupportDirectory.appendingPathComponent("Commands", isDirectory: true)
  }
}

public struct ConfigurationRepository {
  public let fileURL: URL

  public init(fileURL: URL = DexPaths.configurationFile) {
    self.fileURL = fileURL
  }

  public func load() throws -> DexConfiguration {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return DexConfiguration()
    }
    let data = try Data(contentsOf: fileURL)
    return try decode(data)
  }

  public func save(_ configuration: DexConfiguration) throws {
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let data = try encode(configuration)
    try data.write(to: fileURL, options: .atomic)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: fileURL.path
    )
  }

  public func decode(_ data: Data) throws -> DexConfiguration {
    var configuration = try JSONDecoder().decode(DexConfiguration.self, from: data)
    configuration.normalizeBindings()
    return configuration
  }

  public func encode(_ configuration: DexConfiguration) throws -> Data {
    var configuration = configuration
    configuration.purgeExpiredDeletedShortcuts()
    configuration.normalizeBindings()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(configuration)
  }
}

public enum ShellEscaping {
  public static func singleQuoted(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
  }
}
