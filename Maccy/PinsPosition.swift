import Foundation
import Defaults

enum PinsPosition: String, CaseIterable, Identifiable, CustomStringConvertible, Defaults.Serializable {
  case top
  case bottom

  var id: Self { self }

    var description: String {
    switch self {
    case .top:
      return AppLocalization.shared.localizedString("PinToTop", tableName: "AppearanceSettings")
    case .bottom:
      return AppLocalization.shared.localizedString("PinToBottom", tableName: "AppearanceSettings")
    }
  }
}
