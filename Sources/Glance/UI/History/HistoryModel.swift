import Foundation
import Combine

/// Backing model for the history browser: fetches entries, tracks selection,
/// performs confirmed deletions, and re-runs translations on demand.
@MainActor
final class HistoryModel: ObservableObject {
    @Published private(set) var entries: [HistoryEntry] = []
    @Published private(set) var translatingIDs: Set<UUID> = []
    @Published var selectedID: UUID?
    @Published var oldestFirst = false {
        didSet { reload() }
    }
    @Published var searchQuery: String = "" {
        didSet { debounceReload() }
    }
    @Published var statusFilter: SnapshotRecord.Status? = nil {
        didSet { reload() }
    }
    /// Set by row context menu; consumed by the root view's confirm dialog.
    @Published var pendingDelete: HistoryEntry?
    @Published var showDeleteRangeSheet = false

    private let historyStore: HistoryStore
    let settings: SettingsStore
    private var searchDebounceTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(historyStore: HistoryStore, settings: SettingsStore) {
        self.historyStore = historyStore
        self.settings = settings
        HistoryImagePathBridge.shared.store = historyStore

        NotificationCenter.default.publisher(for: .historyStoreDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reload()
            }
            .store(in: &cancellables)

        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    var selectedEntry: HistoryEntry? {
        entries.first { $0.id == selectedID }
    }

    func selectPrevious() {
        guard !entries.isEmpty else { return }
        guard let currentID = selectedID,
              let index = entries.firstIndex(where: { $0.id == currentID }) else {
            selectedID = entries.first?.id
            return
        }
        if index > 0 {
            selectedID = entries[index - 1].id
        }
    }

    func selectNext() {
        guard !entries.isEmpty else { return }
        guard let currentID = selectedID,
              let index = entries.firstIndex(where: { $0.id == currentID }) else {
            selectedID = entries.first?.id
            return
        }
        if index + 1 < entries.count {
            selectedID = entries[index + 1].id
        }
    }

    func isTranslating(_ id: UUID) -> Bool {
        translatingIDs.contains(id)
    }

    private func debounceReload() {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000) // 150ms debounce
            if !Task.isCancelled {
                self.reload()
            }
        }
    }

    func reload() {
        do {
            let previousSelected = selectedID
            entries = try historyStore.search(
                query: searchQuery,
                status: statusFilter,
                limit: 500,
                oldestFirst: oldestFirst
            ).map(HistoryEntry.init)

            if let prev = previousSelected, entries.contains(where: { $0.id == prev }) {
                selectedID = prev
            } else {
                selectedID = entries.first?.id
            }
        } catch {
            NSLog("Glance: failed to load history: \(error)")
            entries = []
        }
    }

    func selectSnapshot(id: UUID) {
        // Clear search and filters to ensure target is visible
        searchQuery = ""
        statusFilter = nil
        reload()
        selectedID = id
    }

    func requestDelete(_ entry: HistoryEntry) {
        do {
            try historyStore.delete(id: entry.id)
        } catch {
            NSLog("Glance: failed to delete snapshot \(entry.id): \(error)")
        }
        reload()
    }

    func countAndSize(since: Date, until: Date) -> (count: Int, totalBytes: Int64) {
        (try? historyStore.countAndSize(since: since, until: until)) ?? (0, 0)
    }

    func deleteRange(since: Date, until: Date) {
        do {
            let count = try historyStore.deleteRange(since: since, until: until)
            NSLog("Glance: deleted \(count) snapshots in date range")
        } catch {
            NSLog("Glance: failed to delete date range: \(error)")
        }
        reload()
    }

    // MARK: - Re-translate (M3.3)

    /// Re-runs translation for an existing snapshot using the ACTIVE endpoint.
    /// Works on pending, failed, empty AND ok rows — "Translate Again".
    func retranslate(_ entry: HistoryEntry) {
        guard !translatingIDs.contains(entry.id) else { return }
        translatingIDs.insert(entry.id)

        Task { @MainActor in
            defer { translatingIDs.remove(entry.id) }
            await runTranslation(for: entry.record)
            reload()
        }
    }

    private func runTranslation(for record: SnapshotRecord) async {
        let fileURL = historyStore.rootDirectory.appendingPathComponent(record.imagePath)
        guard let originalPNG = try? Data(contentsOf: fileURL),
              let originalImage = ScreenCaptureService.cgImage(fromPNGData: originalPNG) else {
            markFailed(record, message: "Could not read the saved image from disk.")
            return
        }

        guard let endpoint = settings.activeEndpoint() else {
            markFailed(record, message: "No translation endpoint configured — add one in Settings.")
            return
        }
        let apiKey = settings.key(for: endpoint.id) ?? ""

        let downscaled = ImageDownscaler.downscaleIfOversized(originalImage)
        guard let uploadPNG = ScreenCaptureService.pngData(from: downscaled) else {
            markFailed(record, message: "Could not encode the image for upload.")
            return
        }

        let outcome = await LLMClient.translate(pngData: uploadPNG,
                                                targetLanguage: settings.targetLanguage,
                                                tone: settings.translationTone,
                                                baseURL: endpoint.baseURL,
                                                apiKey: apiKey,
                                                model: endpoint.model)

        do {
            switch outcome {
            case .ok(let items, let latency):
                try apply(.ok, items: items, record: record, endpoint: endpoint,
                          latency: latency, error: nil)
            case .empty(let latency):
                try apply(.empty, items: [], record: record, endpoint: endpoint,
                          latency: latency, error: nil)
            case .failure(let message, let latency):
                try apply(.failed, items: [], record: record, endpoint: endpoint,
                          latency: latency, error: message)
            }
        } catch {
            NSLog("Glance: failed to persist re-translation for \(record.id): \(error)")
        }
    }

    private func markFailed(_ record: SnapshotRecord, message: String) {
        try? apply(.failed, items: [], record: record, endpoint: nil,
                   latency: nil, error: message)
    }

    private func apply(_ status: SnapshotRecord.Status,
                       items: [TranslationItem],
                       record: SnapshotRecord,
                       endpoint: EndpointConfig?,
                       latency: Int?,
                       error: String?) throws {
        try historyStore.applyTranslation(id: record.id,
                                          status: status,
                                          items: items,
                                          endpointID: endpoint?.id,
                                          endpointLabel: endpoint?.label,
                                          model: endpoint?.model,
                                          latencyMs: latency,
                                          errorMessage: error)
    }
}
