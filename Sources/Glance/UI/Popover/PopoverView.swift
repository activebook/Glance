import SwiftUI

/// Root view of the menu bar popover: endpoint chip header, interactive recents list,
/// and quick management actions. Width fixed at 360pt per design §7.1.
struct PopoverView: View {
    @ObservedObject var settings: SettingsStore
    let historyStore: HistoryStore?
    let onShowHistory: () -> Void
    let onSelectSnapshot: (UUID) -> Void
    let onShowSettings: () -> Void
    let onQuit: () -> Void

    @State private var showEndpointSwitcher = false
    @State private var recents: [SnapshotRecord] = []

    private var activeEndpoint: EndpointConfig? { settings.activeEndpoint() }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            EndpointChip(
                endpoint: activeEndpoint,
                isExpanded: showEndpointSwitcher
            )
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { showEndpointSwitcher.toggle() } }

            if showEndpointSwitcher {
                EndpointSwitcherList(
                    settings: settings,
                    activeEndpoint: activeEndpoint,
                    onManageEndpoints: onShowSettings
                )
                Divider()
            }

            Divider()

            // Recents Section
            if recents.isEmpty {
                RecentsEmptyState()
                    .frame(minHeight: 140)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(recents) { record in
                            PopoverRecentRow(
                                record: record,
                                onSelect: { onSelectSnapshot(record.id) }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 280)
            }

            Divider()

            // Footer
            HStack(spacing: 12) {
                Button("Show All") { onShowHistory() }
                    .font(.system(size: 12, weight: .medium))
                    .help("Open the history browser")

                Spacer()

                Button("Settings…") { onShowSettings() }
                Button("Quit") { onQuit() }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(width: 360)
        .onAppear { loadRecents() }
        .onReceive(NotificationCenter.default.publisher(for: .historyStoreDidChange)) { _ in
            loadRecents()
        }
    }

    private func loadRecents() {
        guard let store = historyStore else { return }
        HistoryImagePathBridge.shared.store = store
        recents = (try? store.fetchAll(limit: 10, oldestFirst: false)) ?? []
    }
}

// MARK: - Recent Snapshot Row

struct PopoverRecentRow: View {
    let record: SnapshotRecord
    let onSelect: () -> Void

    @State private var isHovered = false
    @State private var isCopied = false

    private var image: NSImage? {
        HistoryImagePathBridge.shared.resolve(record.imagePath)
    }

    var body: some View {
        Button {
            onSelect()
        } label: {
            HStack(spacing: 10) {
                // Thumbnail
                Group {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        ZStack {
                            Rectangle().fill(Color.primary.opacity(0.04))
                            Image(systemName: "photo")
                                .font(.system(size: 14))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .frame(width: 48, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )

                // Text snippet
                VStack(alignment: .leading, spacing: 2) {
                    Text(primaryText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        StatusDot(status: record.status)

                        Text(relativeTime(record.createdAt))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Quick Copy Button
                if isHovered || isCopied {
                    Button {
                        copyTranslation()
                    } label: {
                        Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundStyle(isCopied ? Color.green : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy translation")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var primaryText: String {
        switch record.status {
        case .ok where !record.translatedText.isEmpty:
            return record.translatedText.replacingOccurrences(of: "\n", with: " ")
        case .ok:
            return "(empty translation)"
        case .empty:
            return "No text detected"
        case .failed:
            return record.errorMessage ?? "Translation failed"
        case .pending:
            return "Translating…"
        }
    }

    private func copyTranslation() {
        guard !record.translatedText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(record.translatedText, forType: .string)
        isCopied = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            isCopied = false
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = -date.timeIntervalSinceNow
        if seconds < 60 { return "Just now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h ago" }
        return "\(Int(seconds / 86400))d ago"
    }
}

// MARK: - Header chip

struct EndpointChip: View {
    let endpoint: EndpointConfig?
    let isExpanded: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(endpoint == nil ? Color.gray : Color.green)
                .frame(width: 7, height: 7)
            Text(endpoint?.label ?? "No endpoint configured")
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            Spacer()
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - Inline endpoint switcher (D11)

struct EndpointSwitcherList: View {
    @ObservedObject var settings: SettingsStore
    let activeEndpoint: EndpointConfig?
    let onManageEndpoints: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(settings.endpoints) { endpoint in
                Button {
                    settings.setActiveEndpoint(id: endpoint.id)
                } label: {
                    HStack {
                        Image(systemName: isActive(endpoint) ? "circle.inset.filled" : "circle")
                            .font(.system(size: 11))
                        Text(endpoint.label)
                            .font(.system(size: 12))
                            .lineLimit(1)
                        Spacer()
                        if settings.defaultEndpointID == endpoint.id {
                            Text("default")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }

            if settings.endpoints.isEmpty {
                Text("Add an endpoint in Settings to start translating.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            }

            Divider()
                .padding(.vertical, 4)

            Button {
                onManageEndpoints()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11))
                    Text("Manage endpoints…")
                        .font(.system(size: 12))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func isActive(_ endpoint: EndpointConfig) -> Bool {
        endpoint.id == activeEndpoint?.id
    }
}

// MARK: - Empty state for the recents area

struct RecentsEmptyState: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.bubble")
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            Text("No snapshots yet")
                .font(.system(size: 13, weight: .medium))
            Text("Press ⌥⇧T to capture your first translation.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

