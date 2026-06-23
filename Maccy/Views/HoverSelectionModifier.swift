import SwiftUI

private struct HoverSelectionModifier: ViewModifier {
  @Environment(AppState.self) private var appState
  @State private var hoverSelectionTask: Task<Void, Never>?

  var id: UUID

  func body(content: Content) -> some View {
    content
      .onHover { hovering in
        hoverSelectionTask?.cancel()

        guard hovering else {
          return
        }

        hoverSelectionTask = Task { @MainActor in
          try? await Task.sleep(for: .milliseconds(40))
          guard !Task.isCancelled else {
            return
          }

          if !appState.navigator.isKeyboardNavigating && !appState.navigator.isMultiSelectInProgress {
            appState.navigator.selectWithoutScrolling(id: id)
          } else {
            appState.navigator.hoverSelectionWhileKeyboardNavigating = id
          }
        }
      }
      .onDisappear {
        hoverSelectionTask?.cancel()
      }
  }
}

extension View {
  func hoverSelectionId(_ id: UUID) -> some View {
    modifier(HoverSelectionModifier(id: id))
  }
}
