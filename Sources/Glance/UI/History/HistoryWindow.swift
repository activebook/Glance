import AppKit
import SwiftUI
import AVFoundation

/// History browser: master list of saved pairs + detail with zoomable screenshot,
/// prominent translation, search, status filtering, and bulk date-range management.
final class HistoryWindowController: NSWindowController, NSWindowDelegate {
    let model: HistoryModel
    var onShowSettings: (() -> Void)? {
        didSet {
            // Re-bind to hosting view
            if let window = self.window {
                window.contentView = NSHostingView(
                    rootView: HistoryView(model: model, onShowSettings: onShowSettings)
                        .ignoresSafeArea(edges: .top)
                )
            }
        }
    }

    init(historyStore: HistoryStore, settings: SettingsStore) {
        let model = HistoryModel(historyStore: historyStore, settings: settings)
        self.model = model

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Glance"
        window.titleVisibility = .hidden
        window.minSize = NSSize(width: 980, height: 640)
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unified
        window.contentView = NSHostingView(
            rootView: HistoryView(model: model, onShowSettings: nil)
                .ignoresSafeArea(edges: .top)
        )
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("GlanceMainWindow")
        if !window.setFrameUsingName("GlanceMainWindow") {
            window.center()
        }
        super.init(window: window)
        window.delegate = self

        // Restore maximized / zoomed state if previously zoomed
        if UserDefaults.standard.bool(forKey: "GlanceMainWindow_IsZoomed") {
            DispatchQueue.main.async { [weak window] in
                if let window, !window.isZoomed {
                    window.zoom(nil)
                }
            }
        }
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = self.window else { return }
        UserDefaults.standard.set(window.isZoomed, forKey: "GlanceMainWindow_IsZoomed")
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = self.window else { return }
        UserDefaults.standard.set(window.isZoomed, forKey: "GlanceMainWindow_IsZoomed")
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        guard let window = self.window else { return }
        UserDefaults.standard.set(window.isZoomed, forKey: "GlanceMainWindow_IsZoomed")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func selectSnapshot(id: UUID) {
        model.selectSnapshot(id: id)
    }
}

struct HistoryEntry: Identifiable {
    let record: SnapshotRecord
    var id: UUID { record.id }

    var image: NSImage? {
        HistoryImagePathBridge.shared.resolve(record.imagePath)
    }
}

/// Lets views resolve relative image paths without passing the store around.
final class HistoryImagePathBridge {
    static let shared = HistoryImagePathBridge()
    weak var store: HistoryStore?

    func resolve(_ relativePath: String) -> NSImage? {
        guard let store, !relativePath.isEmpty else { return nil }
        return NSImage(contentsOf: store.rootDirectory.appendingPathComponent(relativePath))
    }
}

// MARK: - Status presentation (shared)

extension SnapshotRecord.Status {
    var label: String {
        switch self {
        case .pending: return "Pending"
        case .ok: return "Translated"
        case .empty: return "No text"
        case .failed: return "Failed"
        }
    }

    var tint: Color {
        switch self {
        case .pending: return .orange
        case .ok: return .green
        case .empty: return .secondary
        case .failed: return .red
        }
    }
}

// MARK: - Root view

struct HistoryView: View {
    @ObservedObject var model: HistoryModel
    @ObservedObject private var updateManager = UpdateManager.shared
    var onShowSettings: (() -> Void)? = nil

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailPane
        }
        .navigationSplitViewStyle(.balanced)
        .navigationSplitViewColumnWidth(min: 340, ideal: 400, max: 540)
        .searchable(text: $model.searchQuery, placement: .toolbar, prompt: "Search translation or source text…")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    model.showDeleteRangeSheet = true
                } label: {
                    Label("Delete by Date…", systemImage: "calendar.badge.minus")
                }
                .help("Delete snapshots within a date range")
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    onShowSettings?()
                } label: {
                    Label("Settings…", systemImage: "gearshape")
                }
                .help("Open Glance Settings (⌘,)")
            }
        }
        .sheet(isPresented: $model.showDeleteRangeSheet) {
            DeleteByDateSheet(model: model)
        }
        .sheet(isPresented: $updateManager.showUpdateModal) {
            UpdateModalView()
        }
        .onAppear { model.reload() }
        .confirmationDialog(
            "Delete “\(model.pendingDelete?.record.translatedText.prefix(30) ?? "snapshot")…”?",
            isPresented: Binding(
                get: { model.pendingDelete != nil },
                set: { if !$0 { model.pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Snapshot", role: .destructive) {
                if let entry = model.pendingDelete { model.requestDelete(entry) }
                model.pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { model.pendingDelete = nil }
        } message: {
            Text("The image file will also be removed. This cannot be undone.")
        }
    }

    // MARK: - Sidebar list

    private var sidebar: some View {
        VStack(spacing: 0) {
            // Header: Glance brand + item count + sort menu
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    if let appIcon = NSApp.applicationIconImage ?? NSImage(named: NSImage.applicationIconName) {
                        Image(nsImage: appIcon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 28, height: 28)
                    }

                    Text("Glance")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    VersionPillView()
                }
                .layoutPriority(1)

                Spacer(minLength: 4)

                Menu {
                    Button {
                        model.oldestFirst = false
                    } label: {
                        HStack {
                            Text("Newest First")
                            if !model.oldestFirst {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    Button {
                        model.oldestFirst = true
                    } label: {
                        HStack {
                            Text("Oldest First")
                            if model.oldestFirst {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: model.oldestFirst ? "arrow.up" : "arrow.down")
                            .font(.system(size: 10, weight: .bold))
                        Text(model.oldestFirst ? "Oldest" : "Newest")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
                }
                .menuStyle(.borderlessButton)
                .help("Change sort order (Newest / Oldest first)")
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Status segmented filter
            Picker("", selection: $model.statusFilter) {
                Text("All").tag(SnapshotRecord.Status?.none)
                ForEach([SnapshotRecord.Status.ok, .failed, .empty, .pending], id: \.self) { status in
                    Text(status.label).tag(SnapshotRecord.Status?.some(status))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
            .help("Filter snapshots by status (All, Translated, Failed, Empty, Pending)")

            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)

            if model.entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: model.searchQuery.isEmpty ? "tray" : "magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text(model.searchQuery.isEmpty ? "No snapshots saved yet" : "No matching snapshots")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    if model.settings.endpoints.isEmpty {
                        VStack(spacing: 8) {
                            Text("No AI Service configured yet.")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            Button("Configure AI Service") {
                                onShowSettings?()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                        .padding(.top, 4)
                    } else if model.searchQuery.isEmpty {
                        Text("Capture your screen with \(model.settings.hotkey.displayString) or \(model.settings.repeatHotkey.displayString) to begin translating.")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $model.selectedID) {
                    ForEach(model.entries) { entry in
                        sidebarRow(for: entry)
                            .tag(entry.id)
                            .contextMenu {
                                Button("Copy Translation") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(entry.record.translatedText, forType: .string)
                                }
                                if let image = entry.image {
                                    Button("Copy Image") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.writeObjects([image])
                                    }
                                }
                                Button("Translate Again") { model.retranslate(entry) }
                                    .disabled(model.isTranslating(entry.id))
                                Divider()
                                Button("Delete…", role: .destructive) {
                                    model.pendingDelete = entry
                                }
                            }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }

            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)

            HStack {
                Text(model.entries.count == 1 ? "1 Snapshot" : "\(model.entries.count) Snapshots")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if !model.entries.isEmpty {
                    Text("\(model.settings.hotkey.displayString) to capture")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color.clear)
        }
    }

    private func sidebarRow(for entry: HistoryEntry) -> some View {
        HStack(spacing: 12) {
            // High-Contrast Snapshot Thumbnail with aspect ratio preservation
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(width: 96, height: 64)

                if let image = entry.image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 92, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 18))
                        .foregroundStyle(.tertiary)
                }

                StatusDot(status: entry.record.status)
                    .offset(x: 2, y: 2)
            }
            .frame(width: 96, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75)
            )

            // Content Snippet & Reference Metadata
            VStack(alignment: .leading, spacing: 3) {
                Text(snippetTitle(for: entry.record))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let sub = snippetSubtitle(for: entry.record), !sub.isEmpty {
                    Text(sub)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text(entry.record.createdAt.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text("•")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)

                    Text(entry.record.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func snippetTitle(for record: SnapshotRecord) -> String {
        record.snippetTitle
    }

    private func snippetSubtitle(for record: SnapshotRecord) -> String? {
        record.snippetSubtitle
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "camera.on.rectangle")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text(model.searchQuery.isEmpty && model.statusFilter == nil ? "No snapshots yet" : "No matching snapshots")
                .font(.system(size: 14, weight: .medium))
            Text(model.searchQuery.isEmpty ? "Press \(model.settings.hotkey.displayString) to capture and translate your first region." : "Try adjusting your search query or filter.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    @ViewBuilder
    private var detailPane: some View {
        if let entry = model.selectedEntry {
            HistoryDetailView(entry: entry, model: model)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 32))
                    .foregroundStyle(.tertiary)
                Text("Select a snapshot")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Shared small components

struct StatusDot: View {
    let status: SnapshotRecord.Status

    var body: some View {
        Circle()
            .fill(status.tint)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5)
            )
            .shadow(color: status.tint.opacity(0.4), radius: 2)
    }
}

struct StatusPill: View {
    let status: SnapshotRecord.Status

    var body: some View {
        Text(status.label)
            .font(.system(size: 9, weight: .semibold))
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(status.tint.opacity(0.15)))
            .foregroundStyle(status.tint)
    }
}

// MARK: - Detail View

struct HistoryDetailView: View {
    let entry: HistoryEntry
    @ObservedObject var model: HistoryModel

    @State private var showDeleteConfirm = false
    @State private var copiedItemID: Int?
    @State private var copiedAll = false
    @State private var copiedImage = false
    @State private var copyResetTask: Task<Void, Never>?
    @State private var isZoomed = false
    @ObservedObject private var ttsManager = TTSManager.shared

    private var record: SnapshotRecord { entry.record }
    private var translating: Bool { model.isTranslating(entry.id) }
    private var items: [TranslationItem] { record.decodedItems }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                translationSection
                screenshotCard
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.clear)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                translateButton
            }
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
                .help("Delete this snapshot")
            }
        }
        .confirmationDialog("Delete this snapshot?", isPresented: $showDeleteConfirm,
                            titleVisibility: .visible) {
            Button("Delete Snapshot", role: .destructive) { model.requestDelete(entry) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The image file will also be removed. This cannot be undone.")
        }
    }

    // MARK: header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Prominent Title: Target Translation
            Text(record.snippetTitle)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(2)

            // Context Subtitle: Original Source Text
            if let sub = record.snippetSubtitle, !sub.isEmpty {
                Text(sub)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Snapshot Metadata Chips
            HStack(spacing: 8) {
                StatusDot(status: record.status)

                chip(icon: "calendar", text: record.createdAt.formatted(date: .abbreviated, time: .shortened))

                chip(icon: "viewfinder", text: "\(record.pixelWidth)×\(record.pixelHeight)")

                if let endpoint = record.endpointLabel {
                    chip(icon: "network", text: endpoint)
                }

                if let latency = record.latencyMs {
                    chip(icon: "speedometer", text: "\(latency) ms")
                }
            }
            .padding(.top, 2)
        }
    }

    private func chip(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9))
            Text(text).font(.system(size: 11)).lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }

    // MARK: translation (Hero Section)

    private var translationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("TRANSLATION RESULT", systemImage: "character.bubble.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)

                if translating {
                    ProgressView().controlSize(.small)
                }
                Spacer()

                if hasAnyTranslation {
                    Button {
                        if ttsManager.isPlaying {
                            ttsManager.stop()
                        } else {
                            speakAll()
                        }
                    } label: {
                        if ttsManager.isPlaying {
                            Label("Stop", systemImage: "square.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.red)
                        } else if ttsManager.isLoading {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Label("Speak", systemImage: "speaker.wave.2")
                                .font(.system(size: 11))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(ttsManager.isPlaying ? "Stop pronunciation playback" : "Pronounce translated text aloud (Text-to-Speech)")

                    Button {
                        copyAll()
                    } label: {
                        Label(copiedAll ? "Copied" : "Copy All",
                              systemImage: copiedAll ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Copy all original text and translations to clipboard (⌘C)")
                }
            }

            sectionContent
        }
    }

    private var hasAnyTranslation: Bool {
        !items.isEmpty || (!record.translatedText.isEmpty && record.status == .ok)
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch record.status {
        case .pending:
            infoBox(icon: "clock.fill", tint: .orange,
                    title: "Pending translation",
                    message: "This snapshot was captured before translation completed. Click Translate Now to process it.")
        case .empty:
            infoBox(icon: "text.and.command.macwindow", tint: .gray,
                    title: "No translatable text detected",
                    message: "The vision model inspected this capture and did not detect readable text.")
        case .failed:
            infoBox(icon: "exclamationmark.triangle.fill", tint: .red,
                    title: record.errorMessage ?? "Translation failed",
                    message: "Check your endpoint configuration in Settings, then click Translate Again.")
        case .ok:
            if !items.isEmpty {
                VStack(spacing: 10) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        itemCard(index, item)
                    }
                }
            } else if !record.translatedText.isEmpty {
                // Fallback when itemsJSON was flat or unsegmented
                fallbackTranslationCard
            } else {
                infoBox(icon: "checkmark.circle", tint: .green,
                        title: "Completed",
                        message: "Translation finished with no text returned.")
            }
        }
    }

    private var fallbackTranslationCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !record.sourceText.isEmpty {
                Text(record.sourceText)
                    .font(.system(size: model.settings.sourceFontSize, weight: .regular))
                    .foregroundStyle(model.settings.sourceTextColor.color)
                    .textSelection(.enabled)
                    .lineSpacing(2)
            }

            Text(record.translatedText.isEmpty ? " " : record.translatedText)
                .font(.system(size: model.settings.translatedFontSize, weight: .medium))
                .foregroundStyle(model.settings.translatedTextColor.color)
                .textSelection(.enabled)
                .lineSpacing(4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func itemCard(_ index: Int, _ item: TranslationItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // 1. Original Source Text (Always on top)
            if !item.source.isEmpty {
                Text(item.source)
                    .font(.system(size: model.settings.sourceFontSize, weight: .regular))
                    .foregroundStyle(model.settings.sourceTextColor.color)
                    .textSelection(.enabled)
                    .lineSpacing(2)
            }

            // 2. Target Translated Text (Below original)
            Text(item.translation.isEmpty ? " " : item.translation)
                .font(.system(size: model.settings.translatedFontSize, weight: .medium))
                .foregroundStyle(model.settings.translatedTextColor.color)
                .textSelection(.enabled)
                .lineSpacing(3)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .contextMenu {
            Button("Copy Translation") { copy(item.translation, id: index) }
            Button("Copy Original") { copy(item.source, id: index) }
            Button("Pronounce Translation") { speak(item.translation) }
        }
    }

    private func infoBox(icon: String, tint: Color, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.08))
                .strokeBorder(tint.opacity(0.15), lineWidth: 0.5)
        )
    }

    // MARK: screenshot

    private var screenshotCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("ORIGINAL CAPTURE", systemImage: "viewfinder")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)

                Spacer()

                if let image = entry.image {
                    // Copy Image Button
                    Button {
                        copyImage(image)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: copiedImage ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10))
                            Text(copiedImage ? "Copied" : "Copy Image")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(copiedImage ? Color.accentColor : Color.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Copy captured screenshot to clipboard")

                    // Share Image Button (macOS native share picker / AirDrop / Messages)
                    if #available(macOS 13.0, *) {
                        ShareLink(
                            item: Image(nsImage: image),
                            preview: SharePreview("Glance Capture", image: Image(nsImage: image))
                        ) {
                            HStack(spacing: 4) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 10))
                                Text("Share")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                            )
                        }
                        .buttonStyle(.plain)
                        .help("Share screenshot via AirDrop, Messages, Mail, etc.")
                    }

                    Button {
                        withAnimation(.spring(duration: 0.25)) { isZoomed.toggle() }
                    } label: {
                        Label(isZoomed ? "Fit to View" : "Actual Size",
                              systemImage: isZoomed ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Group {
                if let image = entry.image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: isZoomed ? .fill : .fit)
                        .frame(maxHeight: isZoomed ? nil : 340)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(duration: 0.25)) { isZoomed.toggle() }
                        }
                        .contextMenu {
                            Button("Copy Image") { copyImage(image) }
                            Button("Save Image As…") { saveImageAs(image) }
                        }
                } else {
                    Label("The saved image file is missing on disk", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var translateButton: some View {
        Button {
            model.retranslate(entry)
        } label: {
            if translating {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.mini)
                    Text("Translating…")
                }
            } else {
                Label(record.status == .ok ? "Translate Again" : "Translate Now",
                      systemImage: "arrow.triangle.2.circlepath")
            }
        }
        .disabled(translating)
        .help(record.status == .ok ? "Re-translate snapshot with the active AI service" : "Translate snapshot now")
    }

    // MARK: actions

    private func copy(_ text: String, id: Int) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedItemID = id
        scheduleCopyReset { copiedItemID = nil }
    }

    private func copyAll() {
        let all: String
        if !items.isEmpty {
            all = items.map { item in
                if !item.source.isEmpty && !item.translation.isEmpty {
                    return "\(item.source)\n\(item.translation)"
                } else if !item.translation.isEmpty {
                    return item.translation
                } else {
                    return item.source
                }
            }.joined(separator: "\n\n")
        } else {
            if !record.sourceText.isEmpty && !record.translatedText.isEmpty {
                all = "\(record.sourceText)\n\n\(record.translatedText)"
            } else {
                all = record.translatedText.isEmpty ? record.sourceText : record.translatedText
            }
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(all, forType: .string)
        copiedAll = true
        scheduleCopyReset { copiedAll = false }
    }

    private func speakAll() {
        let all: String
        if !items.isEmpty {
            all = items.map(\.translation).joined(separator: " ")
        } else {
            all = record.translatedText
        }
        speak(all)
    }

    private func speak(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let settings = SettingsStore()
        let targetLang = record.targetLanguage.flatMap { code in
            AppLanguage.allCases.first(where: { $0.rawValue == code || $0.promptName == code })
        } ?? settings.targetLanguage
        ttsManager.speak(text: clean, language: targetLang, engine: settings.ttsEngine, rate: settings.ttsRate)
    }

    private func copyImage(_ image: NSImage) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        copiedImage = true
        scheduleCopyReset { copiedImage = false }
    }

    private func saveImageAs(_ image: NSImage) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = "Glance_\(record.id.uuidString.prefix(8)).png"
        savePanel.begin { result in
            if result == .OK, let url = savePanel.url {
                if let tiffData = image.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmap.representation(using: .png, properties: [:]) {
                    try? pngData.write(to: url)
                }
            }
        }
    }

    private func scheduleCopyReset(_ reset: @escaping () -> Void) {
        copyResetTask?.cancel()
        copyResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            if !Task.isCancelled { reset() }
        }
    }
}

// MARK: - Delete by Date Range Sheet

struct DeleteByDateSheet: View {
    @ObservedObject var model: HistoryModel
    @Environment(\.dismiss) private var dismiss

    enum Preset: String, CaseIterable, Identifiable {
        case today = "Today"
        case last7Days = "Last 7 days"
        case last30Days = "Last 30 days"
        case custom = "Custom range"

        var id: String { rawValue }
    }

    @State private var selectedPreset: Preset = .last7Days
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var customEnd = Date()

    private var dateRange: (since: Date, until: Date) {
        let now = Date()
        let cal = Calendar.current
        switch selectedPreset {
        case .today:
            let start = cal.startOfDay(for: now)
            return (start, now)
        case .last7Days:
            let start = cal.date(byAdding: .day, value: -7, to: now) ?? now
            return (start, now)
        case .last30Days:
            let start = cal.date(byAdding: .day, value: -30, to: now) ?? now
            return (start, now)
        case .custom:
            return (customStart, customEnd)
        }
    }

    private var previewStats: (count: Int, totalBytes: Int64) {
        let range = dateRange
        return model.countAndSize(since: range.since, until: range.until)
    }

    private var formattedSize: String {
        let bytes = previewStats.totalBytes
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB, .useBytes, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Delete Snapshots by Date")
                .font(.system(size: 16, weight: .semibold))

            Text("Select a time window to prune older snapshots and reclaim disk space.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Picker("Preset", selection: $selectedPreset) {
                ForEach(Preset.allCases) { preset in
                    Text(preset.rawValue).tag(preset)
                }
            }
            .pickerStyle(.segmented)

            if selectedPreset == .custom {
                VStack(spacing: 8) {
                    DatePicker("From:", selection: $customStart, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("To:", selection: $customEnd, displayedComponents: [.date, .hourAndMinute])
                }
                .font(.system(size: 12))
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
            }

            // Preview banner
            HStack(spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("This will permanently delete **\(previewStats.count)** snapshots.")
                        .font(.system(size: 12))
                    Text("Disk space freed: **\(formattedSize)**")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.08)))

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Delete \(previewStats.count) Snapshots", role: .destructive) {
                    let range = dateRange
                    model.deleteRange(since: range.since, until: range.until)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(previewStats.count == 0)
            }
            .padding(.top, 8)
        }
        .padding(22)
        .frame(width: 440)
    }
}

// MARK: - SnapshotRecord Snippet Helpers

extension SnapshotRecord {
    var snippetTitle: String {
        switch status {
        case .ok where !translatedText.isEmpty:
            let lines = translatedText
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return lines.first ?? translatedText
        case .ok:
            return "(Empty translation)"
        case .empty:
            return "No text detected"
        case .failed:
            return "Translation failed"
        case .pending:
            return "Translating…"
        }
    }

    var snippetSubtitle: String? {
        if status == .failed {
            return errorMessage
        }
        let lines = sourceText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if let first = lines.first, first != snippetTitle {
            return first
        }
        return nil
    }
}

