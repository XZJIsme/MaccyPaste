import AppKit
import Defaults
import Foundation
import Settings
import SwiftUI

@Observable
class AppState: Sendable {
  static let shared = AppState(history: History.shared, footer: Footer())

  let multiSelectionEnabled = false

  var appDelegate: AppDelegate?
  var popup: Popup
  var history: History
  var footer: Footer
  var navigator: NavigationManager
  var preview: SlideoutController

  var searchVisible: Bool {
    if !Defaults[.showSearch] { return false }
    switch Defaults[.searchVisibility] {
    case .always: return true
    case .duringSearch: return !history.searchQuery.isEmpty
    }
  }

  var menuIconText: String {
    var title = history.unpinnedItems.first?.text.shortened(to: 100)
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    title.unicodeScalars.removeAll(where: CharacterSet.newlines.contains)
    return title.shortened(to: 20)
  }

  private let about = About()
  private var settingsWindowController: SettingsWindowController?

  init(history: History, footer: Footer) {
    self.history = history
    self.footer = footer
    popup = Popup()
    navigator = NavigationManager(history: history, footer: footer)
    preview = SlideoutController(
      onContentResize: { contentWidth in
        Defaults[.windowSize].width = contentWidth
      },
      onSlideoutResize: { previewWidth in
        Defaults[.previewWidth] = previewWidth
      })
    preview.contentWidth = Defaults[.windowSize].width
    preview.slideoutWidth = Defaults[.previewWidth]
  }

  @MainActor
  func select() {
    if !navigator.selection.isEmpty {
      if navigator.isMultiSelectInProgress {
        navigator.isManualMultiSelect = false
        history.startPasteStack(selection: &navigator.selection)
      } else {
        history.select(navigator.selection.first)
      }
    } else if let item = footer.selectedItem {
      // TODO: Use item.suppressConfirmation, but it's not updated!
      if item.confirmation != nil, Defaults[.suppressClearAlert] == false {
        item.showConfirmation = true
      } else {
        item.action()
      }
    } else {
      Clipboard.shared.copy(history.searchQuery)
      history.searchQuery = ""
    }
  }

  @MainActor
  func togglePin() {
    withTransaction(Transaction()) {
      navigator.selection.forEach { _, item in
        history.togglePin(item)
      }
    }
  }

  @MainActor
  func removePasteStack() {
    history.interruptPasteStack()
    navigator.highlightFirst()
  }

  @MainActor
  func deleteSelection() {
    guard let leadItem = navigator.leadHistoryItem else { return }
    let nextUnselectedItem = history.visibleItems.nearest(to: leadItem) { !$0.isSelected }

    withTransaction(Transaction()) {
      navigator.selection.forEach { _, item in
        history.delete(item)
      }
      navigator.select(item: nextUnselectedItem)
    }
  }

  func openAbout() {
    about.openAbout(nil)
  }

  @MainActor
  func openPreferences() { // swiftlint:disable:this function_body_length
    if settingsWindowController == nil {
      settingsWindowController = SettingsWindowController(
        panes: [
          Settings.Pane(
            identifier: Settings.PaneIdentifier.general,
            title: localizedPaneTitle(tableName: "GeneralSettings"),
            toolbarIcon: NSImage.gearshape!
          ) {
            LocalizedView {
              GeneralSettingsPane()
            }
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.storage,
            title: localizedPaneTitle(tableName: "StorageSettings"),
            toolbarIcon: NSImage.externaldrive!
          ) {
            LocalizedView {
              StorageSettingsPane()
            }
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.appearance,
            title: localizedPaneTitle(tableName: "AppearanceSettings"),
            toolbarIcon: NSImage.paintpalette!
          ) {
            LocalizedView {
              AppearanceSettingsPane()
            }
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.pins,
            title: localizedPaneTitle(tableName: "PinsSettings"),
            toolbarIcon: NSImage.pincircle!
          ) {
            LocalizedView {
              PinsSettingsPane()
                .environment(self)
                .modelContainer(Storage.shared.container)
            }
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.ignore,
            title: localizedPaneTitle(tableName: "IgnoreSettings"),
            toolbarIcon: NSImage.nosign!
          ) {
            LocalizedView {
              IgnoreSettingsPane()
            }
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.advanced,
            title: localizedPaneTitle(tableName: "AdvancedSettings"),
            toolbarIcon: NSImage.gearshape2!
          ) {
            LocalizedView {
              AdvancedSettingsPane()
            }
          }
        ]
      )
    }
    settingsWindowController?.show()
    settingsWindowController?.window?.orderFrontRegardless()
  }

  @MainActor
  func reloadPreferencesForLocalizationChange() {
    guard settingsWindowController?.window?.isVisible == true else {
      settingsWindowController = nil
      return
    }

    settingsWindowController?.window?.close()
    settingsWindowController = nil

    DispatchQueue.main.async {
      self.openPreferences()
    }
  }

  private func localizedPaneTitle(tableName: String) -> String {
    AppLocalization.shared.localizedString("Title", tableName: tableName)
  }

  func quit() {
    NSApp.terminate(self)
  }
}
