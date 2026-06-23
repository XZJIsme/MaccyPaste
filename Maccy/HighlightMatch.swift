import Foundation
import Defaults

enum HighlightMatch: String, CaseIterable, Identifiable, CustomStringConvertible, Defaults.Serializable {
  case color
  case bold
  case italic
  case underline

  var id: Self { self }

    var description: String {
    switch self {
    case .bold:
      return AppLocalization.shared.localizedString("HighlightMatchBold", tableName: "AppearanceSettings")
    case .color:
      return AppLocalization.shared.localizedString("HighlightMatchColor", tableName: "AppearanceSettings")
    case .italic:
      return AppLocalization.shared.localizedString("HighlightMatchItalic", tableName: "AppearanceSettings")
    case .underline:
      return AppLocalization.shared.localizedString("HighlightMatchUnderline", tableName: "AppearanceSettings")
    }
  }
}
