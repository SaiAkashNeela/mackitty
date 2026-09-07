import Foundation
import AppKit

final class UpdateCheckerService: ObservableObject {
    @Published var isChecking: Bool = false
    @Published var isUpdateAvailable: Bool = false
    @Published var latestVersion: String = "1.0.0"
    @Published var updateURL: String = "https://mackitty.com"
    @Published var lastCheckedText: String = "Not checked yet"
    @Published var statusMessage: String = "You are on the latest version (v1.0.0)"

    let currentVersion = "1.0.0"

    init() {
        // Run a lightweight background update check on startup
        Task { [weak self] in
            await self?.checkForUpdates(silent: true)
        }
    }

    func checkForUpdates(silent: Bool = false) async {
        await MainActor.run {
            isChecking = true
            if !silent {
                statusMessage = "Checking mackitty.com for updates…"
            }
        }

        // Check remote endpoint
        let endpoint = URL(string: "https://mackitty.com/api/version.json") ?? URL(string: "https://api.github.com/repos/SaiAkashNeela/mackitty/releases/latest")!
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 4.0
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let remoteVer = (json["version"] as? String) ?? (json["tag_name"] as? String) {
                let cleanVer = remoteVer.replacingOccurrences(of: "v", with: "").trimmingCharacters(in: .whitespaces)
                let available = isVersion(cleanVer, higherThan: currentVersion)
                await MainActor.run {
                    self.latestVersion = cleanVer
                    self.isUpdateAvailable = available
                    self.updateURL = (json["url"] as? String) ?? "https://mackitty.com"
                    self.lastCheckedText = "Just now"
                    self.statusMessage = available ? "New version v\(cleanVer) is available!" : "MacKitty is up to date (v\(self.currentVersion))"
                    self.isChecking = false
                }
                return
            }
        } catch {
            // Graceful fallback for offline / serverless setup
        }

        await MainActor.run {
            self.isChecking = false
            self.lastCheckedText = "Just now"
            if !self.isUpdateAvailable {
                self.statusMessage = "MacKitty is up to date (v\(self.currentVersion))"
            }
        }
    }

    func openDownloadPage() {
        if let url = URL(string: updateURL) {
            NSWorkspace.shared.open(url)
        }
    }

    private func isVersion(_ v1: String, higherThan v2: String) -> Bool {
        v1.compare(v2, options: .numeric) == .orderedDescending
    }
}
