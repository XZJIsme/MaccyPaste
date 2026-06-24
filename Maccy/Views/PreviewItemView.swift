import KeyboardShortcuts
import SwiftUI

struct PreviewItemView: View {
  var item: HistoryItemDecorator
  var fallbackImage: NSImage?
  var onPreviewImageLoaded: (NSImage) -> Void

  @State private var loadedPreviewImage: NSImage?
  @State private var previewLoadFailed = false

  private var displayImage: NSImage? {
    item.previewImage ?? loadedPreviewImage ?? item.thumbnailImage ?? fallbackImage
  }

  @ViewBuilder
  func previewImage(content: () -> some View) -> some View {
    content()
      .aspectRatio(contentMode: .fit)
      .clipShape(.rect(cornerRadius: 5))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if item.hasImage {
        if let image = displayImage {
          previewImage {
            Image(nsImage: image)
              .resizable()
          }
        } else if previewLoadFailed {
          previewImage {
            ZStack {
              Color.gray.opacity(0.3)
                .frame(
                  idealWidth: HistoryItemDecorator.previewImageSize.width,
                  idealHeight: HistoryItemDecorator.previewImageSize.height
                )
              Image(systemName: "photo.badge.exclamationmark")
                .symbolRenderingMode(.multicolor)
                .frame(alignment: .center)
            }
          }
        } else {
          previewImage {
            ZStack {
              Color.gray.opacity(0.3)
                .frame(
                  idealWidth: HistoryItemDecorator.previewImageSize.width,
                  idealHeight: HistoryItemDecorator.previewImageSize.height
                )
              ProgressView()
                .frame(alignment: .center)
            }
          }
        }
      } else {
        ScrollView {
          Text(item.text)
            .font(.body)
        }
      }

      Spacer(minLength: 0)

      Divider()
        .padding(.vertical)

      if let application = item.application {
        HStack(spacing: 3) {
          Text("Application", tableName: "PreviewItemView")
          AppImageView(
            appImage: item.applicationImage,
            size: NSSize(width: 11, height: 11)
          )
          Text(application)
        }
      }

      HStack(spacing: 3) {
        Text("FirstCopyTime", tableName: "PreviewItemView")
        Text(item.item.firstCopiedAt, style: .date)
        Text(item.item.firstCopiedAt, style: .time)
      }

      HStack(spacing: 3) {
        Text("LastCopyTime", tableName: "PreviewItemView")
        Text(item.item.lastCopiedAt, style: .date)
        Text(item.item.lastCopiedAt, style: .time)
      }

      HStack(spacing: 3) {
        Text("NumberOfCopies", tableName: "PreviewItemView")
        Text(String(item.item.numberOfCopies))
      }
    }
    .controlSize(.small)
    .task(id: item.id) {
      guard item.hasImage else { return }
      loadedPreviewImage = nil
      previewLoadFailed = false

      guard let image = await item.asyncGetPreviewImage() else {
        previewLoadFailed = true
        return
      }

      guard !Task.isCancelled else { return }
      loadedPreviewImage = image
      onPreviewImageLoaded(image)
    }
  }
}
