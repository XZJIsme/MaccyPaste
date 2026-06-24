import AppKit
import Defaults
import Settings
import SwiftUI

struct StorageSettingsPane: View {
  @Environment(AppState.self) private var appState

  private enum CleanupSheet: String, Identifiable {
    case clearAll
    case advanced
    case optimize

    var id: String { rawValue }
  }

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
  @State private var cleanupSheet: CleanupSheet?
  @State private var confirmsAdvancedCleanup = false
  @State private var cleanupBeforeDate = Date()
  @State private var cleansFiles = true
  @State private var cleansImages = true
  @State private var cleansText = false
  @State private var localization = AppLocalization.shared
  @State private var includesPinnedInClearAll = false
  @State private var includesPinnedInAdvancedCleanup = false
  @State private var optimizationResult: String?

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

  private var cleanupDateFormatter: DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = localization.locale
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
  }

  private var selectedCleanupTypes: [NSPasteboard.PasteboardType] {
    var types: [NSPasteboard.PasteboardType] = []
    if cleansFiles {
      types.append(contentsOf: StorageType.files.types)
    }
    if cleansImages {
      types.append(contentsOf: StorageType.images.types)
    }
    if cleansText {
      types.append(contentsOf: StorageType.text.types)
    }
    return types
  }

  private var selectedCleanupTypeNames: String {
    var names: [String] = []
    if cleansFiles {
      names.append(AppLocalization.shared.localizedString("Files", tableName: "StorageSettings"))
    }
    if cleansImages {
      names.append(AppLocalization.shared.localizedString("Images", tableName: "StorageSettings"))
    }
    if cleansText {
      names.append(AppLocalization.shared.localizedString("Text", tableName: "StorageSettings"))
    }
    return names.joined(separator: AppLocalization.shared.localizedString("ListSeparator", tableName: "StorageSettings"))
  }

  private var cleanupDateStart: Date {
    Calendar.current.startOfDay(for: cleanupBeforeDate)
  }

  private var advancedCleanupConfirmationMessage: String {
    let key = includesPinnedInAdvancedCleanup
      ? "AdvancedCleanupConfirmationIncludingPinned"
      : "AdvancedCleanupConfirmationExcludingPinned"
    return String(
      format: AppLocalization.shared.localizedString(key, tableName: "StorageSettings"),
      selectedCleanupTypeNames,
      cleanupDateFormatter.string(from: cleanupDateStart)
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
        VStack(alignment: .leading) {
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
          }
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

      Settings.Section(label: { Text("Cleanup", tableName: "StorageSettings") }) {
        HStack {
          Button(role: .destructive) {
            cleanupSheet = .clearAll
          } label: {
            Text("ClearAll", tableName: "StorageSettings")
          }

          Button {
            cleanupSheet = .advanced
          } label: {
            Text("AdvancedCleanup", tableName: "StorageSettings")
          }

          Button {
            cleanupSheet = .optimize
          } label: {
            Text("OptimizeDatabase", tableName: "StorageSettings")
          }
        }
      }
    }
    .sheet(item: $cleanupSheet) { sheet in
      cleanupSheetContent(sheet)
        .environment(\.locale, localization.locale)
        .onDisappear {
          if cleanupSheet == nil {
            resetTransientCleanupState()
          }
        }
    }
    .task(id: appState.history.storageStatsVersion) {
      refreshStorageUsage()
    }
  }

  @ViewBuilder
  private func cleanupSheetContent(_ sheet: CleanupSheet) -> some View {
    switch sheet {
    case .clearAll:
      clearAllCleanupSheet
    case .advanced:
      advancedCleanupSheet
    case .optimize:
      optimizeDatabaseSheet
    }
  }

  private var clearAllCleanupSheet: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("ClearAll", tableName: "StorageSettings")
        .font(.headline)

      Text("ClearAllDescription", tableName: "StorageSettings")
        .foregroundStyle(.gray)

      Toggle(isOn: $includesPinnedInClearAll) {
        Text("IncludePinnedItems", tableName: "StorageSettings")
      }

      HStack {
        Spacer()
        Button {
          cleanupSheet = nil
        } label: {
          Text("Cancel", tableName: "StorageSettings")
        }
        Button(role: .destructive) {
          AppState.shared.history.clearSavedRecords(includePinned: includesPinnedInClearAll)
          refreshStorageUsage()
          cleanupSheet = nil
        } label: {
          Text("ClearAll", tableName: "StorageSettings")
        }
      }
    }
    .padding(24)
    .frame(width: 400)
  }

  private var advancedCleanupSheet: some View {
    Group {
      if confirmsAdvancedCleanup {
        advancedCleanupConfirmationSheet
      } else {
        advancedCleanupOptionsSheet
      }
    }
  }

  private var advancedCleanupOptionsSheet: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("AdvancedCleanup", tableName: "StorageSettings")
        .font(.headline)

      Text("AdvancedCleanupDescription", tableName: "StorageSettings")
        .foregroundStyle(.gray)

      VStack(alignment: .leading) {
        Toggle(isOn: $cleansFiles) {
          Text("Files", tableName: "StorageSettings")
        }
        Toggle(isOn: $cleansImages) {
          Text("Images", tableName: "StorageSettings")
        }
        Toggle(isOn: $cleansText) {
          Text("Text", tableName: "StorageSettings")
        }
      }

      DatePicker(
        selection: $cleanupBeforeDate,
        displayedComponents: .date
      ) {
        Text("CleanupBefore", tableName: "StorageSettings")
      }
      .frame(width: 280)

      Toggle(isOn: $includesPinnedInAdvancedCleanup) {
        Text("IncludePinnedItems", tableName: "StorageSettings")
      }

      HStack {
        Spacer()
        Button {
          cleanupSheet = nil
        } label: {
          Text("Cancel", tableName: "StorageSettings")
        }
        Button(role: .destructive) {
          confirmsAdvancedCleanup = true
        } label: {
          Text("Clear", tableName: "StorageSettings")
        }
        .disabled(selectedCleanupTypes.isEmpty)
      }
    }
    .padding(24)
    .frame(width: 380)
  }

  private var advancedCleanupConfirmationSheet: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("ConfirmAdvancedCleanup", tableName: "StorageSettings")
        .font(.headline)

      Text(advancedCleanupConfirmationMessage)
        .foregroundStyle(.gray)
        .fixedSize(horizontal: false, vertical: true)

      HStack {
        Spacer()
        Button {
          confirmsAdvancedCleanup = false
        } label: {
          Text("Back", tableName: "StorageSettings")
        }
        Button(role: .destructive) {
          AppState.shared.history.clearRecords(
            types: selectedCleanupTypes,
            before: cleanupDateStart,
            includePinned: includesPinnedInAdvancedCleanup
          )
          refreshStorageUsage()
          cleanupSheet = nil
        } label: {
          Text("ConfirmCleanup", tableName: "StorageSettings")
        }
      }
    }
    .padding(24)
    .frame(width: 420)
  }

  private var optimizeDatabaseSheet: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("OptimizeDatabase", tableName: "StorageSettings")
        .font(.headline)

      Text("OptimizeDatabaseDescription", tableName: "StorageSettings")
        .foregroundStyle(.gray)

      if let optimizationResult {
        Text(optimizationResult)
          .foregroundStyle(.gray)
          .fixedSize(horizontal: false, vertical: true)
      }

      HStack {
        Spacer()
        Button {
          cleanupSheet = nil
        } label: {
          Text(optimizationResult == nil ? "Cancel" : "Close", tableName: "StorageSettings")
        }
        if optimizationResult == nil {
          Button(role: .destructive) {
            optimizeDatabase()
          } label: {
            Text("StartOptimization", tableName: "StorageSettings")
          }
        }
      }
    }
    .padding(24)
    .frame(width: 440)
  }

  private func refreshStorageUsage() {
    storageSize = Storage.shared.size
    historyCounts = Storage.shared.historyCounts
  }

  private func resetTransientCleanupState() {
    confirmsAdvancedCleanup = false
    includesPinnedInClearAll = false
    includesPinnedInAdvancedCleanup = false
    optimizationResult = nil
  }

  private func optimizeDatabase() {
    do {
      let before = Storage.shared.size
      try AppState.shared.history.optimizeStorage()
      refreshStorageUsage()
      optimizationResult = String(
        format: AppLocalization.shared.localizedString("OptimizationSucceeded", tableName: "StorageSettings"),
        before,
        storageSize
      )
    } catch {
      optimizationResult = String(
        format: AppLocalization.shared.localizedString("OptimizationFailed", tableName: "StorageSettings"),
        error.localizedDescription
      )
    }
  }
}

#Preview {
  StorageSettingsPane()
    .environment(AppState.shared)
    .environment(\.locale, .init(identifier: "en"))
}
