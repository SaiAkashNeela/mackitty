import XCTest
@testable import MacKitty

/// End to end through NativeCleanerService: scan a code folder, clean the project
/// row, and check that only the rebuildable folder is gone.
final class ProjectCleanupTests: XCTestCase {
    private let fm = FileManager.default
    private var root: URL!
    private var outside: URL!
    private var savedRoots: [URL] = []

    override func setUpWithError() throws {
        savedRoots = ProjectFolders.roots
        root = fm.temporaryDirectory.appendingPathComponent("mackitty-clean-\(UUID().uuidString)")
        outside = fm.temporaryDirectory.appendingPathComponent("mackitty-outside-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        root = ProjectArtifactScanner.canonical(root)
        ProjectFolders.roots = [root]
    }

    override func tearDownWithError() throws {
        ProjectFolders.roots = savedRoots
        try? fm.removeItem(at: root)
        try? fm.removeItem(at: outside)
    }

    private func write(_ url: URL, bytes: Int = 600_000) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: bytes).write(to: url)
    }

    func testCleaningRemovesOnlyTheBuildOutput() async throws {
        let app = root.appendingPathComponent("app")
        try write(app.appendingPathComponent("package.json"), bytes: 10)
        try write(app.appendingPathComponent("src/index.js"), bytes: 10)
        try write(app.appendingPathComponent("node_modules/a/index.js"))
        try write(app.appendingPathComponent("node_modules/b/index.js"))

        let cleaner = NativeCleanerService()
        let row = try XCTUnwrap(cleaner.scanProjects(processes: []).first)
        XCTAssertEqual(row.name, "app · node_modules")
        XCTAssertTrue(row.isSelected, "every project starts ticked; the note explains the risk")
        XCTAssertEqual(row.note, "Worked on today")

        let freed = await cleaner.cleanCategory(row) { _ in }

        XCTAssertEqual(freed, 1_200_000)
        XCTAssertFalse(fm.fileExists(atPath: app.appendingPathComponent("node_modules").path))
        XCTAssertTrue(fm.fileExists(atPath: app.appendingPathComponent("package.json").path))
        XCTAssertTrue(fm.fileExists(atPath: app.appendingPathComponent("src/index.js").path))
    }

    func testFolderSwappedForASymlinkAfterTheScanIsNotFollowed() async throws {
        let app = root.appendingPathComponent("app")
        try write(app.appendingPathComponent("package.json"), bytes: 10)
        try write(app.appendingPathComponent("node_modules/a/index.js"), bytes: 1_100_000)
        let precious = outside.appendingPathComponent("keep/me.txt")
        try write(precious)

        let cleaner = NativeCleanerService()
        let row = try XCTUnwrap(cleaner.scanProjects(processes: []).first)
        try fm.removeItem(at: app.appendingPathComponent("node_modules"))
        try fm.createSymbolicLink(at: app.appendingPathComponent("node_modules"), withDestinationURL: outside.appendingPathComponent("keep"))

        let freed = await cleaner.cleanCategory(row) { _ in }

        XCTAssertEqual(freed, 0)
        XCTAssertTrue(fm.fileExists(atPath: precious.path))
    }

    func testFolderOutsideTheCodeFoldersIsNeverCleaned() async throws {
        let app = root.appendingPathComponent("app")
        try write(app.appendingPathComponent("package.json"), bytes: 10)
        try write(app.appendingPathComponent("node_modules/a/index.js"), bytes: 1_100_000)

        let cleaner = NativeCleanerService()
        let row = try XCTUnwrap(cleaner.scanProjects(processes: []).first)
        ProjectFolders.roots = [outside] // the user removed this code folder before cleaning

        let freed = await cleaner.cleanCategory(row) { _ in }

        XCTAssertEqual(freed, 0)
        XCTAssertTrue(fm.fileExists(atPath: app.appendingPathComponent("node_modules/a/index.js").path))
    }
}
