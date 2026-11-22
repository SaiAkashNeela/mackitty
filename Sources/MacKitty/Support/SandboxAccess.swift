import AppKit

/// True for the sandboxed Mac App Store build (compiled with -DAPPSTORE).
#if APPSTORE
let isAppStoreBuild = true
#else
let isAppStoreBuild = false
#endif

/// Mac App Store builds run in the App Sandbox, where the app's "home" is its
/// own container. The user grants access to their real home folder once; the
/// grant is kept as an app-scoped security bookmark so scans and cleanups can
/// reach ~/Library/Caches, ~/Library/Logs and friends.
enum SandboxAccess {
    private static let bookmarkKey = "home-folder-bookmark"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var activeHome: URL?

    /// The user's real home directory, not the sandbox container.
    static var realHomeURL: URL {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static var hasAccess: Bool { homeURL() != nil }

    /// Resolves the stored bookmark and keeps it accessed for the app's lifetime.
    static func homeURL() -> URL? {
        lock.lock(); defer { lock.unlock() }
        if let activeHome { return activeHome }
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource() else {
            return nil
        }
        if stale, let fresh = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: bookmarkKey)
        }
        activeHome = url
        return url
    }

    /// Asks the user to grant their home folder. Returns true once access is stored.
    @MainActor
    static func requestHomeAccess() -> Bool {
        let panel = NSOpenPanel()
        panel.message = "Choose your home folder so MacKitty can find caches and logs. Nothing is removed without your review."
        panel.prompt = "Grant Access"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = realHomeURL.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return false }

        // Only the home folder itself works: every cleanup target is relative to it.
        guard url.standardizedFileURL.path == realHomeURL.standardizedFileURL.path,
              let data = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) else {
            return false
        }
        UserDefaults.standard.set(data, forKey: bookmarkKey)
        return homeURL() != nil
    }
}
