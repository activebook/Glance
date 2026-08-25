import SwiftUI

/// Sleek, interactive version pill that dynamically transforms into an "Update Available"
/// badge with one-click checking and progress indication.
struct VersionPillView: View {
    @ObservedObject var updateManager = UpdateManager.shared
    @State private var isHovered = false

    var body: some View {
        Button {
            handleClick()
        } label: {
            HStack(spacing: 5) {
                switch updateManager.state {
                case .checking:
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.7)
                    Text("Checking…")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))

                case .updateAvailable(let release):
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                        .shadow(color: .green.opacity(0.6), radius: 2)

                    Text("v\(release.versionString) ↗")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.indigo)

                case .downloading(let progress, _, _):
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.indigo)

                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.indigo)

                case .readyToInstall:
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)

                    Text("Ready ↗")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.green)

                case .upToDate:
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.green)
                        Text("v\(updateManager.currentVersion)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.green)
                    }

                case .idle, .error, .installing:
                    Text("v\(updateManager.currentVersion)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(isHovered ? .primary : .secondary)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(backgroundView)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(tooltipText)
    }

    @ViewBuilder
    private var backgroundView: some View {
        switch updateManager.state {
        case .updateAvailable:
            Capsule()
                .fill(Color.indigo.opacity(isHovered ? 0.18 : 0.12))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.indigo.opacity(0.35), lineWidth: 1)
                )

        case .downloading, .readyToInstall:
            Capsule()
                .fill(Color.green.opacity(isHovered ? 0.18 : 0.12))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.green.opacity(0.35), lineWidth: 1)
                )

        case .upToDate:
            Capsule()
                .fill(Color.green.opacity(isHovered ? 0.16 : 0.08))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.green.opacity(0.3), lineWidth: 1)
                )

        default:
            Capsule()
                .fill(Color.primary.opacity(isHovered ? 0.10 : 0.05))
        }
    }

    private var tooltipText: String {
        switch updateManager.state {
        case .updateAvailable(let release):
            return "New version \(release.tag_name) is available! Click to update."
        case .downloading(let progress, _, _):
            return "Downloading update: \(Int(progress * 100))%"
        case .readyToInstall:
            return "Update downloaded. Click to restart and install."
        case .checking:
            return "Checking GitHub for updates…"
        case .upToDate(let date):
            return "Glance v\(updateManager.currentVersion) is up to date (checked \(date.formatted(date: .omitted, time: .shortened))). Click to check again."
        default:
            return "Glance v\(updateManager.currentVersion) — Click to check for updates"
        }
    }

    private func handleClick() {
        switch updateManager.state {
        case .updateAvailable, .readyToInstall, .downloading, .error:
            updateManager.showUpdateModal = true
        default:
            Task {
                await updateManager.checkForUpdates(silent: false)
            }
        }
    }
}
