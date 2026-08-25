import AppKit
import Foundation
import Combine

/// GitHub Release Asset representation
struct GitHubReleaseAsset: Codable {
    let name: String
    let size: Int
    let browser_download_url: URL
}

/// GitHub Release representation from the GitHub REST API
struct GitHubRelease: Codable, Identifiable {
    var id: String { tag_name }
    let tag_name: String
    let name: String?
    let body: String?
    let html_url: URL
    let published_at: String?
    let assets: [GitHubReleaseAsset]

    var versionString: String {
        tag_name.hasPrefix("v") ? String(tag_name.dropFirst()) : tag_name
    }

    var appZipAsset: GitHubReleaseAsset? {
        assets.first { $0.name.hasSuffix(".zip") && $0.name.localizedCaseInsensitiveContains("glance") }
            ?? assets.first { $0.name.hasSuffix(".zip") }
    }
}

/// State machine for application updates
enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate(lastChecked: Date)
    case updateAvailable(release: GitHubRelease)
    case downloading(progress: Double, bytesWritten: Int64, totalBytes: Int64)
    case readyToInstall(zipURL: URL, release: GitHubRelease)
    case installing
    case error(message: String)

    static func == (lhs: UpdateState, rhs: UpdateState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.checking, .checking), (.installing, .installing):
            return true
        case (.upToDate(let a), .upToDate(let b)):
            return a == b
        case (.updateAvailable(let a), .updateAvailable(let b)):
            return a.tag_name == b.tag_name
        case (.downloading(let p1, let b1, let t1), .downloading(let p2, let b2, let t2)):
            return p1 == p2 && b1 == b2 && t1 == t2
        case (.readyToInstall(let u1, let r1), .readyToInstall(let u2, let r2)):
            return u1 == u2 && r1.tag_name == r2.tag_name
        case (.error(let m1), .error(let m2)):
            return m1 == m2
        default:
            return false
        }
    }
}

/// Manages querying GitHub for newer releases, downloading distribution bundles,
/// and executing in-place app replacement.
@MainActor
final class UpdateManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = UpdateManager()

    static let repoOwner = "activebook"
    static let repoName = "Glance"
    static let apiURL = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!

    @Published var state: UpdateState = .idle
    @Published var showUpdateModal: Bool = false
    @Published var latestRelease: GitHubRelease?

    private var downloadTask: URLSessionDownloadTask?
    private var activeRelease: GitHubRelease?
    private var downloadContinuation: CheckedContinuation<URL, Error>?

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    var currentBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    // MARK: - Update Check

    /// Checks GitHub Releases API for the newest tagged release.
    func checkForUpdates(silent: Bool = false) async {
        guard state != .checking && !isDownloading else { return }
        state = .checking

        var request = URLRequest(url: Self.apiURL)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Glance-App/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            if http.statusCode == 404 {
                if !silent {
                    state = .upToDate(lastChecked: Date())
                    Task {
                        try? await Task.sleep(nanoseconds: 4_000_000_000)
                        if case .upToDate = self.state {
                            self.state = .idle
                        }
                    }
                } else {
                    state = .idle
                }
                return
            }

            guard http.statusCode == 200 else {
                throw NSError(domain: "UpdateManager", code: http.statusCode,
                              userInfo: [NSLocalizedDescriptionKey: "GitHub API returned status \(http.statusCode)"])
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            self.latestRelease = release

            if isRemoteVersionNewer(remote: release.versionString, current: currentVersion) {
                state = .updateAvailable(release: release)
                if !silent {
                    showUpdateModal = true
                }
            } else {
                if !silent {
                    state = .upToDate(lastChecked: Date())
                    Task {
                        try? await Task.sleep(nanoseconds: 4_000_000_000)
                        if case .upToDate = self.state {
                            self.state = .idle
                        }
                    }
                } else {
                    state = .idle
                }
            }
        } catch {
            NSLog("Glance: update check error: \(error)")
            if !silent {
                state = .error(message: error.localizedDescription)
                showUpdateModal = true
            } else {
                state = .idle
            }
        }
    }

    private var isDownloading: Bool {
        if case .downloading = state { return true }
        return false
    }

    // MARK: - Version Comparison

    /// Returns true if remote semver string is strictly greater than local version.
    func isRemoteVersionNewer(remote: String, current: String) -> Bool {
        let cleanRemote = remote.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        let cleanCurrent = current.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))

        let rComponents = cleanRemote.split(separator: ".").compactMap { Int($0) }
        let cComponents = cleanCurrent.split(separator: ".").compactMap { Int($0) }

        let count = max(rComponents.count, cComponents.count)
        for i in 0..<count {
            let rVal = i < rComponents.count ? rComponents[i] : 0
            let cVal = i < cComponents.count ? cComponents[i] : 0
            if rVal > cVal { return true }
            if rVal < cVal { return false }
        }
        return false
    }

    // MARK: - Download Asset

    /// Downloads the release zip bundle from GitHub.
    func startDownload(for release: GitHubRelease) {
        guard let asset = release.appZipAsset else {
            state = .error(message: "No Glance.zip asset attached to release \(release.tag_name).")
            return
        }

        self.activeRelease = release
        state = .downloading(progress: 0.0, bytesWritten: 0, totalBytes: Int64(asset.size))

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        let task = session.downloadTask(with: asset.browser_download_url)
        self.downloadTask = task
        task.resume()
    }

    // MARK: - URLSessionDownloadDelegate

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64,
                                totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        let progress = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0.0
        Task { @MainActor in
            self.state = .downloading(progress: progress,
                                      bytesWritten: totalBytesWritten,
                                      totalBytes: totalBytesExpectedToWrite)
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        do {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("GlanceUpdate-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let destZip = tempDir.appendingPathComponent("Glance.zip")
            try FileManager.default.moveItem(at: location, to: destZip)

            Task { @MainActor in
                if let release = self.activeRelease {
                    self.state = .readyToInstall(zipURL: destZip, release: release)
                }
            }
        } catch {
            Task { @MainActor in
                self.state = .error(message: "Failed to store update payload: \(error.localizedDescription)")
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            Task { @MainActor in
                self.state = .error(message: "Download failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - In-Place Extraction & Installation

    /// Extracts the downloaded zip and replaces the running application bundle.
    func installAndRelaunch(zipURL: URL) {
        state = .installing

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let currentAppURL = Bundle.main.bundleURL

        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let extractDir = zipURL.deletingLastPathComponent().appendingPathComponent("Extracted")

            do {
                try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)

                // 1. Unzip using macOS ditto to preserve symlinks and Mach-O permissions
                let unzipProcess = Process()
                unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                unzipProcess.arguments = ["-x", "-k", zipURL.path, extractDir.path]
                try unzipProcess.run()
                unzipProcess.waitUntilExit()

                guard unzipProcess.terminationStatus == 0 else {
                    throw NSError(domain: "UpdateManager", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "Failed to extract Glance.zip"])
                }

                // 2. Locate extracted Glance.app
                let contents = try fm.contentsOfDirectory(at: extractDir, includingPropertiesForKeys: nil)
                guard let newAppURL = contents.first(where: { $0.lastPathComponent == "Glance.app" }) else {
                    throw NSError(domain: "UpdateManager", code: 2,
                                  userInfo: [NSLocalizedDescriptionKey: "Extracted archive did not contain Glance.app"])
                }

                // 3. Script-assisted atomic replacement and relaunch
                let tempParentDir = zipURL.deletingLastPathComponent().path
                let relaunchScript = """
                while kill -0 \(currentPID) 2>/dev/null; do
                    sleep 0.1
                done
                rm -rf "\(currentAppURL.path)"
                cp -R "\(newAppURL.path)" "\(currentAppURL.path)"
                xattr -dr com.apple.quarantine "\(currentAppURL.path)" 2>/dev/null || true
                open "\(currentAppURL.path)"
                rm -rf "\(tempParentDir)"
                """

                let scriptProcess = Process()
                scriptProcess.executableURL = URL(fileURLWithPath: "/bin/sh")
                scriptProcess.arguments = ["-c", relaunchScript]
                try scriptProcess.run()

                DispatchQueue.main.async {
                    exit(0)
                }
            } catch {
                DispatchQueue.main.async {
                    self.state = .error(message: "Installation error: \(error.localizedDescription)")
                }
            }
        }
    }
}
