import AppKit

/// Owns the main window's show/hide behaviour. Closing the window hides it and
/// removes MacKitty from the Dock; the menu bar icon keeps the app reachable.
@MainActor
enum MainWindow {
    /// Strong reference so the window survives being closed and can be shown again.
    private(set) static var window: NSWindow?
    private static let closeHandler = CloseToTrayHandler()
    private static var closeObserver: NSObjectProtocol?

    static func adopt(_ window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window
        window.isReleasedWhenClosed = false

        // Red close button hides instead of closing, keeping all window state.
        if let close = window.standardWindowButton(.closeButton) {
            close.target = closeHandler
            close.action = #selector(CloseToTrayHandler.hideWindow(_:))
        }

        // ⌘W or any other real close: still drop out of the Dock.
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { _ in
            MainActor.assumeIsolated { _ = NSApp.setActivationPolicy(.accessory) }
        }
    }

    static func hide() {
        window?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }

    static func show() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        guard let window = window ?? NSApp.windows.first(where: { $0.canBecomeMain }) else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
    }
}

final class CloseToTrayHandler: NSObject {
    @MainActor @objc func hideWindow(_ sender: Any?) {
        MainWindow.hide()
    }
}
