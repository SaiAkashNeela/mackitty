import SwiftUI
import AppKit

/// Menu-bar popover: a compact version of the Overview dashboard.
struct TrayMiniDashboardView: View {
    @ObservedObject var model: DashboardModel
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            header
            StorageSummary(model: model)
            TrayVitals(monitor: model.monitor)
            primaryAction
            if let last = model.history.first {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(Theme.textTertiary)
                    Text("Last cleanup freed \(last.sizeText)")
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(last.date.formatted(.relative(presentation: .named)))
                        .foregroundStyle(Theme.textTertiary)
                }
                .font(Theme.body(11))
                .padding(.horizontal, 2)
            }
            footer
        }
        .padding(14)
        .frame(width: 340)
        .background(Theme.canvas)
        .preferredColorScheme(.light)
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 10) {
            AppLogoView(size: 30, cornerRadius: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text("MacKitty")
                    .font(Theme.body(13.5, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 5) {
                    Circle().fill(statusColor).frame(width: 6, height: 6)
                    Text(statusText)
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            TrayIconButton(systemName: "macwindow", help: "Open MacKitty", action: openApp)
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        if model.isScanning || model.isCleaning {
            Button(action: openApp) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(model.isScanning ? "Scanning… \(Int(model.scanProgress * 100))%" : "Cleaning… \(Int(model.cleanProgress * 100))%")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(TrayButtonStyle(prominent: false))
        } else if model.screen == .triage && model.hasSelectedCleanup {
            Button(action: openApp) {
                Label("Review \(model.selectedCleanupSizeText) to clean", systemImage: "checklist")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(TrayButtonStyle(prominent: true))
        } else {
            Button(action: scanNow) {
                Label("Scan My Mac", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(TrayButtonStyle(prominent: true))
        }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            TrayTextButton(title: "About", action: openAbout)
            if model.updater.isUpdateAvailable {
                TrayTextButton(title: "Update to \(model.updater.latestVersion)", color: Theme.accentStrong, action: openUpdate)
            } else {
                TrayTextButton(title: "Check for Updates", action: checkUpdate)
            }
            Spacer()
            TrayTextButton(title: "Quit", action: quitApp)
        }
        .padding(.top, 2)
        .overlay(alignment: .top) { Theme.line.frame(height: 1).offset(y: -6) }
    }

    // MARK: State

    private var statusColor: Color {
        if model.isScanning || model.isCleaning { return Theme.accent }
        if model.diskUsedRatio > 0.9 { return Theme.danger }
        if model.diskUsedRatio > 0.75 { return Theme.warning }
        return Theme.success
    }

    private var statusText: String {
        if model.isCleaning { return "Cleaning…" }
        if model.isScanning { return "Scanning…" }
        if model.diskUsedRatio > 0.9 { return "Storage almost full" }
        if model.diskUsedRatio > 0.75 { return "Storage filling up" }
        return "Everything looks good"
    }

    // MARK: Actions

    private func openApp() {
        onClose()
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title == "MacKitty" || $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
            window.deminiaturize(nil)
        }
    }

    private func scanNow() {
        openApp()
        model.selectTopTab(.clean)
        model.resetForFreshScan()
        model.requestScan()
    }

    private func openAbout() {
        openApp()
        model.showAbout = true
    }

    private func openUpdate() {
        openApp()
        model.updater.openUpdateFlow()
    }

    private func checkUpdate() {
        Task { await model.updater.checkForUpdates() }
    }

    private func quitApp() {
        onClose()
        NSApp.terminate(nil)
    }
}

// MARK: - Storage

private struct StorageSummary: View {
    @ObservedObject var model: DashboardModel

    private var color: Color {
        model.diskUsedRatio > 0.9 ? Theme.danger : (model.diskUsedRatio > 0.75 ? Theme.warning : Theme.accent)
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(Theme.canvasDeep, lineWidth: 7)
                Circle()
                    .trim(from: 0, to: max(0.01, model.diskUsedRatio))
                    .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(model.diskUsedRatio * 100))%")
                    .font(Theme.numeric(12, .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(width: 58, height: 58)
            .animation(.easeOut(duration: 0.6), value: model.diskUsedRatio)

            VStack(alignment: .leading, spacing: 2) {
                Text("Macintosh HD")
                    .font(Theme.body(11, .medium))
                    .foregroundStyle(Theme.textTertiary)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(model.diskFreeText)
                        .font(Theme.numeric(20, .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("free")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                }
                Text("\(model.diskUsedText) of \(model.diskCapacityText) used")
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .glassPanel(radius: 12)
    }
}

// MARK: - Vitals

/// Observes the monitor directly so the numbers stay live while the popover is open.
private struct TrayVitals: View {
    @ObservedObject var monitor: SystemMonitorService
    @State private var cpuHistory: [Double] = []
    @State private var memoryHistory: [Double] = []

    var body: some View {
        VStack(spacing: 0) {
            VitalRow(icon: "cpu", label: "CPU", value: monitor.cpuText, history: cpuHistory, color: tint(monitor.cpuUsage))
            Theme.line.frame(height: 1).padding(.leading, 34)
            VitalRow(icon: "memorychip", label: "Memory", value: "\(Int((monitor.memoryRatio * 100).rounded()))%", history: memoryHistory, color: tint(monitor.memoryRatio))
            Theme.line.frame(height: 1).padding(.leading, 34)
            HStack(spacing: 10) {
                RowIcon(systemName: monitor.isCharging ? "bolt.fill" : "battery.75")
                Text(monitor.hasBattery ? "Battery" : "Power")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Capsule().fill(Theme.canvasDeep)
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule()
                                .fill(monitor.batteryRatio > 0.2 ? Theme.success : Theme.danger)
                                .frame(width: max(4, proxy.size.width * monitor.batteryRatio))
                        }
                    }
                    .frame(width: 70, height: 6)
                Text(monitor.batteryText)
                    .font(Theme.numeric(12, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 44, alignment: .trailing)
            }
            .padding(.vertical, 9)
            Theme.line.frame(height: 1).padding(.leading, 34)
            HStack(spacing: 10) {
                RowIcon(systemName: monitor.isOnline ? "wifi" : "wifi.slash")
                Text("Network")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Circle()
                    .fill(monitor.isOnline ? Theme.success : Theme.textTertiary)
                    .frame(width: 6, height: 6)
                Text(monitor.isOnline ? "Online" : "Offline")
                    .font(Theme.body(12, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 44, alignment: .trailing)
            }
            .padding(.vertical, 9)
        }
        .padding(.horizontal, 12)
        .glassPanel(radius: 12)
        .onAppear {
            if cpuHistory.isEmpty { cpuHistory = [monitor.cpuUsage] }
            if memoryHistory.isEmpty { memoryHistory = [monitor.memoryRatio] }
        }
        .onChange(of: monitor.cpuUsage) { _, v in append(v, to: &cpuHistory) }
        .onChange(of: monitor.memoryRatio) { _, v in append(v, to: &memoryHistory) }
    }

    private func append(_ v: Double, to history: inout [Double]) {
        history.append(v)
        if history.count > 24 { history.removeFirst(history.count - 24) }
    }

    private func tint(_ ratio: Double) -> Color {
        ratio > 0.85 ? Theme.danger : (ratio > 0.65 ? Theme.warning : Theme.accent)
    }
}

private struct VitalRow: View {
    let icon: String
    let label: String
    let value: String
    let history: [Double]
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            RowIcon(systemName: icon)
            Text(label)
                .font(Theme.body(12))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            MiniSparkline(values: history, color: color)
                .frame(width: 70, height: 18)
            Text(value)
                .font(Theme.numeric(12, .semibold))
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.vertical, 9)
    }
}

private struct RowIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Theme.accent)
            .frame(width: 24, height: 24)
            .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct MiniSparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let pts = points(in: proxy.size)
            ZStack {
                Path { p in
                    guard let first = pts.first, let last = pts.last else { return }
                    p.move(to: CGPoint(x: first.x, y: proxy.size.height))
                    p.addLines(pts)
                    p.addLine(to: CGPoint(x: last.x, y: proxy.size.height))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [color.opacity(0.22), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                Path { p in p.addLines(pts) }
                    .stroke(color, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        let v = values.count >= 2 ? values : [values.first ?? 0, values.first ?? 0]
        let step = size.width / Double(v.count - 1)
        return v.enumerated().map { i, x in
            CGPoint(x: Double(i) * step, y: 1 + (1 - min(max(x, 0), 1)) * (size.height - 2))
        }
    }
}

// MARK: - Controls

private struct TrayButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body(13, .semibold))
            .foregroundStyle(prominent ? .white : Theme.textPrimary)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(prominent ? (configuration.isPressed ? Theme.accentStrong : Theme.accent) : Theme.card)
            )
            .overlay {
                if !prominent {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.lineStrong, lineWidth: 1)
                }
            }
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct TrayIconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hovered ? Theme.textPrimary : Theme.textSecondary)
                .frame(width: 28, height: 28)
                .background(hovered ? Theme.surfaceHover : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(help)
    }
}

private struct TrayTextButton: View {
    let title: String
    var color: Color = Theme.textSecondary
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.body(11.5, .medium))
                .foregroundStyle(hovered ? Theme.textPrimary : color)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(hovered ? Theme.surfaceHover : .clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
