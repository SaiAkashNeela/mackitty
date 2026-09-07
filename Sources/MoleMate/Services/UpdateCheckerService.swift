import Foundation
import AppKit

@MainActor
final class UpdateCheckerService: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published var isChecking: Bool = false
    @Published var isUpdateAvailable: Bool = false
    @Published var latestVersion: String = "1.0.0"
    @Published var updateURL: String = "https://github.com/SaiAkashNeela/mackitty/releases/latest"
    @Published var packageAssetURL: String? = nil
    @Published var releaseNotes: String = ""
    @Published var lastCheckedText: String = "Not checked yet"
    @Published var statusMessage: String = "MacKitty is up to date"

    // In-place auto-update states
    @Published var isInstalling: Bool = false
    @Published var installProgress: Double = 0.0 // 0.0 ... 1.0
    @Published var installStatusText: String = ""
    @Published var installError: String? = nil
    @Published var showUpdateModal: Bool = false

    private var downloadTask: URLSessionDownloadTask?
    private var downloadContinuation: CheckedContinuation<URL, Error>?

    var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
    }

    override init() {
        super.init()
        // Run a lightweight background update check on startup
        Task { [weak self] in
            await self?.checkForUpdates(silent: true)
        }
    }

    func checkForUpdates(silent: Bool = false) async {
        isChecking = true
        if !silent {
            statusMessage = "Checking for updates…"
        }

        let endpoints = [
            "https://api.github.com/repos/SaiAkashNeela/mackitty/releases/latest",
            "https://mackitty.com/api/version.json"
        ]

        var foundVersion: String?
        var foundReleaseURL: String?
        var foundAssetURL: String?
        var foundNotes: String = ""

        for endpointStr in endpoints {
            guard let url = URL(string: endpointStr) else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 6.0
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("MacKitty-macOS/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continue
                }

                if let rawVer = (json["tag_name"] as? String) ?? (json["version"] as? String) {
                    let cleanVer = rawVer.replacingOccurrences(of: "v", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    foundVersion = cleanVer

                    if let body = json["body"] as? String {
                        foundNotes = body
                    }

                    if let htmlUrl = json["html_url"] as? String {
                        foundReleaseURL = htmlUrl
                    }

                    // Look for zip asset first (best for in-place replacement), then dmg asset
                    if let assets = json["assets"] as? [[String: Any]] {
                        if let zipAsset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".zip") == true }),
                           let zipUrl = zipAsset["browser_download_url"] as? String {
                            foundAssetURL = zipUrl
                        } else if let dmgAsset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".dmg") == true }),
                                  let dmgUrl = dmgAsset["browser_download_url"] as? String {
                            foundAssetURL = dmgUrl
                        }
                    }

                    break
                }
            } catch {
                continue
            }
        }

        self.isChecking = false
        self.lastCheckedText = "Just now"

        if let newVersion = foundVersion {
            let available = self.isVersion(newVersion, higherThan: self.currentVersion)
            self.latestVersion = newVersion
            self.isUpdateAvailable = available
            self.releaseNotes = foundNotes
            self.updateURL = foundReleaseURL ?? "https://github.com/SaiAkashNeela/mackitty/releases/latest"
            self.packageAssetURL = foundAssetURL ?? foundReleaseURL
            self.statusMessage = available ? "New version v\(newVersion) is available!" : "MacKitty is up to date (v\(self.currentVersion))"
        } else {
            if !self.isUpdateAvailable {
                self.statusMessage = "MacKitty is up to date (v\(self.currentVersion))"
            }
        }
    }

    /// Primary action: triggered when clicking "Update vX.Y.Z"
    func openUpdateFlow() {
        showUpdateModal = true
    }

    /// Performs seamless in-place download, verification, replacement, and relaunch
    func startInPlaceUpdate() {
        guard !isInstalling else { return }
        isInstalling = true
        installProgress = 0.05
        installStatusText = "Connecting to download server…"
        installError = nil

        Task { [weak self] in
            guard let self else { return }
            do {
                guard let assetUrlString = self.packageAssetURL, let downloadURL = URL(string: assetUrlString) else {
                    throw NSError(domain: "MacKittyUpdate", code: 404, userInfo: [NSLocalizedDescriptionKey: "Update asset URL not found. Please download manually."])
                }

                // 1. Download Package
                self.installStatusText = "Downloading MacKitty v\(self.latestVersion)…"
                let downloadedTempURL = try await self.downloadFile(from: downloadURL)

                // 2. Extract Package
                self.installProgress = 0.70
                self.installStatusText = "Extracting & verifying update…"

                let extractedAppURL = try await self.extractAndVerifyPackage(at: downloadedTempURL)

                // 3. Replace & Relaunch
                self.installProgress = 0.95
                self.installStatusText = "Restarting MacKitty v\(self.latestVersion)…"

                try self.replaceAndRelaunch(extractedAppURL: extractedAppURL)

            } catch {
                self.isInstalling = false
                self.installError = error.localizedDescription
                self.installStatusText = "Update failed: \(error.localizedDescription)"
            }
        }
    }

    /// Direct fallback to browser DMG download
    func openDownloadPage() {
        if let url = URL(string: updateURL) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Download Handling

    private func downloadFile(from url: URL) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            self.downloadContinuation = continuation
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
            var request = URLRequest(url: url)
            request.setValue("MacKitty-macOS/\(self.currentVersion)", forHTTPHeaderField: "User-Agent")
            let task = session.downloadTask(with: request)
            self.downloadTask = task
            task.resume()
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        Task { @MainActor in
            if totalBytesExpectedToWrite > 0 {
                let ratio = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
                self.installProgress = min(max(ratio * 0.65, 0.05), 0.65)
                let pct = Int(self.installProgress / 0.65 * 100)
                let receivedMB = Double(totalBytesWritten) / (1024 * 1024)
                let totalMB = Double(totalBytesExpectedToWrite) / (1024 * 1024)
                self.installStatusText = String(format: "Downloading MacKitty v%@… %d%% (%.1f / %.1f MB)", self.latestVersion, pct, receivedMB, totalMB)
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Move to persistent temp file because location is deleted when method returns
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("MacKittyUpdate-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let targetFilename = downloadTask.originalRequest?.url?.lastPathComponent ?? "MacKittyPackage"
        let destURL = tempDir.appendingPathComponent(targetFilename)

        do {
            try FileManager.default.moveItem(at: location, to: destURL)
            Task { @MainActor in
                self.downloadContinuation?.resume(returning: destURL)
                self.downloadContinuation = nil
            }
        } catch {
            Task { @MainActor in
                self.downloadContinuation?.resume(throwing: error)
                self.downloadContinuation = nil
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            Task { @MainActor in
                self.downloadContinuation?.resume(throwing: error)
                self.downloadContinuation = nil
            }
        }
    }

    // MARK: - Extraction & Verification

    private func extractAndVerifyPackage(at packageURL: URL) async throws -> URL {
        let fileManager = FileManager.default
        let extractDir = packageURL.deletingLastPathComponent().appendingPathComponent("Extracted")
        try fileManager.createDirectory(at: extractDir, withIntermediateDirectories: true)

        let isZip = packageURL.pathExtension.lowercased() == "zip"
        let isDmg = packageURL.pathExtension.lowercased() == "dmg"

        if isZip {
            // Extract zip using macOS ditto (preserves symlinks, code signatures, and permissions)
            let ditto = Process()
            ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            ditto.arguments = ["-xk", packageURL.path, extractDir.path]
            try ditto.run()
            ditto.waitUntilExit()

            guard ditto.terminationStatus == 0 else {
                throw NSError(domain: "MacKittyUpdate", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to decompress update archive."])
            }
        } else if isDmg {
            // Mount DMG silently, copy .app, and unmount
            let mountPoint = packageURL.deletingLastPathComponent().appendingPathComponent("Mount")
            try fileManager.createDirectory(at: mountPoint, withIntermediateDirectories: true)

            let hdiutil = Process()
            hdiutil.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            hdiutil.arguments = ["attach", "-nobrowse", "-readonly", "-mountpoint", mountPoint.path, packageURL.path]
            try hdiutil.run()
            hdiutil.waitUntilExit()

            let appInMount = mountPoint.appendingPathComponent("MacKitty.app")
            let appInExtract = extractDir.appendingPathComponent("MacKitty.app")
            if fileManager.fileExists(atPath: appInMount.path) {
                let cp = Process()
                cp.executableURL = URL(fileURLWithPath: "/bin/cp")
                cp.arguments = ["-R", appInMount.path, appInExtract.path]
                try cp.run()
                cp.waitUntilExit()
            }

            // Detach DMG
            let detach = Process()
            detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            detach.arguments = ["detach", mountPoint.path, "-force"]
            try? detach.run()
            detach.waitUntilExit()
        }

        // Find MacKitty.app in extractDir
        let potentialAppURLs = [
            extractDir.appendingPathComponent("MacKitty.app"),
            extractDir.appendingPathComponent("dist/MacKitty.app")
        ]

        guard let appURL = potentialAppURLs.first(where: { fileManager.fileExists(atPath: $0.path) }) else {
            throw NSError(domain: "MacKittyUpdate", code: 2, userInfo: [NSLocalizedDescriptionKey: "MacKitty.app not found inside update package."])
        }

        // Verify code signature integrity
        let codesign = Process()
        codesign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        codesign.arguments = ["--verify", "--deep", "--strict", appURL.path]
        try codesign.run()
        codesign.waitUntilExit()

        guard codesign.terminationStatus == 0 else {
            throw NSError(domain: "MacKittyUpdate", code: 3, userInfo: [NSLocalizedDescriptionKey: "Code signature verification failed on downloaded update."])
        }

        return appURL
    }

    // MARK: - In-Place Replacement & Relaunch

    private func replaceAndRelaunch(extractedAppURL: URL) throws {
        let currentAppURL = Bundle.main.bundleURL
        let targetPath: String

        if currentAppURL.path.contains("/Applications") {
            targetPath = currentAppURL.path
        } else if FileManager.default.isWritableFile(atPath: "/Applications") {
            targetPath = "/Applications/MacKitty.app"
        } else {
            targetPath = currentAppURL.path
        }

        // Self-executing bash script that replaces the app and relaunches
        let script = """
        sleep 0.8
        rm -rf "\(targetPath)"
        cp -R "\(extractedAppURL.path)" "\(targetPath)"
        xattr -cr "\(targetPath)" 2>/dev/null || true
        touch "\(targetPath)"
        open -n "\(targetPath)"
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script]
        try process.run()

        NSApp.terminate(nil)
    }

    private func isVersion(_ v1: String, higherThan v2: String) -> Bool {
        v1.compare(v2, options: .numeric) == .orderedDescending
    }
}
