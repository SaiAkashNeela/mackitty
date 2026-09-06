import AppKit
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private weak var model: DashboardModel?

    init(model: DashboardModel) {
        self.model = model
        super.init()
        setupStatusItem()
        setupPopover()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let symbolConfig = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            if let image = NSImage(systemSymbolName: "cat.fill", accessibilityDescription: "MacKitty")?.withSymbolConfiguration(symbolConfig) {
                image.isTemplate = true
                button.image = image
            } else if let fallback = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "MacKitty")?.withSymbolConfiguration(symbolConfig) {
                fallback.isTemplate = true
                button.image = fallback
            }
            button.toolTip = "MacKitty · Mac Cleaner & Monitor"
            button.target = self
            button.action = #selector(statusBarButtonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        self.statusItem = item
    }

    private func setupPopover() {
        guard let model else { return }
        let pop = NSPopover()
        pop.behavior = .transient
        pop.animates = true
        pop.appearance = NSAppearance(named: .darkAqua)

        let view = TrayMiniDashboardView(model: model, onClose: { [weak self] in
            self?.closePopover()
        })
        let hostingController = NSHostingController(rootView: view)
        pop.contentViewController = hostingController
        self.popover = pop
    }

    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            togglePopover(sender)
            return
        }

        if event.type == .rightMouseUp {
            popover?.performClose(nil)
            showContextMenu(sender)
        } else {
            togglePopover(sender)
        }
    }

    private func togglePopover(_ sender: NSStatusBarButton) {
        guard let popover else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }

    func closePopover() {
        popover?.performClose(nil)
    }

    private func showContextMenu(_ sender: NSStatusBarButton) {
        let menu = NSMenu()

        let openItem = NSMenuItem(title: "Open MacKitty", action: #selector(openApp), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        let cleanItem = NSMenuItem(title: "Clean My Mac Now", action: #selector(cleanNow), keyEquivalent: "c")
        cleanItem.target = self
        menu.addItem(cleanItem)

        let scanItem = NSMenuItem(title: "Scan System", action: #selector(analyzeSystem), keyEquivalent: "s")
        scanItem.target = self
        menu.addItem(scanItem)

        menu.addItem(NSMenuItem.separator())

        if let model = model, model.updater.isUpdateAvailable {
            let updateItem = NSMenuItem(
                title: "🚀 Update Available (v\(model.updater.latestVersion))",
                action: #selector(openUpdate),
                keyEquivalent: "u"
            )
            updateItem.target = self
            menu.addItem(updateItem)
            menu.addItem(NSMenuItem.separator())
        }

        let aboutItem = NSMenuItem(title: "About MacKitty…", action: #selector(openAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Quit MacKitty", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    // MARK: - Actions
    @objc private func openApp() {
        closePopover()
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title == "MacKitty" || $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
            window.deminiaturize(nil)
        }
    }

    @objc private func openUpdate() {
        closePopover()
        model?.updater.openDownloadPage()
    }

    @objc private func openAbout() {
        openApp()
        model?.showAbout = true
    }

    @objc private func cleanNow() {
        openApp()
        model?.selectAllCleanupAreas()
        model?.clean()
    }

    @objc private func analyzeSystem() {
        openApp()
        model?.resetForFreshScan()
        model?.scan()
    }

    @objc private func quitApp() {
        closePopover()
        NSApp.terminate(nil)
    }
}
