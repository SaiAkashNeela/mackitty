import AppKit
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private weak var model: DashboardModel?

    init(model: DashboardModel) {
        self.model = model
        super.init()
        setupStatusItem()
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
        }

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        self.statusItem = item
    }

    // MARK: - NSMenuDelegate (Dynamic updates on every click)
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let model else { return }

        // 1. Header with live status
        let headerItem = NSMenuItem(title: "MacKitty", action: #selector(openApp), keyEquivalent: "")
        headerItem.target = self
        if let icon = NSImage(systemSymbolName: "cat.fill", accessibilityDescription: nil) {
            icon.isTemplate = true
            headerItem.image = icon
        }
        menu.addItem(headerItem)

        let statusSubtitle = NSMenuItem(
            title: "RAM: \(model.monitor.memoryUsedText) · Disk Free: \(model.diskFreeText)",
            action: nil,
            keyEquivalent: ""
        )
        statusSubtitle.isEnabled = false
        menu.addItem(statusSubtitle)

        menu.addItem(NSMenuItem.separator())

        // 2. Simple Tasks / Quick Actions
        let cleanItem = NSMenuItem(title: "Clean My Mac Now", action: #selector(cleanNow), keyEquivalent: "c")
        cleanItem.keyEquivalentModifierMask = [.command, .shift]
        cleanItem.target = self
        if let img = NSImage(systemSymbolName: "trash.fill", accessibilityDescription: nil) {
            img.isTemplate = true
            cleanItem.image = img
        }
        menu.addItem(cleanItem)

        let scanItem = NSMenuItem(title: "Analyze / Scan System", action: #selector(analyzeSystem), keyEquivalent: "s")
        scanItem.keyEquivalentModifierMask = [.command, .shift]
        scanItem.target = self
        if let img = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil) {
            img.isTemplate = true
            scanItem.image = img
        }
        menu.addItem(scanItem)

        menu.addItem(NSMenuItem.separator())

        // 3. Live System Telemetry
        let statsHeader = NSMenuItem(title: "LIVE SYSTEM STATS", action: nil, keyEquivalent: "")
        statsHeader.isEnabled = false
        menu.addItem(statsHeader)

        let cpuItem = NSMenuItem(
            title: "CPU: \(model.monitor.cpuText) (\(model.monitor.chipName))",
            action: nil,
            keyEquivalent: ""
        )
        if let img = NSImage(systemSymbolName: "cpu", accessibilityDescription: nil) {
            img.isTemplate = true
            cpuItem.image = img
        }
        menu.addItem(cpuItem)

        let totalRAM = ByteCountFormatter.string(fromByteCount: Int64(model.monitor.memoryTotalBytes), countStyle: .memory)
        let memItem = NSMenuItem(
            title: "Memory: \(model.monitor.memoryUsedText) of \(totalRAM) (\(model.monitor.memoryPercentText))",
            action: nil,
            keyEquivalent: ""
        )
        if let img = NSImage(systemSymbolName: "memorychip", accessibilityDescription: nil) {
            img.isTemplate = true
            memItem.image = img
        }
        menu.addItem(memItem)

        let batteryItem = NSMenuItem(
            title: "Battery: \(model.monitor.batteryText) · \(model.monitor.batterySourceText)",
            action: nil,
            keyEquivalent: ""
        )
        if let img = NSImage(systemSymbolName: model.monitor.isCharging ? "bolt.battery.fill" : "battery.75", accessibilityDescription: nil) {
            img.isTemplate = true
            batteryItem.image = img
        }
        menu.addItem(batteryItem)

        let networkItem = NSMenuItem(
            title: "Network: \(model.monitor.networkNameText) (\(model.monitor.networkStatusText))",
            action: nil,
            keyEquivalent: ""
        )
        if let img = NSImage(systemSymbolName: "wifi", accessibilityDescription: nil) {
            img.isTemplate = true
            networkItem.image = img
        }
        menu.addItem(networkItem)

        menu.addItem(NSMenuItem.separator())

        // 4. Previous Runs / History
        let historyHeader = NSMenuItem(title: "PREVIOUS RUNS", action: nil, keyEquivalent: "")
        historyHeader.isEnabled = false
        menu.addItem(historyHeader)

        if model.history.isEmpty {
            let emptyHistory = NSMenuItem(title: "No cleanups yet · Ready to scan", action: nil, keyEquivalent: "")
            emptyHistory.isEnabled = false
            menu.addItem(emptyHistory)
        } else {
            if let first = model.history.first {
                let lastRun = NSMenuItem(title: "Last: \(first.sizeText) cleaned (\(first.dayText))", action: nil, keyEquivalent: "")
                if let img = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil) {
                    img.isTemplate = true
                    lastRun.image = img
                }
                menu.addItem(lastRun)
            }
            let totalFormatted = ByteCountFormatter.string(fromByteCount: model.totalCleanedBytes, countStyle: .file)
            let totalItem = NSMenuItem(
                title: "Total Freed: \(totalFormatted) across \(model.history.count) run\(model.history.count == 1 ? "" : "s")",
                action: nil,
                keyEquivalent: ""
            )
            menu.addItem(totalItem)
        }

        menu.addItem(NSMenuItem.separator())

        // 5. App Controls
        let openItem = NSMenuItem(title: "Open MacKitty", action: #selector(openApp), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        let quitItem = NSMenuItem(title: "Quit MacKitty", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - Actions
    @objc private func openApp() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title == "MacKitty" || $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
            window.deminiaturize(nil)
        }
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
        NSApp.terminate(nil)
    }
}
