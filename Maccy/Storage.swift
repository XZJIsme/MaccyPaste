import Darwin
import Foundation
import SwiftData

@MainActor
class Storage {
  struct HistoryCounts {
    let pinned: Int
    let unpinned: Int

    var total: Int { pinned + unpinned }
  }

  struct BackupSummary {
    let total: Int
    let images: Int
    let files: Int
    let text: Int
    let fileSize: String
  }

  struct OptimizationSummary {
    let before: String
    let after: String
    let saved: String
  }

  static let shared = Storage()
  private static var realHomeDirectory: URL {
    guard let passwd = getpwuid(getuid()),
          let home = passwd.pointee.pw_dir else {
      return URL.homeDirectory
    }

    return URL(fileURLWithFileSystemRepresentation: home, isDirectory: true, relativeTo: nil)
  }

  var container: ModelContainer
  var context: ModelContext { container.mainContext }

  var size: String {
    guard let size = sizeInBytes, size > 1 else {
      return ""
    }

    return ByteCountFormatter().string(fromByteCount: Int64(size))
  }

  var sizeInBytes: Int? {
    try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
  }

  func optimizationSummary(before beforeSize: Int?, after afterSize: Int?) -> OptimizationSummary {
    OptimizationSummary(
      before: byteCountString(for: beforeSize),
      after: byteCountString(for: afterSize),
      saved: byteCountString(for: max((beforeSize ?? 0) - (afterSize ?? 0), 0))
    )
  }

  var historyCounts: HistoryCounts {
    let pinned = (try? context.fetchCount(FetchDescriptor<HistoryItem>(
      predicate: #Predicate { $0.pin != nil }
    ))) ?? 0
    let unpinned = (try? context.fetchCount(FetchDescriptor<HistoryItem>(
      predicate: #Predicate { $0.pin == nil }
    ))) ?? 0

    return HistoryCounts(pinned: pinned, unpinned: unpinned)
  }

  let url = URL.applicationSupportDirectory.appending(path: "Maccy/Storage.sqlite")
  let originalMaccyStorageURL = Storage.realHomeDirectory
    .appending(path: "Library/Containers/org.p0deje.Maccy/Data/Library/Application Support/Maccy/Storage.sqlite")

  init() {
    var config = ModelConfiguration(url: url)

    #if DEBUG
    if CommandLine.arguments.contains("enable-testing") {
      config = ModelConfiguration(isStoredInMemoryOnly: true)
    }
    #endif

    do {
      container = try ModelContainer(for: HistoryItem.self, configurations: config)
    } catch let error {
      fatalError("Cannot load database: \(error.localizedDescription).")
    }
  }

  func vacuum() throws {
    try context.save()

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    process.arguments = [
      url.path,
      "PRAGMA wal_checkpoint(TRUNCATE); VACUUM;"
    ]

    let errorPipe = Pipe()
    process.standardError = errorPipe

    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
      let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
      let message = String(data: data, encoding: .utf8) ?? "sqlite3 exited with status \(process.terminationStatus)"
      throw NSError(
        domain: "MaccyPaste.Storage.Vacuum",
        code: Int(process.terminationStatus),
        userInfo: [NSLocalizedDescriptionKey: message]
      )
    }
  }

  func backup(to destinationURL: URL) throws -> BackupSummary {
    try context.save()
    try checkpoint()

    let historyItems = try context.fetch(FetchDescriptor<HistoryItem>())

    if FileManager.default.fileExists(atPath: destinationURL.path) {
      try FileManager.default.removeItem(at: destinationURL)
    }
    try FileManager.default.copyItem(at: url, to: destinationURL)

    return BackupSummary(
      total: historyItems.count,
      images: historyItems.filter { $0.containsContent(types: StorageType.images.types) }.count,
      files: historyItems.filter { $0.containsContent(types: StorageType.files.types) }.count,
      text: historyItems.filter { $0.containsContent(types: StorageType.text.types) }.count,
      fileSize: byteCountString(for: destinationURL)
    )
  }

  func temporaryReadableCopy(of sourceURL: URL) throws -> URL {
    let fileManager = FileManager.default
    let directory = fileManager.temporaryDirectory
      .appendingPathComponent("MaccyPasteImport-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

    let destinationURL = directory.appendingPathComponent(sourceURL.lastPathComponent, isDirectory: false)
    try fileManager.copyItem(at: sourceURL, to: destinationURL)

    for suffix in ["-wal", "-shm"] {
      let sidecarURL = URL(fileURLWithPath: sourceURL.path + suffix)
      guard fileManager.fileExists(atPath: sidecarURL.path) else {
        continue
      }
      try? fileManager.copyItem(
        at: sidecarURL,
        to: URL(fileURLWithPath: destinationURL.path + suffix)
      )
    }

    return destinationURL
  }

  var originalMaccyImportSource: (name: String, url: URL)? {
    guard FileManager.default.fileExists(atPath: originalMaccyStorageURL.path),
          originalMaccyStorageURL.standardizedFileURL.path != url.standardizedFileURL.path else {
      return nil
    }

    return ("Maccy", originalMaccyStorageURL)
  }

  private func checkpoint() throws {
    try runSQLite(arguments: [
      url.path,
      "PRAGMA wal_checkpoint(TRUNCATE);"
    ], errorDomain: "MaccyPaste.Storage.Checkpoint")
  }

  private func byteCountString(for url: URL) -> String {
    guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
      return ""
    }

    return byteCountString(for: size)
  }

  private func byteCountString(for size: Int?) -> String {
    guard let size else {
      return ""
    }

    return ByteCountFormatter().string(fromByteCount: Int64(size))
  }

  private func runSQLite(arguments: [String], errorDomain: String) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    process.arguments = arguments

    let errorPipe = Pipe()
    process.standardError = errorPipe

    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
      let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
      let message = String(data: data, encoding: .utf8) ?? "sqlite3 exited with status \(process.terminationStatus)"
      throw NSError(
        domain: errorDomain,
        code: Int(process.terminationStatus),
        userInfo: [NSLocalizedDescriptionKey: message]
      )
    }
  }
}
