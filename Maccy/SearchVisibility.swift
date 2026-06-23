import Defaults
import Foundation

enum SearchVisibility: String, CaseIterable, Identifiable, CustomStringConvertible, Defaults.Serializable {
  case always
  case duringSearch

  var id: Self { self }

    var description: String {
    switch self {
    case .always:
      return AppLocalization.shared.localizedString("SearchVisibilityAlways", tableName: "AppearanceSettings")
    case .duringSearch:
      return AppLocalization.shared.localizedString("SearchVisibilityDuringSearch", tableName: "AppearanceSettings")
    }
  }
}
