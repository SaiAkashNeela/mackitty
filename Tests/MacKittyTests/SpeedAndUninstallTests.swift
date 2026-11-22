import XCTest
@testable import MacKitty

final class SimulatorRuntimeTests: XCTestCase {
    func testKeepsTheNewestRuntimePerPlatform() throws {
        func runtime(_ id: String, _ os: String, _ version: String, platform: String, deletable: Bool = true) -> [String: Any] {
            ["identifier": id, "version": version, "platformIdentifier": platform, "deletable": deletable, "sizeBytes": 1000,
             "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.\(os)-\(version.replacingOccurrences(of: ".", with: "-"))",
             "lastUsedAt": "2026-11-01T10:00:00Z"]
        }
        let ios = "com.apple.platform.iphonesimulator"
        let json = try JSONSerialization.data(withJSONObject: [
            "a": runtime("a", "iOS", "26.5", platform: ios),
            "b": runtime("b", "iOS", "18.6", platform: ios),
            "c": runtime("c", "iOS", "9.3", platform: ios), // numeric compare: 9.3 is older than 18.6
            "d": runtime("d", "iOS", "17.0", platform: ios, deletable: false),
            "e": runtime("e", "watchOS", "11.5", platform: "com.apple.platform.watchsimulator")
        ])

        let old = NativeCleanerService.oldSimulatorRuntimes(fromJSON: json).sorted { $0.identifier < $1.identifier }

        XCTAssertEqual(old.map(\.identifier), ["b", "c"])
        XCTAssertEqual(old.first?.name, "iOS 18.6 Simulator")
        XCTAssertNotNil(old.first?.lastUsed)
    }
}

final class NewCleanupRowsTests: XCTestCase {
    private let fm = FileManager.default
    private var root: URL!

    override func setUpWithError() throws {
        root = ProjectArtifactScanner.canonical(fm.temporaryDirectory.appendingPathComponent("mackitty-rows-\(UUID().uuidString)"))
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
    }

    func testFindsEmulatorsButNeverAFolderOutsideAnAvd() throws {
        try "path=\(root.path)/Pixel_7.avd\n".write(to: root.appendingPathComponent("Pixel_7.ini"), atomically: true, encoding: .utf8)
        try "target=android-34\n".write(to: root.appendingPathComponent("Tablet.ini"), atomically: true, encoding: .utf8) // no path line
        try "path=/Users/me/Documents\n".write(to: root.appendingPathComponent("Bad.ini"), atomically: true, encoding: .utf8)
        try "path=\(root.path)/../x.avd\n".write(to: root.appendingPathComponent("Sneaky.ini"), atomically: true, encoding: .utf8)

        let found = NativeCleanerService.androidEmulators(in: root).sorted { $0.name < $1.name }

        XCTAssertEqual(found.map(\.name), ["Pixel_7", "Tablet"])
        XCTAssertEqual(found.map(\.folder.lastPathComponent), ["Pixel_7.avd", "Tablet.avd"])
    }

    func testExpoKeepsLoginAndSigningFiles() throws {
        for name in ["expo-go", "state.json", "codesigning"] {
            try Data().write(to: root.appendingPathComponent(name))
        }
        let spec = NativeCleanerService.TargetSpec(id: "expo-cache", name: "Expo", detail: "", relativePath: ".expo",
                                                   icon: "", onlySubpaths: ["expo-go"])

        let protected = NativeCleanerService().protectedNames(in: root, for: spec)

        XCTAssertEqual(protected, ["state.json", "codesigning"])
    }
}

final class MemoryReportTests: XCTestCase {
    private func process(_ pid: pid_t, _ path: String, cwd: String? = nil, footprint: UInt64) -> RunningProcess {
        RunningProcess(pid: pid, executablePath: path, workingDirectory: cwd, arguments: [], footprint: footprint)
    }

    func testHelpersCountTowardTheirAppAndToolsSplitByFolder() {
        let users = MemoryReport.group([
            process(1, "/Applications/Edge.app/Contents/MacOS/Edge", footprint: 100),
            process(2, "/Applications/Edge.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper (Renderer)", footprint: 900),
            process(3, "/opt/homebrew/bin/node", cwd: "/tmp/web", footprint: 300),
            process(4, "/opt/homebrew/bin/node", cwd: "/tmp/api", footprint: 200),
            process(5, "/System/Library/Frameworks/WebKit.framework/XPCServices/WebContent", footprint: 50)
        ])

        XCTAssertEqual(users.map(\.name), ["Edge", "node", "node", "WebContent"])
        XCTAssertEqual(users[0].bytes, 1000)
        XCTAssertEqual(users[0].appURL?.path, "/Applications/Edge.app")
        XCTAssertEqual(users[1].folder, "/tmp/web")
        XCTAssertNil(users[1].appURL)
        XCTAssertTrue(users[3].isSystem)
        XCTAssertFalse(users[0].isSystem)
    }
}

final class AppLeftoversTests: XCTestCase {
    private let fm = FileManager.default
    private var root: URL!

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("mackitty-leftovers-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        root = ProjectArtifactScanner.canonical(root)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
    }

    private func app(_ bundleID: String, name: String) throws -> URL {
        let app = root.appendingPathComponent("Applications/\(name).app")
        try fm.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try (["CFBundleIdentifier": bundleID] as NSDictionary).write(to: app.appendingPathComponent("Contents/Info.plist"))
        return app
    }

    private func touch(_ path: String, plist: [String: Any]? = nil) throws {
        let url = root.appendingPathComponent(path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let plist { try (plist as NSDictionary).write(to: url) } else { try Data(count: 10).write(to: url) }
    }

    func testFindsOnlyThisAppsFiles() throws {
        let vpn = try app("com.example.vpn", name: "Example VPN")
        try touch("home/Library/Application Support/com.example.vpn/state.db")
        try touch("home/Library/Application Support/Example VPN/x")
        try touch("home/Library/Preferences/com.example.vpn.plist")
        try touch("home/Library/LaunchAgents/com.other.agent.plist",
                  plist: ["ProgramArguments": [vpn.path + "/Contents/MacOS/agent"]]) // runs from inside the app
        try touch("system/LaunchDaemons/com.example.vpn.helper.plist",
                  plist: ["Program": root.path + "/system/PrivilegedHelperTools/com.example.vpn.helper"])
        try touch("system/PrivilegedHelperTools/com.example.vpn.helper")
        // Not this app's:
        try touch("home/Library/Application Support/com.example.vpnplus/x")
        try touch("home/Library/Application Support/Example/x")
        try touch("system/LaunchDaemons/com.other.daemon.plist",
                  plist: ["Program": vpn.path + "/../Other.app/Contents/MacOS/other"])

        let found = AppLeftovers.find(for: vpn, home: root.appendingPathComponent("home"), systemLibrary: root.appendingPathComponent("system"))
        let relative = { (urls: [URL]) in urls.map { String($0.path.dropFirst(self.root.path.count + 1)) }.sorted() }

        XCTAssertEqual(relative(found.userItems), [
            "home/Library/Application Support/Example VPN",
            "home/Library/Application Support/com.example.vpn",
            "home/Library/LaunchAgents/com.other.agent.plist",
            "home/Library/Preferences/com.example.vpn.plist"
        ])
        XCTAssertEqual(relative(found.systemItems), [
            "system/LaunchDaemons/com.example.vpn.helper.plist",
            "system/PrivilegedHelperTools/com.example.vpn.helper"
        ])
        XCTAssertGreaterThan(found.bytes, 0)
    }

    func testApplesAppsGetNothing() throws {
        let notes = try app("com.apple.Notes", name: "Notes")
        try touch("home/Library/Application Support/Notes/x")
        XCTAssertTrue(AppLeftovers.find(for: notes, home: root.appendingPathComponent("home")).isEmpty)
    }
}
