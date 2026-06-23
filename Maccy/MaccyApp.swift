import SwiftUI

struct LocalizedView<Content: View>: View {
  @State private var localization = AppLocalization.shared
  let content: () -> Content

  init(@ViewBuilder content: @escaping () -> Content) {
    self.content = content
  }

  var body: some View {
    content()
      .environment(\.locale, localization.locale)
  }
}

@main
struct MaccyApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  // It's impossible to create sceneless application,
  // so we are hacking this around by creating a menubar
  // scene that is always hidden.
  @State private var hiddenMenu: Bool = false

  var body: some Scene {
    MenuBarExtra("", isInserted: $hiddenMenu) {
      EmptyView()
    }
  }
}
