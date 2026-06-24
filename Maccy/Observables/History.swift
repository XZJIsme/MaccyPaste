// swiftlint:disable file_length
import AppKit.NSRunningApplication
import Defaults
import Foundation
import Logging
import Observation
import Sauce
import Settings
import SwiftData

@Observable
class History: ItemsContainer { // swiftlint:disable:this type_body_length
  static let shared = History()
  let logger = Logger(label: "org.p0deje.Maccy")

  var items: [HistoryItemDecorator] = []
  var pasteStack: PasteStack?
  var storageStatsVersion = 0

  var pinnedItems: [HistoryItemDecorator] { items.filter(\.isPinned) }
  var unpinnedItems: [HistoryItemDecorator] { items.filter(\.isUnpinned) }

  var searchQuery: String = "" {
    didSet {
      throttler.throttle { [self] in
        updateItems(search.search(string: searchQuery, within: all))

        if searchQuery.isEmpty {
          AppState.shared.navigator.select(item: unpinnedItems.first)
        } else {
          AppState.shared.navigator.highlightFirst()
        }

        AppState.shared.popup.needsResize = true
      }
    }
  }

  var pressedShortcutItem: HistoryItemDecorator? {
    guard let event = NSApp.currentEvent else {
      return nil
    }

    let modifierFlags = event.modifierFlags
      .intersection(.deviceIndependentFlagsMask)
      .subtracting(.capsLock)

    guard HistoryItemAction(modifierFlags) != .unknown else {
      return nil
    }

    let key = Sauce.shared.key(for: Int(event.keyCode))
    return items.first { $0.shortcuts.contains(where: { $0.key == key }) }
  }

  private let search = Search()
  private let sorter = Sorter()
  private let throttler = Throttler(minimumDelay: 0.2)

  @ObservationIgnored
  private var sessionLog: [Int: HistoryItem] = [:]

  @ObservationIgnored
  private var hasLoadedUnpinnedHistory = false

  @ObservationIgnored
  private let unpinnedPageSize = 100

  @ObservationIgnored
  private let initialUnpinnedWindowSize = 200

  @ObservationIgnored
  private let retainedUnpinnedWindowSize = 300

  @ObservationIgnored
  private let pageLoadThreshold = 20

  @ObservationIgnored
  private let duplicateCandidateLimit = 500

  @ObservationIgnored
  private let historyLimitDeleteBatchSize = 500

  @ObservationIgnored
  private var unpinnedStartOffset = 0

  @ObservationIgnored
  private var canLoadNewerUnpinned = false

  @ObservationIgnored
  private var canLoadOlderUnpinned = false

  @ObservationIgnored
  private var isLoadingUnpinnedPage = false

  // The distinction between `all` and `items` is the following:
  // - `all` stores all history items, even the ones that are currently hidden by a search
  // - `items` stores only visible history items, updated during a search
  @ObservationIgnored
  var all: [HistoryItemDecorator] = []

  init() {
    Task { @MainActor in
      try? await loadPinnedItems()
    }

    Task {
      for await _ in Defaults.updates(.pasteByDefault, initial: false) {
        updateShortcuts()
      }
    }

    Task {
      for await _ in Defaults.updates(.sortBy, initial: false) {
        await reloadForCurrentLifecycle()
      }
    }

    Task {
      for await _ in Defaults.updates(.pinTo, initial: false) {
        await reloadForCurrentLifecycle()
      }
    }

    Task {
      for await _ in Defaults.updates(.showSpecialSymbols, initial: false) {
        for item in items {
          await updateTitle(item: item, title: item.item.generateTitle())
        }
      }
    }

    Task {
      for await _ in Defaults.updates(.imageMaxHeight, initial: false) {
        for item in items {
          await item.cleanupImages()
        }
      }
    }
  }

  @MainActor
  func load() async throws {
    try await loadInitialHistoryWindow()
  }

  @MainActor
  func prepareForPopupOpen() async {
    guard !hasLoadedUnpinnedHistory else {
      return
    }

    try? await loadInitialHistoryWindow()
  }

  @MainActor
  func releaseUnpinnedForBackground() {
    throttler.cancel()

    let pinned = all.filter(\.isPinned)
    all.forEach { item in
      if item.isUnpinned {
        cleanup(item)
      } else {
        item.highlight("", [])
      }
    }

    all = pinned
    items = pinned
    hasLoadedUnpinnedHistory = false
    resetUnpinnedPagingState()

    if !searchQuery.isEmpty {
      searchQuery = ""
      throttler.cancel()
    }

    AppState.shared.navigator.selectWithoutScrolling()
    AppState.shared.navigator.scrollTarget = nil

    updateShortcuts()
    AppState.shared.popup.needsResize = true
  }

  @MainActor
  private func loadPinnedItems() async throws {
    let descriptor = FetchDescriptor<HistoryItem>(
      predicate: #Predicate { $0.pin != nil },
      sortBy: sortDescriptors()
    )
    let pinned = try Storage.shared.context.fetch(descriptor).map { HistoryItemDecorator($0) }
    rebuildLoadedItems(pinned: pinned, unpinned: loadedUnpinnedItems)

    updateShortcuts()
  }

  @MainActor
  private func reloadForCurrentLifecycle() async {
    if hasLoadedUnpinnedHistory {
      try? await loadInitialHistoryWindow()
    } else {
      try? await loadPinnedItems()
    }
  }

  @MainActor
  private func loadInitialHistoryWindow() async throws {
    let pinnedDescriptor = FetchDescriptor<HistoryItem>(
      predicate: #Predicate { $0.pin != nil },
      sortBy: sortDescriptors()
    )
    let pinned = try Storage.shared.context.fetch(pinnedDescriptor).map { HistoryItemDecorator($0) }
    let page = try fetchUnpinnedDecorators(offset: 0, limit: initialUnpinnedWindowSize)
    let previousUnpinned = loadedUnpinnedItems

    unpinnedStartOffset = 0
    canLoadNewerUnpinned = false
    canLoadOlderUnpinned = page.hasMore
    hasLoadedUnpinnedHistory = true

    previousUnpinned.forEach(cleanup)
    rebuildLoadedItems(pinned: pinned, unpinned: page.items)
    limitHistorySize(to: Defaults[.size])
    canLoadOlderUnpinned = canLoadMoreUnpinnedWithinLimit && page.hasMore

    updateShortcuts()
    // Ensure that panel size is proper *after* loading all items.
    Task {
      AppState.shared.popup.needsResize = true
    }
  }

  @MainActor
  func loadPreviousUnpinnedPageIfNeeded(around item: HistoryItemDecorator) {
    guard shouldLoadPreviousUnpinnedPage(around: item) else {
      return
    }

    Task { @MainActor in
      await loadNewerUnpinnedPage()
    }
  }

  @MainActor
  func loadNextUnpinnedPageIfNeeded(around item: HistoryItemDecorator) {
    guard shouldLoadNextUnpinnedPage(around: item) else {
      return
    }

    Task { @MainActor in
      await loadOlderUnpinnedPage()
    }
  }

  @MainActor
  private func shouldLoadPreviousUnpinnedPage(around item: HistoryItemDecorator) -> Bool {
    guard searchQuery.isEmpty, canLoadNewerUnpinned, !isLoadingUnpinnedPage else {
      return false
    }
    guard let index = unpinnedItems.firstIndex(of: item) else {
      return false
    }

    return index < pageLoadThreshold
  }

  @MainActor
  private func shouldLoadNextUnpinnedPage(around item: HistoryItemDecorator) -> Bool {
    guard searchQuery.isEmpty,
          canLoadMoreUnpinnedWithinLimit,
          canLoadOlderUnpinned,
          !isLoadingUnpinnedPage else {
      return false
    }
    guard let index = unpinnedItems.firstIndex(of: item) else {
      return false
    }

    return index >= max(unpinnedItems.count - pageLoadThreshold, 0)
  }

  @MainActor
  private func loadOlderUnpinnedPage() async {
    guard !isLoadingUnpinnedPage, canLoadOlderUnpinned else {
      return
    }

    isLoadingUnpinnedPage = true
    defer { isLoadingUnpinnedPage = false }

    let currentPinned = loadedPinnedItems
    var currentUnpinned = loadedUnpinnedItems
    let nextOffset = unpinnedStartOffset + currentUnpinned.count
    guard let page = try? fetchUnpinnedDecorators(offset: nextOffset, limit: unpinnedPageSize) else {
      return
    }

    let newItems = page.items.filter { newItem in
      !currentUnpinned.contains(where: { $0.item == newItem.item })
    }

    guard !newItems.isEmpty else {
      canLoadOlderUnpinned = false
      return
    }

    currentUnpinned.append(contentsOf: newItems)

    if currentUnpinned.count > retainedUnpinnedWindowSize {
      let overflow = currentUnpinned.count - retainedUnpinnedWindowSize
      currentUnpinned.prefix(overflow).forEach(cleanup)
      currentUnpinned.removeFirst(overflow)
      unpinnedStartOffset += overflow
      canLoadNewerUnpinned = true
    }

    canLoadOlderUnpinned = page.hasMore
    rebuildLoadedItems(pinned: currentPinned, unpinned: currentUnpinned)
    updateShortcuts()
    AppState.shared.popup.needsResize = true
  }

  @MainActor
  private func loadNewerUnpinnedPage() async {
    guard !isLoadingUnpinnedPage, canLoadNewerUnpinned else {
      return
    }

    isLoadingUnpinnedPage = true
    defer { isLoadingUnpinnedPage = false }

    let currentPinned = loadedPinnedItems
    var currentUnpinned = loadedUnpinnedItems
    let previousOffset = max(unpinnedStartOffset - unpinnedPageSize, 0)
    let limit = unpinnedStartOffset - previousOffset
    guard limit > 0,
          let page = try? fetchUnpinnedDecorators(offset: previousOffset, limit: limit) else {
      return
    }

    let newItems = page.items.filter { newItem in
      !currentUnpinned.contains(where: { $0.item == newItem.item })
    }

    guard !newItems.isEmpty else {
      canLoadNewerUnpinned = previousOffset > 0
      return
    }

    currentUnpinned.insert(contentsOf: newItems, at: 0)
    unpinnedStartOffset = previousOffset

    if currentUnpinned.count > retainedUnpinnedWindowSize {
      let overflow = currentUnpinned.count - retainedUnpinnedWindowSize
      currentUnpinned.suffix(overflow).forEach(cleanup)
      currentUnpinned.removeLast(overflow)
      canLoadOlderUnpinned = true
    }

    canLoadNewerUnpinned = unpinnedStartOffset > 0
    rebuildLoadedItems(pinned: currentPinned, unpinned: currentUnpinned)
    updateShortcuts()
    AppState.shared.popup.needsResize = true
  }

  @MainActor
  private func fetchUnpinnedDecorators(offset: Int, limit: Int) throws -> (items: [HistoryItemDecorator], hasMore: Bool) {
    var descriptor = FetchDescriptor<HistoryItem>(
      predicate: #Predicate { $0.pin == nil },
      sortBy: sortDescriptors()
    )
    descriptor.fetchLimit = limit + 1
    descriptor.fetchOffset = offset

    let results = try Storage.shared.context.fetch(descriptor)
    let hasMore = results.count > limit
    let items = results.prefix(limit).map { HistoryItemDecorator($0) }

    return (items, hasMore)
  }

  private func sortDescriptors() -> [SortDescriptor<HistoryItem>] {
    switch Defaults[.sortBy] {
    case .firstCopiedAt:
      return [SortDescriptor(\.firstCopiedAt, order: .reverse)]
    case .numberOfCopies:
      return [SortDescriptor(\.numberOfCopies, order: .reverse)]
    default:
      return [SortDescriptor(\.lastCopiedAt, order: .reverse)]
    }
  }

  private var loadedPinnedItems: [HistoryItemDecorator] {
    all.filter(\.isPinned)
  }

  private var loadedUnpinnedItems: [HistoryItemDecorator] {
    all.filter(\.isUnpinned)
  }

  private var canLoadMoreUnpinnedWithinLimit: Bool {
    Defaults[.unlimitedHistory] || loadedUnpinnedItems.count < Defaults[.size]
  }

  private func rebuildLoadedItems(pinned: [HistoryItemDecorator], unpinned: [HistoryItemDecorator]) {
    if Defaults[.pinTo] == .bottom {
      all = unpinned + pinned
    } else {
      all = pinned + unpinned
    }

    items = all
  }

  private func resetUnpinnedPagingState() {
    unpinnedStartOffset = 0
    canLoadNewerUnpinned = false
    canLoadOlderUnpinned = false
    isLoadingUnpinnedPage = false
  }

  @MainActor
  private func limitHistorySize(to maxSize: Int, preserving itemToPreserve: HistoryItem? = nil) {
    guard !Defaults[.unlimitedHistory] else {
      return
    }

    let maxSize = max(maxSize, 0)
    let allowedCount = maxSize + (itemToPreserve == nil ? 0 : 1)
    let countDescriptor = FetchDescriptor<HistoryItem>(
      predicate: #Predicate { $0.pin == nil }
    )
    let currentCount = (try? Storage.shared.context.fetchCount(countDescriptor)) ?? 0
    guard currentCount > allowedCount else {
      return
    }

    var didDeleteItems = false
    let fetchOffset = historyLimitFetchOffset(maxSize: maxSize, preserving: itemToPreserve)
    while true {
      var descriptor = FetchDescriptor<HistoryItem>(
        predicate: #Predicate { $0.pin == nil },
        sortBy: sortDescriptors()
      )
      descriptor.fetchOffset = fetchOffset
      descriptor.fetchLimit = historyLimitDeleteBatchSize

      guard let excess = try? Storage.shared.context.fetch(descriptor),
            !excess.isEmpty else {
        break
      }

      let deletable = excess.filter { candidate in
        guard let itemToPreserve else { return true }
        return candidate !== itemToPreserve
      }
      guard !deletable.isEmpty else {
        break
      }

      removeFromLoadedItems(deletable)
      deletable.forEach(deleteItemAndContents)
      deleteOrphanedContents()
      Storage.shared.context.processPendingChanges()
      didDeleteItems = true
    }

    try? Storage.shared.context.save()
    if didDeleteItems {
      markStorageStatsChanged()
    }
  }

  @MainActor
  private func historyLimitFetchOffset(maxSize: Int, preserving itemToPreserve: HistoryItem?) -> Int {
    guard let itemToPreserve else {
      return maxSize
    }

    var descriptor = FetchDescriptor<HistoryItem>(
      predicate: #Predicate { $0.pin == nil },
      sortBy: sortDescriptors()
    )
    descriptor.fetchLimit = maxSize + 1

    let keptItems = (try? Storage.shared.context.fetch(descriptor)) ?? []
    return keptItems.contains(where: { $0 === itemToPreserve }) ? maxSize + 1 : maxSize
  }

  @MainActor
  private func removeFromLoadedItems(_ historyItems: [HistoryItem]) {
    let itemsToRemove = Set(historyItems.map(ObjectIdentifier.init))

    all.forEach { decorator in
      if itemsToRemove.contains(ObjectIdentifier(decorator.item)) {
        cleanup(decorator)
      }
    }

    all.removeAll { itemsToRemove.contains(ObjectIdentifier($0.item)) }
    items.removeAll { itemsToRemove.contains(ObjectIdentifier($0.item)) }
    sessionLog.removeValues { itemsToRemove.contains(ObjectIdentifier($0)) }
  }

  @MainActor
  func insertIntoStorage(_ item: HistoryItem) throws {
    logger.info("Inserting item with id '\(item.title)'")
    Storage.shared.context.insert(item)
    Storage.shared.context.processPendingChanges()
    try? Storage.shared.context.save()
    markStorageStatsChanged()
  }

  @discardableResult
  @MainActor
  func add(_ item: HistoryItem) -> HistoryItemDecorator {
    if #available(macOS 15.0, *) {
      try? History.shared.insertIntoStorage(item)
    } else {
      // On macOS 14 the history item needs to be inserted into storage directly after creating it.
      // It was already inserted after creation in Clipboard.swift
    }

    var removedItemIndex: Int?
    if let existingHistoryItem = findSimilarItem(item) {
      let modifiedItem = isModified(item)
      let reusesExistingContents = modifiedItem == nil
      if reusesExistingContents {
        item.contents = existingHistoryItem.contents
      }
      item.firstCopiedAt = existingHistoryItem.firstCopiedAt
      item.numberOfCopies += existingHistoryItem.numberOfCopies
      item.pin = existingHistoryItem.pin
      item.title = existingHistoryItem.title
      if !item.fromMaccy {
        item.application = existingHistoryItem.application
      }
      logger.info("Removing duplicate item '\(item.title)'")
      if !reusesExistingContents {
        Array(existingHistoryItem.contents).forEach {
          Storage.shared.context.delete($0)
        }
      }
      Storage.shared.context.delete(existingHistoryItem)
      removedItemIndex = all.firstIndex(where: { $0.item == existingHistoryItem })
      if let removedItemIndex {
        all.remove(at: removedItemIndex)
      }
    } else {
      Task {
        Notifier.notify(body: item.title, sound: .write)
      }
    }

    // Remove exceeding items. Do this after the item is added to avoid removing something
    // if a duplicate was found as then the size already stayed the same.
    limitHistorySize(to: Defaults[.size] - 1, preserving: item)

    sessionLog[Clipboard.shared.changeCount] = item

    var itemDecorator: HistoryItemDecorator
    if item.pin != nil {
      itemDecorator = HistoryItemDecorator(item)
      // Keep pins in the same place.
      if let removedItemIndex {
        all.insert(itemDecorator, at: removedItemIndex)
      }
    } else {
      itemDecorator = HistoryItemDecorator(item)

      guard hasLoadedUnpinnedHistory else {
        return itemDecorator
      }

      let sortedItems = sorter.sort(all.map(\.item) + [item])
      if let index = sortedItems.firstIndex(of: item) {
        all.insert(itemDecorator, at: index)
      }

      items = all
      updateUnpinnedShortcuts()
      AppState.shared.popup.needsResize = true
    }

    return itemDecorator
  }

  @MainActor
  private func withLogging(_ msg: String, _ block: () throws -> Void) rethrows {
    func dataCounts() -> String {
      let historyItemCount = try? Storage.shared.context.fetchCount(FetchDescriptor<HistoryItem>())
      let historyContentCount = try? Storage.shared.context.fetchCount(FetchDescriptor<HistoryItemContent>())
      return "HistoryItem=\(historyItemCount ?? 0) HistoryItemContent=\(historyContentCount ?? 0)"
    }

    logger.info("\(msg) Before: \(dataCounts())")
    try? block()
    logger.info("\(msg) After: \(dataCounts())")
  }

  @MainActor
  func clear() {
    withLogging("Clearing history") {
      all.forEach { item in
        if item.isUnpinned {
          cleanup(item)
        }
      }
      all.removeAll(where: \.isUnpinned)
      sessionLog.removeValues { $0.pin == nil }
      items = all
      resetUnpinnedPagingState()

      try? Storage.shared.context.transaction {
        try? Storage.shared.context.delete(
          model: HistoryItemContent.self,
          where: #Predicate { $0.item?.pin == nil }
        )
        try? Storage.shared.context.delete(
          model: HistoryItem.self,
          where: #Predicate { $0.pin == nil }
        )
        deleteOrphanedContents()
      }
      Storage.shared.context.processPendingChanges()
      try? Storage.shared.context.save()
    }
    markStorageStatsChanged()

    Clipboard.shared.clear()
    AppState.shared.popup.close()
    Task {
      AppState.shared.popup.needsResize = true
    }
  }

  @MainActor
  func clearAll() {
    clearSavedRecords(includePinned: true)

    Clipboard.shared.clear()
    AppState.shared.popup.close()
  }

  @MainActor
  func clearSavedRecords(includePinned: Bool = false) {
    withLogging("Clearing saved history records") {
      let matchingDecorators = all.filter { includePinned || $0.isUnpinned }
      let matchingSet = Set(matchingDecorators.map { ObjectIdentifier($0.item) })

      matchingDecorators.forEach { item in
        cleanup(item)
      }
      all.removeAll { matchingSet.contains(ObjectIdentifier($0.item)) }
      if includePinned {
        sessionLog.removeAll()
      } else {
        sessionLog.removeValues { $0.pin == nil }
      }
      items = all
      resetUnpinnedPagingState()

      if includePinned {
        try? Storage.shared.context.delete(model: HistoryItemContent.self)
        try? Storage.shared.context.delete(model: HistoryItem.self)
      } else {
        try? Storage.shared.context.delete(
          model: HistoryItemContent.self,
          where: #Predicate { $0.item?.pin == nil }
        )
        try? Storage.shared.context.delete(
          model: HistoryItem.self,
          where: #Predicate { $0.pin == nil }
        )
      }
      deleteOrphanedContents()
      Storage.shared.context.processPendingChanges()
      try? Storage.shared.context.save()
    }
    markStorageStatsChanged()

    Task {
      AppState.shared.popup.needsResize = true
    }
  }

  @MainActor
  func clearRecords(types: [NSPasteboard.PasteboardType], before date: Date? = nil, includePinned: Bool = false) {
    guard !types.isEmpty else { return }

    withLogging("Clearing selected history records") {
      let candidates: [HistoryItem]
      if let date {
        let descriptor = FetchDescriptor<HistoryItem>(
          predicate: #Predicate { $0.lastCopiedAt < date }
        )
        candidates = (try? Storage.shared.context.fetch(descriptor)) ?? []
      } else {
        candidates = (try? Storage.shared.context.fetch(FetchDescriptor<HistoryItem>())) ?? []
      }

      let matchingItems = candidates.filter { item in
        (includePinned || item.pin == nil) && item.containsContent(types: types)
      }
      let matchingSet = Set(matchingItems.map(ObjectIdentifier.init))

      all.forEach { item in
        if matchingSet.contains(ObjectIdentifier(item.item)) {
          cleanup(item)
        }
      }
      all.removeAll { matchingSet.contains(ObjectIdentifier($0.item)) }
      items.removeAll { matchingSet.contains(ObjectIdentifier($0.item)) }
      sessionLog.removeValues { matchingSet.contains(ObjectIdentifier($0)) }

      matchingItems.forEach(deleteItemAndContents)
      deleteOrphanedContents()
      Storage.shared.context.processPendingChanges()
      try? Storage.shared.context.save()
    }
    markStorageStatsChanged()

    updateShortcuts()
    Task {
      AppState.shared.popup.needsResize = true
    }
  }

  @MainActor
  func optimizeStorage() throws {
    deleteOrphanedContents()
    Storage.shared.context.processPendingChanges()
    try Storage.shared.context.save()
    try Storage.shared.vacuum()
    markStorageStatsChanged()
  }

  @MainActor
  func delete(_ item: HistoryItemDecorator?) {
    guard let item else { return }

    cleanup(item)
    withLogging("Removing history item") {
      deleteItemAndContents(item.item)
      deleteOrphanedContents()
      Storage.shared.context.processPendingChanges()
      try? Storage.shared.context.save()
    }
    markStorageStatsChanged()

    all.removeAll { $0 == item }
    items.removeAll { $0 == item }
    sessionLog.removeValues { $0 == item.item }

    updateUnpinnedShortcuts()
    Task {
      AppState.shared.popup.needsResize = true
    }
  }

  @MainActor
  private func cleanup(_ item: HistoryItemDecorator) {
    item.cleanupImages()
  }

  @MainActor
  private func deleteOrphanedContents() {
    try? Storage.shared.context.delete(
      model: HistoryItemContent.self,
      where: #Predicate { $0.item == nil }
    )
  }

  @MainActor
  private func deleteItemAndContents(_ item: HistoryItem) {
    Array(item.contents).forEach {
      Storage.shared.context.delete($0)
    }
    Storage.shared.context.delete(item)
  }

  private func currentModifierFlags() -> NSEvent.ModifierFlags {
    return NSApp.currentEvent?.modifierFlags
      .intersection(.deviceIndependentFlagsMask)
      .subtracting([.capsLock, .numericPad, .function]) ?? []
  }

  @MainActor
  func select(_ item: HistoryItemDecorator?) {
    guard let item else {
      return
    }

    let modifierFlags = currentModifierFlags()

    if modifierFlags.isEmpty {
      AppState.shared.popup.close()
      Clipboard.shared.copy(item.item, removeFormatting: Defaults[.removeFormattingByDefault])
      if Defaults[.pasteByDefault] {
        Clipboard.shared.paste()
      }
    } else {
      switch HistoryItemAction(modifierFlags) {
      case .copy:
        AppState.shared.popup.close()
        Clipboard.shared.copy(item.item)
      case .paste:
        AppState.shared.popup.close()
        Clipboard.shared.copy(item.item)
        Clipboard.shared.paste()
      case .pasteWithoutFormatting:
        AppState.shared.popup.close()
        Clipboard.shared.copy(item.item, removeFormatting: true)
        Clipboard.shared.paste()
      case .unknown:
        return
      }
    }

    Task {
      searchQuery = ""
    }
  }

  @MainActor
  func startPasteStack(selection: inout Selection<HistoryItemDecorator>) {
    guard AppState.shared.multiSelectionEnabled else { return }
    guard let item = selection.first else { return }
    PasteStack.initializeIfNeeded()

    let modifierFlags = currentModifierFlags()

    let stack = PasteStack(items: selection.items, modifierFlags: modifierFlags)
    pasteStack = stack

    logger.info("Initialising PasteStack with \(stack.items.count) items")
    logger.info("Copying \(item.item.title) from PasteStack")

    if modifierFlags.isEmpty {
      AppState.shared.popup.close()
      Clipboard.shared.copy(item.item, removeFormatting: Defaults[.removeFormattingByDefault])
    } else {
      switch HistoryItemAction(modifierFlags) {
      case .copy:
        AppState.shared.popup.close()
        Clipboard.shared.copy(item.item)
      case .paste:
        AppState.shared.popup.close()
        Clipboard.shared.copy(item.item)
      case .pasteWithoutFormatting:
        AppState.shared.popup.close()
        Clipboard.shared.copy(item.item, removeFormatting: true)
        Clipboard.shared.paste()
      case .unknown:
        return
      }
    }

    Task {
      searchQuery = ""
    }
  }

  func handlePasteStack() {
    guard let stack = pasteStack else {
      return
    }

    guard let pasted = stack.items.first else {
      pasteStack = nil
      logger.info("PasteStack is empty")
      return
    }

    logger.info("PasteStack pasted \(pasted.item.title)")

    stack.items.removeFirst()

    guard let item = stack.items.first else {
      pasteStack = nil
      logger.info("PasteStack is empty")
      return
    }

    logger.info("Copying \(item.item.title) from PasteStack. \(stack.items.count) items remaining in stack.")

    Task {
      if stack.modifierFlags.isEmpty {
        await Clipboard.shared.copy(item.item, removeFormatting: Defaults[.removeFormattingByDefault])
      } else {
        switch HistoryItemAction(stack.modifierFlags) {
        case .copy:
          await Clipboard.shared.copy(item.item)
        case .paste:
          await Clipboard.shared.copy(item.item)
        case .pasteWithoutFormatting:
          await Clipboard.shared.copy(item.item, removeFormatting: true)
        case .unknown:
          return
        }
      }
    }
  }

  func interruptPasteStack() {
    guard pasteStack != nil else {
      return
    }
    logger.info("Interrupting PasteStack")
    pasteStack = nil
  }

  @MainActor
  func togglePin(_ item: HistoryItemDecorator?) {
    guard let item else { return }

    let wasPinned = item.isPinned
    item.togglePin()
    markStorageStatsChanged()

    if wasPinned, item.isUnpinned {
      limitHistorySize(to: Defaults[.size] - 1, preserving: item.item)
    }

    let sortedItems = sorter.sort(all.map(\.item))
    if let currentIndex = all.firstIndex(of: item),
       let newIndex = sortedItems.firstIndex(of: item.item) {
      all.remove(at: currentIndex)
      all.insert(item, at: newIndex)
    }

    items = all

    searchQuery = ""
    updateUnpinnedShortcuts()
    if item.isUnpinned {
      AppState.shared.navigator.scrollTarget = item.id
    }
  }

  @MainActor
  private func markStorageStatsChanged() {
    storageStatsVersion += 1
  }

  @MainActor
  private func findSimilarItem(_ item: HistoryItem) -> HistoryItem? {
    let duplicates = duplicateCandidates().filter { candidate in
      candidate !== item && (candidate == item || candidate.supersedes(item))
    }

    return duplicates.first ?? isModified(item)
  }

  @MainActor
  private func duplicateCandidates() -> [HistoryItem] {
    var descriptor = FetchDescriptor<HistoryItem>(
      sortBy: [SortDescriptor(\.lastCopiedAt, order: .reverse)]
    )
    descriptor.fetchLimit = duplicateCandidateLimit

    let recentItems = (try? Storage.shared.context.fetch(descriptor)) ?? []
    return all.map(\.item) + Array(sessionLog.values) + recentItems
  }

  private func isModified(_ item: HistoryItem) -> HistoryItem? {
    if let modified = item.modified, sessionLog.keys.contains(modified) {
      return sessionLog[modified]
    }

    return nil
  }

  private func updateItems(_ newItems: [Search.SearchResult]) {
    items = newItems.map { result in
      let item = result.object
      item.highlight(searchQuery, result.ranges)

      return item
    }

    updateUnpinnedShortcuts()
  }

  private func updateShortcuts() {
    for item in pinnedItems {
      item.shortcuts = []
    }

    updateUnpinnedShortcuts()
  }

  @MainActor
  private func updateTitle(item: HistoryItemDecorator, title: String) {
    item.title = title
    item.item.title = title
  }

  private func updateUnpinnedShortcuts() {
    let visibleUnpinnedItems = unpinnedItems.filter(\.isVisible)
    for item in visibleUnpinnedItems {
      item.shortcuts = []
    }

    var index = 1
    for item in visibleUnpinnedItems.prefix(9) {
      item.shortcuts = KeyShortcut.create(character: String(index))
      index += 1
    }
  }
}
