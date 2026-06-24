import AppKit.NSWorkspace
import Defaults
import Foundation
import ImageIO
import Observation

@Observable
class HistoryItemDecorator: Identifiable, Hashable, HasVisibility {
  static func == (lhs: HistoryItemDecorator, rhs: HistoryItemDecorator) -> Bool {
    return lhs.id == rhs.id
  }

  static var previewImageSize: NSSize { NSScreen.forPopup?.visibleFrame.size ?? NSSize(width: 2048, height: 1536) }
  static var thumbnailImageSize: NSSize { NSSize(width: 340, height: Defaults[.imageMaxHeight]) }

  let id = UUID()

  var title: String = ""
  var attributedTitle: AttributedString?

  var isVisible: Bool = true
  var selectionIndex: Int = -1
  var isSelected: Bool {
    return selectionIndex != -1
  }
  var shortcuts: [KeyShortcut] = []

  var application: String? {
    if item.universalClipboard {
      return "iCloud"
    }

    guard let bundle = item.application,
      let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
    else {
      return nil
    }

    return url.deletingPathExtension().lastPathComponent
  }

  var hasImage: Bool { item.imageData != nil }

  var previewImageGenerationTask: Task<Void, Never>?
  var thumbnailImageGenerationTask: Task<Void, Never>?
  var previewImage: NSImage?
  var thumbnailImage: NSImage?
  var accessoryImage: NSImage?
  var applicationImage: ApplicationImage

  // 10k characters seems to be more than enough on large displays
  var text: String { item.previewableText.shortened(to: 10_000) }

  var isPinned: Bool { item.pin != nil }
  var isUnpinned: Bool { item.pin == nil }

  func hash(into hasher: inout Hasher) {
    // We need to hash title and attributedTitle, so SwiftUI knows it needs to update the view if they chage
    hasher.combine(id)
    hasher.combine(title)
    hasher.combine(attributedTitle)
  }

  private(set) var item: HistoryItem

  init(_ item: HistoryItem) {
    self.item = item
    self.title = item.title
    self.accessoryImage = ColorImage.from(item.title)
    self.applicationImage = ApplicationImageCache.shared.getImage(item: item)

    synchronizeItemTitle()
  }

  @MainActor
  func ensureThumbnailImage() {
    guard let imageData = item.imageData else {
      return
    }
    guard thumbnailImage == nil else {
      return
    }
    guard thumbnailImageGenerationTask == nil else {
      return
    }

    let targetSize = Self.thumbnailImageSize
    thumbnailImageGenerationTask = Task { [weak self, imageData, targetSize] in
      let image = await Self.generateImage(from: imageData, targetSize: targetSize)
      guard let self else { return }
      defer { self.thumbnailImageGenerationTask = nil }
      guard !Task.isCancelled else { return }
      self.thumbnailImage = image
    }
  }

  @MainActor
  func ensurePreviewImage() {
    guard let imageData = item.imageData else {
      return
    }
    guard previewImage == nil else {
      return
    }
    guard previewImageGenerationTask == nil else {
      return
    }

    let targetSize = Self.previewImageSize
    previewImageGenerationTask = Task { [weak self, imageData, targetSize] in
      let image = await Self.generateImage(from: imageData, targetSize: targetSize)
      guard let self else { return }
      defer { self.previewImageGenerationTask = nil }
      guard !Task.isCancelled else { return }
      self.previewImage = image
    }
  }

  @MainActor
  func asyncGetPreviewImage() async -> NSImage? {
    if let image = previewImage {
      return image
    }
    ensurePreviewImage()
    _ = await previewImageGenerationTask?.result
    return previewImage
  }

  @MainActor
  func cleanupImages() {
    thumbnailImageGenerationTask?.cancel()
    previewImageGenerationTask?.cancel()
    thumbnailImageGenerationTask = nil
    previewImageGenerationTask = nil
    thumbnailImage?.recache()
    previewImage?.recache()
    thumbnailImage = nil
    previewImage = nil
  }

  @MainActor
  private func generateThumbnailImage() {
    thumbnailImage = Self.makeImage(from: item.imageData, targetSize: Self.thumbnailImageSize, scale: Self.imageScale)
  }

  @MainActor
  private func generatePreviewImage() {
    previewImage = Self.makeImage(from: item.imageData, targetSize: Self.previewImageSize, scale: Self.imageScale)
  }

  @MainActor
  func sizeImages() {
    generatePreviewImage()
    generateThumbnailImage()
  }

  private static func generateImage(from data: Data, targetSize: NSSize) async -> NSImage? {
    let scale = await MainActor.run { imageScale }
    let generated = await Task.detached(priority: .utility) {
      generateCGImage(from: data, targetSize: targetSize, scale: scale)
    }.value

    guard let generated else {
      return nil
    }

    return NSImage(cgImage: generated.cgImage, size: generated.size)
  }

  @MainActor
  private static var imageScale: CGFloat {
    NSScreen.forPopup?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
  }

  private struct GeneratedImage: @unchecked Sendable {
    let cgImage: CGImage
    let size: NSSize
  }

  private static func makeImage(from data: Data?, targetSize: NSSize, scale: CGFloat) -> NSImage? {
    guard let generated = generateCGImage(from: data, targetSize: targetSize, scale: scale) else {
      return nil
    }

    return NSImage(cgImage: generated.cgImage, size: generated.size)
  }

  private static func generateCGImage(from data: Data?, targetSize: NSSize, scale: CGFloat) -> GeneratedImage? {
    guard let data,
          let source = CGImageSourceCreateWithData(data as CFData, nil) else {
      return nil
    }

    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    let sourceWidth = (properties?[kCGImagePropertyPixelWidth] as? CGFloat) ?? 0
    let sourceHeight = (properties?[kCGImagePropertyPixelHeight] as? CGFloat) ?? 0
    guard sourceWidth > 0, sourceHeight > 0 else {
      return nil
    }

    let targetPixelWidth = targetSize.width * scale
    let targetPixelHeight = targetSize.height * scale
    let ratio = min(targetPixelWidth / sourceWidth, targetPixelHeight / sourceHeight, 1)
    let fittedPixelWidth = max(1, sourceWidth * ratio)
    let fittedPixelHeight = max(1, sourceHeight * ratio)
    let fittedSize = NSSize(width: fittedPixelWidth / scale, height: fittedPixelHeight / scale)
    let maxPixelSize = max(1, Int(ceil(max(fittedPixelWidth, fittedPixelHeight))))
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
    ]

    let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
      ?? CGImageSourceCreateImageAtIndex(source, 0, nil)

    guard let cgImage else { return nil }

    return GeneratedImage(cgImage: cgImage, size: fittedSize)
  }

  func highlight(_ query: String, _ ranges: [Range<String.Index>]) {
    guard !query.isEmpty, !title.isEmpty else {
      attributedTitle = nil
      return
    }

    var attributedString = AttributedString(title.shortened(to: 500))
    for range in ranges {
      if let lowerBound = AttributedString.Index(range.lowerBound, within: attributedString),
         let upperBound = AttributedString.Index(range.upperBound, within: attributedString) {
        switch Defaults[.highlightMatch] {
        case .bold:
          attributedString[lowerBound..<upperBound].font = .bold(.body)()
        case .italic:
          attributedString[lowerBound..<upperBound].font = .italic(.body)()
        case .underline:
          attributedString[lowerBound..<upperBound].underlineStyle = .single
        default:
          attributedString[lowerBound..<upperBound].backgroundColor = .findHighlightColor
          attributedString[lowerBound..<upperBound].foregroundColor = .black
        }
      }
    }

    attributedTitle = attributedString
  }

  @MainActor
  func togglePin() {
    if item.pin != nil {
      item.pin = nil
    } else {
      item.pin = ""
    }
  }

  private func synchronizeItemTitle() {
    _ = withObservationTracking {
      item.title
    } onChange: {
      DispatchQueue.main.async {
        self.title = self.item.title
        self.accessoryImage = ColorImage.from(self.item.title)
        self.synchronizeItemTitle()
      }
    }
  }
}
