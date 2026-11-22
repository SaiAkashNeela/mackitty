import Foundation
import AppKit

struct NativeScanResult {
    let categories: [CleanupCategory]
    let totalBytes: Int64
    let totalItems: Int
}

final class NativeCleanerService: @unchecked Sendable {
    private let fileManager = FileManager.default

    struct TargetSpec {
        let id: String
        let name: String
        let detail: String
        let relativePath: String
        let icon: String
        let excludedSubpaths: Set<String>
        /// When set, only these children are cleaned; everything else (logins, signing keys) stays.
        let onlySubpaths: Set<String>
        /// Developer caches can't be emptied while a tool runs from them or holds them open.
        let checksBusy: Bool
        /// An argument that marks a process as using this cache (e.g. "GradleDaemon").
        let busyArgument: String?
        /// False for rows the user should opt into, such as emptying the Trash.
        let startsSelected: Bool

        init(id: String, name: String, detail: String, relativePath: String, icon: String,
             excludedSubpaths: Set<String> = [], onlySubpaths: Set<String> = [], checksBusy: Bool = false,
             busyArgument: String? = nil, startsSelected: Bool = true) {
            self.id = id
            self.name = name
            self.detail = detail
            self.relativePath = relativePath
            self.icon = icon
            self.excludedSubpaths = excludedSubpaths
            self.onlySubpaths = onlySubpaths
            self.checksBusy = checksBusy
            self.busyArgument = busyArgument
            self.startsSelected = startsSelected
        }
    }

    /// Folders found per project row in the last scan, keyed by category id.
    private var projectFolders: [String: [URL]] = [:]
    static let projectCategoryPrefix = "project:"

    private let targets: [TargetSpec] = [
        TargetSpec(
            id: "xcode-data",
            name: "Xcode Derived Data",
            detail: "Rebuildable intermediate build products & symbol indexes",
            relativePath: "Library/Developer/Xcode/DerivedData",
            icon: "hammer"
        ),
        TargetSpec(
            id: "safari-cache",
            name: "Safari Cache",
            detail: "Rebuildable web browsing cache and site media",
            relativePath: "Library/Caches/com.apple.Safari",
            icon: "safari"
        ),
        TargetSpec(
            id: "chrome-cache",
            name: "Google Chrome Cache",
            detail: "Rebuildable Google Chrome HTTP disk cache",
            relativePath: "Library/Caches/Google/Chrome",
            icon: "globe"
        ),
        TargetSpec(
            id: "firefox-cache",
            name: "Firefox Cache",
            detail: "Rebuildable Mozilla Firefox web cache",
            relativePath: "Library/Caches/org.mozilla.firefox",
            icon: "flame"
        ),
        TargetSpec(
            id: "npm-cache",
            name: "npm & Node Cache",
            detail: "Cached Node package manager archives and tarballs",
            relativePath: ".npm",
            icon: "chevron.left.forwardslash.chevron.right"
        ),
        TargetSpec(
            id: "gradle-cache",
            name: "Gradle Cache",
            detail: "Downloaded Android/Java dependencies; the next build fetches them again",
            relativePath: ".gradle/caches",
            icon: "cube.box",
            checksBusy: true,
            busyArgument: "GradleDaemon"
        ),
        TargetSpec(
            id: "uv-cache",
            name: "uv Python Cache",
            detail: "Downloaded Python packages and uvx tool environments",
            relativePath: ".cache/uv",
            icon: "chevron.left.forwardslash.chevron.right",
            checksBusy: true
        ),
        TargetSpec(
            id: "bun-cache",
            name: "Bun Install Cache",
            detail: "Downloaded packages bun reuses across installs",
            relativePath: ".bun/install/cache",
            icon: "chevron.left.forwardslash.chevron.right",
            checksBusy: true
        ),
        TargetSpec(
            id: "pnpm-store",
            name: "pnpm Store",
            detail: "Shared package store; projects re-link packages on the next install",
            relativePath: "Library/pnpm/store",
            icon: "chevron.left.forwardslash.chevron.right",
            checksBusy: true
        ),
        TargetSpec(
            id: "cargo-registry",
            name: "Cargo Registry",
            detail: "Downloaded Rust crates and their sources; cargo fetches them again",
            relativePath: ".cargo/registry",
            icon: "gearshape.2",
            checksBusy: true,
            busyArgument: "cargo"
        ),
        TargetSpec(
            id: "expo-cache",
            name: "Expo Cache",
            detail: "Downloaded Expo Go apps and build caches; your Expo login stays",
            relativePath: ".expo",
            icon: "iphone.and.arrow.forward",
            onlySubpaths: ["expo-go", "ios-simulator-app-cache", "android-apk-cache", "native-modules-cache", "versions-cache", "schema-cache"],
            checksBusy: true
        ),
        TargetSpec(
            id: "ios-device-support",
            name: "iOS Device Support",
            detail: "Debug files Xcode copied from each iPhone you connected; it copies them again next time",
            relativePath: "Library/Developer/Xcode/iOS DeviceSupport",
            icon: "iphone.gen3",
            checksBusy: true
        ),
        TargetSpec(
            id: "logs",
            name: "User App Logs",
            detail: "Stale crash logs and application diagnostics",
            relativePath: "Library/Logs",
            icon: "doc.text"
        ),
        TargetSpec(
            id: "application-cache",
            name: "Other App Caches",
            detail: "Temporary cache files generated by installed apps",
            relativePath: "Library/Caches",
            icon: "shippingbox",
            excludedSubpaths: ["com.apple.Safari", "Google", "org.mozilla.firefox", "com.apple.appstore"]
        ),
        TargetSpec(
            id: "trash",
            name: "Trash",
            detail: "Files you moved to the Trash; emptying it can't be undone",
            relativePath: ".Trash",
            icon: "trash",
            startsSelected: false
        )
    ]

    /// Children of a target that must never be touched. For the catch-all
    /// "Other App Caches" this also protects Apple's own caches (iCloud, CloudKit…)
    /// and the caches of apps that are running right now.
    func protectedNames(in url: URL, for spec: TargetSpec) -> Set<String> {
        var names = spec.excludedSubpaths
        let children = (try? fileManager.contentsOfDirectory(atPath: url.path)) ?? []
        if !spec.onlySubpaths.isEmpty {
            names.formUnion(children.filter { !spec.onlySubpaths.contains($0) })
        }
        guard spec.id == "application-cache" else { return names }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier?.lowercased() })
        for child in children {
            let lower = child.lowercased()
            if lower.hasPrefix("com.apple.") || running.contains(lower) {
                names.insert(child)
            }
        }
        return names
    }

    private func resolveURL(for relativePath: String) -> URL {
        #if APPSTORE
        // In the sandbox the user-granted home folder replaces the container home.
        // Without a grant, point at a path that doesn't exist so nothing is touched.
        let home = SandboxAccess.homeURL() ?? URL(fileURLWithPath: "/nonexistent-mackitty-home")
        return home.appendingPathComponent(relativePath)
        #else
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(relativePath)
        #endif
    }

    /// Calculate the real size and file count of a directory
    func calculateDirectoryMetrics(at url: URL, excluding: Set<String> = []) -> (bytes: Int64, count: Int) {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir) else {
            return (0, 0)
        }

        if !isDir.boolValue {
            let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            return (size, 1)
        }

        var totalBytes: Int64 = 0
        var totalCount: Int = 0

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey, .isRegularFileKey],
            options: [.skipsPackageDescendants]
        ) else {
            return (0, 0)
        }

        for case let fileURL as URL in enumerator {
            // Check exclusions relative to parent directory
            if !excluding.isEmpty {
                let relative = fileURL.path.replacingOccurrences(of: url.path + "/", with: "")
                let topComponent = relative.split(separator: "/").first.map(String.init) ?? ""
                if excluding.contains(topComponent) {
                    enumerator.skipDescendants()
                    continue
                }
            }

            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]) else {
                continue
            }
            if resourceValues.isRegularFile == true {
                totalBytes += Int64(resourceValues.fileSize ?? 0)
                totalCount += 1
            }
        }

        return (totalBytes, totalCount)
    }

    /// A process using a developer cache right now, if the cache checks for one.
    private func busyProcess(for spec: TargetSpec, at url: URL, in processes: [RunningProcess]) -> RunningProcess? {
        guard spec.checksBusy else { return nil }
        if let process = processes.runningFrom(url.path) { return process }
        guard let argument = spec.busyArgument else { return nil }
        return processes.first { $0.arguments.contains { $0.contains(argument) } }
    }

    private static func displayPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    private static func formatted(_ count: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: count), number: .decimal)
    }

    /// Scan all known targets and return populated categories with real disk sizes
    func scanAllTargets(onProgress: @escaping (String, String, Int) -> Void = { _, _, _ in }) async -> NativeScanResult {
        var categories: [CleanupCategory] = []
        var totalBytes: Int64 = 0
        var totalItems: Int = 0
        let processes = RunningProcesses.snapshot()

        for target in targets {
            let url = resolveURL(for: target.relativePath)
            // Developer caches only appear for tools that are installed.
            if target.checksBusy && !fileManager.fileExists(atPath: url.path) { continue }
            let displayPath = "~/" + target.relativePath
            onProgress(target.name, displayPath, totalItems)

            // Sized child by child, so the list under the row is exactly what Clean removes.
            let protected = protectedNames(in: url, for: target)
            var contents: [CleanupItem] = []
            var bytes: Int64 = 0
            var count = 0
            for child in (try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
            where !Self.keeps(child.lastPathComponent, protected: protected) {
                let metrics = calculateDirectoryMetrics(at: child)
                bytes += metrics.bytes
                count += metrics.count
                contents.append(CleanupItem(name: child.lastPathComponent, bytes: metrics.bytes))
            }
            contents.sort { $0.bytes > $1.bytes }
            totalBytes += bytes
            totalItems += count
            onProgress(target.name, displayPath, totalItems)

            let busy = busyProcess(for: target, at: url, in: processes)
            // macOS hides some folders (the Trash) from apps without Full Disk Access.
            let unreadable = fileManager.fileExists(atPath: url.path) && (try? fileManager.contentsOfDirectory(atPath: url.path)) == nil
            let category = CleanupCategory(
                id: target.id,
                name: target.name,
                detail: target.detail,
                path: displayPath,
                items: count > 0 ? Self.formatted(count) : "0",
                sizeBytes: bytes,
                icon: target.icon,
                isSelected: bytes > 0 && busy == nil && target.startsSelected,
                note: busy.map { "In use by \($0.name). Quit it to clean this." }
                    ?? (unreadable ? "Allow MacKitty Full Disk Access in System Settings › Privacy & Security to clean this." : nil),
                contents: contents
            )

            categories.append(category)
        }

        #if !APPSTORE
        // The sandbox can't run git or see other processes, so project cleanup is direct-download only.
        let projects = scanProjects(processes: processes) { onProgress("Code folders", $0, totalItems) }
        categories += projects
        totalBytes += projects.reduce(0) { $0 + $1.sizeBytes }
        #endif

        onProgress("Simulators", "~/Library/Developer/CoreSimulator", totalItems)
        let simulators = await scanSimulators()
        categories += simulators
        totalBytes += simulators.reduce(0) { $0 + $1.sizeBytes }

        let emulators = scanAndroidEmulators(processes: processes)
        categories += emulators
        totalBytes += emulators.reduce(0) { $0 + $1.sizeBytes }

        // Check Docker if installed
        if let dockerMetrics = await inspectDockerMetrics(), dockerMetrics.bytes > 0 || dockerMetrics.count > 0 {
            onProgress("Docker Daemon", "docker://localhost", totalItems)
            let formattedCount = dockerMetrics.count > 0 ? NumberFormatter.localizedString(from: NSNumber(value: dockerMetrics.count), number: .decimal) : "1"
            let dockerCategory = CleanupCategory(
                id: "docker-images",
                name: "Docker Unused Images & Build Cache",
                detail: "Images no container uses and unused build cache; running containers are untouched",
                path: "Docker Daemon",
                items: formattedCount,
                sizeBytes: dockerMetrics.bytes,
                icon: "shippingbox.fill",
                isSelected: dockerMetrics.bytes > 0,
                contents: [CleanupItem(name: "Images no container uses (pulled again when needed)"),
                           CleanupItem(name: "Unused build cache (the next docker build takes longer)")]
            )
            categories.append(dockerCategory)
            totalBytes += dockerMetrics.bytes
            totalItems += dockerMetrics.count
        }

        return NativeScanResult(categories: categories, totalBytes: totalBytes, totalItems: totalItems)
    }

    /// Safely cleans contents inside a target directory or triggers Docker pruning without deleting parent folders
    func cleanCategory(_ category: CleanupCategory, onProgress: @escaping (String) -> Void) async -> Int64 {
        // Docker special category
        if category.id == "docker-images" {
            let beforeBytes = category.sizeBytes
            _ = await cleanDocker(onProgress: onProgress)
            let after = await inspectDockerMetrics()
            let freed = max(beforeBytes - (after?.bytes ?? 0), 0)
            return freed
        }

        if category.id.hasPrefix(Self.projectCategoryPrefix) {
            return cleanProject(category, onProgress: onProgress)
        }

        if category.id.hasPrefix(Self.simulatorRuntimePrefix) || category.id == Self.unavailableSimulatorsID {
            return await cleanSimulator(category, onProgress: onProgress)
        }

        if category.id.hasPrefix(Self.androidEmulatorPrefix) {
            return cleanAndroidEmulator(category, onProgress: onProgress)
        }

        guard let spec = targets.first(where: { $0.id == category.id }) else { return 0 }
        let url = resolveURL(for: spec.relativePath)

        // Checked again at clean time: a build may have started since the scan.
        if let busy = busyProcess(for: spec, at: url, in: RunningProcesses.snapshot()) {
            onProgress("Skipped \(category.name): in use by \(busy.name)")
            return 0
        }

        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return 0
        }

        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: []
        ) else {
            return 0
        }

        var cleanedBytes: Int64 = 0
        let protected = protectedNames(in: url, for: spec)

        for itemURL in contents {
            if Task.isCancelled { break }
            let itemName = itemURL.lastPathComponent
            if Self.keeps(itemName, protected: protected) { continue }

            onProgress("Removing \(category.name) · \(itemName)")

            // Calculate actual recursive size before deletion
            let (itemBytes, _) = calculateDirectoryMetrics(at: itemURL)

            do {
                try fileManager.removeItem(at: itemURL)
                cleanedBytes += itemBytes
            } catch {
                // If permission is denied or file is locked by a running process, continue safely
                continue
            }
        }

        return cleanedBytes
    }

    /// Children Clean leaves alone: hidden system files and protected or excluded names.
    private static func keeps(_ name: String, protected: Set<String>) -> Bool {
        (name.hasPrefix(".") && name != ".npm") || protected.contains(name)
    }

    // MARK: - Code projects

    /// One row per project with rebuildable output, all ticked so the user unticks what to keep.
    /// Notes flag shipped builds, projects open in a running process and recent work.
    func scanProjects(processes: [RunningProcess], onProgress: (String) -> Void = { _ in }) -> [CleanupCategory] {
        projectFolders = [:]
        let now = Date()
        return ProjectArtifactScanner.scan(roots: ProjectFolders.roots) { onProgress(Self.displayPath($0)) }
            .filter { $0.bytes > 0 }
            .map { project in
                let id = Self.projectCategoryPrefix + project.project.path
                projectFolders[id] = project.folders
                let inUse = processes.workingIn(project.project.path)
                let idleDays = Int(now.timeIntervalSince(ProjectArtifactScanner.lastActivity(of: project.project)) / 86_400)

                var notes: [String] = []
                if let first = project.releaseFiles.first {
                    let more = project.releaseFiles.count > 1 ? " and \(project.releaseFiles.count - 1) more" : ""
                    notes.append("Contains \(first)\(more). Copy shipped builds out first")
                }
                if let inUse { notes.append("Open in \(inUse.name)") }
                if idleDays < 7 { notes.append(idleDays == 0 ? "Worked on today" : "Worked on \(idleDays) day\(idleDays == 1 ? "" : "s") ago") }
                if project.trackedFolderCount > 0 {
                    notes.append("\(project.trackedFolderCount) git-tracked folder\(project.trackedFolderCount == 1 ? "" : "s") left out")
                }

                return CleanupCategory(
                    id: id,
                    name: "\(project.project.lastPathComponent) · \(project.kinds.joined(separator: ", "))",
                    detail: "Recreated by the project's next install, build or test run",
                    path: Self.displayPath(project.project.path),
                    items: Self.formatted(project.fileCount),
                    sizeBytes: project.bytes,
                    icon: "folder.badge.gearshape",
                    isSelected: true,
                    note: notes.isEmpty ? nil : notes.joined(separator: " · "),
                    contents: project.folders.map { folder in
                        let relative = folder.path.hasPrefix(project.project.path + "/")
                            ? String(folder.path.dropFirst(project.project.path.count + 1)) : folder.lastPathComponent
                        return CleanupItem(name: "\(relative) · \(project.kindByFolder[folder] ?? "")", bytes: project.bytesByFolder[folder] ?? 0)
                    }.sorted { $0.bytes > $1.bytes }
                )
            }
    }

    private func cleanProject(_ category: CleanupCategory, onProgress: @escaping (String) -> Void) -> Int64 {
        let roots = ProjectFolders.roots.map { ProjectArtifactScanner.canonical($0).path + "/" }
        let processes = RunningProcesses.snapshot()
        let projectName = category.name.components(separatedBy: " · ").first ?? category.name
        var cleaned: Int64 = 0

        for folder in projectFolders[category.id] ?? [] {
            if Task.isCancelled { break }
            let path = folder.path
            // Re-checked at delete time: still inside a chosen code folder, still a real
            // folder (not a symlink), and no program is running from inside it.
            guard roots.contains(where: { path.hasPrefix($0) }),
                  let values = try? folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true,
                  processes.runningFrom(path) == nil else { continue }

            onProgress("Removing \(projectName) · \(folder.lastPathComponent)")
            let bytes = ProjectArtifactScanner.measure(folder).bytes
            do {
                try fileManager.removeItem(at: folder)
                cleaned += bytes
            } catch {
                continue
            }
        }
        return cleaned
    }

    // MARK: - Simulators

    static let simulatorRuntimePrefix = "simruntime:"
    private static let unavailableSimulatorsID = "simulators-unavailable"

    struct SimulatorRuntime {
        let identifier: String
        let name: String
        let path: String
        let bytes: Int64
        let lastUsed: Date?
    }

    /// Xcode's simctl, found through xcode-select rather than xcrun so a Mac without
    /// Xcode never sees the "install developer tools" dialog.
    private func simctlURL() async -> URL? {
        #if APPSTORE
        return nil
        #else
        guard let developer = await run(URL(fileURLWithPath: "/usr/bin/xcode-select"), ["-p"], timeoutSeconds: 5),
              developer.status == 0 else { return nil }
        let simctl = developer.output.trimmingCharacters(in: .whitespacesAndNewlines) + "/usr/bin/simctl"
        return fileManager.isExecutableFile(atPath: simctl) ? URL(fileURLWithPath: simctl) : nil
        #endif
    }

    /// Every runtime except the newest per platform (`simctl runtime list -j`).
    /// Xcode downloads an old one again if a project ever needs it.
    static func oldSimulatorRuntimes(fromJSON data: Data) -> [SimulatorRuntime] {
        guard let all = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { return [] }
        let runtimes = all.values.filter { $0["deletable"] as? Bool == true }
        let newest = Dictionary(grouping: runtimes) { $0["platformIdentifier"] as? String ?? "" }
            .mapValues { $0.compactMap { $0["version"] as? String }.max { $0.compare($1, options: .numeric) == .orderedAscending } }
        let dates = ISO8601DateFormatter()

        return runtimes.compactMap { runtime in
            guard let identifier = runtime["identifier"] as? String,
                  let version = runtime["version"] as? String,
                  let platform = runtime["platformIdentifier"] as? String,
                  version != newest[platform] ?? nil else { return nil }
            // "com.apple.CoreSimulator.SimRuntime.iOS-17-5" → "iOS"
            let os = (runtime["runtimeIdentifier"] as? String)?
                .components(separatedBy: ".").last?.components(separatedBy: "-").first ?? "Simulator"
            return SimulatorRuntime(
                identifier: identifier,
                name: "\(os) \(version) Simulator",
                path: runtime["path"] as? String ?? "",
                bytes: (runtime["sizeBytes"] as? NSNumber)?.int64Value ?? 0,
                lastUsed: (runtime["lastUsedAt"] as? String).flatMap(dates.date(from:))
            )
        }
    }

    private func scanSimulators() async -> [CleanupCategory] {
        guard let simctl = await simctlURL() else { return [] }
        var rows: [CleanupCategory] = []
        let now = Date()

        if let list = await run(simctl, ["runtime", "list", "-j"], timeoutSeconds: 30), list.status == 0 {
            for runtime in Self.oldSimulatorRuntimes(fromJSON: Data(list.output.utf8)) where runtime.bytes > 0 {
                let note = runtime.lastUsed.map { "Last used \(Int(now.timeIntervalSince($0) / 86_400)) days ago" }
                rows.append(CleanupCategory(
                    id: Self.simulatorRuntimePrefix + runtime.identifier,
                    name: runtime.name,
                    detail: "Older runtime; Xcode downloads it again if a project needs it",
                    path: (runtime.path as NSString).deletingLastPathComponent,
                    items: "1",
                    sizeBytes: runtime.bytes,
                    icon: "iphone",
                    isSelected: true,
                    note: note,
                    contents: [CleanupItem(name: (runtime.path as NSString).lastPathComponent, bytes: runtime.bytes)]
                ))
            }
        }

        // Simulators whose runtime is gone can never boot again.
        if let list = await run(simctl, ["list", "devices", "unavailable", "-j"], timeoutSeconds: 30), list.status == 0,
           let json = try? JSONSerialization.jsonObject(with: Data(list.output.utf8)) as? [String: Any],
           let devices = (json["devices"] as? [String: [[String: Any]]])?.values.flatMap({ $0 }), !devices.isEmpty {
            let contents = devices.map { device in
                CleanupItem(name: device["name"] as? String ?? "Simulator",
                            bytes: (device["dataPath"] as? String).map { ProjectArtifactScanner.measure(URL(fileURLWithPath: $0).deletingLastPathComponent()).bytes } ?? 0)
            }.sorted { $0.bytes > $1.bytes }
            let bytes = contents.reduce(0) { $0 + $1.bytes }
            rows.append(CleanupCategory(
                id: Self.unavailableSimulatorsID,
                name: "Unavailable Simulators",
                detail: "Simulators for runtimes that are no longer installed",
                path: "~/Library/Developer/CoreSimulator/Devices",
                items: Self.formatted(devices.count),
                sizeBytes: bytes,
                icon: "iphone.slash",
                isSelected: true,
                contents: contents
            ))
        }
        return rows
    }

    private func cleanSimulator(_ category: CleanupCategory, onProgress: @escaping (String) -> Void) async -> Int64 {
        guard let simctl = await simctlURL() else { return 0 }
        let arguments = category.id == Self.unavailableSimulatorsID
            ? ["delete", "unavailable"]
            : ["runtime", "delete", String(category.id.dropFirst(Self.simulatorRuntimePrefix.count))]
        onProgress("Removing \(category.name)")
        guard await run(simctl, arguments, timeoutSeconds: 300)?.status == 0 else {
            onProgress("Skipped \(category.name): a running simulator may be using it")
            return 0
        }
        return category.sizeBytes
    }

    // MARK: - Android emulators

    static let androidEmulatorPrefix = "avd:"

    /// Emulators Android Studio made: a "<name>.ini" pointer and the "<name>.avd" folder it names.
    // shortcut: ignores ANDROID_AVD_HOME, which an app opened from the Dock doesn't inherit anyway.
    static func androidEmulators(in avdHome: URL) -> [(name: String, ini: URL, folder: URL)] {
        let files = (try? FileManager.default.contentsOfDirectory(at: avdHome, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "ini" }.compactMap { ini in
            let name = ini.deletingPathExtension().lastPathComponent
            let lines = (try? String(contentsOf: ini, encoding: .utf8))?.components(separatedBy: .newlines) ?? []
            let folder = lines.first { $0.hasPrefix("path=") }.map { URL(fileURLWithPath: String($0.dropFirst(5))) }
                ?? avdHome.appendingPathComponent(name + ".avd")
            // Only ever an emulator folder; a path with ".." could point anywhere.
            guard folder.pathExtension == "avd", !folder.path.components(separatedBy: "/").contains("..") else { return nil }
            return (name, ini, folder)
        }
    }

    private static func emulatorProcess(_ name: String, in processes: [RunningProcess]) -> RunningProcess? {
        processes.first { process in
            process.arguments.contains("@" + name)
                || zip(process.arguments, process.arguments.dropFirst()).contains { $0 == "-avd" && $1 == name }
        }
    }

    /// One row per emulator, ticked like every other row; the detail says it holds installed apps.
    private func scanAndroidEmulators(processes: [RunningProcess]) -> [CleanupCategory] {
        #if APPSTORE
        return [] // the sandbox can't see whether an emulator is running
        #else
        return Self.androidEmulators(in: resolveURL(for: ".android/avd")).compactMap { emulator in
            let bytes = ProjectArtifactScanner.measure(emulator.folder).bytes
            guard bytes > 0 else { return nil }
            let running = Self.emulatorProcess(emulator.name, in: processes)
            return CleanupCategory(
                id: Self.androidEmulatorPrefix + emulator.name,
                name: emulator.name.replacingOccurrences(of: "_", with: " ") + " Emulator",
                detail: "Android emulator with the apps and data inside it; Android Studio can make a new one",
                path: Self.displayPath(emulator.folder.path),
                items: "1",
                sizeBytes: bytes,
                icon: "apps.iphone",
                isSelected: running == nil,
                note: running.map { _ in "Running now. Close it to remove this." },
                contents: [CleanupItem(name: emulator.folder.lastPathComponent, bytes: bytes), CleanupItem(name: emulator.ini.lastPathComponent)]
            )
        }
        #endif
    }

    private func cleanAndroidEmulator(_ category: CleanupCategory, onProgress: @escaping (String) -> Void) -> Int64 {
        let name = String(category.id.dropFirst(Self.androidEmulatorPrefix.count))
        guard let emulator = Self.androidEmulators(in: resolveURL(for: ".android/avd")).first(where: { $0.name == name }),
              let values = try? emulator.folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true, values.isSymbolicLink != true else { return 0 }
        if Self.emulatorProcess(name, in: RunningProcesses.snapshot()) != nil {
            onProgress("Skipped \(category.name): it is running")
            return 0
        }
        onProgress("Removing \(category.name)")
        let bytes = ProjectArtifactScanner.measure(emulator.folder).bytes
        guard (try? fileManager.removeItem(at: emulator.folder)) != nil else { return 0 }
        try? fileManager.removeItem(at: emulator.ini)
        return bytes
    }

    // MARK: - Docker Integration

    private var dockerExecutableURL: URL? {
        #if APPSTORE
        return nil
        #else
        let candidates = [
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "/usr/bin/docker",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".docker/bin/docker").path
        ]
        if let found = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: found)
        }
        return nil
        #endif
    }

    private func runDockerCommand(arguments: [String], timeoutSeconds: Double = 3.0) async -> String? {
        guard let executableURL = dockerExecutableURL else { return nil }
        return await run(executableURL, arguments, timeoutSeconds: timeoutSeconds)?.output
    }

    /// Runs a tool and returns its exit status and output, stopping it after the timeout.
    private func run(_ executable: URL, _ arguments: [String], timeoutSeconds: Double) async -> (status: Int32, output: String)? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = executable
                process.arguments = arguments
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                guard (try? process.run()) != nil else { return continuation.resume(returning: nil) }

                let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds, execute: timeout)
                // Read before waiting: a tool with more output than the pipe holds would never exit.
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                timeout.cancel()
                continuation.resume(returning: (process.terminationStatus, String(decoding: data, as: UTF8.self)))
            }
        }
    }

    func inspectDockerMetrics() async -> (bytes: Int64, count: Int, isAvailable: Bool)? {
        guard dockerExecutableURL != nil else { return nil }
        var rawOutput = await runDockerCommand(arguments: ["system", "df", "--format", "{{json .}}"])
        if rawOutput == nil {
            rawOutput = await runDockerCommand(arguments: ["system", "df", "--format", "json"])
        }
        guard let output = rawOutput else { return nil }

        var totalReclaimableBytes: Int64 = 0
        var totalReclaimableCount = 0

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            let type = (json["Type"] as? String) ?? ""
            if type == "Images" || type == "Build Cache" {
                if let reclRaw = json["Reclaimable"] as? String {
                    let sizePart = reclRaw.components(separatedBy: "(").first?.trimmingCharacters(in: .whitespaces) ?? ""
                    let bytes = parseByteString(sizePart)
                    totalReclaimableBytes += bytes
                }
                if let totalCountStr = json["TotalCount"] as? String, let count = Int(totalCountStr) {
                    totalReclaimableCount += count
                }
            }
        }

        if let danglingOutput = await runDockerCommand(arguments: ["images", "-f", "dangling=true", "-q"]) {
            let danglingCount = danglingOutput.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
            if danglingCount > 0 {
                totalReclaimableCount = max(totalReclaimableCount, danglingCount)
            }
        }

        guard totalReclaimableBytes > 0 || totalReclaimableCount > 0 else { return nil }
        return (totalReclaimableBytes, totalReclaimableCount, true)
    }

    func cleanDocker(onProgress: @escaping (String) -> Void) async -> Int64 {
        // "-a" so Clean frees what `docker system df` calls reclaimable, the size the row shows.
        onProgress("Removing Docker images no container uses…")
        _ = await runDockerCommand(arguments: ["image", "prune", "-a", "-f"], timeoutSeconds: 120.0)

        onProgress("Removing unused Docker build cache…")
        _ = await runDockerCommand(arguments: ["builder", "prune", "-a", "-f"], timeoutSeconds: 120.0)

        return 0
    }

    private func parseByteString(_ str: String) -> Int64 {
        let scanner = Scanner(string: str)
        guard let val = scanner.scanDouble() else { return 0 }
        let unit = str.replacingOccurrences(of: "\(val)", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        let multiplier: Double
        if unit.hasPrefix("T") { multiplier = 1024 * 1024 * 1024 * 1024 }
        else if unit.hasPrefix("G") { multiplier = 1024 * 1024 * 1024 }
        else if unit.hasPrefix("M") { multiplier = 1024 * 1024 }
        else if unit.hasPrefix("K") { multiplier = 1024 }
        else { multiplier = 1 }

        return Int64(val * multiplier)
    }
}
