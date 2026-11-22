import Foundation

/// The code folders the user asked MacKitty to look through.
enum ProjectFolders {
    private static let key = "project-roots"

    static var roots: [URL] {
        get { (UserDefaults.standard.stringArray(forKey: key) ?? []).map { URL(fileURLWithPath: $0, isDirectory: true) } }
        set { UserDefaults.standard.set(newValue.map(\.path), forKey: key) }
    }
}

/// One project inside a code folder and the rebuildable output found in it.
struct ProjectArtifacts {
    let project: URL
    var folders: [URL] = []
    var kindByFolder: [URL: String] = [:]
    var bytes: Int64 = 0
    var bytesByFolder: [URL: Int64] = [:]
    var fileCount = 0
    /// Shipped builds (APK, IPA…) that must not disappear with the build folder.
    var releaseFiles: [String] = []
    var trackedFolderCount = 0

    /// Kinds of the folders that will be cleaned, in discovery order.
    var kinds: [String] {
        folders.compactMap { kindByFolder[$0] }.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }
}

/// Finds folders that a build or package install recreates: dependency folders
/// and compiler output. Each kind is recognised by the file that produces it, so
/// a folder that merely has a familiar name is never picked up.
enum ProjectArtifactScanner {
    private static let fileManager = FileManager.default
    private static let releaseExtensions: Set<String> = ["apk", "aab", "ipa", "dmg", "pkg"]
    private static let jsCaches: Set<String> = [".next", ".nuxt", ".svelte-kit", ".turbo", ".parcel-cache", ".angular"]

    /// The kind of rebuildable folder this is, or nil to leave it alone.
    static func artifactKind(name: String, in directory: URL, siblings: Set<String>) -> String? {
        switch name {
        case "node_modules":
            return "node_modules"
        case "target" where fileManager.fileExists(atPath: directory.appendingPathComponent("target/CACHEDIR.TAG").path):
            return "Rust target"
        case "build" where siblings.contains("build.gradle") || siblings.contains("build.gradle.kts"):
            return "Gradle build"
        case ".gradle" where siblings.contains("gradlew") || siblings.contains("settings.gradle") || siblings.contains("settings.gradle.kts"):
            return "Gradle cache"
        case "build" where siblings.contains("pubspec.yaml"), ".dart_tool" where siblings.contains("pubspec.yaml"):
            return "Flutter build"
        case ".build" where siblings.contains("Package.swift"):
            return "Swift build"
        case "Pods" where siblings.contains("Podfile.lock"):
            return "CocoaPods"
        case _ where jsCaches.contains(name) && siblings.contains("package.json"):
            return "\(name) cache"
        case "dist" where siblings.contains("package.json"), "out" where siblings.contains("package.json"):
            return "\(name) output"
        case ".playwright-mcp":
            return "Playwright output"
        case ".playwright" where siblings.contains("package.json"):
            return "Playwright output"
        case "test-results", "playwright-report":
            return siblings.contains { $0.hasPrefix("playwright.config.") } ? "Playwright output" : nil
        case ".venv", "venv":
            let isVenv = fileManager.fileExists(atPath: directory.appendingPathComponent("\(name)/pyvenv.cfg").path)
            let hasDependencyList = ["pyproject.toml", "requirements.txt", "uv.lock", "setup.py"].contains(where: siblings.contains)
            return isVenv && hasDependencyList ? "Python venv" : nil
        case "__pycache__":
            return "Python cache"
        case ".pytest_cache" where fileManager.fileExists(atPath: directory.appendingPathComponent(".pytest_cache/CACHEDIR.TAG").path),
             ".mypy_cache" where fileManager.fileExists(atPath: directory.appendingPathComponent(".mypy_cache/CACHEDIR.TAG").path),
             ".ruff_cache" where fileManager.fileExists(atPath: directory.appendingPathComponent(".ruff_cache/CACHEDIR.TAG").path):
            return "Python cache"
        case ".hypothesis":
            return "Python cache"
        case ".tox" where ["tox.ini", "pyproject.toml", "setup.cfg"].contains(where: siblings.contains),
             ".nox" where siblings.contains("noxfile.py"):
            return "Python test environments"
        case "build" where siblings.contains("setup.py"), ".eggs" where siblings.contains("setup.py"):
            return "Python build"
        case _ where name.hasSuffix(".egg-info") && (siblings.contains("setup.py") || siblings.contains("pyproject.toml")):
            return "Python build"
        default:
            return nil
        }
    }

    /// Rebuildable folders under `root`, outermost only. Symlinks, app bundles and
    /// other hidden folders (.git, virtualenvs…) are never entered.
    static func findArtifacts(in root: URL, maxDepth: Int = 8) -> [(url: URL, kind: String)] {
        var found: [(url: URL, kind: String)] = []
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]

        func walk(_ directory: URL, depth: Int) {
            guard depth <= maxDepth,
                  let entries = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys)) else { return }
            let siblings = Set(entries.map(\.lastPathComponent))
            for entry in entries {
                guard let values = try? entry.resourceValues(forKeys: keys),
                      values.isDirectory == true, values.isSymbolicLink != true, values.isPackage != true else { continue }
                let name = entry.lastPathComponent
                if let kind = artifactKind(name: name, in: directory, siblings: siblings) {
                    found.append((entry, kind))
                } else if !name.hasPrefix(".") {
                    walk(entry, depth: depth + 1)
                }
            }
        }
        walk(root, depth: 0)
        return found
    }

    /// The project an artifact belongs to: the nearest git repository, otherwise
    /// the top-level folder under the code folder that contains it.
    static func project(for artifact: URL, in root: URL) -> URL {
        let rootPath = root.standardizedFileURL.path
        var directory = artifact.deletingLastPathComponent().standardizedFileURL
        while directory.path.count > rootPath.count {
            if fileManager.fileExists(atPath: directory.appendingPathComponent(".git").path) { return directory }
            directory.deleteLastPathComponent()
        }
        if fileManager.fileExists(atPath: root.appendingPathComponent(".git").path) { return root }
        let relative = artifact.standardizedFileURL.path.dropFirst(rootPath.count + 1)
        guard let first = relative.split(separator: "/").first, relative.contains("/") else { return root }
        return root.appendingPathComponent(String(first), isDirectory: true)
    }

    /// Folders that contain git-tracked files. Those are not build output and are never cleaned.
    static func trackedFolders(_ folders: [URL], in repository: URL, git: URL) -> Set<URL> {
        let repoPath = repository.standardizedFileURL.path
        let relative = folders.map { String($0.standardizedFileURL.path.dropFirst(repoPath.count + 1)) }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = git
        process.arguments = ["-C", repoPath, "ls-files", "-z", "--"] + relative
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return Set(folders) } // can't verify, so treat as tracked
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return Set(folders) }

        let tracked = String(decoding: output, as: UTF8.self).split(separator: "\0")
        return Set(zip(folders, relative).filter { _, path in tracked.contains { $0.hasPrefix(path + "/") } }.map(\.0))
    }

    /// Size, file count and any shipped builds inside a folder.
    /// Uses fts(3) like `du`: node_modules trees hold hundreds of thousands of files
    /// and FileManager's per-file URL objects made this 5x slower. Never follows
    /// symlinks or crosses onto another volume.
    static func measure(_ folder: URL) -> (bytes: Int64, files: Int, releaseFiles: [String]) {
        var bytes: Int64 = 0
        var files = 0
        var releaseFiles: [String] = []
        guard let path = strdup(folder.path) else { return (0, 0, []) }
        defer { free(path) }
        var paths: [UnsafeMutablePointer<CChar>?] = [path, nil]
        guard let fts = fts_open(&paths, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { return (0, 0, []) }
        defer { fts_close(fts) }

        let nameOffset = MemoryLayout<FTSENT>.offset(of: \FTSENT.fts_name)!
        while let entry = fts_read(fts) {
            guard entry.pointee.fts_info == FTS_F, let stat = entry.pointee.fts_statp else { continue }
            bytes += Int64(stat.pointee.st_size)
            files += 1
            // Every release extension is ".xxx": test the raw name bytes before building a String.
            let length = Int(entry.pointee.fts_namelen)
            let name = (UnsafeRawPointer(entry) + nameOffset).assumingMemoryBound(to: CChar.self)
            if length > 4, name[length - 4] == 0x2E {
                let candidate = String(cString: name)
                if releaseExtensions.contains((candidate as NSString).pathExtension.lowercased()) {
                    releaseFiles.append(candidate)
                }
            }
        }
        return (bytes, files, releaseFiles)
    }

    /// When the project was last worked on: the latest git activity, or the folder itself.
    static func lastActivity(of project: URL) -> Date {
        [".git/index", ".git/logs/HEAD", ".git", ""]
            .compactMap { try? fileManager.attributesOfItem(atPath: project.appendingPathComponent($0).path)[.modificationDate] as? Date }
            .max() ?? .distantPast
    }

    /// The path as the file system spells found entries (/private/var, not /var), so
    /// found folders and their code folder always share a prefix.
    static func canonical(_ url: URL) -> URL {
        guard let resolved = realpath(url.path, nil) else { return url.standardizedFileURL }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
    }

    /// A git that won't trigger the "install developer tools" dialog when missing.
    static let gitExecutable: URL? = [
        "/opt/homebrew/bin/git",
        "/usr/local/bin/git",
        "/Library/Developer/CommandLineTools/usr/bin/git",
        "/Applications/Xcode.app/Contents/Developer/usr/bin/git"
    ].first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map { URL(fileURLWithPath: $0) }

    /// Every project with rebuildable output under the code folders, with git-tracked folders removed.
    static func scan(roots: [URL], onProgress: (String) -> Void = { _ in }) -> [ProjectArtifacts] {
        var projects: [URL: ProjectArtifacts] = [:]
        for root in roots.map(canonical) {
            onProgress(root.path)
            for (folder, kind) in findArtifacts(in: root) {
                let project = project(for: folder, in: root)
                projects[project, default: ProjectArtifacts(project: project)].folders.append(folder)
                projects[project]?.kindByFolder[folder] = kind
            }
        }

        return projects.values.compactMap { entry in
            var entry = entry
            onProgress(entry.project.path)
            if fileManager.fileExists(atPath: entry.project.appendingPathComponent(".git").path) {
                guard let git = gitExecutable else { return nil } // can't prove the folders are untracked
                let tracked = trackedFolders(entry.folders, in: entry.project, git: git)
                entry.trackedFolderCount = tracked.count
                entry.folders.removeAll { tracked.contains($0) }
            }
            for folder in entry.folders {
                let metrics = measure(folder)
                entry.bytes += metrics.bytes
                entry.bytesByFolder[folder] = metrics.bytes
                entry.fileCount += metrics.files
                entry.releaseFiles += metrics.releaseFiles
            }
            return entry.folders.isEmpty ? nil : entry
        }
    }
}
