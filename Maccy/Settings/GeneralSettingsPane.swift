import SwiftUI
import Defaults
import KeyboardShortcuts
import LaunchAtLogin
import Settings

struct GeneralSettingsPane: View {
  private let notificationsURL = URL(
    string: "x-apple.systempreferences:com.apple.preference.notifications?id=\(Bundle.main.bundleIdentifier ?? "")"
  )

  @Default(.searchMode) private var searchMode

  @State private var localization = AppLocalization.shared
  @State private var softwareUpdater = SoftwareUpdater.shared
  @State private var copyModifier = HistoryItemAction.copy.modifierFlags.description
  @State private var pasteModifier = HistoryItemAction.paste.modifierFlags.description
  @State private var pasteWithoutFormatting = HistoryItemAction.pasteWithoutFormatting.modifierFlags.description

  var body: some View {
    Settings.Container(contentWidth: 650) {
      Settings.Section(title: "", bottomDivider: true) {
        LaunchAtLogin.Toggle {
          Text("LaunchAtLogin", tableName: "GeneralSettings")
        }
      }

      Settings.Section(title: "", bottomDivider: true) {
        Defaults.Toggle(key: .automaticallyDetectsNewVersions) {
          Text("AutomaticallyDetectNewVersions", tableName: "GeneralSettings")
        }
        .fixedSize()

        HStack(spacing: 8) {
          Button {
            softwareUpdater.detectNewVersionManually()
          } label: {
            Text("CheckForNewVersionManually", tableName: "GeneralSettings")
          }
          .disabled(softwareUpdater.detectionState == .checking)

          Button {
            softwareUpdater.installAvailableUpdate()
          } label: {
            Text("UpdateNow", tableName: "GeneralSettings")
          }
          .disabled(!softwareUpdater.updateAvailable)

          if let updateStatusText {
            Text(updateStatusText)
              .controlSize(.small)
              .foregroundStyle(.gray)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }

      Settings.Section(label: { Text("Open", tableName: "GeneralSettings") }) {
        KeyboardShortcuts.Recorder(for: .popup, onChange: { newShortcut in
          if newShortcut == nil {
            // No shortcut is recorded. Remove keys monitor
            AppState.shared.popup.deinitEventsMonitor()
          } else {
            // User is using shortcut. Ensure keys monitor is initialized
            AppState.shared.popup.initEventsMonitor()
          }
        })
          .help(Text("OpenTooltip", tableName: "GeneralSettings"))
      }

      Settings.Section(label: { Text("Pin", tableName: "GeneralSettings") }) {
        KeyboardShortcuts.Recorder(for: .pin)
          .help(Text("PinTooltip", tableName: "GeneralSettings"))
      }
      Settings.Section(label: { Text("Delete", tableName: "GeneralSettings") }
      ) {
        KeyboardShortcuts.Recorder(for: .delete)
          .help(Text("DeleteTooltip", tableName: "GeneralSettings"))
      }
      Settings.Section(
        bottomDivider: true,
        label: { Text("ShowPreview", tableName: "GeneralSettings") }
      ) {
        KeyboardShortcuts.Recorder(for: .togglePreview)
          .help(Text("ShowPreviewTooltip", tableName: "GeneralSettings"))
      }

      Settings.Section(
        bottomDivider: true,
        label: { Text("Search", tableName: "GeneralSettings") }
      ) {
        Picker("", selection: $searchMode) {
          ForEach(Search.Mode.allCases) { mode in
            Text(mode.description)
          }
        }
        .labelsHidden()
        .frame(width: 180, alignment: .leading)
      }

      Settings.Section(
        bottomDivider: true,
        label: { Text("Language", tableName: "GeneralSettings") }
      ) {
        Picker("", selection: Binding(
          get: { localization.language },
          set: { localization.language = $0 }
        )) {
          ForEach(AppLanguage.allCases) { language in
            Text(language.displayName)
              .tag(language)
          }
        }
        .labelsHidden()
        .frame(width: 180, alignment: .leading)
        .onChange(of: localization.language) { _, _ in
          AppState.shared.reloadPreferencesForLocalizationChange()
        }
      }

      Settings.Section(
        bottomDivider: true,
        label: { Text("Behavior", tableName: "GeneralSettings") }
      ) {
        Defaults.Toggle(key: .pasteByDefault) {
          Text("PasteAutomatically", tableName: "GeneralSettings")
        }
        .onChange(refreshModifiers)
        .fixedSize()

        Defaults.Toggle(key: .removeFormattingByDefault) {
          Text("PasteWithoutFormatting", tableName: "GeneralSettings")
        }
        .onChange(refreshModifiers)
        .fixedSize()

        Text(String(
          format: AppLocalization.shared.localizedString("Modifiers", tableName: "GeneralSettings"),
          copyModifier, pasteModifier, pasteWithoutFormatting
        ))
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(.gray)
        .controlSize(.small)
      }

      Settings.Section(title: "") {
        if let notificationsURL = notificationsURL {
          Link(destination: notificationsURL, label: {
            Text("NotificationsAndSounds", tableName: "GeneralSettings")
          })
        }
      }
    }
  }

  private func refreshModifiers(_ sender: Sendable) {
    copyModifier = HistoryItemAction.copy.modifierFlags.description
    pasteModifier = HistoryItemAction.paste.modifierFlags.description
    pasteWithoutFormatting = HistoryItemAction.pasteWithoutFormatting.modifierFlags.description
  }

  private var updateStatusText: String? {
    switch softwareUpdater.detectionState {
    case .idle:
      return nil
    case .checking:
      return AppLocalization.shared.localizedString("CheckingForNewVersion", tableName: "GeneralSettings")
    case .upToDate:
      return AppLocalization.shared.localizedString("NoNewVersionFound", tableName: "GeneralSettings")
    case .updateAvailable(let shortVersion):
      return String(
        format: AppLocalization.shared.localizedString("NewVersionAvailable", tableName: "GeneralSettings"),
        shortVersion
      )
    case .failed:
      return AppLocalization.shared.localizedString("VersionCheckFailed", tableName: "GeneralSettings")
    }
  }
}

#Preview {
  GeneralSettingsPane()
    .environment(\.locale, .init(identifier: "en"))
}
