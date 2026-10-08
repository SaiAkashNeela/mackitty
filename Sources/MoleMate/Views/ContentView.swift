import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var model: DashboardModel

    var body: some View {
        SimpleDashboardView()
            .ignoresSafeArea(.all, edges: .top)
            .background(WindowChromeConfigurator())
            .frame(minWidth: 1040, minHeight: 700)
            .onAppear { model.refreshVersion() }
            .alert("MacKitty", isPresented: Binding(
                get: { model.alertMessage != nil },
                set: { if !$0 { model.alertMessage = nil } }
            )) {
                Button("OK", role: .cancel) { model.alertMessage = nil }
            } message: {
                Text(model.alertMessage ?? "")
            }
    }
}

/// Keeps Apple native traffic light controls visible in a unified, transparent chrome
private struct WindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        MainWindow.adopt(window)
        window.styleMask.insert([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true

        // An empty unified toolbar makes the titlebar 52pt tall, so the native
        // traffic lights sit vertically centred in our 52pt top bar instead of
        // hugging the top edge with dead space around them.
        if window.toolbar == nil {
            let toolbar = NSToolbar(identifier: "MacKittyChrome")
            toolbar.showsBaselineSeparator = false
            window.toolbar = toolbar
            window.toolbarStyle = .unified
            window.titlebarSeparatorStyle = .none
        }

        // Ensure Apple authentic native traffic lights are visible & interactive
        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isHidden = false
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.cornerRadius = 12
        window.contentView?.layer?.masksToBounds = true
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
    }
}

struct SettingsView: View {
    var body: some View {
        Form {
            Section("Cleanup") {
                Toggle("Ask before every cleanup", isOn: .constant(true))
                Toggle("Show Mole output after an operation", isOn: .constant(true))
            }
        }
        .padding(24)
        .frame(width: 420, height: 220)
    }
}
