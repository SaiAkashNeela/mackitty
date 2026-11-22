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
    case speed = "Speed"

    /// The App Store sandbox can't see other apps' processes, so it has no Speed tab.
    static var visible: [TopTab] { isAppStoreBuild ? [.clean, .apps] : allCases }
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

struct CleanupCategory: Identifiable {
    let id: String
    let name: String
    let detail: String
    let path: String
    let items: String
    let sizeBytes: Int64
    let icon: String
    var isSelected: Bool
    /// Why the row was left unselected or what was skipped, shown under its path.
    var note: String? = nil
    /// Every file or folder Clean removes for this row, largest first.
    var contents: [CleanupItem] = []

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

/// One file or folder a row deletes, listed under it so nothing is a surprise.
struct CleanupItem: Hashable {
    let name: String
    var bytes: Int64 = 0
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
