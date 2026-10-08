import SwiftUI
import AppKit
import AVFoundation
import Charts

struct SimpleDashboardView: View {
    @EnvironmentObject private var model: DashboardModel

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            ScreenBody()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
        .background(Theme.canvas.ignoresSafeArea())
        .sheet(isPresented: $model.showScanPermissionModal) {
            ScanPermissionModalView().environmentObject(model)
        }
        .sheet(isPresented: $model.showMoleInstallPrompt) {
            MoleInstallModalView().environmentObject(model)
        }
        .sheet(isPresented: $model.showAbout) { AboutView() }
        .sheet(isPresented: $model.updater.showUpdateModal) { UpdateModalView(updater: model.updater) }
        .onAppear { model.checkFirstRunMolePrompt() }
        .preferredColorScheme(.light)
    }
}

// MARK: - Top bar

private struct TopBar: View {
    @EnvironmentObject private var model: DashboardModel
    @Namespace private var tabNS

    var body: some View {
        ZStack {
            HStack(spacing: 10) {
                // room for the native traffic lights
                Color.clear.frame(width: 70, height: 1)
                Button(action: { model.showAbout = true }) {
                    HStack(spacing: 8) {
                        AppLogoView(size: 22, cornerRadius: 5)
                        Text("MacKitty")
                            .font(Theme.body(13, .semibold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
                .buttonStyle(.plain)
                .help("About MacKitty")

                Spacer()

                if model.updater.isUpdateAvailable {
                    Button(action: { model.updater.openUpdateFlow() }) {
                        Label("Update to \(model.updater.latestVersion)", systemImage: "arrow.down.circle")
                            .font(Theme.body(12, .medium))
                            .foregroundStyle(Theme.accentStrong)
                    }
                    .buttonStyle(.plain)
                }

                StatusPill()
            }

            HStack(spacing: 0) {
                ForEach(TopTab.allCases, id: \.self) { tab in
                    let active = model.topTab == tab
                    Button(action: {
                        withAnimation(.snappy(duration: 0.25)) { model.selectTopTab(tab) }
                    }) {
                        Text(tab.rawValue)
                            .font(Theme.body(12, active ? .semibold : .regular))
                            .foregroundStyle(active ? Theme.textPrimary : Theme.textSecondary)
                            .frame(width: 84)
                            .padding(.vertical, 4)
                            .background {
                                if active {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Theme.card)
                                        .shadow(color: Theme.ink.opacity(0.12), radius: 1.5, y: 1)
                                        .matchedGeometryEffect(id: "tab", in: tabNS)
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(KeyEquivalent(tab == .clean ? "1" : "2"), modifiers: .command)
                    .help("\(tab.rawValue) (⌘\(tab == .clean ? 1 : 2))")
                }
            }
            .padding(2)
            .background(Theme.canvasDeep, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(Theme.card)
        .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
        .zIndex(1)
    }
}

private struct StatusPill: View {
    @EnvironmentObject private var model: DashboardModel

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(Theme.body(12))
                .foregroundStyle(Theme.textSecondary)
        }
        .animation(.easeInOut(duration: 0.2), value: model.screen)
    }

    private var label: String {
        switch model.screen {
        case .welcome: "Idle"
        case .scanning: "Scanning"
        case .triage: "Ready to clean"
        case .cleaning: "Cleaning"
        case .summary: "Complete"
        }
    }

    private var color: Color {
        switch model.screen {
        case .welcome: Theme.textTertiary
        case .scanning, .cleaning: Theme.accent
        case .triage: Theme.warning
        case .summary: Theme.success
        }
    }
}

// MARK: - Router

private struct ScreenBody: View {
    @EnvironmentObject private var model: DashboardModel

    var body: some View {
        Group {
            if model.topTab == .apps {
                AppsScreen()
            } else {
                switch model.screen {
                case .welcome: OverviewScreen()
                case .scanning: ScanningScreen()
                case .triage: TriageScreen()
                case .cleaning: CleaningScreen()
                case .summary: SummaryScreen()
                }
            }
        }
        .transition(.opacity)
        .animation(.easeOut(duration: 0.2), value: model.screen)
        .animation(.easeOut(duration: 0.2), value: model.topTab)
    }
}

/// Page header: title, subtitle and optional trailing controls.
private struct PageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.display(22, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            trailing
        }
    }
}

private extension View {
    func pageFrame() -> some View {
        self
            .frame(maxWidth: 940, alignment: .topLeading)
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Overview

/// One-screen dashboard, no scrolling: the top row flexes with the window,
/// the two rows below keep a fixed height.
private struct OverviewScreen: View {
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                HeroCard()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                StorageDonutCard()
                    .frame(width: 320)
                    .frame(maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)

            SystemRow()
                .frame(height: 128)

            HStack(spacing: 14) {
                HistoryChartCard()
                    .frame(maxWidth: .infinity)
                TotalsCard()
                    .frame(width: 320)
            }
            .frame(height: 172)
        }
        .padding(20)
        .frame(maxWidth: 1200, maxHeight: .infinity)
        .frame(maxWidth: .infinity)
    }
}

/// Card title row used by every dashboard card.
private struct CardTitle<Accessory: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            Text(title)
                .font(Theme.body(12, .semibold))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
            accessory
        }
    }
}

extension CardTitle where Accessory == EmptyView {
    init(title: String, icon: String) {
        self.init(title: title, icon: icon) { EmptyView() }
    }
}

// MARK: Storage donut

private struct StorageDonutCard: View {
    @EnvironmentObject private var model: DashboardModel
    @State private var selectedAngle: Double?

    private struct Slice: Identifiable {
        let id: String
        let gb: Double
        let color: Color
        var text: String { ByteCountFormatter.string(fromByteCount: Int64(gb * 1_000_000_000), countStyle: .file) }
    }

    private var reclaimableBytes: Int64 {
        model.hasScanResults ? model.cleanupCategories.reduce(0) { $0 + $1.sizeBytes } : 0
    }

    private var slices: [Slice] {
        let gb = { (b: Int64) in Double(max(b, 0)) / 1_000_000_000 }
        var out = [Slice(id: "Used", gb: gb(model.diskUsedBytes - reclaimableBytes), color: Color(red: 0.42, green: 0.47, blue: 0.55))]
        if reclaimableBytes > 0 {
            out.append(Slice(id: "Reclaimable", gb: gb(reclaimableBytes), color: Theme.accent))
        }
        out.append(Slice(id: "Free", gb: gb(model.diskFreeBytes), color: Theme.canvasDeep))
        return out
    }

    private var selectedSlice: Slice? {
        guard let angle = selectedAngle else { return nil }
        var running = 0.0
        for slice in slices {
            running += slice.gb
            if angle <= running { return slice }
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle(title: "Storage", icon: "internaldrive") {
                Text(model.diskCapacityText)
                    .font(Theme.numeric(11.5, .regular))
                    .foregroundStyle(Theme.textTertiary)
            }

            ZStack {
                Chart(slices) { slice in
                    SectorMark(
                        angle: .value("Size", slice.gb),
                        innerRadius: .ratio(0.7),
                        outerRadius: .ratio(selectedSlice?.id == slice.id ? 1.0 : 0.94),
                        angularInset: 1.5
                    )
                    .cornerRadius(4)
                    .foregroundStyle(slice.color)
                    .opacity(selectedSlice == nil || selectedSlice?.id == slice.id ? 1 : 0.45)
                }
                .chartAngleSelection(value: $selectedAngle)
                .chartLegend(.hidden)
                .animation(.snappy(duration: 0.25), value: selectedSlice?.id)

                VStack(spacing: 1) {
                    if let s = selectedSlice {
                        Text(s.text)
                            .font(Theme.numeric(17, .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(s.id)
                            .font(Theme.body(11))
                            .foregroundStyle(Theme.textTertiary)
                    } else {
                        Text("\(Int(model.diskUsedRatio * 100))%")
                            .font(Theme.numeric(22, .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("used")
                            .font(Theme.body(11))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .allowsHitTesting(false)
            }
            .frame(maxHeight: .infinity)

            VStack(spacing: 6) {
                ForEach(slices) { slice in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(slice.color)
                            .overlay(RoundedRectangle(cornerRadius: 2.5).strokeBorder(Theme.line, lineWidth: 1))
                            .frame(width: 10, height: 10)
                        Text(slice.id)
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text(slice.text)
                            .font(Theme.numeric(12, .medium))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .opacity(selectedSlice == nil || selectedSlice?.id == slice.id ? 1 : 0.5)
                }
            }
            if reclaimableBytes == 0 {
                Text("Run a scan to see what's reclaimable.")
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(16)
        .glassPanel(radius: 14)
    }
}

// MARK: System row

private struct SystemRow: View {
    @EnvironmentObject private var model: DashboardModel

    var body: some View {
        HStack(spacing: 14) {
            CPUStatCard(monitor: model.monitor)
            MemoryStatCard(monitor: model.monitor)
            BatteryTile(monitor: model.monitor)
            NetworkTile(monitor: model.monitor)
        }
    }
}

/// Live metric with a history chart; click to cycle alternate readings.
private struct MetricTile: View {
    let label: String
    let icon: String
    let faces: [(value: String, caption: String)]
    let color: Color
    var history: [Double] = []

    @State private var face = 0
    @State private var hovered = false

    var body: some View {
        let current = faces[face % faces.count]
        VStack(alignment: .leading, spacing: 6) {
            CardTitle(title: label, icon: icon) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .opacity(hovered ? 1 : 0)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(current.value)
                    .font(Theme.numeric(20, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                Text(current.caption)
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            Sparkline(values: history.count >= 2 ? history : [history.first ?? 0, history.first ?? 0], color: color)
                .frame(maxHeight: .infinity)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassPanel(radius: 12)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.snappy(duration: 0.2)) { face += 1 } }
        .onHover { hovered = $0 }
        .help("Click for more \(label.lowercased()) details. Hover the chart to read past values.")
    }
}

private struct BatteryTile: View {
    @ObservedObject var monitor: SystemMonitorService

    private var color: Color {
        monitor.isCharging ? Theme.accent : (monitor.batteryRatio > 0.2 ? Theme.success : Theme.danger)
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(Theme.canvasDeep, lineWidth: 7)
                Circle()
                    .trim(from: 0, to: min(max(monitor.batteryRatio, 0.01), 1))
                    .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.6), value: monitor.batteryRatio)
                Image(systemName: monitor.isCharging ? "bolt.fill" : (monitor.hasBattery ? "battery.75" : "powerplug"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(color)
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                CardTitle(title: monitor.hasBattery ? "Battery" : "Power", icon: "bolt")
                Text(monitor.batteryText)
                    .font(Theme.numeric(20, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(monitor.isCharging ? "Charging · \(monitor.batterySourceText)" : monitor.batterySourceText)
                    .font(Theme.body(11.5))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .glassPanel(radius: 12)
    }
}

private struct NetworkTile: View {
    @ObservedObject var monitor: SystemMonitorService
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardTitle(title: "Network", icon: "network")
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill((monitor.isOnline ? Theme.success : Theme.textTertiary).opacity(0.18))
                        .frame(width: 26, height: 26)
                        .scaleEffect(pulse && monitor.isOnline ? 1.25 : 0.9)
                        .opacity(pulse && monitor.isOnline ? 0.2 : 1)
                    Circle()
                        .fill(monitor.isOnline ? Theme.success : Theme.textTertiary)
                        .frame(width: 10, height: 10)
                }
                .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: pulse)
                .onAppear { pulse = true }
                Text(monitor.isOnline ? "Online" : "Offline")
                    .font(Theme.numeric(20, .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Text("Local IP")
                    .foregroundStyle(Theme.textTertiary)
                Text(monitor.localIPText)
                    .font(Theme.mono(11.5))
                    .foregroundStyle(Theme.textSecondary)
                    .textSelection(.enabled)
            }
            .font(Theme.body(11.5))
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassPanel(radius: 12)
    }
}

// MARK: History + totals

private struct HistoryChartCard: View {
    @EnvironmentObject private var model: DashboardModel
    @State private var selected: Int?

    private struct Bar: Identifiable {
        let id: Int
        let mb: Double
        let label: String
        let sizeText: String
    }

    private var bars: [Bar] {
        let recent = Array(model.history.prefix(8).reversed())
        return recent.enumerated().map { i, e in
            Bar(id: i, mb: Double(e.bytes) / 1_000_000, label: e.dayText, sizeText: e.sizeText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(title: "Space reclaimed per cleanup", icon: "chart.bar") {
                if let i = selected, let bar = bars.first(where: { $0.id == i }) {
                    Text("\(bar.label) · \(bar.sizeText)")
                        .font(Theme.numeric(11.5, .medium))
                        .foregroundStyle(Theme.accentStrong)
                }
            }

            if bars.isEmpty {
                ZStack {
                    // ghost bars hint at what will appear
                    HStack(alignment: .bottom, spacing: 14) {
                        ForEach([0.35, 0.6, 0.45, 0.8, 0.5, 0.7, 0.4, 0.55], id: \.self) { h in
                            RoundedRectangle(cornerRadius: 4).fill(Theme.canvasDeep)
                                .frame(maxWidth: .infinity)
                                .frame(height: 90 * h)
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    VStack(spacing: 2) {
                        Text("No cleanups yet")
                            .font(Theme.body(12.5, .medium))
                            .foregroundStyle(Theme.textSecondary)
                        Text("Each cleanup you run will appear here.")
                            .font(Theme.body(11.5))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.card.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
                }
            } else {
                Chart(bars) { bar in
                    BarMark(x: .value("Cleanup", bar.id), y: .value("MB", bar.mb), width: .ratio(0.55))
                        .cornerRadius(4)
                        .foregroundStyle(selected == nil || selected == bar.id ? Theme.accent : Theme.accent.opacity(0.35))
                }
                .chartXSelection(value: $selected)
                .chartXAxis {
                    AxisMarks(values: bars.map(\.id)) { value in
                        AxisValueLabel {
                            if let i = value.as(Int.self), let bar = bars.first(where: { $0.id == i }) {
                                Text(bar.label).font(Theme.body(10))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(Theme.line)
                        AxisValueLabel {
                            if let mb = value.as(Double.self) {
                                Text(mb >= 1000 ? String(format: "%.1f GB", mb / 1000) : "\(Int(mb)) MB").font(Theme.body(10))
                            }
                        }
                    }
                }
                .chartXScale(domain: -0.6...(Double(bars.count) - 0.4))
            }
        }
        .padding(16)
        .glassPanel(radius: 14)
    }
}

private struct TotalsCard: View {
    @EnvironmentObject private var model: DashboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardTitle(title: "Lifetime", icon: "sum")
                .padding(.bottom, 10)
            TotalRow(
                icon: "arrow.down.circle",
                label: "Total reclaimed",
                value: model.totalCleanedBytes == 0 ? "0 KB" : ByteCountFormatter.string(fromByteCount: model.totalCleanedBytes, countStyle: .file)
            )
            Theme.line.frame(height: 1)
            TotalRow(icon: "checkmark.circle", label: "Cleanups run", value: "\(model.history.count)")
            Theme.line.frame(height: 1)
            TotalRow(
                icon: "clock",
                label: "Last cleanup",
                value: model.history.first.map { $0.date.formatted(.relative(presentation: .named)) } ?? "Never"
            )
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .glassPanel(radius: 14)
    }
}

private struct TotalRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Theme.accent)
                .frame(width: 24, height: 24)
                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(label)
                .font(Theme.body(12.5))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(Theme.numeric(13, .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxHeight: .infinity)
    }
}

/// The original MacKitty clip: a kitten grooming on the moon. Mirrored by
/// default so the cat sits on the right and text can live on the left.
private struct CatVideoView: NSViewRepresentable {
    var mirrored = true
    var isPlaying = true
    /// Parallax shift in points; the video is overscanned so edges never show.
    var offset: CGSize = .zero
    var cornerRadius: CGFloat = 0
    var roundTopOnly = false

    final class VideoSurface: NSView {
        let playerLayer: AVPlayerLayer
        private let overscan = CGSize(width: 24, height: 14)
        var mirrored = true { didSet { needsLayout = true } }
        var offset: CGSize = .zero {
            didSet {
                guard oldValue != offset else { return }
                // implicit layer animation smooths the cursor-driven drift
                playerLayer.position = center
            }
        }

        private var center: CGPoint {
            CGPoint(x: bounds.midX + offset.width, y: bounds.midY - offset.height)
        }

        init(player: AVPlayer) {
            playerLayer = AVPlayerLayer(player: player)
            super.init(frame: .zero)
            wantsLayer = true
            layer?.masksToBounds = true
            playerLayer.videoGravity = .resizeAspectFill
            layer?.addSublayer(playerLayer)
        }

        func applyCorners(radius: CGFloat, topOnly: Bool) {
            layer?.cornerRadius = radius
            layer?.cornerCurve = .continuous
            // AppKit layers are y-up, so the top edge is maxY
            layer?.maskedCorners = topOnly
                ? [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
                : [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.bounds = bounds.insetBy(dx: -overscan.width, dy: -overscan.height)
            playerLayer.position = center
            playerLayer.transform = mirrored ? CATransform3DMakeScale(-1, 1, 1) : CATransform3DIdentity
            CATransaction.commit()
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
        player.allowsExternalPlayback = false
        player.preventsDisplaySleepDuringVideoPlayback = false
        context.coordinator.player = player
        context.coordinator.looper = AVPlayerLooper(player: player, templateItem: item)
        let view = VideoSurface(player: player)
        view.mirrored = mirrored
        view.applyCorners(radius: cornerRadius, topOnly: roundTopOnly)
        if isPlaying { player.play() }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let surface = nsView as? VideoSurface {
            surface.mirrored = mirrored
            surface.offset = offset
            surface.applyCorners(radius: cornerRadius, topOnly: roundTopOnly)
        }
        guard let player = context.coordinator.player else { return }
        if isPlaying, player.rate == 0 { player.play() }
        if !isPlaying, player.rate != 0 { player.pause() }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.player?.pause()
        coordinator.looper = nil
        coordinator.player = nil
    }
}

/// Button that sits on top of the dark video.
private struct OnVideoButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body(13, .semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(configuration.isPressed ? 0.8 : 1)))
            .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Hero: the video cat fills the card, status and the scan action read over a
/// scrim on the left. The scene drifts with the cursor; the corner button pauses it.
private struct HeroCard: View {
    @EnvironmentObject private var model: DashboardModel
    @State private var pointer: CGPoint?
    @State private var playing = true
    @State private var hovered = false

    private var barColor: Color {
        if model.diskUsedRatio > 0.9 { return Color(red: 1, green: 0.42, blue: 0.42) }
        if model.diskUsedRatio > 0.75 { return Color(red: 1, green: 0.72, blue: 0.3) }
        return Color(red: 0.37, green: 0.9, blue: 0.8)
    }

    private var statusText: String {
        switch model.diskUsedRatio {
        case ..<0.75: "Plenty of space available."
        case ..<0.9: "Storage is filling up. A scan is a good idea."
        default: "Storage is almost full. Run a scan to free space."
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let dx = pointer.map { ($0.x / size.width - 0.5) * -20 } ?? 0
            let dy = pointer.map { ($0.y / size.height - 0.5) * -12 } ?? 0
            ZStack(alignment: .topLeading) {
                Color.black
                CatVideoView(mirrored: true, isPlaying: playing, offset: CGSize(width: dx, height: dy), cornerRadius: 16)
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.82), location: 0),
                        .init(color: .black.opacity(0.5), location: 0.45),
                        .init(color: .clear, location: 0.78)
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
                content
                    .padding(28)
                    .frame(width: min(size.width * 0.58, 500), height: size.height, alignment: .leading)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            Button { playing.toggle() } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(.black.opacity(0.35), in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(14)
            .opacity(hovered || !playing ? 1 : 0)
            .help(playing ? "Pause animation" : "Play animation")
        }
        .shadow(color: Theme.ink.opacity(0.14), radius: 18, y: 8)
        .onContinuousHover { phase in
            switch phase {
            case .active(let p): pointer = p; hovered = true
            case .ended: pointer = nil; hovered = false
            }
        }
        .animation(.easeOut(duration: 0.2), value: hovered)
    }

    private var headline: String {
        switch model.diskUsedRatio {
        case ..<0.75: "Your Mac is in good shape."
        case ..<0.9: "Your Mac is filling up."
        default: "Your Mac is almost out of space."
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Circle().fill(barColor).frame(width: 7, height: 7)
                Text("Macintosh HD · \(Int(model.diskUsedRatio * 100))% used")
                    .font(Theme.body(12, .medium))
                    .foregroundStyle(.white.opacity(0.75))
            }

            Text(headline)
                .font(Theme.display(26, .semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(model.diskFreeText) free of \(model.diskCapacityText). A scan finds caches, logs and leftovers that are safe to remove.")
                .font(Theme.body(13))
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.18))
                    Capsule()
                        .fill(barColor)
                        .frame(width: max(6, proxy.size.width * model.diskUsedRatio))
                }
            }
            .frame(height: 6)
            .help("\(model.diskUsedText) used of \(model.diskCapacityText)")
            .animation(.easeOut(duration: 0.6), value: model.diskUsedRatio)

            Spacer(minLength: 0)

            HStack(spacing: 14) {
                Button(action: model.primaryAction) {
                    Label("Scan My Mac", systemImage: "magnifyingglass")
                }
                .buttonStyle(OnVideoButtonStyle())
                .keyboardShortcut(.defaultAction)

                Label("Nothing is removed without your review", systemImage: "checkmark.shield")
                    .font(Theme.body(12))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}

/// Card with the video cat as a banner; used while scanning and cleaning.
private struct VideoBannerCard<Content: View>: View {
    let title: String
    let subtitle: String
    let progress: Double
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Color.black
                CatVideoView(mirrored: true, cornerRadius: 16, roundTopOnly: true)
                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(Theme.display(20, .semibold))
                            .foregroundStyle(.white)
                        Text(subtitle)
                            .font(Theme.body(12.5))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(Theme.numeric(28, .semibold))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .animation(.default, value: Int(progress * 100))
                }
                .padding(20)
            }
            .frame(height: 200)
            .clipped()

            LinearProgress(value: progress, isActive: progress < 1)
                .padding(.horizontal, 20)
                .padding(.top, 18)

            content
                .padding(20)
        }
        .frame(width: 540)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        .shadow(color: Theme.ink.opacity(0.1), radius: 18, y: 8)
    }
}

/// Live history line; hover to read any sample.
private struct Sparkline: View {
    let values: [Double]
    let color: Color
    @State private var hoverIndex: Int?

    var body: some View {
        GeometryReader { proxy in
            let pts = points(in: proxy.size)
            ZStack(alignment: .topLeading) {
                Path { p in
                    guard let first = pts.first, let last = pts.last else { return }
                    p.move(to: CGPoint(x: first.x, y: proxy.size.height))
                    p.addLines(pts)
                    p.addLine(to: CGPoint(x: last.x, y: proxy.size.height))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [color.opacity(0.22), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                Path { p in p.addLines(pts) }
                    .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

                if let i = hoverIndex, i < pts.count {
                    Path { p in
                        p.move(to: CGPoint(x: pts[i].x, y: 0))
                        p.addLine(to: CGPoint(x: pts[i].x, y: proxy.size.height))
                    }
                    .stroke(Theme.lineStrong, lineWidth: 1)
                    Circle().fill(color).frame(width: 6, height: 6).position(pts[i])
                    Text("\(Int((values[i] * 100).rounded()))%")
                        .font(Theme.numeric(10, .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Theme.ink, in: Capsule())
                        .position(x: min(max(pts[i].x, 16), proxy.size.width - 16), y: max(pts[i].y - 13, 7))
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                if case .active(let p) = phase, values.count > 1 {
                    let i = Int((p.x / max(proxy.size.width, 1) * Double(values.count - 1)).rounded())
                    hoverIndex = min(max(i, 0), values.count - 1)
                } else {
                    hoverIndex = nil
                }
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let step = size.width / Double(values.count - 1)
        return values.enumerated().map { i, v in
            CGPoint(x: Double(i) * step, y: 2 + (1 - min(max(v, 0), 1)) * (size.height - 4))
        }
    }
}

/// Rolling sample buffer for a live metric.
private struct MetricHistory: ViewModifier {
    let value: Double
    @Binding var history: [Double]

    func body(content: Content) -> some View {
        content
            .onAppear { if history.isEmpty { history = [value] } }
            .onChange(of: value) { _, v in
                history.append(v)
                if history.count > 40 { history.removeFirst(history.count - 40) }
            }
    }
}

private func loadColor(_ ratio: Double) -> Color {
    ratio > 0.85 ? Theme.danger : (ratio > 0.65 ? Theme.warning : Theme.accent)
}

private struct CPUStatCard: View {
    @ObservedObject var monitor: SystemMonitorService
    @State private var history: [Double] = []

    var body: some View {
        MetricTile(
            label: "CPU", icon: "cpu",
            faces: [(monitor.cpuText, "load"), (monitor.coreCountText, monitor.chipName)],
            color: loadColor(monitor.cpuUsage),
            history: history
        )
        .modifier(MetricHistory(value: monitor.cpuUsage, history: $history))
    }
}

private struct MemoryStatCard: View {
    @ObservedObject var monitor: SystemMonitorService
    @State private var history: [Double] = []

    var body: some View {
        MetricTile(
            label: "Memory", icon: "memorychip",
            faces: [(monitor.memoryUsedText, "used"), (monitor.memoryPercentText, "pressure"), (monitor.memoryFreeText, "free")],
            color: loadColor(monitor.memoryRatio),
            history: history
        )
        .modifier(MetricHistory(value: monitor.memoryRatio, history: $history))
    }
}

// MARK: - Progress primitives

private struct LinearProgress: View {
    let value: Double
    var color: Color = Theme.accent
    /// While work is running, a light sweep travels across the bar so it never looks frozen.
    var isActive = false

    var body: some View {
        GeometryReader { proxy in
            let filled = max(6, proxy.size.width * min(max(value, 0), 1))
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.canvasDeep)
                Capsule().fill(color)
                    .frame(width: filled)
                    .overlay {
                        if isActive {
                            TimelineView(.animation) { timeline in
                                let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                                LinearGradient(colors: [.white.opacity(0), .white.opacity(0.55), .white.opacity(0)], startPoint: .leading, endPoint: .trailing)
                                    .frame(width: 80)
                                    .offset(x: -80 + phase * (filled + 80))
                            }
                            .frame(width: filled, alignment: .leading)
                            .clipShape(Capsule())
                        }
                    }
            }
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.4), value: value)
    }
}

/// Animated "working" line: bouncing dots plus a reassurance note when the
/// percentage hasn't moved for a few seconds (large folders take time).
private struct WorkingStatus: View {
    let text: String
    let progress: Double
    @State private var lastChange = Date()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.35)) { timeline in
            let step = Int(timeline.date.timeIntervalSinceReferenceDate / 0.35) % 3
            let stalled = timeline.date.timeIntervalSince(lastChange) > 3
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    HStack(spacing: 3) {
                        ForEach(0..<3) { i in
                            Circle()
                                .fill(Theme.accent)
                                .frame(width: 5, height: 5)
                                .offset(y: i == step ? -3 : 0)
                                .opacity(i == step ? 1 : 0.4)
                        }
                    }
                    .animation(.easeInOut(duration: 0.25), value: step)
                    Text(text)
                        .font(Theme.body(12.5, .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                if stalled {
                    Text("Still working. Large folders can take a moment.")
                        .font(Theme.body(11.5))
                        .foregroundStyle(Theme.textTertiary)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.3), value: stalled)
        }
        .onChange(of: progress) { _, _ in lastChange = Date() }
    }
}

// MARK: - Scanning

private struct ScanningScreen: View {
    @EnvironmentObject private var model: DashboardModel

    var body: some View {
        VStack {
            Spacer()
            VideoBannerCard(
                title: "Scanning your Mac",
                subtitle: "Dry run. Nothing is removed during a scan.",
                progress: model.scanProgress
            ) {
                VStack(spacing: 14) {
                    WorkingStatus(text: model.scanPhase, progress: model.scanProgress)

                    HStack {
                        Label("\(model.scanFilesInspected.formatted()) files inspected", systemImage: "doc.text.magnifyingglass")
                            .contentTransition(.numericText())
                        Spacer()
                    }
                    .font(Theme.numeric(12.5, .medium))
                    .foregroundStyle(Theme.textSecondary)

                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .foregroundStyle(Theme.textTertiary)
                        Text(model.scanCurrentPath)
                            .font(Theme.mono(11.5))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    HStack {
                        Spacer()
                        Button("Cancel Scan") { model.cancelScan() }
                            .buttonStyle(GhostButtonStyle())
                            .keyboardShortcut(.cancelAction)
                    }
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Triage

private struct TriageScreen: View {
    @EnvironmentObject private var model: DashboardModel
    @State private var sortBySize = true
    @State private var confirmClean = false

    /// Rows keep their original index so each category keeps its colour when re-sorted.
    private var rows: [(index: Int, category: CleanupCategory)] {
        let indexed = model.cleanupCategories.enumerated().map { (index: $0.offset, category: $0.element) }
        return sortBySize
            ? indexed.sorted { $0.category.sizeBytes > $1.category.sizeBytes }
            : indexed.sorted { $0.category.name.localizedCaseInsensitiveCompare($1.category.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { model.screen = .welcome } }) {
                Label("Overview", systemImage: "chevron.left")
                    .font(Theme.body(12.5, .medium))
                    .foregroundStyle(Theme.accentStrong)
            }
            .buttonStyle(.plain)

            PageHeader(
                title: "Review cleanup",
                subtitle: "\(model.cleanupCategories.count) safe areas found. Choose what to remove."
            ) {
                HStack(spacing: 10) {
                    Picker("Sort", selection: $sortBySize.animation(.snappy)) {
                        Text("Size").tag(true)
                        Text("Name").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 130)
                    Button(model.hasSelectedCleanup ? "Deselect All" : "Select All") {
                        withAnimation(.snappy) {
                            model.hasSelectedCleanup ? model.clearCleanupAreas() : model.selectAllCleanupAreas()
                        }
                    }
                    .buttonStyle(GhostButtonStyle())
                }
            }

            if !model.activeAppWarnings.isEmpty { AppWarnings() }

            VStack(spacing: 0) {
                HStack {
                    Text("Location").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Size").frame(width: 90, alignment: .trailing)
                    Color.clear.frame(width: 28, height: 1)
                }
                .font(Theme.body(11, .medium))
                .foregroundStyle(Theme.textTertiary)
                .padding(.leading, 46)
                .padding(.trailing, 14)
                .padding(.vertical, 9)
                Theme.line.frame(height: 1)

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.category.id) { position, row in
                            CleanupItemRow(category: row.category, color: Theme.category(row.index), showDivider: position > 0) {
                                withAnimation(.snappy) { model.toggleCleanupCategory(row.category.id) }
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            .glassPanel()

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(model.cleanupCategories.filter(\.isSelected).count) of \(model.cleanupCategories.count) selected")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                    Text(model.selectedCleanupSizeText)
                        .font(Theme.numeric(20, .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.numericText())
                }
                Spacer()
                Button { confirmClean = true } label: {
                    Text("Clean \(model.selectedCleanupSizeText)")
                }
                .buttonStyle(PrimaryButtonStyle(isEnabled: model.hasSelectedCleanup))
                .disabled(!model.hasSelectedCleanup)
                .keyboardShortcut(confirmClean ? nil : .defaultAction)
            }
            .padding(16)
            .glassPanel()
        }
        .pageFrame()
        .overlay {
            if confirmClean {
                CleanConfirmSheet(isPresented: $confirmClean)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: confirmClean)
    }
}

/// In-app confirmation before anything is deleted (replaces the system alert).
private struct CleanConfirmSheet: View {
    @EnvironmentObject private var model: DashboardModel
    @Binding var isPresented: Bool
    @State private var appeared = false

    private var selected: [CleanupCategory] { model.cleanupCategories.filter(\.isSelected) }

    var body: some View {
        ZStack {
            Theme.ink.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.danger)
                        .frame(width: 40, height: 40)
                        .background(Theme.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clean \(model.selectedCleanupSizeText)?")
                            .font(Theme.display(17, .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("\(selected.count) area\(selected.count == 1 ? "" : "s") will be emptied")
                            .font(Theme.body(12.5))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                VStack(spacing: 0) {
                    ForEach(Array(selected.prefix(5).enumerated()), id: \.element.id) { index, category in
                        HStack {
                            Text(category.name)
                                .font(Theme.body(12.5))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Text(category.id == DashboardModel.moleCategoryID ? "Varies" : category.sizeText)
                                .font(Theme.numeric(12.5, .medium))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.vertical, 7)
                        .overlay(alignment: .top) { if index > 0 { Theme.line.frame(height: 1) } }
                    }
                    if selected.count > 5 {
                        Text("and \(selected.count - 5) more")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 7)
                            .overlay(alignment: .top) { Theme.line.frame(height: 1) }
                    }
                }
                .padding(.horizontal, 12)
                .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                Label("Files are deleted permanently, not moved to the Trash. Apps rebuild caches when needed.", systemImage: "info.circle")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Spacer()
                    Button("Cancel") { isPresented = false }
                        .buttonStyle(GhostButtonStyle())
                        .keyboardShortcut(.cancelAction)
                    Button("Clean \(model.selectedCleanupSizeText)") {
                        isPresented = false
                        model.clean()
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: Theme.danger))
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(22)
            .frame(width: 420)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
            .shadow(color: Theme.ink.opacity(0.2), radius: 30, y: 12)
            .scaleEffect(appeared ? 1 : 0.94)
            .opacity(appeared ? 1 : 0)
            .onAppear { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { appeared = true } }
        }
    }
}

private struct AppWarnings: View {
    @EnvironmentObject private var model: DashboardModel

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.warning)
            VStack(alignment: .leading, spacing: 4) {
                Text("Some apps are running")
                    .font(Theme.body(12.5, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                ForEach(model.activeAppWarnings, id: \.self) { warning in
                    Text(warning)
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Button("Check Again") { model.checkRunningAppWarnings() }
                .buttonStyle(GhostButtonStyle())
        }
        .padding(14)
        .glassPanel(tint: Theme.warning)
    }
}

private struct CleanupItemRow: View {
    let category: CleanupCategory
    let color: Color
    let showDivider: Bool
    let toggle: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(get: { category.isSelected }, set: { _ in toggle() }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .tint(Theme.accent)

            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 4, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(category.name)
                    .font(Theme.body(13, .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(category.path)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(category.sizeText)
                .font(Theme.numeric(12.5, .medium))
                .foregroundStyle(category.isSelected ? Theme.textPrimary : Theme.textTertiary)
                .frame(width: 90, alignment: .trailing)

            Button { FinderOpener.open(path: category.path) } label: {
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
            .frame(width: 28)
            .opacity(hovered ? 1 : 0.4)
            .help("Show in Finder")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(hovered ? Theme.surface : .clear)
        .overlay(alignment: .top) { if showDivider { Theme.line.frame(height: 1).padding(.leading, 46) } }
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .onHover { hovered = $0 }
    }
}

// MARK: - Cleaning

private struct CleaningScreen: View {
    @EnvironmentObject private var model: DashboardModel

    var body: some View {
        VStack {
            Spacer()
            VideoBannerCard(title: "Cleaning up", subtitle: "Removing only the areas you selected.", progress: model.cleanProgress) {
                WorkingStatus(text: model.cleanPhase, progress: model.cleanProgress)
                    .padding(.bottom, 8)
                if model.cleanLog.isEmpty {
                    Text("Preparing…")
                        .font(Theme.body(12.5))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(model.cleanLog.enumerated()), id: \.offset) { index, entry in
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Theme.success)
                                Text(entry)
                                    .font(Theme.body(12.5))
                                    .foregroundStyle(Theme.textSecondary)
                                Spacer()
                            }
                            .padding(.vertical, 7)
                            .overlay(alignment: .top) { if index > 0 { Theme.line.frame(height: 1) } }
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .animation(.easeOut(duration: 0.25), value: model.cleanLog)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Summary

private struct SummaryScreen: View {
    @EnvironmentObject private var model: DashboardModel
    @State private var appeared = false

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 20) {
                Image(systemName: "checkmark")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.success)
                    .frame(width: 52, height: 52)
                    .background(Theme.success.opacity(0.12), in: Circle())
                    .scaleEffect(appeared ? 1 : 0.6)
                    .opacity(appeared ? 1 : 0)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: appeared)

                VStack(spacing: 4) {
                    Text("Cleanup complete")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textSecondary)
                    Text("\(model.history.first?.sizeText ?? "0 B") reclaimed")
                        .font(Theme.numeric(28, .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(model.history.first?.categoryCount ?? 0) areas cleaned on Macintosh HD")
                        .font(Theme.body(12.5))
                        .foregroundStyle(Theme.textTertiary)
                }

                if !model.lastCleanupBreakdown.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(Array(model.lastCleanupBreakdown.enumerated()), id: \.offset) { index, item in
                            HStack(spacing: 12) {
                                Text(item.0)
                                    .font(Theme.body(12))
                                    .foregroundStyle(Theme.textSecondary)
                                    .frame(width: 130, alignment: .leading)
                                    .lineLimit(1)
                                GeometryReader { proxy in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Theme.canvasDeep)
                                        Capsule()
                                            .fill(Theme.category(index))
                                            .frame(width: appeared ? max(4, proxy.size.width * breakdownRatio(item.1)) : 0)
                                            .animation(.easeOut(duration: 0.6).delay(0.05 * Double(index)), value: appeared)
                                    }
                                }
                                .frame(height: 6)
                                Text(ByteCountFormatter.string(fromByteCount: item.1, countStyle: .file))
                                    .font(Theme.numeric(12, .medium))
                                    .foregroundStyle(Theme.textSecondary)
                                    .frame(width: 70, alignment: .trailing)
                            }
                        }
                    }
                    .padding(16)
                    .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                Button("Done") { model.resetForFreshScan() }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            .padding(28)
            .frame(width: 500)
            .glassPanel(radius: 14)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .onAppear { appeared = true }
    }

    private func breakdownRatio(_ value: Int64) -> Double {
        let maxValue = max(model.lastCleanupBreakdown.map(\.1).max() ?? 1, 1)
        return min(max(Double(value) / Double(maxValue), 0), 1)
    }
}

// MARK: - Apps

private struct AppsScreen: View {
    @EnvironmentObject private var model: DashboardModel
    @State private var appToRemove: InstalledApp?
    @State private var query = ""

    private var filtered: [InstalledApp] {
        query.isEmpty ? model.installedApps : model.installedApps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(
                title: "Applications",
                subtitle: "\(model.installedApps.count) apps installed. Uninstalled apps go to the Trash."
            ) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.textTertiary)
                    TextField("Search", text: $query)
                        .textFieldStyle(.plain)
                        .font(Theme.body(13))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(width: 220)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.lineStrong, lineWidth: 1))
            }

            VStack(spacing: 0) {
                if filtered.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 22))
                            .foregroundStyle(Theme.textTertiary)
                        Text(query.isEmpty ? "No applications found" : "No results for \u{201C}\(query)\u{201D}")
                            .font(Theme.body(13, .medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(filtered.enumerated()), id: \.element.id) { index, app in
                                AppRow(app: app, showDivider: index > 0) { appToRemove = app }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .frame(maxHeight: .infinity)
            .glassPanel()
        }
        .pageFrame()
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

private struct AppRow: View {
    let app: InstalledApp
    let showDivider: Bool
    let onUninstall: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                .resizable()
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .font(Theme.body(13, .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(app.path)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            HStack(spacing: 8) {
                Button("Show in Finder") { FinderOpener.open(path: app.path) }
                    .buttonStyle(GhostButtonStyle())
                Button("Uninstall", action: onUninstall)
                    .font(Theme.body(12.5, .medium))
                    .foregroundStyle(Theme.danger)
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
            }
            .opacity(hovered ? 1 : 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(hovered ? Theme.surface : .clear)
        .overlay(alignment: .top) { if showDivider { Theme.line.frame(height: 1).padding(.leading, 56) } }
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}
