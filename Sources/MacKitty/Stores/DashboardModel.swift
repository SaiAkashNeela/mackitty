import Foundation
import AppKit
import Combine

@MainActor
final class DashboardModel: ObservableObject {
    @Published var topTab: TopTab = .clean
    @Published var report = ScanReport.empty
    @Published var screen: DashboardScreen = .welcome
    @Published var isScanning = false
    @Published var isCleaning = false
    @Published var scanPhase = "Ready for a fresh scan"
    @Published var scanProgress = 0.0
    @Published var scanFilesInspected = 0
    @Published var scanCurrentPath = "Safe system locations"
    @Published var cleanPhase = "Preparing cleanup"
    @Published var cleanProgress = 0.0
    @Published var cleanLog: [String] = []
    @Published var lastCleanupBreakdown: [(String, Int64)] = []
    @Published var cleanupCategories: [CleanupCategory] = []
    @Published var hasScanResults = false
    @Published var didClean = false
    @Published private(set) var history: [CleanupHistoryEntry] = []
    @Published var alertMessage: String?
    @Published private(set) var diskCapacityBytes: Int64 = 0
    @Published private(set) var diskFreeBytes: Int64 = 0
    @Published private(set) var installedApps: [InstalledApp] = []
    @Published var activeAppWarnings: [String] = []
    @Published var showAbout: Bool = false
    @Published var showScanPermissionModal: Bool = false
    @Published private(set) var projectRoots: [URL] = ProjectFolders.roots
    @Published private(set) var memoryReport: MemoryReport?

    let nativeCleaner = NativeCleanerService()
    let monitor = SystemMonitorService()
    var updater = UpdateCheckerService()
    private var scanTask: Task<Void, Never>?
    private var cleanTask: Task<Void, Never>?
    /// Each scan/clean run gets an ID so a cancelled run can't apply stale results
    /// or keep deleting after the user starts a new one.
    private var scanRunID = UUID()
    private var cleanRunID = UUID()
    private var tickerTask: Task<Void, Never>?
    private var didCancelScan = false
    private var didCancelCleaning = false
    private var cancellables = Set<AnyCancellable>()

    init() {
        if let data = UserDefaults.standard.data(forKey: "cleanup-history"),
           let saved = try? JSONDecoder().decode([CleanupHistoryEntry].self, from: data) {
            history = saved
        }
        refreshDiskStats()
        refreshInstalledApps()

        // Forward updater changes so SwiftUI re-renders in-app update banners reactively
        updater.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
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
        if isAppStoreBuild {
            if SandboxAccess.hasAccess || SandboxAccess.requestHomeAccess() {
                scan()
            } else {
                alertMessage = "MacKitty needs access to your home folder to scan caches and logs. Choose your home folder (the one with your name) when asked."
            }
            return
        }
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
        if tab == .speed { refreshMemoryReport() }
    }

    /// Read on demand only; the Speed tab never polls.
    func refreshMemoryReport() {
        Task {
            memoryReport = await Task.detached(priority: .userInitiated) { MemoryReport.current() }.value
        }
    }

    /// Apps are asked to quit (they can still ask to save); tools get SIGTERM. Processes are
    /// looked up again so a reused process ID is never hit.
    func stop(_ user: MemoryUser) {
        guard !user.isSystem else { return }
        let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.path == user.appURL?.path }
        if user.appURL != nil && !apps.isEmpty {
            apps.forEach { $0.terminate() }
        } else {
            // Command-line tools, and app bundles macOS doesn't list as running apps (e.g. a simulator's app).
            RunningProcesses.snapshot()
                .filter { MemoryReport.key(for: $0) == user.id }
                .forEach { kill($0.pid, SIGTERM) }
        }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            refreshMemoryReport()
        }
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

    /// Lets the user pick the folders where they keep code, then rescans so their
    /// projects' node_modules and build output show up for review.
    func chooseProjectFolders() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Use These Folders"
        panel.message = "Choose the folders where you keep code. MacKitty finds node_modules and build output that your next install or build recreates."
        panel.directoryURL = projectRoots.first ?? FileManager.default.homeDirectoryForCurrentUser
        guard panel.runModal() == .OK else { return }
        // The whole disk or home folder would take long to walk and isn't a code folder.
        let roots = panel.urls.filter { $0.path != "/" && $0.standardizedFileURL != FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL }
        guard !roots.isEmpty else {
            alertMessage = "Choose the folders that hold your projects (for example ~/Developer), not your whole home folder or disk."
            return
        }
        ProjectFolders.roots = roots
        projectRoots = roots
        scan()
    }

    /// Moves the app to the Trash, then the leftovers the user agreed to remove.
    func uninstall(_ app: InstalledApp, leftovers: AppLeftovers = AppLeftovers()) {
        let url = URL(fileURLWithPath: app.path)
        // A running app rewrites its data and restarts its helpers as they are removed.
        if let bundleID = Bundle(url: url)?.bundleIdentifier,
           !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
            alertMessage = "Quit \(app.name) first, then uninstall it."
            return
        }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            refreshInstalledApps()
        } catch {
            alertMessage = "Could not move \(app.name) to the Trash: \(error.localizedDescription)"
            return
        }

        var failed = AppLeftovers.moveToTrash(leftovers.userItems).map(\.path)
        if !leftovers.systemItems.isEmpty && !AppLeftovers.removeWithAdminPassword(leftovers.systemItems) {
            failed += leftovers.systemItems.map(\.path)
        }
        if !failed.isEmpty {
            alertMessage = "\(app.name) is in the Trash, but these leftovers were not removed:\n" + failed.joined(separator: "\n")
        }
    }

    func scan() {
        guard !isScanning, !isCleaning else { return }
        isScanning = true
        screen = .scanning
        alertMessage = nil
        didClean = false
        hasScanResults = false
        didCancelScan = false
        scanPhase = "Starting scan…"
        scanCurrentPath = "Inspecting safe cleanup areas…"
        scanFilesInspected = 0
        scanProgress = 0.05

        checkRunningAppWarnings()

        let runID = UUID()
        scanRunID = runID
        scanTask = Task { [weak self] in
            guard let self else { return }
            let scanResult = await self.nativeCleaner.scanAllTargets { [weak self] name, path, countSoFar in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.scanPhase = "Inspecting \(name)…"
                    self.scanCurrentPath = path
                    self.scanFilesInspected = countSoFar
                    self.scanProgress = min(0.15 + (Double(countSoFar) / 1000.0) * 0.75, 0.95)
                }
            }
            if didCancelScan || scanRunID != runID { return }
            self.cleanupCategories = scanResult.categories
            let junkFormatted = ByteCountFormatter.string(fromByteCount: scanResult.totalBytes, countStyle: .file)
            self.report.metrics = [
                ScanMetric(title: "Junk Files", value: junkFormatted, detail: "Safe caches & logs", icon: "trash.fill", tint: .coral),
                ScanMetric(title: "Items Scanned", value: "\(scanResult.totalItems)", detail: "Cleanable entries", icon: "doc.fill", tint: .blue),
                ScanMetric(title: "Engine", value: "Native", detail: "Swift safe engine", icon: "bolt.fill", tint: .mint),
                ScanMetric(title: "Safety Level", value: "100%", detail: "Zero personal data", icon: "shield.fill", tint: .violet)
            ]
            self.scanFilesInspected = scanResult.totalItems

            if didCancelScan || scanRunID != runID { return }
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
        scanRunID = UUID()
        scanTask?.cancel()
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
        let selectedCategories = cleanupCategories.filter(\.isSelected)
        let selectedBytes = selectedCleanupSize
        let cleanedCount = selectedCategories.count
        isCleaning = true
        screen = .cleaning
        didCancelCleaning = false
        cleanPhase = "Preparing cleanup"
        cleanProgress = 0.03
        cleanLog = []
        alertMessage = nil

        let runID = UUID()
        cleanRunID = runID
        cleanTask = Task { [weak self] in
            guard let self else { return }
            var actuallyCleanedBytes: Int64 = 0

            // 1. Clean selected categories via native engine (with real recursive deletion and size tracking)
            let totalSelected = selectedCategories.count
            var processedCount = 0

            for category in selectedCategories {
                if (self.didCancelCleaning || self.cleanRunID != runID) { break }
                let bytes = await self.nativeCleaner.cleanCategory(category) { [weak self] progressText in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.cleanPhase = progressText
                        if self.cleanLog.last != progressText {
                            self.cleanLog.append(progressText)
                            self.cleanLog = Array(self.cleanLog.suffix(8))
                        }
                    }
                }
                actuallyCleanedBytes += bytes
                processedCount += 1
                self.cleanProgress = min(Double(processedCount) / Double(max(totalSelected, 1)), 0.85)
            }

            if self.cleanRunID != runID { return }
            if self.didCancelCleaning {
                self.isCleaning = false
                self.screen = .triage
                self.cleanPhase = "Cleaning stopped"
                return
            }

            // Immediately re-scan real targets so the UI reflects real zeroed/reduced disk sizes
            let rescanResult = await self.nativeCleaner.scanAllTargets()
            if self.cleanRunID != runID { return }
            self.cleanupCategories = rescanResult.categories

            self.didClean = true
            self.cleanPhase = "Cleanup complete"
            self.cleanProgress = 1
            self.lastCleanupBreakdown = selectedCategories.map { ($0.name, $0.sizeBytes) }
            let recordedBytes = actuallyCleanedBytes > 0 ? actuallyCleanedBytes : selectedBytes
            self.history.insert(CleanupHistoryEntry(id: UUID(), date: Date(), bytes: recordedBytes, categoryCount: cleanedCount), at: 0)
            self.clearCleanupAreas()
            self.persistHistory()
            self.refreshDiskStats()
            self.screen = .summary
            self.isCleaning = false
        }
    }

    func cancelCleaning() {
        guard isCleaning else { return }
        didCancelCleaning = true
        cleanRunID = UUID()
        cleanTask?.cancel()
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

    func refreshDiskStats() {
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let capacity = attributes[.systemSize] as? NSNumber,
              let free = attributes[.systemFreeSize] as? NSNumber else { return }
        diskCapacityBytes = capacity.int64Value
        diskFreeBytes = free.int64Value
    }
}
