import SwiftUI

struct SlideoutContentView: View {
  @Environment(AppState.self) var appState
  @State private var lastPreviewImage: NSImage?

  var body: some View {
    VStack {
      ToolbarView()

      if let item = appState.navigator.leadHistoryItem {
        PreviewItemView(item: item, fallbackImage: lastPreviewImage) { image in
          lastPreviewImage = image
        }
          .id(item.id)
      } else if let pasteStack = appState.history.pasteStack,
        appState.navigator.pasteStackSelected {
        PasteStackPreviewView(pasteStack: pasteStack)
      } else {
        EmptyView()
      }
    }
    .padding(.horizontal)
    .padding(.bottom)
    .padding(.top, Popup.verticalPadding)
  }

}
