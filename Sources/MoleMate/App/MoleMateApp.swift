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
