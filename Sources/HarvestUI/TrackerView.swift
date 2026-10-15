import HarvestKit
import SwiftUI
#if os(macOS)
import ServiceManagement
#endif

struct TaskSection: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let tasks: [TrackableTask]
    /// Shown when `tasks` is empty; sections without one are hidden instead.
    var emptyHint: String?
}

/// Timer card, search, then Favorites / Recent / Suggested as grids of tiles.
/// The grid adds columns as the window (or iPad screen) gets wider.
struct TrackerView: View {
    @Environment(TimeTracker.self) private var tracker
    @Environment(\.openURL) private var openURL
    @Environment(\.windowActions) private var windowActions

    @State private var query = ""
    @State private var selection: TaskKey?
    /// Search is two steps: pick a project, then one of its tasks.
    @State private var pickedProject: Int?
    @State private var isAddingEntry = false
    @State private var isPlanning = false
    /// Folded sections (Favorites, Recent, Suggested), remembered between launches.
    @AppStorage("collapsedSections") private var collapsedRaw = ""
    private var collapsed: Set<String> { Set(collapsedRaw.split(separator: ",").map(String.init)) }
    @State private var selectedDay = LocalDate()
    @State private var gridWidth: CGFloat = 0
    @AppStorage(MenuBarDisplay.contentKey) private var menuBarContent = MenuBarDisplay.Content.task.rawValue
    @AppStorage(MenuBarDisplay.lengthKey) private var menuBarLength = 28
    @AppStorage(MenuBarDisplay.truncationKey) private var menuBarTruncation = MenuBarDisplay.Truncation.end.rawValue
    @AppStorage(MenuBarDisplay.showTimeKey) private var menuBarShowTime = true
    @FocusState private var searchFocused: Bool

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    private func sections() -> [TaskSection] {
        if isSearching {
            let tasks: [TrackableTask]
            if let pickedProject {
                tasks = tracker.tasks.filter { $0.project.id == pickedProject }.sorted { $0.task.name < $1.task.name }
            } else {
                // One row per project: its best-matching task stands in for it.
                var seen = Set<Int>()
                tasks = Self.groupedByClient(tracker.search(query)).filter { seen.insert($0.project.id).inserted }
            }
            return [TaskSection(
                id: "results", title: "Results", systemImage: "magnifyingglass",
                tasks: tasks, emptyHint: "No projects match “\(query)”"
            )]
        }
        return [
            TaskSection(
                id: "favorites", title: "Favorites", systemImage: "star.fill",
                tasks: tracker.favoriteTasks, emptyHint: "Tap the star on any task to keep it here"
            ),
            TaskSection(id: "recent", title: "Recent", systemImage: "clock.arrow.circlepath", tasks: tracker.recentTasks),
            TaskSection(id: "suggested", title: "Suggested", systemImage: "sparkles", tasks: tracker.suggestedTasks),
        ]
        .filter { !$0.tasks.isEmpty || $0.emptyHint != nil }
    }

    /// Keeps the ranking, but pulls each client's tasks together under the
    /// position of that client's best match, and within a client each
    /// project's tasks together, so results read as client → project → task.
    static func groupedByClient(_ ranked: [TrackableTask]) -> [TrackableTask] {
        var order: [Int?] = []
        var groups: [Int?: [TrackableTask]] = [:]
        for task in ranked {
            let id = task.client?.id
            if groups[id] == nil { order.append(id) }
            groups[id, default: []].append(task)
        }
        return order.flatMap { groupedByProject(groups[$0] ?? []) }
    }

    private static func groupedByProject(_ ranked: [TrackableTask]) -> [TrackableTask] {
        var order: [Int] = []
        var groups: [Int: [TrackableTask]] = [:]
        for task in ranked {
            if groups[task.project.id] == nil { order.append(task.project.id) }
            groups[task.project.id, default: []].append(task)
        }
        return order.flatMap { groups[$0] ?? [] }
    }

    /// Search results as a compact list, otherwise the tile sections.
    @ViewBuilder private func content(_ sections: [TaskSection]) -> some View {
        if isSearching {
            SearchResultsList(tasks: sections.first?.tasks ?? [], selection: selection, query: query,
                              pickedProject: pickedProject, pick: pick, back: backToProjects)
        } else {
            tileGrid(sections)
        }
    }

    var body: some View {
        let sections = sections()
        platformBody(sections)
            .onChange(of: query) {
                pickedProject = nil
                selection = isSearching ? sections.first?.tasks.first?.key : nil
            }
            .onChange(of: tracker.focusRequest, initial: true) {
                query = ""
                selection = nil
                Task { searchFocused = true }
            }
    }

    // MARK: Shared grid

    private var columnCount: Int {
        max(1, Int((gridWidth + Metrics.spacing) / (Metrics.tileMinWidth + Metrics.spacing)))
    }

    private func toggleCollapsed(_ id: String) {
        var set = collapsed
        if !set.insert(id).inserted { set.remove(id) }
        withAnimation(.snappy(duration: 0.2)) { collapsedRaw = set.sorted().joined(separator: ",") }
    }

    private func tileGrid(_ sections: [TaskSection]) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(sections) { section in
                let isCollapsed = !isSearching && collapsed.contains(section.id)
                VStack(alignment: .leading, spacing: 8) {
                    Button { toggleCollapsed(section.id) } label: {
                        HStack(spacing: 6) {
                            Label(section.title, systemImage: section.systemImage)
                                .labelStyle(SectionLabelStyle())
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                            if isCollapsed {
                                Text("\(section.tasks.count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.leading, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(isCollapsed ? "Show \(section.title)" : "Hide \(section.title)")

                    if isCollapsed {
                        EmptyView()
                    } else if section.tasks.isEmpty, let hint = section.emptyHint {
                        Text(hint)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 64)
                            .background(
                                RoundedRectangle(cornerRadius: Metrics.tileCorner, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                            )
                    } else {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: Metrics.tileMinWidth), spacing: Metrics.spacing)],
                            spacing: Metrics.spacing
                        ) {
                            ForEach(section.tasks) { task in
                                TaskTile(
                                    task: task, isSelected: selection == task.key, showsStar: section.id != "favorites",
                                    onRemove: section.id == "suggested"
                                        ? { withAnimation(.snappy(duration: 0.2)) { tracker.hideSuggestion(task.key) } }
                                        : nil
                                )
                                    .id(task.key)
                            }
                        }
                    }
                }
            }
            if !isSearching {
                Text("Search to find any of your \(tracker.tasks.count) tasks")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { gridWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in gridWidth = width }
            }
        )
    }

    // MARK: Mac

    #if os(macOS)
    private func platformBody(_ sections: [TaskSection]) -> some View {
        // The window's title bar is transparent; draw our own orange one under
        // the traffic lights, as tall as the system made it.
        GeometryReader { proxy in
            VStack(spacing: 0) {
                TitleBar(selectedDay: $selectedDay)
                    .frame(height: max(proxy.safeAreaInsets.top, 28))
                    .zIndex(1)
                // Clip so scrolled content can't slide up over the title bar.
                mainColumn(sections)
                    .clipped()
            }
            .ignoresSafeArea(edges: .top)
        }
        .onChange(of: selectedDay.dayTitle(today: LocalDate()), initial: true) { _, title in
            windowActions?.setTitle(title)
        }
    }

    private func mainColumn(_ sections: [TaskSection]) -> some View {
        // Keyboard selection skips folded sections.
        let flat = sections.filter { isSearching || !collapsed.contains($0.id) }.flatMap(\.tasks)
        return VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 22) {
                        if !isSearching { DayView(selectedDay: $selectedDay) }
                        content(sections)
                    }
                    .padding(.horizontal, Metrics.padding)
                    .padding(.vertical, isSearching ? 10 : Metrics.padding)
                }
                .onChange(of: selection) { _, key in
                    guard let key else { return }
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(key) }
                }
            }

            if let error = tracker.errorMessage {
                ErrorBanner(message: error) { tracker.errorMessage = nil }
            }
            if let deleted = tracker.lastDeleted {
                UndoBanner(entry: deleted, task: tracker.task(for: deleted))
            }

            Divider()
            bottomBar(flat)
        }
        .background {
            // Pause the running timer from the keyboard.
            Button("") { Task { await tracker.pause() } }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(tracker.running == nil)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    private func searchField(_ flat: [TrackableTask]) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(searchFocused ? AnyShapeStyle(.harvestOrange) : AnyShapeStyle(.secondary))
            TextField("Start something new…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focusEffectDisabled()
                .focused($searchFocused)
                .onKeyPress(.downArrow) { moveSelection(by: isSearching ? 1 : columnCount, in: flat); return .handled }
                .onKeyPress(.upArrow) { moveSelection(by: isSearching ? -1 : -columnCount, in: flat); return .handled }
                .onKeyPress(.rightArrow) {
                    guard selection != nil else { return .ignored }
                    moveSelection(by: 1, in: flat)
                    return .handled
                }
                .onKeyPress(.leftArrow) {
                    guard selection != nil else { return .ignored }
                    moveSelection(by: -1, in: flat)
                    return .handled
                }
                .onSubmit {
                    guard let key = selection ?? (isSearching ? flat.first?.key : nil),
                          let task = flat.first(where: { $0.key == key }) else { return }
                    pick(task)
                }
                .onExitCommand {
                    if pickedProject != nil {
                        backToProjects()
                    } else if !query.isEmpty {
                        query = ""
                    } else if selection != nil {
                        selection = nil
                    } else {
                        windowActions?.close()
                    }
                }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 17, style: .continuous).fill(Color.panelBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .strokeBorder(searchFocused ? Color.harvestOrange.opacity(0.7) : Color.primary.opacity(0.1), lineWidth: searchFocused ? 1.5 : 1)
        )
    }

    /// In search: a project row opens its tasks; a task row starts it.
    private func pick(_ task: TrackableTask) {
        if isSearching && pickedProject == nil {
            pickedProject = task.project.id
            selection = sections().first?.tasks.first?.key
            return
        }
        query = ""
        pickedProject = nil
        selection = nil
        Task { await tracker.toggle(task) }
    }

    private func backToProjects() {
        let project = pickedProject
        pickedProject = nil
        selection = sections().first?.tasks.first { $0.project.id == project }?.key
    }

    private func moveSelection(by step: Int, in flat: [TrackableTask]) {
        guard !flat.isEmpty else { return }
        let current = selection.flatMap { key in flat.firstIndex { $0.key == key } }
        let next: Int
        if let current {
            next = min(max(current + step, 0), flat.count - 1)
        } else {
            next = step > 0 ? 0 : flat.count - 1
        }
        selection = flat[next].key
    }

    /// Search lives at the bottom, next to refresh, Open Harvest and settings.
    private func bottomBar(_ flat: [TrackableTask]) -> some View {
        HStack(spacing: 4) {
            FooterButton(systemImage: "plus", help: "New time entry (⌘N)") { isAddingEntry = true }
                .keyboardShortcut("n", modifiers: .command)
                .popover(isPresented: $isAddingEntry, arrowEdge: .top) { NewEntryEditor(day: selectedDay) }
            FooterButton(systemImage: "sparkles", help: "Plan your day in plain words (⌘P)") { isPlanning = true }
                .keyboardShortcut("p", modifiers: .command)
                .popover(isPresented: $isPlanning, arrowEdge: .top) { PlanDayView(day: selectedDay) }
                .padding(.trailing, 2)
            searchField(flat)
                .padding(.trailing, 6)

            FooterButton(systemImage: "arrow.clockwise", help: "Refresh (⌘R)") {
                Task { await tracker.refresh(force: true) }
            }
            .keyboardShortcut("r", modifiers: .command)
            .rotationEffect(.degrees(tracker.isRefreshing ? 360 : 0))
            .animation(tracker.isRefreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default,
                       value: tracker.isRefreshing)

            FooterButton(systemImage: "arrow.up.forward.app", help: "Open Harvest") {
                if let url = tracker.harvestWebURL { openURL(url) }
            }

            Menu {
                if let windowActions {
                    Toggle("Keep on Top", isOn: Binding(
                        get: { windowActions.isKeptOnTop() },
                        set: { windowActions.setKeptOnTop($0) }
                    ))
                    Button("Move Below Menu Bar Icon") { windowActions.snapToMenuBar() }
                    Button("Reset Window Size") { windowActions.resetSize() }
                    if !tracker.hiddenSuggestions.isEmpty {
                        Button("Show Removed Suggestions") { tracker.showHiddenSuggestions() }
                    }
                    Divider()
                }
                Menu("Menu Bar") {
                    Picker("Show", selection: $menuBarContent) {
                        ForEach(MenuBarDisplay.Content.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                    }
                    .pickerStyle(.inline)
                    Toggle("Show Elapsed Time", isOn: $menuBarShowTime)
                    Divider()
                    Picker("Length", selection: $menuBarLength) {
                        ForEach(MenuBarDisplay.lengths, id: \.value) { Text($0.label).tag($0.value) }
                    }
                    .pickerStyle(.inline)
                    Divider()
                    Picker("Truncate", selection: $menuBarTruncation) {
                        ForEach(MenuBarDisplay.Truncation.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                    }
                    .pickerStyle(.inline)
                }
                Divider()
                Toggle("Open at Login", isOn: Binding(
                    get: { SMAppService.mainApp.status == .enabled },
                    set: { enabled in
                        try? enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                    }
                ))
                Divider()
                Button("Sign Out of \(tracker.accountName ?? "Harvest")") { tracker.signOut() }
                Divider()
                Button("Quit Harvest Bar") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .tint(.secondary)
            .fixedSize()
            .frame(width: 30, height: 30)
            .help("Settings · \(tracker.accountName ?? "Harvest") · ⌥H shows or hides this window")
        }
        .foregroundStyle(.secondary)
        .padding(.leading, Metrics.padding)
        .padding(.trailing, 8)
        .padding(.vertical, 10)
        .background(Color.tileBackground)
    }
    #endif

    // MARK: iPhone and iPad

    #if os(iOS)
    private func platformBody(_ sections: [TaskSection]) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let error = tracker.errorMessage {
                        ErrorBanner(message: error) { tracker.errorMessage = nil }
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    if let deleted = tracker.lastDeleted {
                        UndoBanner(entry: deleted, task: tracker.task(for: deleted))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    if !isSearching { DayView(selectedDay: $selectedDay) }
                    content(sections)
                }
                .padding(Metrics.padding)
                .frame(maxWidth: 960)
                .frame(maxWidth: .infinity)
            }
            .background(Color.panelBackground)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Start something new…")
            .refreshable { await tracker.refresh(force: true) }
            .navigationTitle("Timer")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if let url = tracker.harvestWebURL {
                            Link(destination: url) { Label("Open Harvest", systemImage: "safari") }
                        }
                        Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                            tracker.signOut()
                        }
                    } label: {
                        Label(tracker.accountName ?? "Account", systemImage: "person.crop.circle")
                    }
                }
            }
        }
    }
    #endif
}

private struct SectionLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(.harvestOrange)
            configuration.title.foregroundStyle(.secondary)
        }
        .font(.subheadline.weight(.semibold))
    }
}

/// "Deleted … · Undo", shown after deleting an entry instead of asking first.
/// Goes away on its own after a few seconds.
private struct UndoBanner: View {
    @Environment(TimeTracker.self) private var tracker
    let entry: TimeEntry
    let task: TrackableTask

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "trash").foregroundStyle(.secondary)
            Text("Deleted \(task.project.name) · \(TimeFormat.hoursMinutes(entry.elapsed()))")
                .font(.callout)
                .lineLimit(1)
            Spacer()
            Button("Undo") { Task { await tracker.undoDelete() } }
                .buttonStyle(SoftPillButtonStyle())
                .keyboardShortcut("z", modifiers: .command)
            Button { tracker.lastDeleted = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.05))
        .task(id: entry.id) {
            try? await Task.sleep(for: .seconds(8))
            if tracker.lastDeleted?.id == entry.id { tracker.lastDeleted = nil }
        }
    }
}

private struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.harvestOrange)
            Text(message).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action: dismiss) { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.harvestOrange.opacity(0.12))
    }
}

#if os(macOS)
private struct FooterButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(isHovered ? 0.08 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
    }
}
#endif

#if os(macOS)
/// Orange title bar: the selected day and its week total in the middle, then
/// Today and keyboard help on the right. The traffic lights sit on the left.
private struct TitleBar: View {
    static let barTrailing = Color(red: 0.92, green: 0.32, blue: 0.16)
    @Environment(TimeTracker.self) private var tracker
    @Binding var selectedDay: LocalDate
    @State private var showingHelp = false

    var body: some View {
        let today = LocalDate()
        TimelineView(.periodic(from: .now, by: 30)) { context in
            ZStack {
                VStack(spacing: 0) {
                    Text(selectedDay.dayTitle(today: today))
                        .font(.system(size: 13, weight: .semibold))
                    Text("Week \(TimeFormat.hoursMinutes(tracker.weekSeconds(containing: selectedDay, at: context.date)))")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .opacity(0.8)
                }
                .lineLimit(1)

                HStack(spacing: 2) {
                    Spacer()
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { selectedDay = today }
                    } label: {
                        Image(systemName: "\(Calendar.current.component(.day, from: .now)).calendar")
                            // Harvest's "jump to today" mark: an up arrow on the
                            // calendar's corner, cut out of the bar behind it.
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(1.5)
                                    .background(Circle().fill(Self.barTrailing))
                                    .offset(x: 4, y: 4)
                            }
                    }
                    .buttonStyle(TitleBarButtonStyle())
                    .keyboardShortcut("t", modifiers: .command)
                    .help("Go to today (⌘T)")
                    .accessibilityLabel("Go to today")

                    Button { showingHelp.toggle() } label: {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(TitleBarButtonStyle())
                    .help("Time summary")
                    .popover(isPresented: $showingHelp, arrowEdge: .bottom) { TimeSummary() }
                }
                .padding(.trailing, 10)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Color(red: 0.95, green: 0.45, blue: 0.20), Self.barTrailing],
                startPoint: .leading, endPoint: .trailing
            )
        )
    }
}

private struct TitleBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .regular))
            .frame(width: 30, height: 28)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Harvest's Time Summary: hours today, yesterday, this week and this month.
#if DEBUG
/// For offscreen snapshots; white text around it like the title bar.
public func debugTimeSummary() -> some View { TimeSummary().foregroundStyle(.white) }
#endif

private struct TimeSummary: View {
    @Environment(TimeTracker.self) private var tracker

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let today = LocalDate(context.date)
            VStack(spacing: 0) {
                Text("Time Summary")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.vertical, 12)
                Divider()
                HStack(spacing: 0) {
                    cell("Hours Today", tracker.seconds(on: today, at: context.date))
                    Divider()
                    cell("Hours Yesterday", tracker.seconds(on: today.adding(days: -1), at: context.date))
                }
                .fixedSize(horizontal: false, vertical: true)
                Divider()
                HStack(spacing: 0) {
                    cell("Hours This Week", tracker.weekSeconds(containing: today, at: context.date))
                    Divider()
                    cell("Hours This Month", tracker.monthSeconds(containing: today, at: context.date))
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: 300)
        // The title bar sets white text, and `.primary` would inherit it; use
        // the real label colors.
        .foregroundStyle(Color.primary)
        .presentationBackground(Color.tileBackground)
    }

    private func cell(_ label: String, _ seconds: TimeInterval) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Color.secondary)
            Text(TimeFormat.hoursMinutes(seconds))
                .font(.system(size: 24, weight: .light).monospacedDigit())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }
}
#endif
