import Darwin
import Foundation

/// One of the current user's processes, used to avoid deleting folders a tool is using right now.
struct RunningProcess {
    let pid: pid_t
    let executablePath: String
    let workingDirectory: String?
    let arguments: [String]
    /// Memory the process costs the Mac (Activity Monitor's "Memory" column).
    let footprint: UInt64

    var name: String { (executablePath as NSString).lastPathComponent }
}

enum RunningProcesses {
    /// The current user's processes. Empty in the App Store sandbox, which cannot inspect them.
    static func snapshot() -> [RunningProcess] {
        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(capacity) + 64)
        let found = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard found > 0 else { return [] }
        let uid = getuid()

        return pids.prefix(Int(found)).compactMap { pid in
            guard pid > 0 else { return nil }
            var info = proc_bsdshortinfo()
            let infoSize = Int32(MemoryLayout<proc_bsdshortinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &info, infoSize) == infoSize,
                  info.pbsi_uid == uid else { return nil }
            var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
            guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return nil }
            return RunningProcess(
                pid: pid,
                executablePath: String(cString: path),
                workingDirectory: workingDirectory(of: pid),
                arguments: arguments(of: pid),
                footprint: footprint(of: pid)
            )
        }
    }

    private static func workingDirectory(of pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return path.isEmpty ? nil : path
    }

    private static func footprint(of pid: pid_t) -> UInt64 {
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        return result == 0 ? usage.ri_phys_footprint : 0
    }

    /// KERN_PROCARGS2 layout: argc, the executable path, NUL padding, then argc strings.
    private static func arguments(of pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return [] }

        let argc = buffer.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        var index = MemoryLayout<Int32>.size
        while index < size, buffer[index] != 0 { index += 1 }
        while index < size, buffer[index] == 0 { index += 1 }
        var arguments: [String] = []
        while arguments.count < argc, index < size {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            arguments.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return arguments
    }
}

extension Array where Element == RunningProcess {
    /// A process whose executable lives inside `directory` (e.g. a uv tool running from its cache).
    func runningFrom(_ directory: String) -> RunningProcess? {
        let prefix = directory.hasSuffix("/") ? directory : directory + "/"
        return first { $0.executablePath.hasPrefix(prefix) }
    }

    /// A process whose working directory is `directory` or inside it (e.g. a dev server).
    func workingIn(_ directory: String) -> RunningProcess? {
        let prefix = directory.hasSuffix("/") ? directory : directory + "/"
        return first { process in process.workingDirectory.map { ($0 + "/").hasPrefix(prefix) } ?? false }
    }
}
