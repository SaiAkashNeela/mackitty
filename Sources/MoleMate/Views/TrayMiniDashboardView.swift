import SwiftUI
import AppKit

struct TrayMiniDashboardView: View {
    @ObservedObject var model: DashboardModel
    var onClose: () -> Void

    private let panelBg = Color(red: 0.08, green: 0.09, blue: 0.12)
    private let cardBg = Color.white.opacity(0.05)
    private let strokeColor = Color.white.opacity(0.08)
    private let accentBlue = Color(red: 0.22, green: 0.58, blue: 0.98)

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack(spacing: 8) {
                AppLogoView(size: 20)

                Text("MacKitty")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                // Status pill
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusPillColor)
                        .frame(width: 5, height: 5)
                    Text(statusPillText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.06), in: Capsule())

                Spacer()

                Button(action: openApp) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("Open Full App")
            }
            .padding(.bottom, 2)

            // 2x2 Telemetry Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                // CPU Card
                MiniStatCard(
                    icon: "cpu",
                    iconColor: accentBlue,
                    title: "CPU",
                    value: model.monitor.cpuText,
                    subtitle: model.monitor.chipName,
                    progress: model.monitor.cpuUsage,
                    progressColor: accentBlue
                )

                // Memory Card
                MiniStatCard(
                    icon: "memorychip",
                    iconColor: Color.cyan,
                    title: "Memory",
                    value: model.monitor.memoryPercentText,
                    subtitle: "\(model.monitor.memoryUsedText) used",
                    progress: model.monitor.memoryRatio,
                    progressColor: Color.cyan
                )

                // Disk Card
                MiniStatCard(
                    icon: "internaldrive",
                    iconColor: Color.orange,
                    title: "Storage",
                    value: model.diskFreeText,
                    subtitle: "\(model.diskUsedText) of \(model.diskCapacityText)",
                    progress: model.diskUsedRatio,
                    progressColor: Color.orange
                )

                // Battery Card
                MiniStatCard(
                    icon: model.monitor.isCharging ? "bolt.battery.fill" : "battery.75",
                    iconColor: model.monitor.isCharging ? Color.green : Color.yellow,
                    title: "Battery",
                    value: model.monitor.batteryText,
                    subtitle: model.monitor.batterySourceText,
                    progress: model.monitor.batteryRatio,
                    progressColor: model.monitor.isCharging ? Color.green : Color.yellow
                )
            }

            // Network connection row
            HStack(spacing: 8) {
                Image(systemName: "wifi")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.green)

                Text(model.monitor.networkNameText)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))

                Spacer()

                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 5, height: 5)
                    Text(model.monitor.networkStatusText)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(cardBg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(strokeColor) }

            // Action Buttons
            HStack(spacing: 8) {
                Button(action: cleanNow) {
                    HStack(spacing: 6) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Clean My Mac")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(
                        LinearGradient(
                            colors: [accentBlue, accentBlue.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button(action: scanNow) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Scan")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(Color.white.opacity(0.12)) }
                    .foregroundStyle(.white.opacity(0.9))
                }
                .buttonStyle(.plain)
            }

            // Recent history summary
            if let last = model.history.first {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                    Text("Last cleanup: \(last.sizeText) freed")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    Text(last.dayText)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .padding(.horizontal, 4)
            }

            Divider().overlay(strokeColor)

            // Bottom controls
            HStack {
                Button("About", action: openAbout)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .buttonStyle(.plain)

                Text("·").foregroundStyle(.white.opacity(0.2))

                if model.updater.isUpdateAvailable {
                    Button("Update Available (v\(model.updater.latestVersion))", action: openUpdate)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.yellow)
                        .buttonStyle(.plain)
                } else {
                    Button("Check Updates", action: checkUpdate)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                        .buttonStyle(.plain)
                }

                Spacer()

                Button("Quit", action: quitApp)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.red.opacity(0.75))
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
        }
        .padding(14)
        .frame(width: 320)
        .background(panelBg)
        .preferredColorScheme(.dark)
    }

    private var statusPillColor: Color {
        if model.isCleaning { return Color.green }
        if model.isScanning { return accentBlue }
        return Color.green
    }

    private var statusPillText: String {
        if model.isCleaning { return "Cleaning…" }
        if model.isScanning { return "Scanning…" }
        return "Healthy"
    }

    private func openApp() {
        onClose()
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title == "MacKitty" || $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
            window.deminiaturize(nil)
        }
    }

    private func cleanNow() {
        openApp()
        model.selectAllCleanupAreas()
        model.clean()
    }

    private func scanNow() {
        openApp()
        model.resetForFreshScan()
        model.scan()
    }

    private func openAbout() {
        openApp()
        model.showAbout = true
    }

    private func openUpdate() {
        onClose()
        model.updater.openDownloadPage()
    }

    private func checkUpdate() {
        Task { await model.updater.checkForUpdates() }
    }

    private func quitApp() {
        onClose()
        NSApp.terminate(nil)
    }
}

private struct MiniStatCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    let subtitle: String
    let progress: Double
    let progressColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text(value)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(progressColor)
                        .frame(width: max(2, min(geo.size.width * CGFloat(progress), geo.size.width)), height: 3)
                }
            }
            .frame(height: 3)

            Text(subtitle)
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.38))
                .lineLimit(1)
        }
        .padding(8)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(Color.white.opacity(0.07)) }
    }
}
