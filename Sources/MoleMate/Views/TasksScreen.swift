import SwiftUI

/// The Tasks tab: the same list as the notch tray's Tasks tab, with room to breathe.
struct TasksScreen: View {
    @ObservedObject var store: TaskStore
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    private var todo: [NotchTask] { store.tasks.filter { !$0.isDone } }
    private var done: [NotchTask] { store.tasks.filter(\.isDone) }
    private var hasDraft: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var subtitle: String {
        let counts = store.tasks.isEmpty
            ? "Nothing on your list"
            : "\(store.remainingCount) to do, \(store.doneCount) done"
        return counts + ". The same list opens from the notch."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "Tasks", subtitle: subtitle) {
                HStack(spacing: 10) {
                    if store.doneCount > 0 {
                        Button("Clear Done") {
                            withAnimation(.snappy(duration: 0.3)) { store.clearDone() }
                        }
                        .buttonStyle(GhostButtonStyle())
                    }
                    if !store.tasks.isEmpty {
                        Button("Clear All") {
                            withAnimation(.snappy(duration: 0.3)) { store.clearAll() }
                        }
                        .buttonStyle(GhostButtonStyle())
                    }
                }
            }

            inputField
            list

            if let cleared = store.lastCleared {
                undoBar(count: cleared.count)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .pageFrame()
        .animation(.snappy(duration: 0.3), value: store.lastCleared)
        .onAppear { inputFocused = true }
    }

    // MARK: Input

    private var inputField: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(hasDraft ? Theme.accent : Theme.textTertiary)
            TextField("Add a task", text: $draft)
                .textFieldStyle(.plain)
                .font(Theme.body(14))
                .focused($inputFocused)
                .onSubmit(add)
            Button("Add", action: add)
                .buttonStyle(PrimaryButtonStyle(isEnabled: hasDraft))
                .disabled(!hasDraft)
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .glassPanel(radius: 12)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.accent.opacity(inputFocused ? 0.5 : 0), lineWidth: 1.5)
        )
        .animation(.easeOut(duration: 0.15), value: inputFocused)
        .animation(.easeOut(duration: 0.15), value: hasDraft)
    }

    private func add() {
        guard hasDraft else { return }
        let title = draft
        withAnimation(.snappy(duration: 0.3)) { store.add(title) }
        draft = ""
        inputFocused = true
    }

    // MARK: List

    private var list: some View {
        VStack(spacing: 0) {
            if store.tasks.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "checklist")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.textTertiary)
                    Text("No tasks yet")
                        .font(Theme.body(13, .medium))
                        .foregroundStyle(Theme.textSecondary)
                    Text("Type one above and press Return.")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if !todo.isEmpty {
                            SectionLabel(title: "To do", count: todo.count)
                            ForEach(Array(todo.enumerated()), id: \.element.id) { index, task in
                                row(task, showDivider: index > 0)
                            }
                        }
                        if !done.isEmpty {
                            SectionLabel(title: "Done", count: done.count)
                            ForEach(Array(done.enumerated()), id: \.element.id) { index, task in
                                row(task, showDivider: index > 0)
                            }
                        }
                    }
                    .padding(.bottom, 6)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxHeight: .infinity)
        .glassPanel()
    }

    private func row(_ task: NotchTask, showDivider: Bool) -> some View {
        TaskListRow(
            task: task,
            showDivider: showDivider,
            toggle: { withAnimation(.snappy(duration: 0.3)) { store.toggle(task.id) } },
            remove: { withAnimation(.snappy(duration: 0.3)) { store.remove(task.id) } }
        )
        .transition(.asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .opacity
        ))
    }

    private func undoBar(count: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "trash")
                .foregroundStyle(Theme.textTertiary)
            Text("Cleared \(count) \(count == 1 ? "task" : "tasks")")
                .font(Theme.body(12.5))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Button("Undo") {
                withAnimation(.snappy(duration: 0.3)) { store.undoClear() }
            }
            .buttonStyle(GhostButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassPanel(radius: 12)
    }
}

private struct SectionLabel: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            Text("\(count)").monospacedDigit()
        }
        .font(Theme.body(11, .medium))
        .foregroundStyle(Theme.textTertiary)
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }
}

private struct TaskListRow: View {
    let task: NotchTask
    let showDivider: Bool
    let toggle: () -> Void
    let remove: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: toggle) {
                ZStack {
                    Circle()
                        .strokeBorder(Theme.lineStrong, lineWidth: 1.5)
                        .opacity(task.isDone ? 0 : 1)
                    Circle()
                        .fill(Theme.accent)
                        .scaleEffect(task.isDone ? 1 : 0.3)
                        .opacity(task.isDone ? 1 : 0)
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Color.white)
                        .scaleEffect(task.isDone ? 1 : 0.2)
                        .opacity(task.isDone ? 1 : 0)
                }
                .frame(width: 18, height: 18)
                .contentShape(Circle())
                .animation(.bouncy(duration: 0.35, extraBounce: 0.2), value: task.isDone)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isDone ? "Mark \(task.title) as not done" : "Mark \(task.title) as done")

            Text(task.title)
                .font(Theme.body(13, .medium))
                .strikethrough(task.isDone, color: Theme.textTertiary)
                .foregroundStyle(task.isDone ? Theme.textTertiary : Theme.textPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(task.createdAt.formatted(.relative(presentation: .named)))
                .font(Theme.body(11.5))
                .foregroundStyle(Theme.textTertiary)
                .help(task.createdAt.formatted(date: .abbreviated, time: .shortened))

            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(Theme.surfaceHover, in: Circle())
            }
            .buttonStyle(.plain)
            .opacity(hovered ? 1 : 0)
            .help("Delete task")
            .accessibilityLabel("Delete \(task.title)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(hovered ? Theme.surface : .clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .overlay(alignment: .top) {
            if showDivider { Theme.line.frame(height: 1).padding(.leading, 44) }
        }
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}
