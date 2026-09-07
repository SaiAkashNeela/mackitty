import SwiftUI
import AppKit

@main
struct MacKittyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = DashboardModel()

    var body: some Scene {
        WindowGroup("MacKitty") {
            ContentView()
                .environmentObject(model)
                .onAppear {
                    appDelegate.setupStatusBar(with: model)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1120, height: 720)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About MacKitty") {
                    AboutWindowController.shared.show()
                }
            }
        }

        Settings {
            SettingsView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let icon = AppLogo.nsImage {
            NSApp.applicationIconImage = icon
        }
        setupAppMenu()
        checkMoveToApplicationsIfNeeded()
    }

    private func checkMoveToApplicationsIfNeeded() {
        let bundlePath = Bundle.main.bundlePath
        // Only prompt if running from a mounted DMG volume or Downloads folder
        guard !bundlePath.hasPrefix("/Applications"),
              bundlePath.hasPrefix("/Volumes/") || bundlePath.contains("/Downloads/") else {
            return
        }

        #if DEBUG
        guard !bundlePath.contains(".build/") else { return }
        #endif

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            let alert = NSAlert()
            alert.messageText = "Move to Applications Folder?"
            alert.informativeText = "MacKitty is currently running from a disk image or download folder. Moving it to /Applications ensures automatic updates and full system integration."
            alert.addButton(withTitle: "Move to Applications")
            alert.addButton(withTitle: "Do Not Move")
            alert.alertStyle = .informational

            if alert.runModal() == .alertFirstButtonReturn {
                let destinationURL = URL(fileURLWithPath: "/Applications/MacKitty.app")
                let sourceURL = Bundle.main.bundleURL

                do {
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

                    NSWorkspace.shared.openApplication(at: destinationURL, configuration: NSWorkspace.OpenConfiguration()) { _, _ in
                        DispatchQueue.main.async {
                            NSApp.terminate(nil)
                        }
                    }
                } catch {
                    let errAlert = NSAlert(error: error)
                    errAlert.runModal()
                }
            }
        }
    }

    private func setupAppMenu() {
        // Intercept standard AppKit "About MacKitty" menu item next to the Apple logo
        DispatchQueue.main.async {
            if let mainMenu = NSApp.mainMenu,
               let appMenu = mainMenu.items.first?.submenu {
                for item in appMenu.items {
                    if item.action == #selector(NSApplication.orderFrontStandardAboutPanel(_:)) ||
                       item.title.localizedCaseInsensitiveContains("About") {
                        item.target = self
                        item.action = #selector(self.openAboutMacKitty)
                    }
                }
            }
        }
    }

    @objc func openAboutMacKitty() {
        AboutWindowController.shared.show()
    }

    func setupStatusBar(with model: DashboardModel) {
        guard statusBarController == nil else { return }
        statusBarController = StatusBarController(model: model)
    }
}
