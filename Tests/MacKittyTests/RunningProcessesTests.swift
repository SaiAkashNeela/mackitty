import XCTest
@testable import MacKitty

final class RunningProcessesTests: XCTestCase {
    func testSnapshotSeesThisProcessWithItsFolderAndArguments() throws {
        let me = try XCTUnwrap(RunningProcesses.snapshot().first { $0.pid == getpid() })
        let cwd = ProjectArtifactScanner.canonical(URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).path

        XCTAssertEqual(me.executablePath, ProjectArtifactScanner.canonical(Bundle.main.executableURL!).path)
        XCTAssertEqual(me.workingDirectory, cwd)
        XCTAssertEqual(me.arguments.count, CommandLine.arguments.count)
        XCTAssertEqual([me].workingIn(cwd)?.pid, getpid())
        XCTAssertNil([me].workingIn(cwd + "-elsewhere"))
    }

    /// The uv case: a tool executing from inside a cache must mark that cache busy.
    func testDetectsAProgramRunningFromInsideAFolder() throws {
        let folder = ProjectArtifactScanner.canonical(FileManager.default.temporaryDirectory)
            .appendingPathComponent("mackitty-busy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let tool = folder.appendingPathComponent("tool")
        try FileManager.default.copyItem(atPath: "/bin/sleep", toPath: tool.path)

        let process = Process()
        process.executableURL = tool
        process.arguments = ["30"]
        try process.run()
        defer { process.terminate() }

        let busy = RunningProcesses.snapshot().runningFrom(folder.path)
        XCTAssertEqual(busy?.pid, process.processIdentifier)
        XCTAssertNil(RunningProcesses.snapshot().runningFrom(folder.path + "-other"))
    }
}
