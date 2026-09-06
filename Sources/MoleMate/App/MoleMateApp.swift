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
    }

    func setupStatusBar(with model: DashboardModel) {
        guard statusBarController == nil else { return }
        statusBarController = StatusBarController(model: model)
    }
}
