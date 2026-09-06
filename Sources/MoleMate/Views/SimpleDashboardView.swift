import SwiftUI
import AppKit
import AVFoundation

private let moleBlue = Color(red: 0.04, green: 0.52, blue: 1.0)
private let moleGreen = Color(red: 0.19, green: 0.82, blue: 0.35)
private let windowBackground = Color(red: 0.11, green: 0.11, blue: 0.12)
private let panelBackground = Color(red: 0.10, green: 0.10, blue: 0.11)
private let hairline = Color.white.opacity(0.08)

struct SimpleDashboardView: View {
    @EnvironmentObject private var model: DashboardModel

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.07)
                .ignoresSafeArea()
            BackgroundVideoView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
            Color.black.opacity(0.48)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HTMLChrome()
                ScreenBody()
            }
            .frame(minWidth: 1080, minHeight: 662)
            .background(Color.black.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .preferredColorScheme(.dark)
    }
}

private struct BackgroundVideoView: NSViewRepresentable {
    final class VideoSurface: NSView {
        let playerLayer: AVPlayerLayer

        init(player: AVPlayer) {
            playerLayer = AVPlayerLayer(player: player)
            super.init(frame: .zero)
            wantsLayer = true
            playerLayer.videoGravity = .resizeAspectFill
            layer?.addSublayer(playerLayer)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layout() {
            super.layout()
            playerLayer.frame = bounds
        }
    }

    final class Coordinator {
        var player: AVQueuePlayer?
        var looper: AVPlayerLooper?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        guard let url = Bundle.module.url(forResource: "bg", withExtension: "mp4") else { return NSView(frame: .zero) }

        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        player.isMuted = true
        player.volume = 0
        player.allowsExternalPlayback = false
        player.preventsDisplaySleepDuringVideoPlayback = false
        context.coordinator.player = player
        context.coordinator.looper = AVPlayerLooper(player: player, templateItem: item)
        let view = VideoSurface(player: player)
        player.play()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.player?.isMuted = true
        context.coordinator.player?.volume = 0
        if context.coordinator.player?.rate == 0 { context.coordinator.player?.play() }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.player?.pause()
        coordinator.looper = nil
        coordinator.player = nil
    }
}

private struct HTMLChrome: View {
    @EnvironmentObject private var model: DashboardModel

    var body: some View {
        HStack {
            HStack(spacing: 7) {
                WindowControl(symbol: "xmark", color: Color(red: 1, green: 0.37, blue: 0.34), label: "Close") {
                    NSApp.keyWindow?.performClose(nil)
                }
                WindowControl(symbol: "minus", color: Color(red: 1, green: 0.74, blue: 0.18), label: "Minimize") {
                    NSApp.keyWindow?.performMiniaturize(nil)
                }
            }

            Spacer()
            HStack(spacing: 12) {
                Button(action: { model.showAbout = true }) {
                    HStack(spacing: 7) {
                        AppLogoView(size: 16)
                        Text("MacKitty")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .buttonStyle(.plain)
                .help("About MacKitty")

                HStack(spacing: 3) {
                    ForEach(TopTab.allCases, id: \.self) { tab in
                        Button(action: { model.selectTopTab(tab) }) {
                            Text(tab.rawValue)
                                .font(.system(size: 11.5, weight: model.topTab == tab ? .semibold : .medium))
                                .foregroundStyle(model.topTab == tab ? .white : .white.opacity(0.48))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(
                                    model.topTab == tab
                                        ? Color.white.opacity(0.12)
                                        : Color.clear,
                                    in: Capsule()
                                )
                                .overlay {
                                    if model.topTab == tab {
                                        Capsule()
                                            .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.8)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(Color.white.opacity(0.04), in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
                }
            }
            Spacer()

            HStack(spacing: 8) {
                if model.updater.isUpdateAvailable {
                    Button(action: { model.updater.openDownloadPage() }) {
                        HStack(spacing: 4) {
                            Circle().fill(Color.yellow).frame(width: 5, height: 5)
                            Text("Update v\(model.updater.latestVersion)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.yellow)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(Color.yellow.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Button(action: { model.showAbout = true }) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .buttonStyle(.plain)
                .help("About MacKitty")

                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    Text(statusLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(Color.black.opacity(0.12))
        .overlay(alignment: .bottom) { hairline.frame(height: 1) }
        .sheet(isPresented: $model.showAbout) {
            AboutView()
        }
    }

    private var statusLabel: String {
        switch model.screen {
        case .welcome: "Idle"
        case .scanning: "Scanning…"
        case .triage: "Ready to Clean"
        case .cleaning: "Cleaning…"
        case .summary: "Complete"
        }
    }

    private var statusColor: Color {
        switch model.screen {
        case .welcome: .gray
        case .scanning: moleBlue
        case .triage: .yellow
        case .cleaning, .summary: moleGreen
        }
    }
}

private struct WindowControl: View {
    let symbol: String
    let color: Color
    let label: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color.opacity(isHovered ? 0.38 : 0.16))
                Circle()
                    .strokeBorder(color.opacity(isHovered ? 0.80 : 0.40), lineWidth: 1)
                Image(systemName: symbol)
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(color.opacity(isHovered ? 1.0 : 0.72))
            }
            .frame(width: 13, height: 13)
        }
        .buttonStyle(.plain)
        .help(label)
        .onHover { isHovered = $0 }
        .accessibilityLabel(label)
    }
}

private struct ScreenBody: View {
    @EnvironmentObject private var model: DashboardModel

    var body: some View {
        if model.topTab == .apps {
            AppsScreen()
        } else {
            switch model.screen {
            case .welcome: WelcomeScreen()
            case .scanning: ScanningScreen()
            case .triage: TriageScreen()
            case .cleaning: CleaningScreen()
            case .summary: SummaryScreen()
            }
        }
    }
}

private struct AppsScreen: View {
    @EnvironmentObject private var model: DashboardModel
    @State private var appToRemove: InstalledApp?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Installed Apps")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(.white.opacity(0.92))
                    Text("Remove apps you no longer need. They will be moved to the Trash.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                Text("\(model.installedApps.count) apps")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }

            if model.installedApps.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 28))
                        .foregroundStyle(moleBlue)
                    Text("No applications found")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Applications in /Applications will appear here.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(model.installedApps) { app in
                            HStack(spacing: 12) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                                    .resizable()
                                    .frame(width: 34, height: 34)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(app.name)
                                        .font(.system(size: 13, weight: .medium))
                                    Text(app.path)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.35))
                                        .lineLimit(1)
                                }
                                Spacer()
                                Button("Finder") { FinderOpener.open(path: app.path) }
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(moleBlue)
                                    .buttonStyle(.plain)
                                Button("Uninstall") { appToRemove = app }
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(.red.opacity(0.9))
                                    .buttonStyle(.plain)
                            }
                            .padding(.vertical, 10)
                            .overlay(alignment: .bottom) { hairline.frame(height: 1) }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: 680, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 30)
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .center)
        .alert(item: $appToRemove) { app in
            Alert(
                title: Text("Move \(app.name) to Trash?"),
                message: Text("The application will be moved to the Trash. You can restore it from there."),
                primaryButton: .destructive(Text("Move to Trash")) { model.uninstall(app) },
                secondaryButton: .cancel()
            )
        }
    }
}

private struct WelcomeScreen: View {
    @EnvironmentObject private var model: DashboardModel

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    DiskGauge()

                    Button(action: model.primaryAction) {
                        Text("Scan My Mac")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 12)
                            .background(moleBlue, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    StatsStrip()
                    LifetimeStrip()
                    RecentActivity()
                }
                .frame(maxWidth: 640)
                .frame(minHeight: max(0, proxy.size.height - 48), alignment: .center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct DiskGauge: View {
    @EnvironmentObject private var model: DashboardModel

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: model.diskUsedRatio)
                    .stroke(moleBlue, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("\(Int(model.diskUsedRatio * 100))%")
                        .font(.system(size: 30, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.92))
                    Text("used")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(width: 170, height: 170)

            Text("Macintosh HD")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
            Text("\(model.diskUsedText) of \(model.diskCapacityText) used · \(model.diskFreeText) free")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}

private struct StatsStrip: View {
    @EnvironmentObject private var model: DashboardModel

    var body: some View {
        HStack(spacing: 10) {
            CPUStatCard(monitor: model.monitor)
            GPUStatCard(monitor: model.monitor)
            MemoryStatCard(monitor: model.monitor)
            NetworkStatCard(monitor: model.monitor)
            BatteryStatCard(monitor: model.monitor)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CPUStatCard: View {
    @ObservedObject var monitor: SystemMonitorService
    @State private var mode = 0
    @State private var isHovered = false

    var body: some View {
        InteractiveStatCard(
            label: "CPU",
            value: mode == 0 ? monitor.cpuText : (mode == 1 ? monitor.chipName : monitor.coreCountText),
            subtext: mode == 0 ? "Load" : (mode == 1 ? "Chip" : "Cores"),
            color: monitor.cpuUsage > 0.8 ? .red : (monitor.cpuUsage > 0.5 ? .orange : moleBlue),
            progress: monitor.cpuUsage,
            isLive: true,
            isHovered: isHovered,
            action: {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    mode = (mode + 1) % 3
                }
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            }
        )
        .onHover { isHovered = $0 }
    }
}

private struct GPUStatCard: View {
    @ObservedObject var monitor: SystemMonitorService
    @State private var mode = 0
    @State private var isHovered = false

    var body: some View {
        InteractiveStatCard(
            label: "GPU",
            value: mode == 0 ? "Metal 3" : (mode == 1 ? "Unified" : "Active"),
            subtext: mode == 0 ? "Graphics" : (mode == 1 ? "Memory" : "Status"),
            color: Color.purple,
            progress: 0.18,
            isLive: true,
            isHovered: isHovered,
            action: {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    mode = (mode + 1) % 3
                }
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            }
        )
        .onHover { isHovered = $0 }
    }
}

private struct MemoryStatCard: View {
    @ObservedObject var monitor: SystemMonitorService
    @State private var mode = 0
    @State private var isHovered = false

    var body: some View {
        InteractiveStatCard(
            label: "MEMORY",
            value: mode == 0 ? monitor.memoryUsedText : (mode == 1 ? monitor.memoryPercentText : monitor.memoryFreeText),
            subtext: mode == 0 ? "Used" : (mode == 1 ? "Percentage" : "Free"),
            color: monitor.memoryRatio > 0.85 ? .red : (monitor.memoryRatio > 0.70 ? .orange : moleBlue),
            progress: monitor.memoryRatio,
            isLive: true,
            isHovered: isHovered,
            action: {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    mode = (mode + 1) % 3
                }
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            }
        )
        .onHover { isHovered = $0 }
    }
}

private struct NetworkStatCard: View {
    @ObservedObject var monitor: SystemMonitorService
    @State private var mode = 0
    @State private var isHovered = false

    var body: some View {
        InteractiveStatCard(
            label: "NETWORK",
            value: mode == 0 ? monitor.networkNameText : (mode == 1 ? monitor.localIPText : monitor.networkStatusText),
            subtext: mode == 0 ? "Network" : (mode == 1 ? "Local IP" : "Status"),
            color: monitor.isOnline ? moleGreen : .gray,
            progress: monitor.isOnline ? 1.0 : 0.0,
            isLive: monitor.isOnline,
            isHovered: isHovered,
            action: {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    mode = (mode + 1) % 3
                }
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            }
        )
        .onHover { isHovered = $0 }
    }
}

private struct BatteryStatCard: View {
    @ObservedObject var monitor: SystemMonitorService
    @State private var mode = 0
    @State private var isHovered = false

    var body: some View {
        InteractiveStatCard(
            label: monitor.hasBattery ? "BATTERY" : "POWER",
            value: mode == 0 ? monitor.batteryText : (mode == 1 ? monitor.batterySourceText : (monitor.isCharging ? "Charging" : "Good")),
            subtext: mode == 0 ? (monitor.isCharging ? "⚡ Charging" : "Capacity") : (mode == 1 ? "Source" : "Health"),
            color: monitor.isCharging ? moleBlue : (monitor.batteryRatio > 0.2 ? moleGreen : .red),
            progress: monitor.batteryRatio,
            isLive: true,
            isHovered: isHovered,
            action: {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    mode = (mode + 1) % 3
                }
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            }
        )
        .onHover { isHovered = $0 }
    }
}

private struct InteractiveStatCard: View {
    let label: String
    let value: String
    let subtext: String
    let color: Color
    let progress: Double?
    let isLive: Bool
    let isHovered: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(label.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(.white.opacity(0.42))

                    Spacer()

                    if isLive {
                        Circle()
                            .fill(color)
                            .frame(width: 5, height: 5)
                            .opacity(isHovered ? 1.0 : 0.65)
                    }
                }

                Text(value)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if let progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(color)
                        .scaleEffect(y: 0.45)
                        .animation(.easeInOut(duration: 0.35), value: progress)
                } else {
                    Color.clear
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
            .background(panelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isHovered ? color.opacity(0.45) : hairline, lineWidth: 1)
            }
            .scaleEffect(isHovered ? 1.025 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isHovered)
        }
        .buttonStyle(.plain)
        .help("Click to toggle \(label) details")
    }
}

private struct LifetimeStrip: View {
    @EnvironmentObject private var model: DashboardModel

    var body: some View {
        HStack(spacing: 12) {
            LifetimeCard(label: "Total Cleaned", value: ByteCountFormatter.string(fromByteCount: model.totalCleanedBytes, countStyle: .file))
            LifetimeCard(label: "Cleanups Run", value: "\(model.history.count)")
        }
        .frame(maxWidth: .infinity)
    }
}

private struct LifetimeCard: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(.white.opacity(0.4))
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(panelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(hairline) }
    }
}

private struct RecentActivity: View {
    @EnvironmentObject private var model: DashboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("RECENT ACTIVITY")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(.white.opacity(0.4))
                .padding(.top, 8)
                .padding(.bottom, 4)

            if model.history.isEmpty {
                Text("Your cleanup history will appear here.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.32))
                    .padding(.vertical, 10)
            } else {
                ForEach(model.history.prefix(3)) { entry in
                    HStack {
                        Text("\(entry.categoryCount) safe areas cleaned")
                            .foregroundStyle(.white.opacity(0.55))
                        Spacer()
                        Text(entry.sizeText)
                            .font(.system(size: 12.5, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.75))
                        Text(entry.dayText)
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .font(.system(size: 12.5))
                    .padding(.vertical, 8)
                    .overlay(alignment: .top) { hairline.frame(height: 1) }
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(panelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(hairline) }
    }
}

private struct ScanningScreen: View {
    @EnvironmentObject private var model: DashboardModel
    @State private var radarAngle: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.5
    @State private var cursorVisible = true

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Dynamic Interactive Radar & Sonar Scanning Visual
            ZStack {
                // Outer subtle sonar ripples (never looks frozen)
                Circle()
                    .stroke(moleBlue.opacity(0.12), lineWidth: 1.5)
                    .frame(width: 140, height: 140)
                    .scaleEffect(pulseScale)
                    .opacity(pulseOpacity)

                Circle()
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    .frame(width: 110, height: 110)

                // Background track
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 5)
                    .frame(width: 90, height: 90)

                // Progress ring track
                Circle()
                    .trim(from: 0, to: max(0.04, model.scanProgress))
                    .stroke(
                        LinearGradient(
                            colors: [moleBlue, Color.cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 90, height: 90)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: model.scanProgress)

                // Continuous rotating radar sweep
                Circle()
                    .fill(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                moleBlue.opacity(0),
                                moleBlue.opacity(0.03),
                                moleBlue.opacity(0.25),
                                moleBlue.opacity(0.55)
                            ]),
                            center: .center
                        )
                    )
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(radarAngle))

                // Center logo emblem
                AppLogoView(size: 34)
                    .shadow(color: moleBlue.opacity(0.5), radius: 8, y: 0)
            }
            .onAppear {
                withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                    radarAngle = 360
                }
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    pulseScale = 1.15
                    pulseOpacity = 0.15
                }
            }

            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                        .shadow(color: .green.opacity(0.8), radius: 4)

                    Text("ANALYZING SYSTEM")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.65))
                        .tracking(1.2)
                }

                Text("\(Int(model.scanProgress * 100))%")
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.95))
            }

            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.system(size: 12))
                        .foregroundStyle(moleBlue)
                    Text("\(model.scanFilesInspected.formatted()) files inspected")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                }

                // Interactive lively path box with terminal cursor
                HStack(spacing: 4) {
                    Text(model.scanCurrentPath)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text("▌")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(moleBlue.opacity(cursorVisible ? 0.9 : 0.1))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08))
                }
                .frame(maxWidth: 440)
                .onAppear {
                    Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                        cursorVisible.toggle()
                    }
                }
            }

            Button(action: { model.cancelScan() }) {
                HStack(spacing: 6) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Cancel Scan")
                }
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(Color.white.opacity(0.12)) }
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(30)
    }
}

private struct ProgressRing: View {
    let progress: Double
    let color: Color
    let size: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.1), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.01, progress))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}

private struct TriageScreen: View {
    @EnvironmentObject private var model: DashboardModel

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Scan Complete")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(.white.opacity(0.92))
                        Text("\(model.cleanupCategories.count) safe cleanup areas found")
                            .font(.system(size: 12.5, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer()
                    Button(model.hasSelectedCleanup ? "Clear All" : "Select All") {
                        model.hasSelectedCleanup ? model.clearCleanupAreas() : model.selectAllCleanupAreas()
                    }
                    .font(.system(size: 12.5))
                    .foregroundStyle(moleBlue)
                    .buttonStyle(.plain)
                }
                .padding(.trailing, 20)

                // Active App Warnings (e.g., Firefox or Chrome is open and locking files)
                if !model.activeAppWarnings.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.orange)

                            Text("Active Application Notice (\(model.activeAppWarnings.count))")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.92))

                            Spacer()

                            Button("Re-check") {
                                model.checkRunningAppWarnings()
                            }
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Color.orange)
                            .buttonStyle(.plain)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(model.activeAppWarnings, id: \.self) { warning in
                                HStack(alignment: .top, spacing: 6) {
                                    Circle()
                                        .fill(Color.orange.opacity(0.85))
                                        .frame(width: 4, height: 4)
                                        .padding(.top, 5)
                                    Text(warning)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(Color.white.opacity(0.82))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.orange.opacity(0.25), lineWidth: 1)
                    }
                    .padding(.trailing, 20)
                }

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(model.cleanupCategories.enumerated()), id: \.element.id) { index, category in
                            CleanupItemRow(category: category, color: categoryColor(index)) {
                                model.toggleCleanupCategory(category.id)
                            }
                        }
                    }
                    .padding(.trailing, 16)
                }
                .scrollIndicators(.hidden)
            }
            .padding(.top, 20)
            .padding(.leading, 20)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            TriageSidebar()
        }
    }

    private func categoryColor(_ index: Int) -> Color {
        [moleBlue, .orange, .purple, Color.cyan, .gray][index % 5]
    }
}

private struct CleanupItemRow: View {
    let category: CleanupCategory
    let color: Color
    let toggle: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: toggle) {
                    Image(systemName: category.isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 16))
                        .foregroundStyle(category.isSelected ? color : .white.opacity(0.42))
                }
                .buttonStyle(.plain)

                Text(category.name.prefix(2).uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                    .frame(width: 30, height: 30)
                    .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(category.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                    Text(category.path)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                        .lineLimit(1)
                }

                Spacer(minLength: 10)
                Text(category.sizeText)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                Button { FinderOpener.open(path: category.path) } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 12))
                        .foregroundStyle(moleGreen)
                }
                .buttonStyle(.plain)
                .help("Open in Finder")
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
            .onTapGesture(perform: toggle)
            .overlay(alignment: .bottom) { hairline.frame(height: 1) }
        }
    }
}

private struct TriageSidebar: View {
    @EnvironmentObject private var model: DashboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SELECTED")
                .font(.system(size: 11.5, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(.white.opacity(0.4))
            Text(model.selectedCleanupSizeText)
                .font(.system(size: 34, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.92))
            Text("\(model.cleanupCategories.filter(\.isSelected).count) of \(model.cleanupCategories.count) areas")
                .font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(0.5))

            hairline.frame(height: 1)

            Text("SAFE BREAKDOWN")
                .font(.system(size: 11.5, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(.white.opacity(0.4))
            ForEach(Array(model.cleanupCategories.enumerated()), id: \.element.id) { index, category in
                if category.isSelected {
                    HStack {
                        Circle().fill([moleBlue, .orange, .purple, .cyan, .gray][index % 5]).frame(width: 6, height: 6)
                        Text(category.name).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                        Spacer()
                        Text(category.sizeText).font(.system(size: 12, design: .monospaced)).foregroundStyle(.white.opacity(0.45))
                    }
                }
            }
            Spacer()
            Button(action: model.primaryAction) {
                Text("Clean Up — \(model.selectedCleanupSizeText)")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(moleBlue.opacity(model.hasSelectedCleanup ? 1 : 0.4), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!model.hasSelectedCleanup)
        }
        .padding(20)
        .frame(width: 260, alignment: .leading)
        .background(panelBackground)
        .overlay(alignment: .leading) { hairline.frame(width: 1) }
    }
}

private struct CleaningScreen: View {
    @EnvironmentObject private var model: DashboardModel

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                ProgressRing(progress: model.cleanProgress, color: moleGreen, size: 180, lineWidth: 14)
                VStack(spacing: 2) {
                    Text("\(Int(model.cleanProgress * 100))%")
                        .font(.system(size: 30, weight: .bold, design: .monospaced))
                    Text("Cleaning…")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            Text("\(model.cleanPhase)")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))

            if !model.cleanLog.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(model.cleanLog, id: \.self) { entry in
                        Text("✓  \(entry)")
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(moleGreen.opacity(0.85))
                    }
                }
                .frame(width: 480, alignment: .leading)
                .padding(12)
                .background(Color(red: 0.095, green: 0.095, blue: 0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(hairline) }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(30)
    }
}

private struct SummaryScreen: View {
    @EnvironmentObject private var model: DashboardModel

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                Circle().fill(moleGreen.opacity(0.15))
                Image(systemName: "checkmark")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(moleGreen)
            }
            .frame(width: 84, height: 84)

            VStack(spacing: 5) {
                Text("Cleanup Complete")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.5))
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(model.history.first?.sizeText ?? "0 B")
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.95))
                    Text("reclaimed")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                }
                Text("\(model.history.first?.categoryCount ?? 0) safe areas cleaned from Macintosh HD")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.45))
            }

            VStack(spacing: 10) {
                ForEach(Array(model.lastCleanupBreakdown.enumerated()), id: \.offset) { index, item in
                    HStack(spacing: 10) {
                        Text(item.0)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(width: 112, alignment: .leading)
                            .lineLimit(1)
                        GeometryReader { proxy in
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill([moleBlue, .orange, .purple, .cyan, .gray][index % 5])
                                        .frame(width: proxy.size.width * breakdownRatio(item.1))
                                }
                        }
                        .frame(height: 8)
                        Text(ByteCountFormatter.string(fromByteCount: item.1, countStyle: .file))
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(width: 64, alignment: .trailing)
                    }
                }
            }
            .frame(width: 360)

            Button("Done") { model.resetForFreshScan() }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 30)
                .padding(.vertical, 11)
                .background(moleBlue, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(30)
    }

    private func breakdownRatio(_ value: Int64) -> Double {
        let maxValue = max(model.lastCleanupBreakdown.map(\.1).max() ?? 1, 1)
        return min(max(Double(value) / Double(maxValue), 0), 1)
    }
}
