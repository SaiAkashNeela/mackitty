import Foundation

enum DashboardScreen {
    case welcome
    case scanning
    case triage
    case cleaning
    case summary
}

enum TopTab: String, CaseIterable {
    case clean = "Clean"
    case apps = "Apps"
}

enum AppSection: String, CaseIterable, Identifiable {
    case home
    case clean
    case manageApps
    case largeFiles
    case duplicates
    case startupItems
    case diskUsage
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .clean: "Clean"
        case .manageApps: "Manage Apps"
        case .largeFiles: "Large Files"
        case .duplicates: "Duplicates"
        case .startupItems: "Startup Items"
        case .diskUsage: "Disk Usage"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .clean: "trash"
        case .manageApps: "square.grid.2x2"
        case .largeFiles: "doc.fill"
        case .duplicates: "square.on.square"
        case .startupItems: "rocket.launch"
        case .diskUsage: "chart.pie.fill"
        case .settings: "gearshape"
        }
    }
}

struct ScanMetric: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let detail: String
    let icon: String
    let tint: MetricTint
}

enum MetricTint {
    case coral
    case blue
    case violet
    case mint

    var colorName: String {
        switch self {
        case .coral: "coral"
        case .blue: "blue"
        case .violet: "violet"
        case .mint: "mint"
        }
    }
}

struct ScanReport {
    var metrics: [ScanMetric]
    var scannedAt: Date?
    var status: String

    static let sample = ScanReport(
        metrics: [
            ScanMetric(title: "Junk Files", value: "3.4 GB", detail: "Can be cleaned", icon: "trash.fill", tint: .coral),
            ScanMetric(title: "Large Files", value: "12.8 GB", detail: "Found (23 files)", icon: "doc.fill", tint: .blue),
            ScanMetric(title: "Duplicates", value: "1.1 GB", detail: "Found (184 files)", icon: "square.on.square.fill", tint: .violet),
            ScanMetric(title: "Unused Apps", value: "6", detail: "Not used in 6+ months", icon: "shippingbox.fill", tint: .mint)
        ],
        scannedAt: nil,
        status: "Ready for a fresh scan"
    )
}

struct MoleOperation {
    let title: String
    let command: String
    let detail: String
}

struct CleanupCategory: Identifiable {
    let id: String
    let name: String
    let detail: String
    let path: String
    let items: String
    let sizeBytes: Int64
    let icon: String
    var isSelected: Bool

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    static let sample = [
        CleanupCategory(id: "application-cache", name: "User App Cache", detail: "Temporary files created by apps", path: "~/Library/Caches", items: "1,420", sizeBytes: 896_400_000, icon: "shippingbox", isSelected: false),
        CleanupCategory(id: "logs", name: "User App Logs", detail: "System and app log files", path: "~/Library/Logs", items: "1,932", sizeBytes: 512_800_000, icon: "doc.text", isSelected: false),
        CleanupCategory(id: "app-store-cache", name: "App Store Cache", detail: "Temporary App Store data", path: "~/Library/Caches/com.apple.appstore", items: "248", sizeBytes: 248_500_000, icon: "bag", isSelected: false),
        CleanupCategory(id: "safari-cache", name: "Safari Cache", detail: "Rebuildable browser cache", path: "~/Library/Caches/com.apple.Safari", items: "642", sizeBytes: 642_000_000, icon: "safari", isSelected: false),
        CleanupCategory(id: "chrome-cache", name: "Chrome Cache", detail: "Rebuildable browser cache", path: "~/Library/Caches/Google/Chrome", items: "1,256", sizeBytes: 1_200_000_000, icon: "globe", isSelected: false),
        CleanupCategory(id: "npm-cache", name: "npm Cache", detail: "Rebuildable developer cache", path: "~/.npm", items: "—", sizeBytes: 420_000_000, icon: "chevron.left.forwardslash.chevron.right", isSelected: false),
        CleanupCategory(id: "xcode-data", name: "Xcode Derived Data", detail: "Rebuildable build artifacts", path: "~/Library/Developer/Xcode/DerivedData", items: "5", sizeBytes: 2_100_000_000, icon: "hammer", isSelected: false)
    ]
}

struct CleanupHistoryEntry: Identifiable, Codable {
    let id: UUID
    let date: Date
    let bytes: Int64
    let categoryCount: Int

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    var dayText: String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }
}

struct InstalledApp: Identifiable {
    let id: String
    let name: String
    let path: String
    let sizeText: String
}
