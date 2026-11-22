import AppKit
import Darwin

/// One app, or one command-line tool in one folder, and the memory its processes use.
struct MemoryUser: Identifiable {
    let id: String
    let name: String
    let bytes: UInt64
    /// The app to quit; nil for command-line tools such as a dev server.
    let appURL: URL?
    /// Where a command-line tool runs, e.g. the project a dev server serves.
    let folder: String?
    /// Part of macOS: shown for context, never stopped.
    let isSystem: Bool

    var sizeText: String { ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory) }
}

/// Why the Mac feels slow right now: memory pressure, swap and who uses the memory.
struct MemoryReport {
    enum Pressure { case normal, warning, critical }

    var pressure: Pressure
    var swapUsed: UInt64
    var swapTotal: UInt64
    var uptime: TimeInterval
    var users: [MemoryUser]

    /// Swap more than half full: the Mac is short of memory and stalls while paging.
    var swapIsHigh: Bool { swapTotal > 0 && swapUsed * 2 > swapTotal }

    static func current() -> MemoryReport {
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)
        var swap = xsw_usage()
        size = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &swap, &size, nil, 0)

        return MemoryReport(
            pressure: level >= 4 ? .critical : (level == 2 ? .warning : .normal),
            swapUsed: swap.xsu_used,
            swapTotal: swap.xsu_total,
            uptime: ProcessInfo.processInfo.systemUptime,
            users: Array(group(RunningProcesses.snapshot()).prefix(10))
        )
    }

    /// Helpers count toward the app they ship in (Edge's renderers, Firefox's
    /// plugin-container); tools are split by folder so each dev server is its own row.
    static func group(_ processes: [RunningProcess]) -> [MemoryUser] {
        let ownApp = Bundle.main.bundleURL.path
        var groups: [String: [RunningProcess]] = [:]
        for process in processes where process.footprint > 0 {
            groups[key(for: process), default: []].append(process)
        }

        return groups.compactMap { key, members in
            let first = members[0]
            let appPath = outermostApp(first.executablePath)
            if appPath == ownApp { return nil }
            let path = appPath ?? first.executablePath
            return MemoryUser(
                id: key,
                name: appPath.map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension }
                    ?? friendlyNames[first.name] ?? first.name,
                bytes: members.reduce(0) { $0 + $1.footprint },
                appURL: appPath.map { URL(fileURLWithPath: $0) },
                folder: appPath == nil ? first.workingDirectory.map(displayPath) : nil,
                isSystem: path.hasPrefix("/System/") || path.hasPrefix("/usr/") || path.hasPrefix("/Library/Apple/")
            )
        }
        .sorted { $0.bytes > $1.bytes }
    }

    /// macOS process names that don't say what they are.
    private static let friendlyNames = [
        "com.apple.Virtualization.VirtualMachine": "Virtual machine (Docker or a VM app; quit that app)"
    ]

    static func key(for process: RunningProcess) -> String {
        outermostApp(process.executablePath) ?? process.executablePath + "|" + (process.workingDirectory ?? "")
    }

    /// "/Applications/Edge.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper" → "/Applications/Edge.app"
    private static func outermostApp(_ path: String) -> String? {
        guard let range = path.range(of: ".app/") else { return nil }
        return String(path[..<range.lowerBound]) + ".app"
    }

    private static func displayPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}
