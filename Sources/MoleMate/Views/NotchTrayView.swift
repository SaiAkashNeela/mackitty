import SwiftUI

enum NotchTrayLayout {
    static let openWidth: CGFloat = 380
    /// Tallest the tray gets: the Clean tab mid-review, with a warning and the confirm step.
    static let maxHeight: CGFloat = 480
    static let listMaxHeight: CGFloat = 220
    static let areaListMaxHeight: CGFloat = 162
    /// Width of the hover strip on screens without a notch.
    static let fallbackZoneWidth: CGFloat = 200

    static let openAnimation = Animation.bouncy(duration: 0.5, extraBounce: 0.05)
    static let closeAnimation = Animation.smooth(duration: 0.32)
    static let listAnimation = Animation.snappy(duration: 0.32)
}

enum NotchTab: String {
    case tasks
    case clean
}

/// Colours for the black notch tray. The rest of MacKitty is light, so these
/// live here rather than in Theme.
private enum TrayPalette {
    static let accent = Color(red: 0.176, green: 0.831, blue: 0.749)   // #2DD4BF, Theme.accent lifted for black
    static let warning = Color(red: 0.984, green: 0.749, blue: 0.141)  // #FBBF24, Theme.warning lifted for black
    static let danger = Color(red: 0.973, green: 0.443, blue: 0.443)   // #F87171, Theme.danger lifted for black
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
    let model: DashboardModel
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
                TrayContent(state: state, store: store, model: model, onClose: onClose)
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
    let model: DashboardModel
    var onClose: () -> Void
    @AppStorage("notchTrayTab") private var tab: NotchTab = .tasks

    var body: some View {
        VStack(spacing: 10) {
            header
            if tab == .tasks {
                TasksPane(state: state, store: store, onClose: onClose)
                    .transition(.paneSwap)
            } else {
                CleanPane(model: model, onClose: onClose)
                    .transition(.paneSwap)
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .frame(width: NotchTrayLayout.openWidth)
    }

    private var header: some View {
        HStack(spacing: 8) {
            TabSwitcher(tab: $tab, tasksLeft: store.remainingCount, doneCount: store.doneCount, model: model)
            Spacer(minLength: 8)
            if tab == .tasks {
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
            } else {
                NotchIconButton(systemName: "macwindow", help: "Open MacKitty") {
                    onClose()
                    MainWindow.show()
                }
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .frame(height: 26)
    }
}

/// Tasks | Clean, with the highlight sliding between them.
private struct TabSwitcher: View {
    @Binding var tab: NotchTab
    let tasksLeft: Int
    let doneCount: Int
    let model: DashboardModel
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 2) {
            tabButton(.tasks) {
                Image(systemName: "checklist")
                    .symbolEffect(.bounce, value: doneCount)
                Text("Tasks")
                if tasksLeft > 0 {
                    Text("\(tasksLeft)")
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .contentTransition(.numericText(value: Double(tasksLeft)))
                        .opacity(0.7)
                }
            }
            tabButton(.clean) {
                Image(systemName: "sparkles")
                Text("Clean")
                CleanActivityDot(model: model)
            }
        }
        .padding(2)
        .background(Capsule().fill(TrayPalette.fill))
    }

    private func tabButton<TabLabel: View>(_ value: NotchTab, @ViewBuilder label: () -> TabLabel) -> some View {
        let selected = tab == value
        return Button {
            withAnimation(.snappy(duration: 0.3)) { tab = value }
        } label: {
            HStack(spacing: 5) { label() }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(selected ? Color.black : TrayPalette.secondary)
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background {
                    if selected {
                        Capsule()
                            .fill(TrayPalette.accent)
                            .matchedGeometryEffect(id: "tab", in: highlight)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Pulses while a scan or cleanup runs; steady when results are waiting for review.
private struct CleanActivityDot: View {
    @ObservedObject var model: DashboardModel

    private var busy: Bool { model.isScanning || model.isCleaning }
    private var ready: Bool { !busy && model.screen == .triage && model.hasScanResults }

    var body: some View {
        if busy || ready {
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .symbolEffect(.pulse, isActive: busy)
                .transition(.scale.combined(with: .opacity))
        }
    }
}

// MARK: - Tasks

private struct TasksPane: View {
    @ObservedObject var state: NotchTrayState
    @ObservedObject var store: TaskStore
    var onClose: () -> Void
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            input
            taskList
            if let cleared = store.lastCleared {
                UndoBar(count: cleared.count) {
                    withAnimation(NotchTrayLayout.listAnimation) { store.undoClear() }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(NotchTrayLayout.listAnimation, value: store.lastCleared)
        .onChange(of: inputFocused) { _, focused in state.isEditing = focused }
        .onChange(of: state.focusRequest) { _, _ in inputFocused = true }
        .onDisappear { state.isEditing = false }
    }

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

// MARK: - Clean

/// The cleaner, compact: the same scan, review and confirm steps as the main
/// window, run against the same model, so both places always agree.
private struct CleanPane: View {
    @ObservedObject var model: DashboardModel
    var onClose: () -> Void
    @State private var confirming = false

    private enum Phase: Equatable { case idle, scanning, review, cleaning, done }

    private var phase: Phase {
        if model.isScanning { return .scanning }
        if model.isCleaning { return .cleaning }
        if model.screen == .summary && model.didClean { return .done }
        if model.screen == .triage && model.hasScanResults { return .review }
        return .idle
    }

    var body: some View {
        VStack(spacing: 10) {
            switch phase {
            case .idle:
                idle.transition(.paneSwap)
            case .scanning:
                ProgressCard(
                    title: "Scanning",
                    detail: model.scanPhase,
                    progress: model.scanProgress,
                    footnote: "\(model.scanFilesInspected) items checked · nothing is removed",
                    stop: { model.cancelScan() }
                )
                .transition(.paneSwap)
            case .review:
                review.transition(.paneSwap)
            case .cleaning:
                ProgressCard(
                    title: "Cleaning",
                    detail: model.cleanPhase,
                    progress: model.cleanProgress,
                    footnote: nil,
                    stop: { model.cancelCleaning() }
                )
                .transition(.paneSwap)
            case .done:
                done.transition(.paneSwap)
            }
        }
        .animation(NotchTrayLayout.listAnimation, value: phase)
        .animation(NotchTrayLayout.listAnimation, value: confirming)
        .onAppear { model.refreshDiskStats() }
        .onChange(of: phase) { _, _ in confirming = false }
    }

    // MARK: Idle

    private var idle: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                StorageRing(ratio: model.diskUsedRatio)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Macintosh HD")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(TrayPalette.tertiary)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(model.diskFreeText)
                            .font(.system(size: 19, weight: .semibold).monospacedDigit())
                            .foregroundStyle(TrayPalette.text)
                        Text("free")
                            .font(.system(size: 12))
                            .foregroundStyle(TrayPalette.secondary)
                    }
                    Text("\(model.diskUsedText) of \(model.diskCapacityText) used")
                        .font(.system(size: 11))
                        .foregroundStyle(TrayPalette.tertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(TrayPalette.fill))

            if let last = model.history.first {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(TrayPalette.tertiary)
                    Text("Last cleanup freed \(last.sizeText)")
                        .foregroundStyle(TrayPalette.secondary)
                    Spacer()
                    Text(last.date.formatted(.relative(presentation: .named)))
                        .foregroundStyle(TrayPalette.tertiary)
                }
                .font(.system(size: 11.5))
                .padding(.horizontal, 2)
            }

            NotchActionButton(title: "Scan My Mac", systemImage: "magnifyingglass", style: .accent) {
                scan()
            }
        }
    }

    private func scan() {
        model.selectTopTab(.clean)
        model.resetForFreshScan()
        if model.canScanWithoutPrompt {
            model.requestScan()
        } else {
            // The first scan asks for access in the main window.
            onClose()
            MainWindow.show()
            model.requestScan()
        }
    }

    // MARK: Review

    private var areas: [CleanupCategory] {
        model.cleanupCategories.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    private var selectedCount: Int { model.cleanupCategories.filter(\.isSelected).count }

    private var areaListHeight: CGFloat {
        let count = CGFloat(model.cleanupCategories.count)
        let total = count * CleanAreaRow.height + max(count - 1, 0) * CleanAreaRow.spacing
        return min(total, NotchTrayLayout.areaListMaxHeight)
    }

    private var review: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.hasSelectedCleanup ? model.selectedCleanupSizeText : "Nothing selected")
                        .font(.system(size: 19, weight: .semibold).monospacedDigit())
                        .foregroundStyle(TrayPalette.text)
                        .contentTransition(.numericText())
                    Text("\(selectedCount) of \(model.cleanupCategories.count) safe areas selected")
                        .font(.system(size: 11.5))
                        .foregroundStyle(TrayPalette.secondary)
                }
                Spacer(minLength: 8)
                NotchPillButton(title: "Review", systemImage: "macwindow") {
                    onClose()
                    model.topTab = .clean
                    MainWindow.show()
                }
                .help("See every path in MacKitty")
            }

            if let warning = model.activeAppWarnings.first {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(TrayPalette.warning)
                        .padding(.top, 1)
                    Text(model.activeAppWarnings.count == 1 ? warning : "\(model.activeAppWarnings.count) apps are open. Close them to clean their caches.")
                        .font(.system(size: 11))
                        .foregroundStyle(TrayPalette.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(TrayPalette.warning.opacity(0.10)))
                .help(model.activeAppWarnings.joined(separator: "\n"))
            }

            ScrollView(.vertical) {
                VStack(spacing: CleanAreaRow.spacing) {
                    ForEach(areas) { area in
                        CleanAreaRow(area: area) {
                            withAnimation(NotchTrayLayout.listAnimation) { model.toggleCleanupCategory(area.id) }
                        }
                    }
                }
            }
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: areaListHeight)

            if confirming {
                confirmStep.transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                NotchActionButton(
                    title: "Clean \(model.selectedCleanupSizeText)",
                    systemImage: "sparkles",
                    style: .accent,
                    isEnabled: model.hasSelectedCleanup
                ) {
                    confirming = true
                }
                .transition(.opacity)
            }
        }
    }

    /// The same second step as the main window: nothing is deleted on the first click.
    private var confirmStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Files are deleted permanently, not moved to the Trash. Apps rebuild caches when needed.", systemImage: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(TrayPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                NotchActionButton(title: "Cancel", style: .plain) {
                    confirming = false
                }
                NotchActionButton(title: "Delete \(model.selectedCleanupSizeText)", systemImage: "trash", style: .danger) {
                    confirming = false
                    model.clean()
                }
            }
        }
    }

    // MARK: Done

    private var done: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                DoneSeal()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Freed \(model.history.first?.sizeText ?? "")")
                        .font(.system(size: 17, weight: .semibold).monospacedDigit())
                        .foregroundStyle(TrayPalette.text)
                    Text("\(model.diskFreeText) free now")
                        .font(.system(size: 12))
                        .foregroundStyle(TrayPalette.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(TrayPalette.fill))

            NotchActionButton(title: "Done", style: .plain) {
                withAnimation(NotchTrayLayout.listAnimation) { model.resetForFreshScan() }
            }
        }
    }
}

private struct CleanAreaRow: View {
    static let height: CGFloat = 30
    static let spacing: CGFloat = 3

    let area: CleanupCategory
    let toggle: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 10) {
            CheckCircle(isOn: area.isSelected)
            Text(area.name)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(area.isSelected ? TrayPalette.text : TrayPalette.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(area.id == DashboardModel.moleCategoryID ? "Varies" : area.sizeText)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(area.isSelected ? TrayPalette.secondary : TrayPalette.tertiary)
        }
        .padding(.horizontal, 10)
        .frame(height: Self.height)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hovered ? TrayPalette.fillHover : TrayPalette.fill)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .help(area.path)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(area.isSelected ? "Selected" : "Not selected")
    }
}

/// Used storage as a ring that draws itself in when the tab appears.
private struct StorageRing: View {
    let ratio: Double
    @State private var drawn = false

    private var color: Color {
        ratio > 0.9 ? TrayPalette.danger : (ratio > 0.75 ? TrayPalette.warning : TrayPalette.accent)
    }

    var body: some View {
        ZStack {
            Circle().stroke(TrayPalette.fill, lineWidth: 6)
            Circle()
                .trim(from: 0, to: drawn ? max(0.01, ratio) : 0)
                .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((ratio * 100).rounded()))%")
                .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(TrayPalette.text)
        }
        .frame(width: 52, height: 52)
        .animation(.easeOut(duration: 0.6), value: ratio)
        .onAppear {
            withAnimation(.easeOut(duration: 0.8).delay(0.1)) { drawn = true }
        }
    }
}

private struct ProgressCard: View {
    let title: String
    let detail: String
    let progress: Double
    let footnote: String?
    let stop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TrayPalette.text)
                Spacer()
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(TrayPalette.accent)
                    .contentTransition(.numericText(value: progress))
            }
            ProgressBar(value: progress)
            Text(detail)
                .font(.system(size: 11.5))
                .foregroundStyle(TrayPalette.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack {
                if let footnote {
                    Text(footnote)
                        .font(.system(size: 11))
                        .foregroundStyle(TrayPalette.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                NotchPillButton(title: "Stop", systemImage: "stop.fill", action: stop)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(TrayPalette.fill))
    }
}

private struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(TrayPalette.fill)
                Capsule()
                    .fill(LinearGradient(colors: [TrayPalette.accent.opacity(0.6), TrayPalette.accent], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, proxy.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.4), value: value)
    }
}

/// A seal that pops in with a bounce when a cleanup finishes.
private struct DoneSeal: View {
    @State private var shown = false

    var body: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.system(size: 30))
            .foregroundStyle(TrayPalette.accent)
            .scaleEffect(shown ? 1 : 0.4)
            .opacity(shown ? 1 : 0)
            .symbolEffect(.bounce, value: shown)
            .onAppear {
                withAnimation(.bouncy(duration: 0.45, extraBounce: 0.2)) { shown = true }
            }
    }
}

// MARK: - Shared controls

/// Fills with the accent and pops a checkmark in when on.
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

private struct NotchActionButton: View {
    enum Style { case accent, danger, plain }

    let title: String
    var systemImage: String? = nil
    var style: Style = .accent
    var isEnabled = true
    let action: () -> Void
    @State private var hovered = false

    private var foreground: Color {
        switch style {
        case .accent: return Color.black
        case .danger: return Color.white
        case .plain: return TrayPalette.text
        }
    }

    private var background: Color {
        switch style {
        case .accent: return TrayPalette.accent.opacity(hovered ? 1 : 0.92)
        case .danger: return TrayPalette.danger.opacity(hovered ? 0.95 : 0.8)
        case .plain: return hovered ? TrayPalette.fillHover : TrayPalette.fill
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(background))
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

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

    /// Switching tabs, or between the cleaner's steps.
    static var paneSwap: AnyTransition {
        AnyTransition.opacity
            .combined(with: .scale(scale: 0.97, anchor: .top))
            .combined(with: .modifier(active: BlurEffect(radius: 4), identity: BlurEffect(radius: 0)))
    }
}
