import SwiftUI
import AppKit

/// Finder-style horizontal gallery filmstrip for visual snapshot browsing.
struct GalleryFilmstripView: View {
    @ObservedObject var model: HistoryModel
    @State private var filmstripScrollProxy: ScrollViewProxy? = nil

    private var isNotAtStart: Bool {
        guard let firstID = model.entries.first?.id else { return false }
        return model.selectedID != firstID
    }

    private func jumpToStart() {
        guard let firstID = model.entries.first?.id else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            filmstripScrollProxy?.scrollTo(firstID, anchor: .center)
        }
        model.selectedID = firstID
    }

    private func selectPrevious() {
        guard let currentID = model.selectedID,
              let index = model.entries.firstIndex(where: { $0.id == currentID }),
              index > 0 else { return }
        let prevID = model.entries[index - 1].id
        withAnimation(.easeInOut(duration: 0.2)) {
            model.selectedID = prevID
            filmstripScrollProxy?.scrollTo(prevID, anchor: .center)
        }
    }

    private func selectNext() {
        guard let currentID = model.selectedID,
              let index = model.entries.firstIndex(where: { $0.id == currentID }),
              index + 1 < model.entries.count else { return }
        let nextID = model.entries[index + 1].id
        withAnimation(.easeInOut(duration: 0.2)) {
            model.selectedID = nextID
            filmstripScrollProxy?.scrollTo(nextID, anchor: .center)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Control Header: Glance Brand + Filter chips + Snapshot count + Sort
            HStack(spacing: 12) {
                // App Brand: Icon + Name + Version Badge
                HStack(spacing: 6) {
                    if let appIcon = NSApp.applicationIconImage ?? NSImage(named: NSImage.applicationIconName) {
                        Image(nsImage: appIcon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                    }

                    Text("Glance")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    VersionPillView()
                }
                .layoutPriority(1)

                Divider()
                    .frame(height: 16)
                    .opacity(0.3)

                // Status Filter Segmented Control (no label prefix)
                Picker("", selection: $model.statusFilter) {
                    Text("All").tag(SnapshotRecord.Status?.none)
                    Text("Translated").tag(SnapshotRecord.Status?.some(.ok))
                    Text("Failed").tag(SnapshotRecord.Status?.some(.failed))
                    Text("No text").tag(SnapshotRecord.Status?.some(.empty))
                    Text("Pending").tag(SnapshotRecord.Status?.some(.pending))
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 360)

                Spacer()

                // Snapshot count & Jump to Top
                HStack(spacing: 8) {
                    Text(model.entries.count == 1 ? "1 Snapshot" : "\(model.entries.count) Snapshots")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    if isNotAtStart {
                        Button {
                            jumpToStart()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.up.to.line")
                                    .font(.system(size: 9.5, weight: .bold))
                                Text("Top")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.12))
                            )
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.upArrow, modifiers: .command)
                        .help("Jump to latest snapshot at the top (⌘↑)")
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    }
                }
                .animation(.easeInOut(duration: 0.18), value: isNotAtStart)

                // Sort Dropdown Menu
                Menu {
                    Button {
                        model.oldestFirst = false
                    } label: {
                        HStack {
                            Text("Newest First")
                            if !model.oldestFirst { Image(systemName: "checkmark") }
                        }
                    }
                    Button {
                        model.oldestFirst = true
                    } label: {
                        HStack {
                            Text("Oldest First")
                            if model.oldestFirst { Image(systemName: "checkmark") }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: model.oldestFirst ? "arrow.up" : "arrow.down")
                            .font(.system(size: 10, weight: .semibold))
                        Text(model.oldestFirst ? "Oldest" : "Newest")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.8))
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))

            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)

            // Horizontal Carousel
            if model.entries.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "photo.stack")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text(model.searchQuery.isEmpty && model.statusFilter == nil ? "No snapshots yet" : "No matching snapshots")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(height: 154)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: true) {
                        LazyHStack(spacing: 12) {
                            ForEach(model.entries) { entry in
                                GalleryCardView(
                                    entry: entry,
                                    isSelected: model.selectedID == entry.id,
                                    onSelect: {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            model.selectedID = entry.id
                                            proxy.scrollTo(entry.id, anchor: .center)
                                        }
                                    },
                                    onDelete: {
                                        model.pendingDelete = entry
                                    },
                                    onRetranslate: {
                                        model.retranslate(entry)
                                    }
                                )
                                .id(entry.id)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    .frame(height: 154)
                    .onAppear {
                        filmstripScrollProxy = proxy
                        if let selectedID = model.selectedID {
                            proxy.scrollTo(selectedID, anchor: .center)
                        }
                    }
                    .onChange(of: model.selectedID) { _, newID in
                        if let newID {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo(newID, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.35))
    }
}

// MARK: - Gallery Card Item

struct GalleryCardView: View {
    let entry: HistoryEntry
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onRetranslate: () -> Void

    @State private var isHovered = false

    private var titleText: String {
        let raw = entry.record.translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty { return raw }
        let src = entry.record.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !src.isEmpty { return src }
        return "Snapshot"
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                // High-Resolution Thumbnail with status dot
                ZStack(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))

                    if let image = entry.image {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 16))
                            .foregroundStyle(.tertiary)
                    }

                    StatusDot(status: entry.record.status)
                        .padding(5)
                }
                .frame(width: 156, height: 86)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                // Card Footer Text
                VStack(alignment: .leading, spacing: 2) {
                    Text(titleText)
                        .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                        .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.85))
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text(entry.record.createdAt.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)

                        if entry.record.pixelWidth > 0 && entry.record.pixelHeight > 0 {
                            Text("•")
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                            Text("\(entry.record.pixelWidth)×\(entry.record.pixelHeight)")
                                .font(.system(size: 9.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: 156, alignment: .leading)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : (isHovered ? Color.primary.opacity(0.05) : Color(nsColor: .controlBackgroundColor).opacity(0.6)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor : (isHovered ? Color.primary.opacity(0.18) : Color.primary.opacity(0.08)),
                        lineWidth: isSelected ? 1.75 : 0.75
                    )
            )
            .shadow(color: isSelected ? Color.accentColor.opacity(0.2) : .clear, radius: 4, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .contextMenu {
            if !entry.record.translatedText.isEmpty {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.record.translatedText, forType: .string)
                } label: {
                    Label("Copy Translation", systemImage: "doc.on.doc")
                }
            }

            if !entry.record.sourceText.isEmpty {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.record.sourceText, forType: .string)
                } label: {
                    Label("Copy Source Text", systemImage: "text.quote")
                }
            }

            if let img = entry.image {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([img])
                } label: {
                    Label("Copy Snapshot Image", systemImage: "photo.on.rectangle")
                }
            }

            Divider()

            Button {
                onRetranslate()
            } label: {
                Label("Re-translate Snapshot", systemImage: "arrow.triangle.2.circlepath")
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete Snapshot", systemImage: "trash")
            }
        }
    }
}
