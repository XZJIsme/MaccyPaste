import AppKit
import CryptoKit
import Defaults
import SwiftUI
import UniformTypeIdentifiers

struct HistoryItemView: View {
  @Bindable var item: HistoryItemDecorator
  var previous: HistoryItemDecorator?
  var next: HistoryItemDecorator?
  var index: Int

  private var visualIndex: Int? {
    if appState.navigator.isMultiSelectInProgress && item.selectionIndex >= 0 {
      return item.selectionIndex
    }
    return nil
  }

  private var selectionAppearance: SelectionAppearance {
    let previousSelected = previous?.isSelected ?? false
    let nextSelected = next?.isSelected ?? false
    switch (previousSelected, nextSelected) {
    case (true, false):
      return .topConnection
    case (false, true):
      return .bottomConnection
    case (true, true):
      return .topBottomConnection
    default:
      return .none
    }
  }

  @Environment(AppState.self) private var appState

  var body: some View {
    ListItemView(
      id: item.id,
      selectionId: item.id,
      appIcon: item.applicationImage,
      image: item.thumbnailImage,
      accessoryImage: item.thumbnailImage != nil ? nil : item.accessoryImage,
      attributedTitle: item.attributedTitle,
      shortcuts: item.shortcuts,
      isSelected: item.isSelected,
      selectionIndex: visualIndex,
      selectionAppearance: selectionAppearance,
      onHoverSelection: {
        appState.navigator.selectWithoutScrolling(item: item)
      }
    ) {
      Text(verbatim: item.title)
    }
    .onAppear {
      item.ensureThumbnailImage()
      if item.isSelected && appState.preview.state.isOpen {
        item.ensurePreviewImage()
      }
      appState.history.loadPreviousUnpinnedPageIfNeeded(around: item)
      appState.history.loadNextUnpinnedPageIfNeeded(around: item)
    }
    .onChange(of: item.isSelected) {
      if item.isSelected && appState.preview.state.isOpen {
        item.ensurePreviewImage()
      }
    }
    .onTapGesture {
      if NSEvent.modifierFlags.contains(.command) && appState.multiSelectionEnabled {
        appState.navigator.addToSelection(item: item)
      } else {
        Task {
          appState.history.select(item)
        }
      }
    }
    .contextMenu {
      if item.item.canSaveAsImage {
        Menu {
          Button("PNG") {
            HistoryItemSavePanel.scheduleSaveImage(item.item, as: .png)
          }

          Button("JPG") {
            HistoryItemSavePanel.scheduleSaveImage(item.item, as: .jpeg)
          }
        } label: {
          Text("context_menu_save_as", tableName: "Localizable")
        }

        Divider()
      } else if item.item.canSaveAsText {
        Menu {
          Button {
            HistoryItemSavePanel.scheduleSaveText(item.item, as: .markdown)
          } label: {
            Text("context_menu_markdown", tableName: "Localizable")
          }

          Button {
            HistoryItemSavePanel.scheduleSaveText(item.item, as: .plainText)
          } label: {
            Text("context_menu_plain_text", tableName: "Localizable")
          }
        } label: {
          Text("context_menu_save_as", tableName: "Localizable")
        }

        Divider()
      }

      Button {
        appState.history.togglePin(item)
      } label: {
        Text(LocalizedStringKey(item.isPinned ? "context_menu_unpin" : "context_menu_pin"), tableName: "Localizable")
      }

      Button(role: .destructive) {
        deleteItem()
      } label: {
        Text("context_menu_delete", tableName: "Localizable")
      }
    }
  }

  @MainActor
  private func deleteItem() {
    let shouldMoveSelection = appState.navigator.leadHistoryItem == item
    let nextItem = shouldMoveSelection
      ? appState.history.visibleItems.nearest(to: item) { $0 != item && !$0.isSelected }
      : nil

    withTransaction(Transaction()) {
      appState.history.delete(item)
      if shouldMoveSelection {
        appState.navigator.select(item: nextItem)
      }
    }
  }
}

private extension HistoryItem {
  var canSaveAsImage: Bool {
    imageData != nil
  }

  var canSaveAsText: Bool {
    saveableText != nil
  }

  var saveableText: String? {
    guard imageData == nil, fileURLs.isEmpty else {
      return nil
    }

    if let text, !text.isEmpty {
      return text
    }

    if let rtf, !rtf.string.isEmpty {
      return rtf.string
    }

    if let html, !html.string.isEmpty {
      return html.string
    }

    return nil
  }
}

@MainActor
private enum HistoryItemSavePanel {
  enum ImageFormat {
    case png
    case jpeg

    var contentType: UTType {
      switch self {
      case .png: return .png
      case .jpeg: return .jpeg
      }
    }

    var fileExtension: String {
      switch self {
      case .png: return "png"
      case .jpeg: return "jpg"
      }
    }

    var bitmapFileType: NSBitmapImageRep.FileType {
      switch self {
      case .png: return .png
      case .jpeg: return .jpeg
      }
    }

    var bitmapProperties: [NSBitmapImageRep.PropertyKey: Any] {
      switch self {
      case .png: return [:]
      case .jpeg: return [.compressionFactor: 0.92]
      }
    }
  }

  enum TextFormat {
    case markdown
    case plainText

    var contentType: UTType {
      switch self {
      case .markdown: return UTType(filenameExtension: fileExtension) ?? .plainText
      case .plainText: return .plainText
      }
    }

    var fileExtension: String {
      switch self {
      case .markdown: return "md"
      case .plainText: return "txt"
      }
    }
  }

  static func scheduleSaveImage(_ item: HistoryItem, as format: ImageFormat) {
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(150))
      saveImage(item, as: format)
    }
  }

  static func scheduleSaveText(_ item: HistoryItem, as format: TextFormat) {
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(150))
      saveText(item, as: format)
    }
  }

  static func saveImage(_ item: HistoryItem, as format: ImageFormat) {
    guard let sourceData = item.imageData else {
      return
    }

    guard let url = destinationURL(
      defaultFileName: defaultFileName(for: sourceData, fileExtension: format.fileExtension),
      allowedContentTypes: [format.contentType]
    ) else {
      return
    }

    guard let data = imageData(from: item, as: format) else {
      return
    }

    write(data, to: url)
  }

  static func saveText(_ item: HistoryItem, as format: TextFormat) {
    guard let text = item.saveableText,
          let data = text.data(using: .utf8) else {
      return
    }

    guard let url = destinationURL(
      defaultFileName: defaultFileName(for: data, fileExtension: format.fileExtension),
      allowedContentTypes: [format.contentType]
    ) else {
      return
    }

    write(data, to: url)
  }

  private static func imageData(from item: HistoryItem, as format: ImageFormat) -> Data? {
    guard let image = item.image,
          let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData) else {
      return nil
    }

    return bitmap.representation(using: format.bitmapFileType, properties: format.bitmapProperties)
  }

  private static func destinationURL(
    defaultFileName: String,
    allowedContentTypes: [UTType]
  ) -> URL? {
    AppState.shared.popup.close()
    NSApp.activate(ignoringOtherApps: true)

    let panel = NSSavePanel()
    panel.canCreateDirectories = true
    panel.isExtensionHidden = false
    panel.nameFieldStringValue = defaultFileName
    panel.allowedContentTypes = allowedContentTypes

    guard panel.runModal() == .OK,
          let url = panel.url else {
      return nil
    }

    return url
  }

  private static func write(_ data: Data, to url: URL) {
    do {
      try data.write(to: url, options: .atomic)
    } catch {
      NSAlert(error: error).runModal()
    }
  }

  private static func defaultFileName(for data: Data, fileExtension: String) -> String {
    let timestamp = timestampFormatter.string(from: Date())
    let md5Prefix = Insecure.MD5.hash(data: data)
      .map { String(format: "%02x", $0) }
      .joined()
      .prefix(8)

    return "MaccyPaste-\(timestamp)-\(md5Prefix).\(fileExtension)"
  }

  private static let timestampFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter
  }()
}
