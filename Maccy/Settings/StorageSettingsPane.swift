import SwiftUI
import Defaults
import Settings

struct StorageSettingsPane: View {
  @Observable
  class ViewModel {
    var saveFiles = false {
      didSet {
        Defaults.withoutPropagation {
          if saveFiles {
            Defaults[.enabledPasteboardTypes].formUnion(StorageType.files.types)
          } else {
            Defaults[.enabledPasteboardTypes].subtract(StorageType.files.types)
          }
        }
      }
    }

    var saveImages = false {
      didSet {
        Defaults.withoutPropagation {
          if saveImages {
            Defaults[.enabledPasteboardTypes].formUnion(StorageType.images.types)
          } else {
            Defaults[.enabledPasteboardTypes].subtract(StorageType.images.types)
          }
        }
      }
    }

    var saveText = false {
      didSet {
        Defaults.withoutPropagation {
          if saveText {
            Defaults[.enabledPasteboardTypes].formUnion(StorageType.text.types)
          } else {
            Defaults[.enabledPasteboardTypes].subtract(StorageType.text.types)
          }
        }
      }
    }

    private var observer: Defaults.Observation?

    init() {
      observer = Defaults.observe(.enabledPasteboardTypes) { change in
        self.saveFiles = change.newValue.isSuperset(of: StorageType.files.types)
        self.saveImages = change.newValue.isSuperset(of: StorageType.images.types)
        self.saveText = change.newValue.isSuperset(of: StorageType.text.types)
      }
    }

    deinit {
      observer?.invalidate()
    }
  }

  @Default(.size) private var size
  @Default(.unlimitedHistory) private var unlimitedHistory
  @Default(.sortBy) private var sortBy

  @State private var viewModel = ViewModel()
  @State private var storageSize = Storage.shared.size
  @State private var historyCounts = Storage.shared.historyCounts

  private let sizeFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.allowsFloats = false
    return formatter
  }()

  private var storageUsageSummary: String {
    let countSummary = String(
      format: AppLocalization.shared.localizedString("HistoryCountSummary", tableName: "StorageSettings"),
      historyCounts.total,
      historyCounts.pinned,
      historyCounts.unpinned
    )

    guard !storageSize.isEmpty else {
      return countSummary
    }

    return "\(storageSize)  \(countSummary)"
  }

  private var limitedSize: Binding<Int> {
    Binding(
      get: { size },
      set: { size = min(max($0, 1), 9999) }
    )
  }

  var body: some View {
    Settings.Container(contentWidth: 450) {
      Settings.Section(
        bottomDivider: true,
        label: { Text("Save", tableName: "StorageSettings") }
      ) {
        Toggle(
          isOn: $viewModel.saveFiles,
          label: { Text("Files", tableName: "StorageSettings") }
        )
        Toggle(
          isOn: $viewModel.saveImages,
          label: { Text("Images", tableName: "StorageSettings") }
        )
        Toggle(
          isOn: $viewModel.saveText,
          label: { Text("Text", tableName: "StorageSettings") }
        )
        Text("SaveDescription", tableName: "StorageSettings")
          .controlSize(.small)
          .foregroundStyle(.gray)
      }

      Settings.Section(label: { Text("Size", tableName: "StorageSettings") }) {
        HStack {
          HStack {
            TextField("", value: limitedSize, formatter: sizeFormatter)
              .frame(width: 80)
              .help(Text("SizeTooltip", tableName: "StorageSettings"))
            Stepper("", value: limitedSize, in: 1...9999)
              .labelsHidden()
          }
          .disabled(unlimitedHistory)
          Defaults.Toggle(key: .unlimitedHistory) {
            Text("UnlimitedHistory", tableName: "StorageSettings")
          }
          .help(Text("UnlimitedHistoryTooltip", tableName: "StorageSettings"))
          Text(storageUsageSummary)
            .controlSize(.small)
            .foregroundStyle(.gray)
            .fixedSize(horizontal: false, vertical: true)
            .help(Text("CurrentSizeTooltip", tableName: "StorageSettings"))
            .onAppear {
              refreshStorageUsage()
            }
        }
      }

      Settings.Section(label: { Text("SortBy", tableName: "StorageSettings") }) {
        Picker("", selection: $sortBy) {
          ForEach(Sorter.By.allCases) { mode in
            Text(mode.description)
          }
        }
        .labelsHidden()
        .frame(width: 160, alignment: .leading)
        .help(Text("SortByTooltip", tableName: "StorageSettings"))
      }
    }
  }

  private func refreshStorageUsage() {
    storageSize = Storage.shared.size
    historyCounts = Storage.shared.historyCounts
  }
}

#Preview {
  StorageSettingsPane()
    .environment(\.locale, .init(identifier: "en"))
}
