import Foundation
import AppKit
import Security

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
    private var periodicCheck: Timer?
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
        // MacKitty often lives in the menu bar for days; keep checking quietly.
        periodicCheck = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isInstalling else { return }
                await self.checkForUpdates(silent: true)
            }
        }
    }

    func checkForUpdates(silent: Bool = false) async {
        // App Store builds are updated by the App Store.
        if isAppStoreBuild { return }
        isChecking = true
        if !silent {
            statusMessage = "Checking for updates…"
        }

        // Only the GitHub Releases API is trusted. The downloaded build is
        // additionally verified against MacKitty's signing identity before install.
        let endpoints = [
            "https://api.github.com/repos/SaiAkashNeela/mackitty/releases/latest"
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

                if let rawVer = (json["tag_name"] as? String) ?? (json["version"] as? String),
                   let cleanVer = Self.sanitizedVersion(rawVer) {
                    foundVersion = cleanVer

                    if let body = json["body"] as? String {
                        foundNotes = body
                    }

                    if let htmlUrl = json["html_url"] as? String, Self.isTrustedURL(htmlUrl) {
                        foundReleaseURL = htmlUrl
                    }

                    // Look for zip asset first (best for in-place replacement), then dmg asset
                    if let assets = json["assets"] as? [[String: Any]] {
                        if let zipAsset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".zip") == true }),
                           let zipUrl = zipAsset["browser_download_url"] as? String, Self.isTrustedURL(zipUrl) {
                            foundAssetURL = zipUrl
                        } else if let dmgAsset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".dmg") == true }),
                                  let dmgUrl = dmgAsset["browser_download_url"] as? String, Self.isTrustedURL(dmgUrl) {
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
            self.packageAssetURL = foundAssetURL
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
        session.finishTasksAndInvalidate()

        guard let http = downloadTask.response as? HTTPURLResponse, http.statusCode == 200 else {
            Task { @MainActor in
                self.downloadContinuation?.resume(throwing: NSError(domain: "MacKittyUpdate", code: 5, userInfo: [NSLocalizedDescriptionKey: "The update server returned an error. Please try again later."]))
                self.downloadContinuation = nil
            }
            return
        }

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
            session.invalidateAndCancel()
            Task { @MainActor in
                self.downloadContinuation?.resume(throwing: error)
                self.downloadContinuation = nil
            }
        }
    }

    // MARK: - Extraction & Verification

    nonisolated private func extractAndVerifyPackage(at packageURL: URL) async throws -> URL {
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
            guard hdiutil.terminationStatus == 0 else {
                throw NSError(domain: "MacKittyUpdate", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to open the update disk image."])
            }

            let appInMount = mountPoint.appendingPathComponent("MacKitty.app")
            let appInExtract = extractDir.appendingPathComponent("MacKitty.app")
            if fileManager.fileExists(atPath: appInMount.path) {
                let cp = Process()
                cp.executableURL = URL(fileURLWithPath: "/bin/cp")
                cp.arguments = ["-R", appInMount.path, appInExtract.path]
                try cp.run()
                cp.waitUntilExit()
                guard cp.terminationStatus == 0 else {
                    throw NSError(domain: "MacKittyUpdate", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to copy the update from the disk image."])
                }
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

        try Self.verifyTrustedBuild(at: appURL)
        return appURL
    }

    // MARK: - In-Place Replacement & Relaunch

    private func replaceAndRelaunch(extractedAppURL: URL) throws {
        let target = Bundle.main.bundleURL
        // Only ever replace an installed MacKitty bundle, never an arbitrary directory.
        guard target.pathExtension == "app",
              Bundle(url: target)?.bundleIdentifier == Self.bundleIdentifier else {
            throw NSError(domain: "MacKittyUpdate", code: 6, userInfo: [NSLocalizedDescriptionKey: "MacKitty isn't running from an installed app bundle. Please download the update manually."])
        }

        // Atomic swap (rename on the same volume); the old bundle is removed only on success.
        _ = try FileManager.default.replaceItemAt(target, withItemAt: extractedAppURL)

        // Relaunch only once this process has really exited (up to 10 s), so two
        // copies never run side by side. Paths and PID are passed as arguments,
        // never interpolated into the shell script.
        let pid = String(ProcessInfo.processInfo.processIdentifier)
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = [
            "-c",
            "i=0; while kill -0 \"$2\" 2>/dev/null && [ $i -lt 100 ]; do sleep 0.1; i=$((i+1)); done; /usr/bin/open \"$1\"",
            "mackitty-relaunch", target.path, pid
        ]
        try relaunch.run()

        NSApp.terminate(nil)
        // An open sheet or popover can stall a normal quit; the update is already
        // installed, so make sure this old copy goes away.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { exit(0) }
    }

    // MARK: - Trust checks

    nonisolated static let bundleIdentifier = "com.mackitty.app"
    nonisolated static let teamIdentifier = "8GG7J6LQZL"

    /// The downloaded app must be MacKitty, signed by MacKitty's Developer ID team,
    /// with every nested component intact, and accepted by Gatekeeper (notarized).
    nonisolated static func verifyTrustedBuild(at appURL: URL) throws {
        let failure = { (detail: String) in
            NSError(domain: "MacKittyUpdate", code: 3, userInfo: [NSLocalizedDescriptionKey: "The downloaded update failed verification (\(detail)). It was not installed."])
        }

        guard Bundle(url: appURL)?.bundleIdentifier == bundleIdentifier else { throw failure("unexpected app") }

        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(appURL as CFURL, [], &staticCode) == errSecSuccess, let staticCode else {
            throw failure("unreadable signature")
        }
        let requirementText = "identifier \"\(bundleIdentifier)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess, let requirement else {
            throw failure("requirement")
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidity(staticCode, flags, requirement) == errSecSuccess else {
            throw failure("signature")
        }

        // Gatekeeper assessment confirms Apple notarized this exact build.
        let spctl = Process()
        spctl.executableURL = URL(fileURLWithPath: "/usr/sbin/spctl")
        spctl.arguments = ["--assess", "--type", "execute", appURL.path]
        spctl.standardOutput = FileHandle.nullDevice
        spctl.standardError = FileHandle.nullDevice
        try spctl.run()
        spctl.waitUntilExit()
        guard spctl.terminationStatus == 0 else { throw failure("not notarized") }
    }

    /// Release downloads must come from GitHub over HTTPS.
    nonisolated static func isTrustedURL(_ string: String) -> Bool {
        guard let url = URL(string: string), url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return ["github.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com"].contains(host)
    }

    /// Accepts "v1.2.3" or "1.2.3"; rejects anything that isn't a plain dotted version.
    nonisolated static func sanitizedVersion(_ raw: String) -> String? {
        var v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.hasPrefix("v") || v.hasPrefix("V") { v.removeFirst() }
        return v.range(of: #"^\d+(\.\d+){0,3}$"#, options: .regularExpression) != nil ? v : nil
    }

    private func isVersion(_ v1: String, higherThan v2: String) -> Bool {
        v1.compare(v2, options: .numeric) == .orderedDescending
    }
}
