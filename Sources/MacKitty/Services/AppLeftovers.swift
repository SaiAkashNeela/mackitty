import Foundation

/// What an app leaves behind after its bundle is gone: data, caches and preferences in
/// the user's Library, and background jobs it installed (VPN and virtualization helpers).
/// Matched only by the app's bundle ID, its exact name, or a launchd job that runs a
/// program from inside the app, so another app's files are never picked up.
struct AppLeftovers {
    /// In the user's Library; moved to the Trash.
    var userItems: [URL] = []
    /// Launch daemons and privileged helpers in /Library; removing them needs an admin password.
    var systemItems: [URL] = []
    var bytes: Int64 = 0

    var isEmpty: Bool { userItems.isEmpty && systemItems.isEmpty }
    var count: Int { userItems.count + systemItems.count }
    var sizeText: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

    static func find(
        for app: URL,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        systemLibrary: URL = URL(fileURLWithPath: "/Library")
    ) -> AppLeftovers {
        #if APPSTORE
        return AppLeftovers()
        #else
        // Apple's apps share folders with macOS itself.
        guard let bundleID = Bundle(url: app)?.bundleIdentifier, !bundleID.hasPrefix("com.apple.") else { return AppLeftovers() }
        let fm = FileManager.default
        let name = app.deletingPathExtension().lastPathComponent
        let library = home.appendingPathComponent("Library")
        var result = AppLeftovers()

        let paths = [
            "Application Support/\(bundleID)", "Application Support/\(name)",
            "Caches/\(bundleID)", "HTTPStorages/\(bundleID)", "WebKit/\(bundleID)",
            "Preferences/\(bundleID).plist", "Saved Application State/\(bundleID).savedState",
            "Logs/\(bundleID)", "Logs/\(name)"
        ]
        result.userItems = paths.map { library.appendingPathComponent($0) }.filter { fm.fileExists(atPath: $0.path) }
        result.userItems += launchJobs(in: library.appendingPathComponent("LaunchAgents"), bundleID: bundleID, app: app)

        let helpers = systemLibrary.appendingPathComponent("PrivilegedHelperTools").path + "/"
        for folder in ["LaunchDaemons", "LaunchAgents"] {
            let jobs = launchJobs(in: systemLibrary.appendingPathComponent(folder), bundleID: bundleID, app: app)
            result.systemItems += jobs
            // The helper binary a daemon runs, if it lives with the other privileged helpers.
            result.systemItems += jobs.compactMap(program).filter { $0.path.hasPrefix(helpers) && fm.fileExists(atPath: $0.path) }
        }
        result.systemItems += ((try? fm.contentsOfDirectory(atPath: helpers)) ?? [])
            .filter { $0.hasPrefix(bundleID + ".") || $0 == bundleID }
            .map { URL(fileURLWithPath: helpers + $0) }

        result.userItems = unique(result.userItems)
        result.systemItems = unique(result.systemItems)
        result.bytes = (result.userItems + result.systemItems).reduce(0) { $0 + ProjectArtifactScanner.measure($1).bytes }
        return result
        #endif
    }

    /// launchd plists named after the bundle ID, or that run a program from inside the app.
    private static func launchJobs(in folder: URL, bundleID: String, app: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let appPath = app.path + "/"
        return files.filter { file in
            file.pathExtension == "plist"
                && (file.lastPathComponent.hasPrefix(bundleID + ".") || program(of: file)?.path.hasPrefix(appPath) == true)
        }
    }

    /// The executable a launchd plist starts. A path with ".." could point anywhere, so it never matches.
    private static func program(of plist: URL) -> URL? {
        guard let job = NSDictionary(contentsOf: plist),
              let path = job["Program"] as? String ?? (job["ProgramArguments"] as? [String])?.first,
              !path.components(separatedBy: "/").contains("..") else { return nil }
        return URL(fileURLWithPath: path)
    }

    private static func unique(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.path.lowercased()).inserted }
    }

    // MARK: - Removing

    /// Stops the user's own launch agents, then moves everything to the Trash. Returns what failed.
    static func moveToTrash(_ items: [URL]) -> [URL] {
        items.filter { item in
            if item.deletingLastPathComponent().lastPathComponent == "LaunchAgents" {
                launchctl(["bootout", "gui/\(getuid())", item.path])
            }
            return (try? FileManager.default.trashItem(at: item, resultingItemURL: nil)) == nil
        }
    }

    /// Stops the background jobs and deletes them and their helpers, after the user types
    /// their admin password in the standard macOS prompt. Files only, never folders.
    static func removeWithAdminPassword(_ items: [URL]) -> Bool {
        func quoted(_ url: URL) -> String { "'" + url.path.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let stops = items.filter { $0.pathExtension == "plist" }.map { item in
            let domain = item.deletingLastPathComponent().lastPathComponent == "LaunchDaemons" ? "system" : "gui/\(getuid())"
            return "/bin/launchctl bootout \(domain) \(quoted(item)) 2>/dev/null"
        }
        let shell = (stops + ["/bin/rm -f -- " + items.map(quoted).joined(separator: " ")]).joined(separator: "; ")
        let escaped = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var error: NSDictionary?
        NSAppleScript(source: "do shell script \"\(escaped)\" with administrator privileges")?.executeAndReturnError(&error)
        return error == nil
    }

    private static func launchctl(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return }
        process.waitUntilExit()
    }
}
