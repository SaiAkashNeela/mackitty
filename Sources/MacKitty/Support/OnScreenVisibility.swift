import AppKit
import SwiftUI

/// Tracks whether this view's window is actually on screen. Closing MacKitty's
/// window only orders it out, so SwiftUI's onDisappear never fires; occlusion does,
/// and it also covers hidden, minimized and fully covered windows and closed popovers.
class OcclusionTrackingView: NSView {
    private(set) var isOnScreen = false
    var onChange: (Bool) -> Void = { _ in }
    private var observer: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = window.map {
            NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: $0, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        refresh()
    }

    func refresh() {
        let visible = window?.occlusionState.contains(.visible) ?? false
        guard visible != isOnScreen else { return }
        isOnScreen = visible
        // Deferred: this can run inside a SwiftUI update, where state changes are not allowed.
        DispatchQueue.main.async { [onChange] in onChange(visible) }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}

private struct OnScreenReader: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> OcclusionTrackingView {
        let view = OcclusionTrackingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: OcclusionTrackingView, context: Context) {
        nsView.onChange = onChange
    }
}

extension View {
    /// Calls `action` with true when this view's window comes on screen and false
    /// when it is closed, hidden, minimized or fully covered.
    func onScreenChange(_ action: @escaping (Bool) -> Void) -> some View {
        background(OnScreenReader(onChange: action))
    }
}
