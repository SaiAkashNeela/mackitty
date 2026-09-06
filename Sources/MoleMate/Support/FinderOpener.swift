import AppKit

enum FinderOpener {
    static func open(path: String) {
        let expandedPath = (path as NSString).expandingTildeInPath
        NSWorkspace.shared.open(URL(fileURLWithPath: expandedPath, isDirectory: true))
    }
}
