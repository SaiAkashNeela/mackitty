import SwiftUI

enum NotchTrayLayout {
    static let openWidth: CGFloat = 380
    /// Tallest the tray gets: notch, header, input, a scrolling list and the undo bar.
    static let maxHeight: CGFloat = 460
    static let listMaxHeight: CGFloat = 220
    /// Width of the hover strip on screens without a notch.
    static let fallbackZoneWidth: CGFloat = 200

    static let openAnimation = Animation.bouncy(duration: 0.5, extraBounce: 0.05)
    static let closeAnimation = Animation.smooth(duration: 0.32)
    static let listAnimation = Animation.snappy(duration: 0.32)
}

/// Colours for the black notch tray. The rest of MacKitty is light, so these
/// live here rather than in Theme.
private enum TrayPalette {
    static let accent = Color(red: 0.176, green: 0.831, blue: 0.749)   // #2DD4BF, Theme.accent lifted for black
    static let text = Color.white
    static let secondary = Color.white.opacity(0.58)
    static let tertiary = Color.white.opacity(0.36)
    static let fill = Color.white.opacity(0.06)
    static let fillHover = Color.white.opacity(0.11)
    static let line = Color.white.opacity(0.10)
}

/// The tray that pours out of the notch: a black island that springs open from
/// the camera housing and folds back into it.
struct NotchTrayView: View {
    @ObservedObject var state: NotchTrayState
    @ObservedObject var store: TaskStore
    var onClose: () -> Void

    var body: some View {
        island
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
            .environment(\.colorScheme, .dark)
    }

    private var island: some View {
        VStack(spacing: 0) {
            if state.isOpen {
                TrayContent(state: state, store: store, onClose: onClose)
                    .padding(.top, contentTopInset)
                    .transition(.asymmetric(insertion: .trayContentIn, removal: .trayContentOut))
            }
        }
        .frame(
            width: state.isOpen ? NotchTrayLayout.openWidth : state.notchSize.width,
            height: state.isOpen ? nil : state.notchSize.height,
            alignment: .top
        )
        .background(shape.fill(Color.black))
        .clipShape(shape)
        // Without a real notch there's nothing to hide the closed shape behind, so it fades out.
        .opacity(state.isOpen || state.hasNotch ? 1 : 0)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: IslandSizeKey.self, value: proxy.size)
        })
        .onPreferenceChange(IslandSizeKey.self) { state.islandSize = $0 }
    }

    private var shape: NotchShape {
        state.isOpen ? NotchShape(topRadius: 14, bottomRadius: 26) : NotchShape(topRadius: 6, bottomRadius: 12)
    }

    /// Content starts below the camera housing.
    private var contentTopInset: CGFloat { state.hasNotch ? state.notchSize.height : 10 }
}

private struct IslandSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

// MARK: - Content

private struct TrayContent: View {
    @ObservedObject var state: NotchTrayState
    @ObservedObject var store: TaskStore
    var onClose: () -> Void
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            header
            input
            taskList
            if let cleared = store.lastCleared {
                UndoBar(count: cleared.count) {
                    withAnimation(NotchTrayLayout.listAnimation) { store.undoClear() }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .frame(width: NotchTrayLayout.openWidth)
        .animation(NotchTrayLayout.listAnimation, value: store.lastCleared)
        .onChange(of: inputFocused) { _, focused in state.isEditing = focused }
        .onChange(of: state.focusRequest) { _, _ in inputFocused = true }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: allDone ? "checkmark.circle.fill" : "checklist")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(TrayPalette.accent)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: store.doneCount)
            Text("Tasks")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(TrayPalette.text)
            Text(summary)
                .font(.system(size: 12))
                .foregroundStyle(TrayPalette.secondary)
                .contentTransition(.numericText(value: Double(store.remainingCount)))
            Spacer(minLength: 8)
            if store.doneCount > 0 {
                NotchPillButton(title: "Clear done", systemImage: "checkmark") {
                    withAnimation(NotchTrayLayout.listAnimation) { store.clearDone() }
                }
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
            if !store.tasks.isEmpty {
                NotchIconButton(systemName: "trash", help: "Clear all tasks") {
                    withAnimation(NotchTrayLayout.listAnimation) { store.clearAll() }
                }
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .frame(height: 26)
    }

    private var allDone: Bool { !store.tasks.isEmpty && store.remainingCount == 0 }

    private var summary: String {
        if store.tasks.isEmpty { return "Nothing yet" }
        if allDone { return "All done" }
        return "\(store.remainingCount) to do"
    }

    // MARK: Input

    private var hasDraft: Bool { !state.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var input: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(hasDraft ? TrayPalette.accent : TrayPalette.tertiary)
                .rotationEffect(.degrees(hasDraft ? 90 : 0))
            TextField("Add a task", text: $state.draft)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(TrayPalette.text)
                .focused($inputFocused)
                .onSubmit(addTask)
                .onExitCommand(perform: onClose)
            if hasDraft {
                Image(systemName: "return")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(TrayPalette.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(TrayPalette.line, lineWidth: 1))
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(inputFocused ? TrayPalette.fillHover : TrayPalette.fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(inputFocused ? TrayPalette.accent.opacity(0.55) : TrayPalette.line, lineWidth: 1)
        )
        .animation(.snappy(duration: 0.25), value: hasDraft)
        .animation(.easeOut(duration: 0.15), value: inputFocused)
    }

    private func addTask() {
        guard hasDraft else { return }
        let title = state.draft
        withAnimation(NotchTrayLayout.listAnimation) {
            store.add(title)
            state.draft = ""
        }
        inputFocused = true
    }

    // MARK: List

    @ViewBuilder
    private var taskList: some View {
        if store.tasks.isEmpty {
            EmptyTasksView()
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
        } else {
            ScrollView(.vertical) { rows }
                .scrollIndicators(.never)
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: listHeight)
        }
    }

    /// Rows have a fixed height, so the list's height is known up front and
    /// grows and shrinks in step with row animations. Past the cap, it scrolls.
    private var listHeight: CGFloat {
        let count = CGFloat(store.tasks.count)
        let total = count * TaskRow.height + max(count - 1, 0) * TaskRow.spacing
        return min(total, NotchTrayLayout.listMaxHeight)
    }

    private var rows: some View {
        VStack(spacing: TaskRow.spacing) {
            ForEach(store.tasks) { task in
                TaskRow(
                    task: task,
                    toggle: { withAnimation(NotchTrayLayout.listAnimation) { store.toggle(task.id) } },
                    remove: { withAnimation(NotchTrayLayout.listAnimation) { store.remove(task.id) } }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .opacity.combined(with: .scale(scale: 0.9, anchor: .leading))
                ))
            }
        }
    }
}

// MARK: - Rows

private struct TaskRow: View {
    static let height: CGFloat = 32
    static let spacing: CGFloat = 4

    let task: NotchTask
    let toggle: () -> Void
    let remove: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: toggle) {
                CheckCircle(isOn: task.isDone)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isDone ? "Mark \(task.title) as not done" : "Mark \(task.title) as done")

            Text(task.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(task.isDone ? TrayPalette.tertiary : TrayPalette.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .overlay(alignment: .leading) {
                    // Drawn rather than Text.strikethrough, so it can sweep across.
                    Capsule()
                        .fill(TrayPalette.secondary)
                        .frame(height: 1.5)
                        .scaleEffect(x: task.isDone ? 1 : 0, anchor: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(task.title)

            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(hovered ? TrayPalette.text : TrayPalette.tertiary)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(hovered ? TrayPalette.fillHover : Color.clear))
            }
            .buttonStyle(.plain)
            .help("Delete task")
            .accessibilityLabel("Delete \(task.title)")
        }
        .padding(.horizontal, 10)
        .frame(height: Self.height)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(hovered ? TrayPalette.fillHover : TrayPalette.fill)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

/// Fills with the accent and pops a checkmark in when a task is done.
private struct CheckCircle: View {
    let isOn: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(TrayPalette.tertiary, lineWidth: 1.5)
                .opacity(isOn ? 0 : 1)
            Circle()
                .fill(TrayPalette.accent)
                .scaleEffect(isOn ? 1 : 0.3)
                .opacity(isOn ? 1 : 0)
            Image(systemName: "checkmark")
                .font(.system(size: 8.5, weight: .heavy))
                .foregroundStyle(Color.black)
                .scaleEffect(isOn ? 1 : 0.2)
                .opacity(isOn ? 1 : 0)
        }
        .frame(width: 18, height: 18)
        .contentShape(Circle())
        .animation(.bouncy(duration: 0.35, extraBounce: 0.2), value: isOn)
    }
}

private struct EmptyTasksView: View {
    @State private var bounce = 0

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(TrayPalette.accent)
                .symbolEffect(.bounce, value: bounce)
            VStack(alignment: .leading, spacing: 1) {
                Text("All clear")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TrayPalette.text)
                Text("Type above and press Return to add a task.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(TrayPalette.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(TrayPalette.fill))
        .onAppear { bounce += 1 }
    }
}

private struct UndoBar: View {
    let count: Int
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "trash")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(TrayPalette.secondary)
            Text("Cleared \(count) \(count == 1 ? "task" : "tasks")")
                .font(.system(size: 12))
                .foregroundStyle(TrayPalette.secondary)
            Spacer(minLength: 0)
            Button(action: undo) {
                Text("Undo")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TrayPalette.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(TrayPalette.accent.opacity(0.14)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(TrayPalette.line, lineWidth: 1)
        )
    }
}

// MARK: - Controls

private struct NotchPillButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hovered ? TrayPalette.text : TrayPalette.secondary)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(Capsule().fill(hovered ? TrayPalette.fillHover : TrayPalette.fill))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

private struct NotchIconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hovered ? TrayPalette.text : TrayPalette.secondary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(hovered ? TrayPalette.fillHover : TrayPalette.fill))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Shape & transitions

/// The notch silhouette: flat along the top edge of the screen, flaring out
/// into the menu bar at the top corners, rounded at the bottom.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let top = max(0, min(topRadius, rect.height / 2, rect.width / 4))
        let bottom = max(0, min(bottomRadius, rect.height - top, (rect.width - 2 * top) / 2))

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + top, y: rect.minY + top),
                          control: CGPoint(x: rect.minX + top, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        path.addQuadCurve(to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
                          control: CGPoint(x: rect.minX + top, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
                          control: CGPoint(x: rect.maxX - top, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                          control: CGPoint(x: rect.maxX - top, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

private struct BlurEffect: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        content.blur(radius: radius)
    }
}

private extension AnyTransition {
    /// Content blurs and settles into place a beat after the island starts to grow.
    static var trayContentIn: AnyTransition {
        AnyTransition.opacity
            .combined(with: .scale(scale: 0.94, anchor: .top))
            .combined(with: .modifier(active: BlurEffect(radius: 10), identity: BlurEffect(radius: 0)))
            .animation(.smooth(duration: 0.35).delay(0.08))
    }

    /// Content fades quickly so the island can fold back into the notch.
    static var trayContentOut: AnyTransition {
        AnyTransition.opacity
            .combined(with: .modifier(active: BlurEffect(radius: 6), identity: BlurEffect(radius: 0)))
            .animation(.easeOut(duration: 0.12))
    }
}
