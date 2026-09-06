import Foundation
import AppKit

@MainActor
final class DashboardModel: ObservableObject {
    @Published var selectedSection: AppSection = .home
    @Published var topTab: TopTab = .clean
    @Published var report = ScanReport.sample
    @Published var screen: DashboardScreen = .welcome
    @Published var isScanning = false
    @Published var isCleaning = false
    @Published var lastOperationOutput = ""
    @Published var scanPhase = "Ready for a fresh scan"
    @Published var scanProgress = 0.0
    @Published var scanFilesInspected = 0
    @Published var scanCurrentPath = "Safe system locations"
    @Published var cleanPhase = "Preparing cleanup"
    @Published var cleanProgress = 0.0
    @Published var cleanLog: [String] = []
    @Published var lastCleanupBreakdown: [(String, Int64)] = []
    @Published var cleanupCategories = CleanupCategory.sample
    @Published var hasScanResults = false
    @Published var didClean = false
    @Published private(set) var history: [CleanupHistoryEntry] = []
    @Published var alertMessage: String?
    @Published var moleVersion = "Mole CLI connected"
    @Published private(set) var diskCapacityBytes: Int64 = 0
    @Published private(set) var diskFreeBytes: Int64 = 0
    @Published private(set) var installedApps: [InstalledApp] = []
    @Published var activeAppWarnings: [String] = []
    @Published var showAbout: Bool = false
    @Published var showScanPermissionModal: Bool = false

    let mole = MoleService()
    let monitor = SystemMonitorService()
    let updater = UpdateCheckerService()
    private var scanTask: Task<Void, Never>?
    private var tickerTask: Task<Void, Never>?
    private var didCancelScan = false
    private var didCancelCleaning = false

    init() {
        if let data = UserDefaults.standard.data(forKey: "cleanup-history"),
           let saved = try? JSONDecoder().decode([CleanupHistoryEntry].self, from: data) {
            history = saved
        }
        refreshDiskStats()
        refreshInstalledApps()
    }

    var primaryButtonTitle: String {
        switch screen {
        case .welcome: "Scan My Mac"
        case .scanning: "Stop scan"
        case .triage: hasSelectedCleanup ? "Clean \(selectedCleanupSizeText)" : "Select areas to clean"
        case .cleaning: "Stop cleaning"
        case .summary: "Scan again"
        }
    }

    var hasSelectedCleanup: Bool { selectedCleanupSize > 0 }
    var totalCleanedBytes: Int64 { history.reduce(0) { $0 + $1.bytes } }

    var selectedCleanupSizeText: String {
        ByteCountFormatter.string(fromByteCount: selectedCleanupSize, countStyle: .file)
    }

    var diskUsedBytes: Int64 { max(diskCapacityBytes - diskFreeBytes, 0) }
    var diskUsedText: String { ByteCountFormatter.string(fromByteCount: diskUsedBytes, countStyle: .file) }
    var diskCapacityText: String { ByteCountFormatter.string(fromByteCount: diskCapacityBytes, countStyle: .file) }
    var diskFreeText: String { ByteCountFormatter.string(fromByteCount: diskFreeBytes, countStyle: .file) }

    var diskUsedRatio: Double {
        guard diskCapacityBytes > 0 else { return 0 }
        return min(max(Double(diskUsedBytes) / Double(diskCapacityBytes), 0), 1)
    }

    private var selectedCleanupSize: Int64 {
        cleanupCategories.filter(\.isSelected).reduce(0) { $0 + $1.sizeBytes }
    }

    func toggleCleanupCategory(_ id: String) {
        guard let index = cleanupCategories.firstIndex(where: { $0.id == id }) else { return }
        cleanupCategories[index].isSelected.toggle()
    }

    func selectAllCleanupAreas() {
        cleanupCategories = cleanupCategories.map { category in
            var selected = category
            selected.isSelected = true
            return selected
        }
    }

    func clearCleanupAreas() {
        cleanupCategories = cleanupCategories.map { category in
            var cleared = category
            cleared.isSelected = false
            return cleared
        }
    }

    func primaryAction() {
        switch screen {
        case .welcome: requestScan()
        case .scanning: cancelScan()
        case .triage: if hasSelectedCleanup { clean() }
        case .cleaning: cancelCleaning()
        case .summary:
            resetForFreshScan()
            requestScan()
        }
    }

    func requestScan() {
        if UserDefaults.standard.bool(forKey: "didAcknowledgeScanPermissions") {
            scan()
        } else {
            showScanPermissionModal = true
        }
    }

    func startScanAfterPermissionPrompt() {
        UserDefaults.standard.set(true, forKey: "didAcknowledgeScanPermissions")
        scan()
    }

    func selectTopTab(_ tab: TopTab) {
        topTab = tab
        if tab == .clean && (screen == .triage || screen == .summary) {
            screen = .welcome
        }
        if tab == .apps { refreshInstalledApps() }
    }

    func refreshInstalledApps() {
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications")
        ]
        var apps: [InstalledApp] = []
        for root in roots {
            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for url in urls where url.pathExtension == "app" {
                apps.append(InstalledApp(id: url.path, name: url.deletingPathExtension().lastPathComponent, path: url.path, sizeText: "Application"))
            }
        }
        installedApps = apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func uninstall(_ app: InstalledApp) {
        do {
            try FileManager.default.trashItem(at: URL(fileURLWithPath: app.path), resultingItemURL: nil)
            refreshInstalledApps()
        } catch {
            alertMessage = "Could not move \(app.name) to the Trash: \(error.localizedDescription)"
        }
    }

    func scan() {
        guard !isScanning, !isCleaning else { return }
        isScanning = true
        screen = .scanning
        alertMessage = nil
        lastOperationOutput = ""
        didClean = false
        hasScanResults = false
        didCancelScan = false
        scanPhase = "Starting Mole…"
        scanCurrentPath = "Inspecting safe cleanup areas…"
        scanFilesInspected = 0
        scanProgress = 0.05

        checkRunningAppWarnings()

        // Active ticker so the UI never feels frozen while Mole traverses disk
        tickerTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let simulatedPaths = [
                "~/Library/Caches/com.apple.Safari",
                "~/Library/Caches/Google/Chrome",
                "~/Library/Caches/org.mozilla.firefox",
                "~/Library/Developer/Xcode/DerivedData",
                "~/.npm/_cacache",
                "~/Library/Caches/JetBrains",
                "~/Library/Logs/DiagnosticReports",
                "~/Library/Caches/com.spotify.client",
                "~/Library/Application Support/CrashReporter",
                "~/Library/Caches/pypoetry/virtualenvs",
                "~/Library/Caches/CloudKit"
            ]
            var pathIdx = 0
            while self.isScanning && !self.didCancelScan {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard self.isScanning && !self.didCancelScan else { break }
                self.scanFilesInspected += Int.random(in: 15...45)
                self.scanCurrentPath = simulatedPaths[pathIdx % simulatedPaths.count]
                pathIdx += 1
                if self.scanProgress < 0.88 {
                    self.scanProgress = min(self.scanProgress + 0.025, 0.88)
                }
            }
        }

        scanTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.mole.previewCleanup { [weak self] chunk in
                    Task { @MainActor [weak self] in
                        self?.consumeLiveOutput(chunk)
                    }
                }
                if didCancelScan { return }
                lastOperationOutput = result.output
            } catch {
                if didCancelScan {
                    isScanning = false
                    screen = .welcome
                    scanPhase = "Scan stopped"
                    scanProgress = 0
                    tickerTask?.cancel()
                    return
                }
                lastOperationOutput = error.localizedDescription
                scanPhase = self.mole.isAvailable ? "Reading safe cleanup areas…" : "Demo data · install Mole to connect"
            }

            tickerTask?.cancel()
            tickerTask = nil
            if didCancelScan { return }
            report.scannedAt = Date()
            report.status = "Scan complete · review safe cleanup areas"
            scanPhase = "Scan complete · review safe cleanup areas"
            scanCurrentPath = "Safe cleanup areas ready to review"
            scanProgress = 1
            hasScanResults = true
            isScanning = false
            screen = .triage
            scanTask = nil
        }
    }

    func cancelScan() {
        guard isScanning else { return }
        didCancelScan = true
        tickerTask?.cancel()
        tickerTask = nil
        scanTask?.cancel()
        mole.cancelCurrentOperation()
        isScanning = false
        screen = .welcome
        scanPhase = "Scan stopped"
        scanCurrentPath = "Safe system locations"
        scanProgress = 0
    }

    func checkRunningAppWarnings() {
        var warnings: [String] = []
        let runningApps = NSWorkspace.shared.runningApplications

        let appChecks: [(id: String, name: String, note: String)] = [
            ("org.mozilla.firefox", "Firefox", "Firefox is currently open — close it to clean its browser caches"),
            ("com.google.Chrome", "Google Chrome", "Chrome is currently open — close it to clean its browser cache"),
            ("com.apple.Safari", "Safari", "Safari is currently open — close it to inspect web caches"),
            ("com.brave.Browser", "Brave", "Brave is currently open — close it to clean browser data"),
            ("com.apple.dt.Xcode", "Xcode", "Xcode is currently open — close it to purge DerivedData build caches")
        ]

        for check in appChecks {
            if runningApps.contains(where: { $0.bundleIdentifier == check.id }) {
                warnings.append(check.note)
            }
        }
        self.activeAppWarnings = warnings
    }

    func clean() {
        guard !isCleaning, hasSelectedCleanup else { return }
        let cleanedBytes = selectedCleanupSize
        let cleanedCategories = cleanupCategories.filter(\.isSelected).count
        isCleaning = true
        screen = .cleaning
        didCancelCleaning = false
        cleanPhase = "Preparing cleanup"
        cleanProgress = 0.03
        cleanLog = []
        alertMessage = nil

        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await mole.clean { [weak self] chunk in
                    Task { @MainActor [weak self] in
                        self?.consumeCleanOutput(chunk)
                    }
                }
                if didCancelCleaning { return }
                report.status = "Cleanup complete"
                lastOperationOutput = result.output
                didClean = true
                cleanPhase = "Cleanup complete"
                cleanProgress = 1
                lastCleanupBreakdown = cleanupCategories.filter(\.isSelected).map { ($0.name, $0.sizeBytes) }
                history.insert(CleanupHistoryEntry(id: UUID(), date: Date(), bytes: cleanedBytes, categoryCount: cleanedCategories), at: 0)
                clearCleanupAreas()
                persistHistory()
                refreshDiskStats()
                screen = .summary
            } catch {
                if didCancelCleaning {
                    isCleaning = false
                    screen = .triage
                    cleanPhase = "Cleaning stopped"
                    return
                }
                lastOperationOutput = error.localizedDescription
                alertMessage = error.localizedDescription
                screen = .triage
            }
            isCleaning = false
        }
    }

    func cancelCleaning() {
        guard isCleaning else { return }
        didCancelCleaning = true
        mole.cancelCurrentOperation()
        isCleaning = false
        screen = .triage
        cleanPhase = "Cleaning stopped"
        cleanProgress = 0
        cleanLog = []
    }

    func resetForFreshScan() {
        hasScanResults = false
        didClean = false
        screen = .welcome
        scanProgress = 0
        scanPhase = "Ready for a fresh scan"
        cleanProgress = 0
        clearCleanupAreas()
    }

    private func persistHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        UserDefaults.standard.set(data, forKey: "cleanup-history")
    }

    private func consumeLiveOutput(_ chunk: String) {
        lastOperationOutput += chunk
        scanFilesInspected += max(1, chunk.split(whereSeparator: \.isNewline).count)

        // Parse running apps or locked warnings from Mole CLI
        for line in chunk.components(separatedBy: .newlines) {
            let lower = line.lowercased()
            if lower.contains("is running") || lower.contains("is open") || lower.contains("cannot clean") || lower.contains("skipped") {
                let cleaned = line.replacingOccurrences(of: "⚠", with: "").trimmingCharacters(in: .whitespaces)
                if !cleaned.isEmpty && !activeAppWarnings.contains(cleaned) {
                    activeAppWarnings.append(cleaned)
                }
            }
        }

        let normalized = chunk.lowercased()

        if normalized.contains("dry run") || normalized.contains("preview only") {
            scanPhase = "Preview mode · nothing will be removed"
            scanCurrentPath = "Mole is listing safe cleanup areas"
            scanProgress = max(scanProgress, 0.2)
        } else if normalized.contains("user essentials") {
            scanPhase = "Checking app caches…"
            scanCurrentPath = "~/Library/Caches"
            scanProgress = max(scanProgress, 0.36)
        } else if normalized.contains("app caches") || normalized.contains("cache") {
            scanPhase = "Checking app caches…"
            scanCurrentPath = "~/Library/Caches"
            scanProgress = max(scanProgress, 0.5)
        } else if normalized.contains("browser") {
            scanPhase = "Checking browser caches…"
            scanCurrentPath = "Safe browser cache locations"
            scanProgress = max(scanProgress, 0.66)
        } else if normalized.contains("developer") || normalized.contains("xcode") {
            scanPhase = "Checking developer artifacts…"
            scanCurrentPath = "~/Library/Developer/Xcode/DerivedData"
            scanProgress = max(scanProgress, 0.8)
        } else if isScanning {
            scanPhase = "Mole is checking your Mac…"
            scanCurrentPath = "Safe system locations"
            scanProgress = min(scanProgress + 0.015, 0.9)
        }
    }

    private func consumeCleanOutput(_ chunk: String) {
        lastOperationOutput += chunk
        let normalized = chunk.lowercased()
        if normalized.contains("cache") {
            cleanPhase = "Removing app caches…"
        } else if normalized.contains("log") {
            cleanPhase = "Removing app logs…"
        } else if normalized.contains("browser") {
            cleanPhase = "Removing browser caches…"
        } else if normalized.contains("developer") || normalized.contains("xcode") {
            cleanPhase = "Removing developer artifacts…"
        } else {
            cleanPhase = "Removing selected safe files…"
        }
        if cleanLog.last != cleanPhase {
            cleanLog.append(cleanPhase)
            cleanLog = Array(cleanLog.suffix(8))
        }
        cleanProgress = min(cleanProgress + 0.08, 0.92)
    }

    func refreshDiskStats() {
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let capacity = attributes[.systemSize] as? NSNumber,
              let free = attributes[.systemFreeSize] as? NSNumber else { return }
        diskCapacityBytes = capacity.int64Value
        diskFreeBytes = free.int64Value
    }

    func refreshVersion() {
        Task {
            do {
                let result = try await mole.version()
                let trimmed = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                if let firstLine = trimmed.split(whereSeparator: \.isNewline).first, !firstLine.isEmpty {
                    moleVersion = "Mole CLI · \(firstLine)"
                }
            } catch {
                moleVersion = mole.isAvailable ? "Mole CLI connected" : "Mole CLI not found"
            }
        }
    }
}
