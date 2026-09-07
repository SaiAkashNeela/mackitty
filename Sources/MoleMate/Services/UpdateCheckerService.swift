import Foundation
import AppKit

@MainActor
final class UpdateCheckerService: ObservableObject {
    @Published var isChecking: Bool = false
    @Published var isUpdateAvailable: Bool = false
    @Published var latestVersion: String = "1.0.0"
    @Published var updateURL: String = "https://github.com/SaiAkashNeela/mackitty/releases/latest"
    @Published var lastCheckedText: String = "Not checked yet"
    @Published var statusMessage: String = "MacKitty is up to date"

    var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
    }

    init() {
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

        // Endpoint candidates in order of priority:
        // 1. Official GitHub Releases API (automatically updated by CI/CD on every release)
        // 2. Custom domain version API
        let endpoints = [
            "https://api.github.com/repos/SaiAkashNeela/mackitty/releases/latest",
            "https://mackitty.com/api/version.json"
        ]

        var foundVersion: String?
        var foundURL: String?

        for endpointStr in endpoints {
            guard let url = URL(string: endpointStr) else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 5.0
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("MacKitty-macOS/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continue
                }

                // Extract version: supports "tag_name" (GitHub) and "version" (custom JSON)
                if let rawVer = (json["tag_name"] as? String) ?? (json["version"] as? String) {
                    let cleanVer = rawVer.replacingOccurrences(of: "v", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    foundVersion = cleanVer

                    // Extract user-facing download URL:
                    // Check for direct .dmg asset first
                    if let assets = json["assets"] as? [[String: Any]],
                       let dmgAsset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".dmg") == true }),
                       let downloadUrl = dmgAsset["browser_download_url"] as? String {
                        foundURL = downloadUrl
                    } else if let htmlUrl = json["html_url"] as? String {
                        foundURL = htmlUrl
                    } else if let customUrl = json["url"] as? String {
                        foundURL = customUrl
                    }

                    break // successfully obtained update info
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
            self.updateURL = foundURL ?? "https://github.com/SaiAkashNeela/mackitty/releases/latest"
            self.statusMessage = available ? "New version v\(newVersion) is available!" : "MacKitty is up to date (v\(self.currentVersion))"
        } else {
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
