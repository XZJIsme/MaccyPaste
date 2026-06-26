import Defaults
import Foundation
import Sparkle

@MainActor
@Observable
class SoftwareUpdater {
  enum DetectionState: Equatable {
    case idle
    case checking
    case upToDate
    case updateAvailable(shortVersion: String)
    case failed
  }

  private struct AppcastItem {
    let version: String
    let shortVersion: String
  }

  static let shared = SoftwareUpdater()

  private final class AppcastParser: NSObject, XMLParserDelegate {
    private var items: [AppcastItem] = []
    private var currentVersion: String?
    private var currentShortVersion: String?
    private var isInItem = false
    private var currentElement = ""

    func parse(data: Data) -> [AppcastItem] {
      let parser = XMLParser(data: data)
      parser.delegate = self
      _ = parser.parse()
      return items
    }

    func parser(
      _ parser: XMLParser,
      didStartElement elementName: String,
      namespaceURI: String?,
      qualifiedName qName: String?,
      attributes attributeDict: [String: String] = [:]
    ) {
      currentElement = elementName

      if elementName == "item" {
        isInItem = true
        currentVersion = nil
        currentShortVersion = nil
      } else if isInItem && elementName == "enclosure" {
        currentVersion = attributeDict["sparkle:version"] ?? attributeDict["version"] ?? currentVersion
        currentShortVersion = attributeDict["sparkle:shortVersionString"]
          ?? attributeDict["shortVersionString"]
          ?? currentShortVersion
      }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
      guard isInItem else { return }

      let value = string.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !value.isEmpty else { return }

      switch currentElement {
      case "sparkle:version":
        currentVersion = value
      case "sparkle:shortVersionString", "title":
        currentShortVersion = currentShortVersion ?? value
      default:
        break
      }
    }

    func parser(
      _ parser: XMLParser,
      didEndElement elementName: String,
      namespaceURI: String?,
      qualifiedName qName: String?
    ) {
      guard elementName == "item" else { return }

      if let currentVersion {
        items.append(AppcastItem(
          version: currentVersion,
          shortVersion: currentShortVersion ?? currentVersion
        ))
      }

      isInItem = false
      currentVersion = nil
      currentShortVersion = nil
    }
  }

  static let appcastURL = URL(
    string: "https://raw.githubusercontent.com/XZJIsme/MaccyPaste/refs/heads/maccypaste/appcast.xml"
  )!

  var detectionState: DetectionState = .idle

  var updateAvailable: Bool {
    if case .updateAvailable = detectionState {
      return true
    }

    return false
  }

  private let checkInterval: TimeInterval = 24 * 60 * 60
  private var startedAutomaticDetection = false
  private var updater: SPUUpdater

  private let updaterController = SPUStandardUpdaterController(
    startingUpdater: true,
    updaterDelegate: nil,
    userDriverDelegate: nil
  )

  init() {
    updater = updaterController.updater
    updater.automaticallyChecksForUpdates = false
  }

  func startAutomaticDetection() {
    guard !startedAutomaticDetection else { return }
    startedAutomaticDetection = true

    if Defaults[.automaticallyDetectsNewVersions] {
      Task {
        await detectNewVersion(force: false, showUpToDate: false)
      }
    }

    Task {
      for await enabled in Defaults.updates(.automaticallyDetectsNewVersions, initial: false) where enabled {
        await detectNewVersion(force: true, showUpToDate: false)
      }
    }
  }

  func detectNewVersionManually() {
    Task {
      await detectNewVersion(force: true, showUpToDate: true)
    }
  }

  func installAvailableUpdate() {
    updater.checkForUpdates()
  }

  private func detectNewVersion(force: Bool, showUpToDate: Bool) async {
    if !force, let lastDetection = Defaults[.lastVersionDetectionAt],
       Date().timeIntervalSince(lastDetection) < checkInterval {
      return
    }

    detectionState = .checking

    do {
      let latestItem = try await latestAppcastItem()
      Defaults[.lastVersionDetectionAt] = Date()

      if isRemoteVersionNewer(latestItem.version) {
        detectionState = .updateAvailable(shortVersion: latestItem.shortVersion)
      } else {
        detectionState = showUpToDate ? .upToDate : .idle
      }
    } catch {
      detectionState = .failed
    }
  }

  private func latestAppcastItem() async throws -> AppcastItem {
    let (data, response) = try await URLSession.shared.data(from: Self.appcastURL)

    if let httpResponse = response as? HTTPURLResponse,
       !(200..<300).contains(httpResponse.statusCode) {
      throw URLError(.badServerResponse)
    }

    guard let latest = AppcastParser()
      .parse(data: data)
      .max(by: { compareVersions($0.version, $1.version) == .orderedAscending }) else {
      throw URLError(.cannotParseResponse)
    }

    return latest
  }

  private func isRemoteVersionNewer(_ remoteVersion: String) -> Bool {
    compareVersions(currentBuildVersion, remoteVersion) == .orderedAscending
  }

  private var currentBuildVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
  }

  private func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
    lhs.compare(rhs, options: .numeric)
  }
}
