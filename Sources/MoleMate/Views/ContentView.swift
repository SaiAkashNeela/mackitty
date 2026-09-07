import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var model: DashboardModel

    var body: some View {
        SimpleDashboardView()
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

/// Keeps the reference design's custom chrome in charge of the top edge.
/// macOS creates the red/yellow/green window buttons automatically, so hide
/// those standard controls while preserving normal Cmd-W window behavior.
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
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
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
