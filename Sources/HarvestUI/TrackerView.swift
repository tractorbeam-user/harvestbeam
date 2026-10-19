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
    /// Search starts as an icon and opens into a field when you need it.
    @State private var isSearchOpen = false
    @State private var favoritesTargeted = false
    /// Classic with the big "What are you working on?" box is the one layout.
    /// Tiles and List were tried and set aside; flip this to bring them back.
    private static let showsLayoutSwitcher = false
    private static let showsAskBox = true
    @AppStorage("windowLayout") private var layoutRaw = WindowLayout.classic.rawValue
    private var layout: WindowLayout {
        Self.showsLayoutSwitcher ? WindowLayout(rawValue: layoutRaw) ?? .classic : .classic
    }
    private var asksFirst: Bool { Self.showsAskBox && layout == .classic }
    @State private var dimmer = PopoverDimmer()
    /// Folded sections (Favorites, Recent, Suggested), remembered between launches.
    @AppStorage("collapsedSections") private var collapsedRaw = ""
    private var collapsed: Set<String> { Set(collapsedRaw.split(separator: ",").map(String.init)) }
    @State private var selectedDay = LocalDate()
    /// The date when the window last checked, to notice a new day.
    @State private var lastToday = LocalDate()
    @State private var gridWidth: CGFloat = 0
    @AppStorage(MenuBarDisplay.contentKey) private var menuBarContent = MenuBarDisplay.Content.task.rawValue
    @AppStorage(MenuBarDisplay.lengthKey) private var menuBarLength = 28
    @AppStorage(MenuBarDisplay.truncationKey) private var menuBarTruncation = MenuBarDisplay.Truncation.end.rawValue
    @AppStorage(MenuBarDisplay.showTimeKey) private var menuBarShowTime = true
    @FocusState private var searchFocused: Bool

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    /// "10 min on tb corporate": what typing a duration in the ask box would add.
    private var quickPlan: [PlannedEntry] { isSearching ? tracker.quickPlan(query) : [] }

    private func sections() -> [TaskSection] {
        if isSearching {
            // One row per matching project; the open one lists its tasks right
            // below it, like an accordion.
            var seen = Set<Int>()
            var tasks: [TrackableTask] = []
            // The best 40 projects are plenty, and keep a one-letter search
            // from building hundreds of rows on every keystroke.
            for match in Self.groupedByClient(tracker.search(query)) where seen.insert(match.project.id).inserted {
                if seen.count > 40 { break }
                tasks.append(match.projectRow)
                if match.project.id == pickedProject {
                    tasks += tracker.tasks.filter { $0.project.id == match.project.id }.sorted { $0.task.name < $1.task.name }
                }
            }
            return [TaskSection(
                id: "results", title: "Results", systemImage: "magnifyingglass",
                tasks: tasks, emptyHint: "No projects match “\(query)”"
            )]
        }
        return [
            TaskSection(
                id: "favorites", title: "Favorites", systemImage: "star.fill",
                tasks: tracker.favoriteTasks, emptyHint: "Drag a task here, or star it, to keep it handy"
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
            #if os(macOS)
            let plan = quickPlan
            if !plan.isEmpty {
                QuickPlanRow(entries: plan, day: selectedDay, isSelected: selection == nil) { addQuickPlan(plan) }
            }
            let planOnly = !plan.isEmpty && (sections.first?.tasks.isEmpty ?? true)
            #else
            let planOnly = false
            #endif
            // With an "Add …" row up top, "No projects match" is just noise.
            if !planOnly {
                SearchResultsList(tasks: sections.first?.tasks ?? [], selection: selection, query: query,
                                  pickedProject: pickedProject, pick: pick)
            }
        } else {
            tileGrid(sections)
        }
    }

    var body: some View {
        let sections = sections()
        platformBody(sections)
            .onChange(of: query) {
                pickedProject = nil
                selection = isSearching && quickPlan.isEmpty ? sections.first?.tasks.first?.key : nil
            }
            .onChange(of: tracker.focusRequest, initial: true) {
                query = ""
                selection = nil
                isSearchOpen = false
                if asksFirst && tracker.focusRequestWantsSearch {
                    Task { searchFocused = true }
                } else {
                    searchFocused = false
                }
                // Opening the window on a new day goes straight to it.
                let today = LocalDate()
                if today != lastToday {
                    selectedDay = today
                    lastToday = today
                }
            }
            // At midnight with the window open, follow along if you were on today.
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    let today = LocalDate()
                    guard today != lastToday else { continue }
                    if selectedDay == lastToday { selectedDay = today }
                    lastToday = today
                    await tracker.refresh(force: true)
                }
            }
            .onChange(of: layoutRaw) { query = ""; isSearchOpen = false }
            .onChange(of: searchFocused) { _, focused in
                if !focused && query.isEmpty { withAnimation(.snappy(duration: 0.2)) { isSearchOpen = false } }
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
        VStack(alignment: .leading, spacing: 20) {
            ForEach(sections) { section in
                let isCollapsed = !isSearching && collapsed.contains(section.id)
                VStack(alignment: .leading, spacing: 8) {
                    Button { toggleCollapsed(section.id) } label: {
                        HStack(spacing: 6) {
                            Label(section.title, systemImage: section.systemImage)
                                .labelStyle(SectionLabelStyle(isPanel: section.id == "favorites"))
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
                                    .strokeBorder(Color.harvestOrange.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
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
                                        : nil,
                                    acceptsDrops: section.id == "favorites"
                                )
                                    .id(task.key)
                            }
                        }
                    }
                }
                // Drop anywhere in Favorites (even when empty) to add at the end.
                .dropDestination(for: String.self) { items, _ in
                    guard section.id == "favorites", let key = items.first.flatMap(TaskKey.init) else { return false }
                    withAnimation(.snappy(duration: 0.2)) { tracker.favorites.place(key, before: nil) }
                    return true
                } isTargeted: { targeted in
                    if section.id == "favorites" { favoritesTargeted = targeted }
                }
                // Favorites sit on their own soft orange panel, brighter while
                // something is dragged over it.
                .padding(section.id == "favorites" ? 10 : 0)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.panelCorner, style: .continuous)
                        .fill(section.id != "favorites" ? Color.clear : favoritesTargeted ? Color.harvestOrange.opacity(0.18) : Color.orangeSoft)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.panelCorner, style: .continuous)
                        .strokeBorder(Color.harvestOrange.opacity(section.id == "favorites" && favoritesTargeted ? 0.5 : 0), lineWidth: 1.5)
                )
            }
            if !isSearching {
                #if os(macOS)
                // Clicking it puts you in the search box.
                Button(action: openSearch) {
                    Text("Search to find any of your \(tracker.tasks.count) tasks")
                }
                .buttonStyle(HintLinkStyle())
                .frame(maxWidth: .infinity)
                #else
                Text("Search to find any of your \(tracker.tasks.count) tasks")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                #endif
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
            // Dim everything, title bar included, while a popover is open.
            .overlay {
                Color.black.opacity(dimmer.openCount > 0 ? 0.22 : 0)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .animation(.easeOut(duration: dimmer.openCount > 0 ? 0.15 : 0.08), value: dimmer.openCount > 0)
            }
        }
        .environment(dimmer)
        .onChange(of: selectedDay.dayTitle(today: LocalDate()), initial: true) { _, title in
            windowActions?.setTitle(title)
        }
    }

    private func mainColumn(_ sections: [TaskSection]) -> some View {
        // Keyboard selection skips folded sections.
        let flat = sections.filter { isSearching || !collapsed.contains($0.id) }.flatMap(\.tasks)
        return VStack(spacing: 0) {
            if asksFirst {
                // Ask first: the big box is always there, focused when the window opens.
                searchField(flat, large: true)
                    .padding(.horizontal, Metrics.padding)
                    .padding(.top, 14)
                    .padding(.bottom, 2)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 20) {
                        if isSearching {
                            content(sections)
                        } else {
                            switch layout {
                            case .classic:
                                DayView(selectedDay: $selectedDay)
                                content(sections)
                            case .tiles:
                                BigTilesView(openSearch: openSearch)
                                DayView(selectedDay: $selectedDay)
                            case .list:
                                DayView(selectedDay: $selectedDay)
                                StartListView()
                            }
                        }
                    }
                    .padding(.horizontal, Metrics.padding)
                    .padding(.vertical, isSearching ? 10 : Metrics.padding)
                }
                // Scrolled content dissolves under the search box (and above
                // the footer) instead of stopping at a hard edge.
                .mask(
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                            .frame(height: 14)
                        Rectangle()
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: 10)
                    }
                )
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

            Rectangle().fill(Color.hairline).frame(height: 1)
            bottomBar(flat)
        }
        .background {
            // Pause the running timer, or open search, from the keyboard.
            Group {
                Button("") { Task { await tracker.pause() } }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(tracker.running == nil)
                Button("") { openSearch() }
                    .keyboardShortcut("f", modifiers: .command)
                // No refresh button: it syncs every minute and when opened.
                Button("") { Task { await tracker.refresh(force: true) } }
                    .keyboardShortcut("r", modifiers: .command)
            }
            .opacity(0)
            .accessibilityHidden(true)
        }
    }

    private func closeSearch() {
        query = ""
        searchFocused = false
        withAnimation(.snappy(duration: 0.2)) { isSearchOpen = false }
    }

    private func openSearch() {
        withAnimation(.snappy(duration: 0.2)) { isSearchOpen = true }
        Task { searchFocused = true }
    }

    /// The search field: small in the bottom bar, or `large` as the Classic
    /// layout's "What are you working on?" box.
    private func searchField(_ flat: [TrackableTask], large: Bool = false) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: large ? 14 : 13, weight: .medium))
                .foregroundStyle(searchFocused ? AnyShapeStyle(.harvestOrange) : AnyShapeStyle(.secondary))
            TextField(large ? "" : "Start something new…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: large ? 15 : 13))
                .focusEffectDisabled()
                .focused($searchFocused)
                .overlay(alignment: .leading) {
                    if large && query.isEmpty { RotatingPrompt(examples: askExamples).allowsHitTesting(false) }
                }
                .onKeyPress(.downArrow) { moveSelection(by: isSearching ? 1 : columnCount, in: flat); return .handled }
                .onKeyPress(.upArrow) {
                    // From the first result, up goes back to the "Add …" row.
                    if isSearching, !quickPlan.isEmpty, selection == flat.first?.key { selection = nil; return .handled }
                    moveSelection(by: isSearching ? -1 : -columnCount, in: flat)
                    return .handled
                }
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
                    let plan = quickPlan
                    if selection == nil, !plan.isEmpty { return addQuickPlan(plan) }
                    guard let key = selection ?? (isSearching ? flat.first?.key : nil),
                          let task = flat.first(where: { $0.key == key }) else { return }
                    pick(task)
                }
                .onExitCommand {
                    if pickedProject != nil {
                        backToProjects()
                    } else if !query.isEmpty {
                        query = ""
                    } else if large, let windowActions {
                        // Nothing typed: one Escape puts the window away,
                        // rather than first leaving the box and then closing.
                        selection = nil
                        searchFocused = false
                        windowActions.close()
                    } else {
                        selection = nil
                        closeSearch()
                    }
                }
            // Clears the text, or closes search when it's already empty.
            if !large || !query.isEmpty {
                Button {
                    if query.isEmpty { closeSearch() } else { query = "" }
                    // The click took focus out of the box; it's still the place to type.
                    if large { searchFocused = true }
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help(query.isEmpty ? "Close search" : "Clear search")
            }
            if large {
                // Dictate into the box, same as pressing fn twice.
                Button {
                    searchFocused = true
                    #if os(macOS)
                    DispatchQueue.main.async { NSApp.sendAction(Selector(("startDictation:")), to: nil, from: nil) }
                    #endif
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.harvestOrange)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.orangeSoft))
                }
                .buttonStyle(.plain)
                .help("Dictate")
            }
        }
        .padding(.horizontal, 12)
        // Small: the same height as the footer buttons, so opening search doesn't resize the bar.
        .frame(height: large ? 44 : 30)
        .background(RoundedRectangle(cornerRadius: large ? 12 : 15, style: .continuous).fill(Color.tileBackground))
        .overlay(
            RoundedRectangle(cornerRadius: large ? 12 : 15, style: .continuous)
                .strokeBorder(searchFocused ? Color.harvestOrange : Color.hairline, lineWidth: 1)
        )
        // Focused: a soft orange ring outside the border, like the landing page.
        .background(
            RoundedRectangle(cornerRadius: (large ? 12 : 15) + 3, style: .continuous)
                .fill(Color.orangeSoft)
                .padding(-3)
                .opacity(searchFocused ? 1 : 0)
        )
        .animation(.easeOut(duration: 0.15), value: searchFocused)
    }

    /// In search: a project row opens its tasks; a task row starts it.
    /// In search: a project row opens or closes its tasks below it; a task
    /// row starts it.
    private func pick(_ task: TrackableTask) {
        if task.isProjectRow {
            withAnimation(.snappy(duration: 0.2)) {
                pickedProject = pickedProject == task.project.id ? nil : task.project.id
            }
            selection = task.key
            return
        }
        query = ""
        pickedProject = nil
        selection = nil
        Task { await tracker.toggle(task) }
    }

    /// What the ask box suggests you can type: a search, then a few entries
    /// built from your own recent work.
    private var askExamples: [String] {
        let recent = tracker.recentTasks.prefix(3)
        var out = ["What are you working on?"]
        let minutes = ["10 min", "an hour", "30 min"]
        for (i, task) in recent.enumerated() {
            out.append("\(minutes[i % minutes.count]) on \(task.projectNameParts.name)")
            if i == 0 { out.append("Search a project, client or code") }
        }
        if out.count == 1 { out += ["10 min on Website Redesign", "Search a project, client or code"] }
        return out
    }

    private func addQuickPlan(_ plan: [PlannedEntry]) {
        let day = selectedDay
        query = ""
        selection = nil
        Task {
            for entry in plan {
                await tracker.addEntry(task: entry.task, on: day, notes: entry.notes, hours: entry.hours ?? 0)
            }
        }
    }

    private func backToProjects() {
        guard let project = pickedProject else { return }
        withAnimation(.snappy(duration: 0.2)) { pickedProject = nil }
        selection = TaskKey(projectID: project, taskID: TrackableTask.projectRowTaskID)
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

    /// A star in the footer: your favorites as a menu, to start (or pause)
    /// one without scrolling to the Favorites panel.
    private var favoritesMenu: some View {
        Menu {
            let favorites = tracker.favoriteTasks
            if favorites.isEmpty {
                Text("Star a task to add it here")
            }
            ForEach(favorites) { task in
                let isRunning = tracker.running?.key == task.key
                Button {
                    Task { await tracker.toggle(task) }
                } label: {
                    Label {
                        Text(task.projectNameParts.name + " · " + task.task.name)
                    } icon: {
                        Image(systemName: isRunning ? "pause.fill" : "play.fill")
                    }
                }
            }
        } label: {
            Image(systemName: "star")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(.secondary)
        .fixedSize()
        .frame(width: 30, height: 30)
        .help("Favorites")
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
            favoritesMenu
                .padding(.trailing, 2)
            if asksFirst {
                Spacer()
            } else if isSearchOpen || !query.isEmpty {
                searchField(flat)
                    .padding(.trailing, 6)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .leading)))
            } else {
                FooterButton(systemImage: "magnifyingglass", help: "Search tasks (⌘F)") { openSearch() }
                Spacer()
            }


            // Layout switcher (hidden for now).
            if Self.showsLayoutSwitcher {
            Picker("Layout", selection: $layoutRaw) {
                ForEach(WindowLayout.allCases) { option in
                    Image(systemName: option.systemImage).help(option.label).tag(option.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.trailing, 4)
            .help("Layout: Classic, Tiles or List")
            }

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
                if let open = windowActions?.openPreferences {
                    Button("Preferences…") { open() }
                        .keyboardShortcut(",", modifiers: .command)
                }
                Button("Sign Out of \(tracker.accountName ?? "Harvest")") { tracker.signOut() }
                Divider()
                Button("Quit Harvestbeam") { NSApplication.shared.terminate(nil) }
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
        .padding(.vertical, 8)
        .background(Color.panelBackground)
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

/// Quiet text that turns orange on hover, for hints you can click.
private struct HintLinkStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5))
            .foregroundStyle(isHovered ? AnyShapeStyle(.harvestOrange) : AnyShapeStyle(.tertiary))
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.15), value: isHovered)
            #if os(macOS)
            .onHover { isHovered = $0 }
            #endif
    }
}

/// Section headings as on the landing page: Favorites in plain words on its
/// orange panel, the others small caps-style labels.
private struct SectionLabelStyle: LabelStyle {
    var isPanel = false

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
                .foregroundStyle(.harvestOrange)
                .font(.system(size: isPanel ? 12 : 10.5, weight: .semibold))
            if isPanel {
                configuration.title
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            } else {
                configuration.title
                    .textCase(.uppercase)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.66)
                    .foregroundStyle(.secondary)
            }
        }
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
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(isHovered ? 0.06 : 0)))
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
    static let barColor = Color.harvestOrange
    @Environment(TimeTracker.self) private var tracker
    @Binding var selectedDay: LocalDate
    @State private var showingHelp = false

    var body: some View {
        let today = LocalDate()
        TimelineView(.periodic(from: .now, by: 30)) { context in
            ZStack {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(selectedDay.dayTitle(today: today))
                        .font(.system(size: 13, weight: .semibold))
                    Text("Week \(TimeFormat.hoursMinutes(tracker.weekSeconds(containing: selectedDay, at: context.date)))")
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
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
                                    .background(Circle().fill(Self.barColor))
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
        .background(Self.barColor)
    }
}

private struct TitleBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .regular))
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
        .dimsWindow()
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

extension TrackableTask {
    /// Search lists projects as rows of their own; this marks one.
    static let projectRowTaskID = -1
    var isProjectRow: Bool { task.id == Self.projectRowTaskID }
    var projectRow: TrackableTask {
        TrackableTask(project: project, projectCode: projectCode, client: client,
                      task: NamedRef(id: Self.projectRowTaskID, name: ""))
    }
}

/// The ask box's placeholder: "What are you working on?", then examples that
/// fade and rise into place every few seconds, so you learn you can type
/// "10 min on TB Corporate" here as well as search.
private struct RotatingPrompt: View {
    let examples: [String]
    @State private var index = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(examples.isEmpty ? "" : examples[index % examples.count])
            .font(.system(size: 15))
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .id(index)
            .transition(reduceMotion ? .opacity : .asymmetric(
                insertion: .opacity.combined(with: .offset(y: 8)),
                removal: .opacity.combined(with: .offset(y: -8))))
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .task(id: examples) {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(index == 0 ? 3.2 : 2.6))
                    withAnimation(.easeInOut(duration: 0.35)) { index += 1 }
                }
            }
            .accessibilityHidden(true)
    }
}

/// Above the search results when what you typed says how long: "Add 0:10 ·
/// TB Corporate · Product Design". Return (or a click) adds it.
private struct QuickPlanRow: View {
    let entries: [PlannedEntry]
    let day: LocalDate
    let isSelected: Bool
    let add: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: add) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.harvestOrange))
                VStack(alignment: .leading, spacing: 1) {
                    if entries.count == 1, let entry = entries.first {
                        Text("Add \(TimeFormat.hoursMinutes((entry.hours ?? 0) * 3600)) to \(entry.task.projectNameParts.name)")
                            .font(.system(size: 13, weight: .semibold))
                        Text(entry.task.task.name + (day == LocalDate() ? "" : " · \(day.dayTitle(today: LocalDate()))"))
                            .font(.system(size: 11.5))
                            .opacity(0.75)
                    } else {
                        Text("Add \(entries.count) entries")
                            .font(.system(size: 13, weight: .semibold))
                        Text(entries.map { "\($0.task.projectNameParts.name) \(TimeFormat.hoursMinutes(($0.hours ?? 0) * 3600))" }.joined(separator: " · "))
                            .font(.system(size: 11.5))
                            .opacity(0.75)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 6)
                Text("⏎")
                    .font(.system(size: 12, weight: .medium))
                    .opacity(isSelected ? 0.9 : 0)
            }
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.harvestOrange : isHovered ? Color.orangeSoft : Color.tileBackground))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(isSelected ? Color.clear : Color.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .onHover { isHovered = $0 }
        #endif
        .accessibilityHint("Adds the time entry")
    }
}
