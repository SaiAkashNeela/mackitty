import Foundation
import Combine

struct NotchTask: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var isDone: Bool
    let createdAt: Date

    init(title: String) {
        id = UUID()
        self.title = title
        isDone = false
        createdAt = Date()
    }
}

/// The task list behind the notch tray. Stays on this Mac in UserDefaults,
/// like cleanup history.
@MainActor
final class TaskStore: ObservableObject {
    /// What a "Clear" removed, kept for a few seconds so it can be undone.
    struct ClearedTasks: Equatable {
        let id = UUID()
        let previous: [NotchTask]
        let count: Int
    }

    @Published private(set) var tasks: [NotchTask] = []
    @Published private(set) var lastCleared: ClearedTasks?

    private static let storageKey = "notch-tasks"
    static let maxTitleLength = 200
    private var undoExpiry: Task<Void, Never>?

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([NotchTask].self, from: data) {
            tasks = saved
        }
    }

    var remainingCount: Int { tasks.filter { !$0.isDone }.count }
    var doneCount: Int { tasks.count - remainingCount }

    /// New tasks go to the top, right under the input field.
    func add(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        dropUndo()
        tasks.insert(NotchTask(title: String(trimmed.prefix(Self.maxTitleLength))), at: 0)
        persist()
    }

    func toggle(_ id: NotchTask.ID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        dropUndo()
        tasks[index].isDone.toggle()
        persist()
    }

    func remove(_ id: NotchTask.ID) {
        dropUndo()
        tasks.removeAll { $0.id == id }
        persist()
    }

    func clearDone() {
        clear(keeping: { !$0.isDone })
    }

    func clearAll() {
        clear(keeping: { _ in false })
    }

    func undoClear() {
        guard let lastCleared else { return }
        tasks = lastCleared.previous
        dropUndo()
        persist()
    }

    private func clear(keeping keep: (NotchTask) -> Bool) {
        let kept = tasks.filter(keep)
        let removed = tasks.count - kept.count
        guard removed > 0 else { return }
        let cleared = ClearedTasks(previous: tasks, count: removed)
        tasks = kept
        lastCleared = cleared
        persist()

        undoExpiry?.cancel()
        undoExpiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, !Task.isCancelled, self.lastCleared?.id == cleared.id else { return }
            self.lastCleared = nil
        }
    }

    /// Any other edit makes the undo snapshot stale, so it's dropped.
    private func dropUndo() {
        undoExpiry?.cancel()
        undoExpiry = nil
        lastCleared = nil
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(tasks) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
