import AppKit
import SwiftUI

/// The on/off switch for the notch task tray (Settings and the menu bar menu).
enum NotchTasksSetting {
    static let key = "notchTasksEnabled"

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

/// What the SwiftUI tray renders. The controller drives it.
@MainActor
final class NotchTrayState: ObservableObject {
    @Published var isOpen = false
    /// The shape the tray grows out of and folds back into: the camera housing,
    /// or a thin stand-in on screens without one.
    @Published var notchSize = CGSize(width: 200, height: 32)
    @Published var hasNotch = true
    /// The "Add a task" text. Lives here so a half-typed task survives the tray closing.
    @Published var draft = ""
    @Published var isEditing = false
    /// Bumped when the panel becomes key, so the view can put the cursor in the input field.
    @Published var focusRequest = 0
    /// Laid-out size of the tray, for hover hit-testing. Nothing renders from it.
    var islandSize: CGSize = .zero
}

/// Opens a task tray out of the camera notch when the pointer rests on it.
///
/// Hover is detected from mouse events and `NSEvent.mouseLocation`, not from a
/// window parked over the notch, so nothing sits on top of the menu bar while the
/// tray is closed. On screens without a notch, a thin strip at the top centre of
/// the screen stands in for it.
@MainActor
final class NotchTrayController {
    private struct HotZone {
        /// Where resting the pointer opens the tray, in screen coordinates.
        let rect: NSRect
        let screenFrame: NSRect
        let notchSize: CGSize
        let hasNotch: Bool

        /// Inclusive at the top: against the top edge of the screen the pointer sits at `maxY`.
        func contains(_ point: NSPoint) -> Bool {
            point.x >= rect.minX && point.x <= rect.maxX && point.y >= rect.minY && point.y <= rect.maxY + 1
        }
    }

    /// Room for the tallest tray; the SwiftUI content is pinned to its top edge.
    private static let panelSize = NSSize(width: NotchTrayLayout.openWidth, height: NotchTrayLayout.maxHeight)
    /// Resting time before opening, so sweeping past the notch doesn't pop the tray.
    private static let openDelay: Duration = .milliseconds(120)
    /// Grace period after the pointer leaves before the tray folds away.
    private static let closeDelay: Duration = .milliseconds(350)

    private let store = TaskStore()
    private let state = NotchTrayState()
    private var panel: NotchPanel?
    private var zones: [HotZone] = []
    private var currentZone: HotZone?
    /// The controller's truth; `state.isOpen` follows it with an animation.
    private var isPresented = false
    /// Set when the tray closes with the pointer still on the notch, so it doesn't pop right back open.
    private var needsPointerToLeave = false
    private var openTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?
    private var eventMonitors: [Any] = []
    private var activeAppTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.applyEnabledSetting()
            }
        })
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.screensChanged()
            }
        })
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.startActiveAppTimer()
            }
        })
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.stopActiveAppTimer()
            }
        })
        rebuildZones()
        applyEnabledSetting()
    }

    // MARK: Enabling

    private func applyEnabledSetting() {
        if NotchTasksSetting.isEnabled {
            installEventMonitors()
            if NSApp.isActive { startActiveAppTimer() }
        } else {
            close(animated: false)
            removeEventMonitors()
            stopActiveAppTimer()
        }
    }

    /// Mouse events need no permission to monitor (only key events do).
    private func installEventMonitors() {
        guard eventMonitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown]

        // Copies of the events other apps receive. Monitor handlers run on the main thread.
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let isClick = event.type != .mouseMoved
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pointerChanged(isClick: isClick)
            }
        }) {
            eventMonitors.append(monitor)
        }

        // MacKitty's own events, including clicks inside the tray.
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let isClick = event.type != .mouseMoved
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pointerChanged(isClick: isClick)
            }
            return event
        }) {
            eventMonitors.append(monitor)
        }
    }

    private func removeEventMonitors() {
        for monitor in eventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        eventMonitors.removeAll()
    }

    /// The global monitor only sees other apps' events, so while MacKitty itself is
    /// frontmost the pointer is sampled instead, ten times a second.
    private func startActiveAppTimer() {
        guard NotchTasksSetting.isEnabled, activeAppTimer == nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pointerChanged(isClick: false)
            }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        activeAppTimer = timer
    }

    private func stopActiveAppTimer() {
        activeAppTimer?.invalidate()
        activeAppTimer = nil
    }

    // MARK: Screens

    private func screensChanged() {
        close(animated: false)
        rebuildZones()
    }

    private func rebuildZones() {
        zones = NSScreen.screens.map { Self.hotZone(for: $0) }
    }

    private static func hotZone(for screen: NSScreen) -> HotZone {
        let frame = screen.frame
        // The camera housing sits between the two unobscured top areas.
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea,
           right.minX > left.maxX {
            let height = screen.safeAreaInsets.top
            let rect = NSRect(x: left.maxX, y: frame.maxY - height, width: right.minX - left.maxX, height: height)
            return HotZone(rect: rect, screenFrame: frame, notchSize: rect.size, hasNotch: true)
        }
        let width = NotchTrayLayout.fallbackZoneWidth
        let rect = NSRect(x: frame.midX - width / 2, y: frame.maxY - 3, width: width, height: 3)
        return HotZone(rect: rect, screenFrame: frame, notchSize: CGSize(width: width, height: 6), hasNotch: false)
    }

    // MARK: Pointer

    private func pointerChanged(isClick: Bool) {
        guard NotchTasksSetting.isEnabled else { return }
        let point = NSEvent.mouseLocation

        if isPresented {
            if isInsideTray(point) {
                cancelClose()
            } else if isClick {
                close()
            } else if !keepsOpen {
                scheduleClose()
            }
            return
        }

        guard let zone = zones.first(where: { $0.contains(point) }) else {
            needsPointerToLeave = false
            cancelOpen()
            return
        }
        guard !needsPointerToLeave, openTask == nil else { return }
        openTask = Task { [weak self] in
            try? await Task.sleep(for: NotchTrayController.openDelay)
            guard let self, !Task.isCancelled else { return }
            self.openTask = nil
            // Still resting on the notch, and not dragging a window or file past it.
            guard zone.contains(NSEvent.mouseLocation), NSEvent.pressedMouseButtons == 0 else { return }
            self.open(on: zone)
        }
    }

    private func isInsideTray(_ point: NSPoint) -> Bool {
        if currentZone?.contains(point) == true { return true }
        guard let panel else { return false }
        let size = state.islandSize == .zero ? panel.frame.size : state.islandSize
        let island = NSRect(
            x: panel.frame.midX - size.width / 2,
            y: panel.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        return island.insetBy(dx: -6, dy: -6).contains(point)
    }

    /// A half-typed task keeps the tray open when the pointer drifts off.
    private var keepsOpen: Bool {
        state.isEditing && !state.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private func cancelOpen() {
        openTask?.cancel()
        openTask = nil
    }

    private func cancelClose() {
        closeTask?.cancel()
        closeTask = nil
    }

    private func scheduleClose() {
        guard closeTask == nil else { return }
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: NotchTrayController.closeDelay)
            guard let self, !Task.isCancelled else { return }
            self.closeTask = nil
            guard !self.isInsideTray(NSEvent.mouseLocation), !self.keepsOpen else { return }
            self.close()
        }
    }

    // MARK: Open & close

    private func open(on zone: HotZone) {
        guard !isPresented else { return }
        let panel = self.panel ?? makePanel()
        isPresented = true
        currentZone = zone
        cancelClose()
        state.notchSize = zone.notchSize
        state.hasNotch = zone.hasNotch

        let size = Self.panelSize
        panel.setFrame(
            NSRect(x: (zone.rect.midX - size.width / 2).rounded(), y: zone.screenFrame.maxY - size.height, width: size.width, height: size.height),
            display: true
        )
        panel.orderFrontRegardless()
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()

        // Let the closed shape render in place first, so the spring starts from the notch.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isPresented else { return }
                withAnimation(self.reduceMotion ? .easeOut(duration: 0.2) : NotchTrayLayout.openAnimation) {
                    self.state.isOpen = true
                }
            }
        }
    }

    func close(animated: Bool = true) {
        cancelOpen()
        cancelClose()
        guard isPresented else { return }
        isPresented = false
        needsPointerToLeave = currentZone?.contains(NSEvent.mouseLocation) ?? false
        state.isEditing = false

        let hide = { [weak self] in
            guard let self, !self.isPresented else { return }
            self.panel?.orderOut(nil)
        }
        guard animated else {
            state.isOpen = false
            hide()
            return
        }
        withAnimation(reduceMotion ? .easeIn(duration: 0.15) : NotchTrayLayout.closeAnimation, completionCriteria: .logicallyComplete) {
            state.isOpen = false
        } completion: {
            hide()
        }
    }

    private func makePanel() -> NotchPanel {
        let size = Self.panelSize
        let panel = NotchPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        // Above the menu bar, below menus; on every Space, including full-screen ones.
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)

        let container = TrayTrackingView(frame: NSRect(origin: .zero, size: size))
        container.onPointerEvent = { [weak self] in self?.pointerChanged(isClick: false) }
        let hosting = FirstMouseHostingView(rootView: NotchTrayView(state: state, store: store, onClose: { [weak self] in
            self?.close()
        }))
        hosting.sizingOptions = []
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        panel.contentView = container

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.state.focusRequest += 1
            }
        })
        // Clicking or switching to another app while typing.
        observers.append(center.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isPresented, !self.isInsideTray(NSEvent.mouseLocation) else { return }
                self.close()
            }
        })

        self.panel = panel
        return panel
    }
}

/// Borderless windows can't become key unless they say so, and the tray must,
/// so its input field can take typing. Being a non-activating panel, it does
/// that without bringing MacKitty to the front.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Content view of the tray panel. Its tracking area reports the pointer over
/// the tray even while another app is active.
final class TrayTrackingView: NSView {
    var onPointerEvent: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseEntered(with event: NSEvent) { onPointerEvent?() }
    override func mouseExited(with event: NSEvent) { onPointerEvent?() }
    override func mouseMoved(with event: NSEvent) { onPointerEvent?() }
}

/// Lets the tray's buttons take the first click, though MacKitty isn't the active app.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
