import Foundation
import SwiftData

@MainActor
class Storage {
  struct HistoryCounts {
    let pinned: Int
    let unpinned: Int

    var total: Int { pinned + unpinned }
  }

  static let shared = Storage()

  var container: ModelContainer
  var context: ModelContext { container.mainContext }

  var size: String {
    guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).allValues.first?.value as? Int64, size > 1 else {
      return ""
    }

    return ByteCountFormatter().string(fromByteCount: size)
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

  private let url = URL.applicationSupportDirectory.appending(path: "Maccy/Storage.sqlite")

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
}
