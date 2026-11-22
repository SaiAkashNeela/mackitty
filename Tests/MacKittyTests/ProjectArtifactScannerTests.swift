import XCTest
@testable import MacKitty

/// Builds a fake code folder on disk and checks that only rebuildable output is
/// offered for cleaning, and nothing git-tracked, linked or merely similarly named.
final class ProjectArtifactScannerTests: XCTestCase {
    private var root: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("mackitty-tests-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        root = ProjectArtifactScanner.canonical(root)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
    }

    private func write(_ relativePath: String, _ contents: String = "x") throws {
        let url = root.appendingPathComponent(relativePath)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func git(_ arguments: String..., in directory: URL) throws {
        let process = Process()
        process.executableURL = try XCTUnwrap(ProjectArtifactScanner.gitExecutable)
        process.arguments = ["-C", directory.path] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "git \(arguments.joined(separator: " "))")
    }

    private func names(_ found: [(url: URL, kind: String)]) -> [String] {
        found.map { String($0.url.path.dropFirst(root.path.count + 1)) }.sorted()
    }

    func testFindsOnlyFoldersItsBuildToolRecreates() throws {
        try write("web/package.json")
        try write("web/node_modules/react/index.js")
        try write("web/node_modules/react/node_modules/nested/index.js") // nested: parent is enough
        try write("web/.next/cache/x")
        try write("rust/Cargo.toml")
        try write("rust/target/CACHEDIR.TAG")
        try write("rust/target/debug/app")
        try write("app/android/app/build.gradle")
        try write("app/android/app/build/outputs/apk/debug/app-debug.apk")
        try write("app/android/gradlew")
        try write("app/android/.gradle/8.0/x")
        try write("web/dist/main.js")
        try write("web/.playwright-mcp/console.log")
        try write("e2e/playwright.config.ts")
        try write("e2e/test-results/trace.zip")
        // Same names, but nothing that produces them: must be left alone.
        try write("docs/build/index.html")
        try write("docs/target/notes.md")
        try write("docs/.next/x")
        try write("docs/dist/x")
        try write("docs/out/x")
        try write("docs/test-results/x")
        try write("web/.git/config") // hidden folders are never entered

        let found = ProjectArtifactScanner.findArtifacts(in: root)

        XCTAssertEqual(names(found), [
            "app/android/.gradle",
            "app/android/app/build",
            "e2e/test-results",
            "rust/target",
            "web/.next",
            "web/.playwright-mcp",
            "web/dist",
            "web/node_modules"
        ])
    }

    func testFindsPythonEnvironmentsAndCaches() throws {
        try write("api/pyproject.toml")
        try write("api/.venv/pyvenv.cfg")
        try write("api/.venv/lib/site.py")
        try write("api/src/__pycache__/main.cpython-312.pyc")
        try write("api/.pytest_cache/CACHEDIR.TAG")
        try write("api/.ruff_cache/CACHEDIR.TAG")
        try write("api/.tox/py312/x")
        try write("api/.hypothesis/examples/x")
        try write("lib/setup.py")
        try write("lib/build/lib/pkg.py")
        try write("lib/pkg.egg-info/PKG-INFO")
        // A venv with no dependency list can't be recreated; a folder named venv isn't one.
        try write("scratch/.venv/pyvenv.cfg")
        try write("notes/requirements.txt")
        try write("notes/venv/readme.md")
        try write("notes/.mypy_cache/x")

        XCTAssertEqual(names(ProjectArtifactScanner.findArtifacts(in: root)), [
            "api/.hypothesis",
            "api/.pytest_cache",
            "api/.ruff_cache",
            "api/.tox",
            "api/.venv",
            "api/src/__pycache__",
            "lib/build",
            "lib/pkg.egg-info"
        ])
    }

    func testSkipsSymlinkedFolders() throws {
        let outside = fm.temporaryDirectory.appendingPathComponent("mackitty-outside-\(UUID().uuidString)")
        try fm.createDirectory(at: outside.appendingPathComponent("node_modules"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: outside) }
        try fm.createSymbolicLink(at: root.appendingPathComponent("linked"), withDestinationURL: outside)
        try fm.createSymbolicLink(at: root.appendingPathComponent("node_modules"), withDestinationURL: outside.appendingPathComponent("node_modules"))

        XCTAssertTrue(ProjectArtifactScanner.findArtifacts(in: root).isEmpty)
    }

    func testGroupsByGitRepositoryAndLeavesTrackedFoldersOut() throws {
        try write("shop/package.json")
        try write("shop/node_modules/lib/index.js")
        try write("shop/server/build.gradle")
        try write("shop/server/build/libs/server.jar") // committed on purpose
        try git("init", "-q", in: root.appendingPathComponent("shop"))
        try git("add", "-f", "package.json", "server/build.gradle", "server/build/libs/server.jar", in: root.appendingPathComponent("shop"))

        let projects = ProjectArtifactScanner.scan(roots: [root])

        XCTAssertEqual(projects.count, 1)
        let shop = try XCTUnwrap(projects.first)
        XCTAssertEqual(shop.project.lastPathComponent, "shop")
        XCTAssertEqual(shop.folders.map(\.lastPathComponent), ["node_modules"])
        XCTAssertEqual(shop.kinds, ["node_modules"])
        XCTAssertEqual(shop.trackedFolderCount, 1)
    }

    func testFlagsShippedBuildsInsideBuildOutput() throws {
        try write("game/android/app/build.gradle")
        try write("game/android/app/build/outputs/apk/release/app-release.apk", String(repeating: "a", count: 2048))

        let project = try XCTUnwrap(ProjectArtifactScanner.scan(roots: [root]).first)

        XCTAssertEqual(project.project.lastPathComponent, "game")
        XCTAssertEqual(project.releaseFiles, ["app-release.apk"])
        XCTAssertGreaterThanOrEqual(project.bytes, 2048)
    }
}
