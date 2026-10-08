import AppKit

enum FinderOpener {
    /// Reveals the item in Finder (never launches it). Non-filesystem paths are ignored.
    static func open(path: String) {
        // In the App Store sandbox "~" is the container, so map to the real home.
        let expandedPath = isAppStoreBuild && path.hasPrefix("~/")
            ? SandboxAccess.realHomeURL.appendingPathComponent(String(path.dropFirst(2))).path
            : (path as NSString).expandingTildeInPath
        guard expandedPath.hasPrefix("/"), FileManager.default.fileExists(atPath: expandedPath) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: expandedPath)])
    }
}
