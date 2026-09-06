import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: DashboardModel

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HeaderView(report: model.report)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(model.report.metrics) { metric in
                        MetricCard(metric: metric)
                    }
                }

                ScanHeroView(
                    isScanning: model.isScanning,
                    status: model.report.status,
                    phase: model.scanPhase,
                    progress: model.scanProgress,
                    action: model.scan
                )

                Text("Quick Tools")
                    .font(.system(size: 22, weight: .bold, design: .rounded))

                LazyVGrid(columns: columns, spacing: 12) {
                    QuickToolCard(icon: "trash.fill", title: "System Cleanup", detail: "Preview caches, logs and leftovers.", tint: .coral) {
                        model.selectedSection = .clean
                    }
                    QuickToolCard(icon: "shippingbox.fill", title: "Uninstall Apps", detail: "Remove apps and their remnants.", tint: .mint) {
                        model.selectedSection = .manageApps
                    }
                    QuickToolCard(icon: "doc.fill", title: "Find Large Files", detail: "Spot the files taking up space.", tint: .blue) {
                        model.selectedSection = .largeFiles
                    }
                    QuickToolCard(icon: "square.on.square.fill", title: "Find Duplicates", detail: "Review duplicate files safely.", tint: .violet) {
                        model.selectedSection = .duplicates
                    }
                }
            }
            .padding(38)
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.42))
    }
}

private struct HeaderView: View {
    let report: ScanReport

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Good morning,")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("Keep your Mac clean, fast and focused.")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 11) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 11, height: 11)
                    .shadow(color: .green.opacity(0.35), radius: 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(report.scannedAt == nil ? "All good" : "Scan complete")
                        .font(.system(size: 13, weight: .semibold))
                    Text(lastScanText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08))
            }
        }
    }

    private var lastScanText: String {
        guard let scannedAt = report.scannedAt else { return "Ready when you are" }
        return "Last scan: \(scannedAt.formatted(date: .abbreviated, time: .shortened))"
    }
}

private struct MetricCard: View {
    let metric: ScanMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                IconBadge(icon: metric.icon, tint: metric.tint)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(metric.title)
                    .font(.system(size: 13, weight: .medium))
                Text(metric.value)
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                Text(metric.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.075))
        }
    }
}

struct ScanHeroView: View {
    let isScanning: Bool
    let status: String
    let phase: String
    let progress: Double
    let action: () -> Void

    var body: some View {
        HStack(spacing: 30) {
            VStack(alignment: .leading, spacing: 13) {
                Text("Free up space in minutes")
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                Text("Mole previews safe cleanup candidates before anything changes.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: action) {
                    HStack(spacing: 9) {
                        if isScanning {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.system(size: 12, weight: .bold))
                        }
                        Text(isScanning ? "Scanning…" : "Start Scan")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 23)
                    .padding(.vertical, 13)
                    .background(Color.green.opacity(0.82), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isScanning)

                HStack(spacing: 7) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                    Text(isScanning ? phase : status)
                        .font(.system(size: 12))
                }
                .foregroundStyle(.secondary)

                if isScanning {
                    ProgressView(value: progress)
                        .tint(.green)
                        .frame(maxWidth: 270)
                }
            }

            Spacer()

            MacIllustration()
                .frame(width: 300, height: 178)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 24)
        .background {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.075))
        }
    }
}

private struct MacIllustration: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            Circle()
                .fill(Color.green.opacity(0.10))
                .frame(width: 190, height: 190)
                .blur(radius: 2)

            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.92))
                    .frame(width: 205, height: 122)
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(
                                LinearGradient(colors: [Color.blue.opacity(0.72), Color.indigo.opacity(0.45), Color.green.opacity(0.43)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .padding(6)
                            .overlay {
                                AppLogoView(size: 48, cornerRadius: 10)
                            }
                    }
                Capsule()
                    .fill(Color.primary.opacity(0.78))
                    .frame(width: 250, height: 8)
                    .offset(y: 3)
            }
            .shadow(color: .black.opacity(0.18), radius: 15, y: 8)
        }
    }
}

private struct IconBadge: View {
    let icon: String
    let tint: MetricTint

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 21, weight: .semibold))
            .foregroundStyle(tint.color)
            .frame(width: 48, height: 48)
            .background(tint.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

private extension MetricTint {
    var color: Color {
        switch self {
        case .coral: Color(red: 0.90, green: 0.27, blue: 0.24)
        case .blue: Color(red: 0.16, green: 0.38, blue: 0.86)
        case .violet: Color(red: 0.50, green: 0.28, blue: 0.86)
        case .mint: Color(red: 0.10, green: 0.48, blue: 0.34)
        }
    }
}

private struct QuickToolCard: View {
    let icon: String
    let title: String
    let detail: String
    let tint: MetricTint
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                IconBadge(icon: icon, tint: tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
                Spacer(minLength: 2)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(17)
            .frame(maxWidth: .infinity, minHeight: 93, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.075))
            }
        }
        .buttonStyle(.plain)
    }
}
