import SwiftUI

/// Modal sheet presenting update status, release notes, progress bar, and install trigger.
struct UpdateModalView: View {
    @ObservedObject var updateManager = UpdateManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                if let appIcon = NSApp.applicationIconImage ?? NSImage(named: NSImage.applicationIconName) {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 44, height: 44)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Software Update")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.primary)

                    Text("Glance for macOS")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            // Content Body based on state
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch updateManager.state {
                    case .checking:
                        VStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.regular)
                            Text("Checking GitHub for the latest release…")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 180)

                    case .upToDate(let lastChecked):
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 38))
                                .foregroundStyle(.green)

                            Text("You're Up to Date!")
                                .font(.system(size: 15, weight: .bold))

                            Text("Glance v\(updateManager.currentVersion) is currently the newest version available.")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            Text("Last checked: \(lastChecked.formatted(date: .abbreviated, time: .shortened))")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    case .updateAvailable, .downloading, .readyToInstall:
                        if let release = updateManager.latestRelease {
                            VStack(alignment: .leading, spacing: 14) {
                            // Version comparison banner
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("CURRENT")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.tertiary)
                                    Text("v\(updateManager.currentVersion)")
                                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                }

                                Image(systemName: "arrow.right")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.secondary)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("NEW RELEASE")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.indigo)
                                    Text(release.tag_name)
                                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.indigo)
                                }

                                Spacer()

                                if let date = release.published_at {
                                    Text(date.prefix(10))
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.indigo.opacity(0.08))
                            )

                            // Release notes
                            if let body = release.body, !body.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("What's New in \(release.name ?? release.tag_name):")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.secondary)

                                    Text(body)
                                        .font(.system(size: 12))
                                        .lineSpacing(3)
                                        .padding(12)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(Color.primary.opacity(0.04))
                                        )
                                }
                            }

                            // Download Progress
                            if case .downloading(let progress, let written, let total) = updateManager.state {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("Downloading update…")
                                            .font(.system(size: 12, weight: .medium))
                                        Spacer()
                                        Text("\(Int(progress * 100))%")
                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                            .foregroundStyle(.indigo)
                                    }

                                    ProgressView(value: progress)
                                        .tint(.indigo)

                                    Text("\(ByteCountFormatter.string(fromByteCount: written, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.primary.opacity(0.04))
                                )
                            }
                        }
                    }

                    case .installing:
                        VStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.regular)
                            Text("Installing update and preparing to relaunch…")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 180)

                    case .error(let message):
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 34))
                                .foregroundStyle(.orange)

                            Text("Update Check Failed")
                                .font(.system(size: 14, weight: .bold))

                            Text(message)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 180)

                    case .idle:
                        EmptyView()
                    }
                }
                .padding(20)
            }

            Divider()

            // Footer Actions
            HStack(spacing: 10) {
                if let release = updateManager.latestRelease {
                    Link(destination: release.html_url) {
                        HStack(spacing: 4) {
                            Text("View on GitHub")
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9))
                        }
                        .font(.system(size: 12))
                    }
                    .buttonStyle(.link)
                }

                Spacer()

                switch updateManager.state {
                case .upToDate:
                    Button("Done") {
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)

                case .updateAvailable(let release):
                    Button("Remind Me Later") {
                        dismiss()
                    }

                    Button {
                        updateManager.startDownload(for: release)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Download & Install")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    .keyboardShortcut(.defaultAction)

                case .readyToInstall(let zipURL, _):
                    Button {
                        updateManager.installAndRelaunch(zipURL: zipURL)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                            Text("Restart & Install")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .keyboardShortcut(.defaultAction)

                case .error:
                    Button("Close") {
                        dismiss()
                    }
                    Button("Check Again") {
                        Task { await updateManager.checkForUpdates(silent: false) }
                    }
                    .buttonStyle(.borderedProminent)

                default:
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 480, height: 420)
    }
}
