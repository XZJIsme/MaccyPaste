import SwiftUI

private struct HoverSelectionModifier: ViewModifier {
  @Environment(AppState.self) private var appState

  var id: UUID

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

        appState.navigator.selectWithoutScrolling(id: id)
      }
  }
}

extension View {
  func hoverSelectionId(_ id: UUID) -> some View {
    modifier(HoverSelectionModifier(id: id))
  }
}
