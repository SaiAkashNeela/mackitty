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

    static let empty = ScanReport(
        metrics: [],
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
