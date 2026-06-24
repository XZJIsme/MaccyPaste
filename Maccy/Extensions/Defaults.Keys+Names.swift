import AppKit
import Defaults
import Observation

enum AppLanguage: String, CaseIterable, Identifiable, Defaults.Serializable {
  case system
  case ar
  case be
  case bg
  case bn
  case bs
  case ca
  case ckb
  case cs
  case da
  case de
  case el
  case en
  case eo
  case es
  case et
  case fa
  case fi
  case fil
  case fr
  case he
  case hi
  case hr
  case hu
  case id
  case it
  case ja
  case ko
  case lt
  case lv
  case ms
  case nb
  case nl
  case pl
  case pt
  case ptBR = "pt-BR"
  case ro
  case ru
  case sk
  case sr
  case sl
  case sv
  case ta
  case th
  case tr
  case uk
  case ur
  case uz
  case vi
  case zhHans = "zh-Hans"
  case zhHant = "zh-Hant"

  var id: Self { self }

  var localeIdentifier: String? {
    self == .system ? nil : rawValue
  }

  var locale: Locale {
    if let localeIdentifier {
      return Locale(identifier: localeIdentifier)
    }

    return .autoupdatingCurrent
  }

  var displayName: String {
    if self == .system {
      return AppLocalization.shared.localizedString("SystemDefault", tableName: "GeneralSettings")
    }

    return Locale(identifier: rawValue).localizedString(forIdentifier: rawValue) ?? rawValue
  }
}

@Observable
class AppLocalization {
  static let shared = AppLocalization()

  var language: AppLanguage {
    didSet {
      Defaults[.language] = language
    }
  }

  var locale: Locale {
    language.locale
  }

  private var bundle: Bundle {
    guard let localeIdentifier = language.localeIdentifier,
          let path = Bundle.main.path(forResource: localeIdentifier, ofType: "lproj"),
          let bundle = Bundle(path: path) else {
      return .main
    }

    return bundle
  }

  private init() {
    language = Defaults[.language]
  }

  func localizedString(_ key: String, tableName: String? = nil, comment: String = "") -> String {
    bundle.localizedString(forKey: key, value: nil, table: tableName)
  }
}

struct StorageType {
  static let files = StorageType(types: [.fileURL])
  static let images = StorageType(types: [.png, .tiff])
  static let text = StorageType(types: [.html, .rtf, .string])
  static let all = StorageType(types: files.types + images.types + text.types)

  var types: [NSPasteboard.PasteboardType]
}

extension Defaults.Keys {
  static let clearOnQuit = Key<Bool>("clearOnQuit", default: false)
  static let clearSystemClipboard = Key<Bool>("clearSystemClipboard", default: false)
  static let clipboardCheckInterval = Key<Double>("clipboardCheckInterval", default: 0.5)
  static let enabledPasteboardTypes = Key<Set<NSPasteboard.PasteboardType>>(
    "enabledPasteboardTypes", default: Set(StorageType.all.types)
  )
  static let highlightMatch = Key<HighlightMatch>("highlightMatch", default: .bold)
  static let ignoreAllAppsExceptListed = Key<Bool>("ignoreAllAppsExceptListed", default: false)
  static let ignoreEvents = Key<Bool>("ignoreEvents", default: false)
  static let ignoreOnlyNextEvent = Key<Bool>("ignoreOnlyNextEvent", default: false)
  static let ignoreRegexp = Key<[String]>("ignoreRegexp", default: [])
  static let ignoredApps = Key<[String]>("ignoredApps", default: [])
  static let ignoredPasteboardTypes = Key<Set<String>>(
    "ignoredPasteboardTypes",
    default: Set([
      "Pasteboard generator type",
      "com.agilebits.onepassword",
      "com.typeit4me.clipping",
      "de.petermaurer.TransientPasteboardType",
      "net.antelle.keeweb"
    ])
  )
  static let imageMaxHeight = Key<Int>("imageMaxHeight", default: 40)
  static let language = Key<AppLanguage>("language", default: .system)
  static let lastReviewRequestedAt = Key<Date>("lastReviewRequestedAt", default: Date.now)
  static let menuIcon = Key<MenuIcon>("menuIcon", default: .maccy)
  static let migrations = Key<[String: Bool]>("migrations", default: [:])
  static let numberOfUsages = Key<Int>("numberOfUsages", default: 0)
  static let pasteByDefault = Key<Bool>("pasteByDefault", default: false)
  static let pinTo = Key<PinsPosition>("pinTo", default: .top)
  static let popupPosition = Key<PopupPosition>("popupPosition", default: .cursor)
  static let popupScreen = Key<Int>("popupScreen", default: 0)
  static let previewDelay = Key<Int>("previewDelay", default: 1500)
  static let removeFormattingByDefault = Key<Bool>("removeFormattingByDefault", default: false)
  static let searchMode = Key<Search.Mode>("searchMode", default: .exact)
  static let showFooter = Key<Bool>("showFooter", default: true)
  static let showInStatusBar = Key<Bool>("showInStatusBar", default: true)
  static let showRecentCopyInMenuBar = Key<Bool>("showRecentCopyInMenuBar", default: false)
  static let showSearch = Key<Bool>("showSearch", default: true)
  static let searchVisibility = Key<SearchVisibility>("searchVisibility", default: .always)
  static let showSpecialSymbols = Key<Bool>("showSpecialSymbols", default: true)
  static let showTitle = Key<Bool>("showTitle", default: true)
  static let size = Key<Int>("historySize", default: 9999)
  static let unlimitedHistory = Key<Bool>("unlimitedHistory", default: false)
  static let sortBy = Key<Sorter.By>("sortBy", default: .lastCopiedAt)
  static let suppressClearAlert = Key<Bool>("suppressClearAlert", default: false)
  static let windowSize = Key<NSSize>("windowSize", default: NSSize(width: 450, height: 800))
  static let windowPosition = Key<NSPoint>("windowPosition", default: NSPoint(x: 0.5, y: 0.8))
  static let showApplicationIcons = Key<Bool>("showApplicationIcons", default: false)
  static let previewWidth = Key<CGFloat>("previewWidth", default: 400)
}
