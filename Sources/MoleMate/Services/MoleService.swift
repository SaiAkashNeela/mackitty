import Foundation

struct MoleCommandResult {
    let output: String
    let exitCode: Int32
}

private final class OutputAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    var string: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

enum MoleServiceError: LocalizedError {
    case executableNotFound
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            "Mole is not installed or could not be found on PATH."
        case let .commandFailed(output):
            output.isEmpty ? "Mole could not complete the operation." : output
        }
    }
}

final class MoleService {
    private let fileManager = FileManager.default
    private let processLock = NSLock()
    private var runningProcess: Process?

    private var executableURL: URL? {
        #if APPSTORE
        // Sandboxed builds can't launch external tools; the native engine is used instead.
        return nil
        #else
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["MOLE_PATH"], Self.isSafeExecutable(atPath: override) {
            return URL(fileURLWithPath: override)
        }
        #endif

        // Only Homebrew's standard prefixes. Shared or PATH-relative locations
        // could let another account plant a binary that runs as this user.
        let candidates = ["/opt/homebrew/bin/mo", "/usr/local/bin/mo"]
        return candidates.first(where: Self.isSafeExecutable(atPath:)).map { URL(fileURLWithPath: $0) }
        #endif
    }

    var isAvailable: Bool { executableURL != nil }

    /// The binary (after resolving symlinks) and its folder must be owned by this
    /// user or root and must not be writable by group or others.
    private static func isSafeExecutable(atPath path: String) -> Bool {
        let fm = FileManager.default
        let resolved = (path as NSString).resolvingSymlinksInPath
        guard fm.isExecutableFile(atPath: resolved) else { return false }
        for candidate in [resolved, (resolved as NSString).deletingLastPathComponent] {
            guard let attrs = try? fm.attributesOfItem(atPath: candidate),
                  let owner = (attrs[.ownerAccountID] as? NSNumber)?.uint32Value,
                  let perms = (attrs[.posixPermissions] as? NSNumber)?.uint16Value else { return false }
            if owner != getuid() && owner != 0 { return false }
            if perms & 0o022 != 0 { return false }
        }
        return true
    }

    func cancelCurrentOperation() {
        processLock.lock()
        let process = runningProcess
        processLock.unlock()
        process?.terminate()
    }

    func previewCleanup(onOutput: @escaping (String) -> Void) async throws -> MoleCommandResult {
        try await run(arguments: ["clean", "--dry-run"], onOutput: onOutput)
    }

    func clean(onOutput: @escaping (String) -> Void = { _ in }) async throws -> MoleCommandResult {
        try await run(arguments: ["clean"], onOutput: onOutput)
    }

    func version() async throws -> MoleCommandResult {
        try await run(arguments: ["--version"], onOutput: { _ in })
    }

    private func run(arguments: [String], onOutput: @escaping (String) -> Void) async throws -> MoleCommandResult {
        guard let executableURL else { throw MoleServiceError.executableNotFound }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            let output = OutputAccumulator()
            process.executableURL = executableURL
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = pipe
            process.standardError = pipe
            process.environment = (ProcessInfo.processInfo.environment).merging(["MO_NO_OPLOG": "1"]) { _, new in new }

            self.processLock.lock()
            self.runningProcess = process
            self.processLock.unlock()

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                output.append(chunk)
                if let text = String(data: chunk, encoding: .utf8) {
                    onOutput(text)
                }
            }

            process.terminationHandler = { process in
                pipe.fileHandleForReading.readabilityHandler = nil
                self.processLock.lock()
                self.runningProcess = nil
                self.processLock.unlock()
                let result = MoleCommandResult(output: output.string, exitCode: process.terminationStatus)
                if process.terminationStatus == 0 {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: MoleServiceError.commandFailed(output.string))
                }
            }

            do {
                try process.run()
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                self.processLock.lock()
                self.runningProcess = nil
                self.processLock.unlock()
                continuation.resume(throwing: error)
            }
        }
    }
}
