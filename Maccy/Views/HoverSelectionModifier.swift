import SwiftUI

private struct HoverSelectionModifier: ViewModifier {
  @Environment(AppState.self) private var appState

  var id: UUID
  var action: (() -> Void)?

  func body(content: Content) -> some View {
    content
      .onHover { hovering in
        guard hovering else {
          return
        }

        appState.navigator.isKeyboardNavigating = false
        guard !appState.navigator.isMultiSelectInProgress else {
          return
        }

        if let action {
          action()
        } else {
          appState.navigator.selectWithoutScrolling(id: id)
        }
      }
  }
}

extension View {
  func hoverSelectionId(_ id: UUID, action: (() -> Void)? = nil) -> some View {
    modifier(HoverSelectionModifier(id: id, action: action))
  }
}
