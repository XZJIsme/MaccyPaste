import KeyboardShortcuts
import SwiftUI

struct PreviewItemView: View {
  var item: HistoryItemDecorator
  var fallbackImage: NSImage?
  var onPreviewImageLoaded: (NSImage) -> Void

  @ViewBuilder
  func previewImage(content: () -> some View) -> some View {
    content()
      .aspectRatio(contentMode: .fit)
      .clipShape(.rect(cornerRadius: 5))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if item.hasImage {
        if let image = item.previewImage {
          previewImage {
            Image(nsImage: image)
              .resizable()
          }
          .onAppear {
            onPreviewImageLoaded(image)
          }
        } else {
          AsyncView<NSImage?, _, _> {
            return await item.asyncGetPreviewImage()
          } content: { image in
            if let image = image {
              previewImage {
                Image(nsImage: image)
                  .resizable()
              }
              .onAppear {
                onPreviewImageLoaded(image)
              }
            } else {
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
            }
          } placeholder: {
            if let fallbackImage {
              previewImage {
                Image(nsImage: fallbackImage)
                  .resizable()
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
  }
}
