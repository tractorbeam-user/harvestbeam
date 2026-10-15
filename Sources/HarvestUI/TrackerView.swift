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
    @State private var selectedDay = LocalDate()
    @State private var gridWidth: CGFloat = 0
    @State private var scope: BrowseScope = .everything
    @AppStorage("sidebarVisible") private var sidebarVisible = false
    @AppStorage(MenuBarDisplay.contentKey) private var menuBarContent = MenuBarDisplay.Content.task.rawValue
    @AppStorage(MenuBarDisplay.lengthKey) private var menuBarLength = 28
    @AppStorage(MenuBarDisplay.truncationKey) private var menuBarTruncation = MenuBarDisplay.Truncation.end.rawValue
    @AppStorage(MenuBarDisplay.showTimeKey) private var menuBarShowTime = true
    @FocusState private var searchFocused: Bool

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    private func sections() -> [TaskSection] {
        if isSearching {
            return [TaskSection(
                id: "results", title: "Results", systemImage: "magnifyingglass",
                tasks: Self.groupedByClient(tracker.search(query)), emptyHint: "No tasks match “\(query)”"
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
    /// position of that client's best match, so results read as groups.
    static func groupedByClient(_ ranked: [TrackableTask]) -> [TrackableTask] {
        var order: [Int?] = []
        var groups: [Int?: [TrackableTask]] = [:]
        for task in ranked {
            let id = task.client?.id
            if groups[id] == nil { order.append(id) }
            groups[id, default: []].append(task)
        }
        return order.flatMap { groups[$0] ?? [] }
    }

    /// Search results as a compact list, otherwise the tile sections.
    @ViewBuilder private func content(_ sections: [TaskSection]) -> some View {
        if isSearching {
            SearchResultsList(tasks: sections.first?.tasks ?? [], selection: selection, query: query)
        } else {
            tileGrid(sections)
        }
    }

    var body: some View {
        let sections = sections()
        platformBody(sections)
            .onChange(of: query) {
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

    private func tileGrid(_ sections: [TaskSection]) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 10) {
                    Label(section.title, systemImage: section.systemImage)
                        .labelStyle(SectionLabelStyle())
                        .padding(.leading, 4)

                    if section.tasks.isEmpty, let hint = section.emptyHint {
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
                                TaskTile(task: task, isSelected: selection == task.key)
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
        HStack(spacing: 0) {
            if sidebarVisible {
                SidebarView(scope: $scope)
                Divider()
            }
            mainColumn(sections)
        }
    }

    private func toggleSidebar() {
        let show = !sidebarVisible
        withAnimation(.snappy(duration: 0.2)) { sidebarVisible = show }
        if !show { scope = .everything }
        // Grow the window to make room rather than squeezing the tiles.
        if let window = NSApp.keyWindow {
            var frame = window.frame
            let delta: CGFloat = show ? 191 : -191
            frame.origin.x -= delta
            frame.size.width += delta
            window.setFrame(frame, display: true, animate: true)
        }
    }

    private func mainColumn(_ sections: [TaskSection]) -> some View {
        let flat = sections.flatMap(\.tasks)
        return VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 22) {
                        if isSearching || scope == .everything {
                            if !isSearching { DayView(selectedDay: $selectedDay) }
                            content(sections)
                        } else {
                            ScopeContent(scope: scope)
                        }
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
                    query = ""
                    selection = nil
                    Task { await tracker.toggle(task) }
                }
                .onExitCommand {
                    if !query.isEmpty {
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
            FooterButton(systemImage: "sidebar.left", help: "Folders and clients (⌃⌘S)") { toggleSidebar() }
                .keyboardShortcut("s", modifiers: [.command, .control])
                .foregroundStyle(sidebarVisible ? AnyShapeStyle(.harvestOrange) : AnyShapeStyle(.secondary))
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
                    if isSearching || scope == .everything {
                        if !isSearching { DayView(selectedDay: $selectedDay) }
                        content(sections)
                    } else {
                        ScopeContent(scope: scope)
                    }
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
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Show", selection: $scope) {
                            Label("Everything", systemImage: "square.grid.2x2").tag(BrowseScope.everything)
                            Label("Favorites", systemImage: "star.fill").tag(BrowseScope.favorites)
                        }
                        if !tracker.favorites.folders.isEmpty {
                            Section("Folders") {
                                Picker("Folders", selection: $scope) {
                                    ForEach(tracker.favorites.folders, id: \.self) { Label($0, systemImage: "folder").tag(BrowseScope.folder($0)) }
                                }
                            }
                        }
                        Section("Clients") {
                            Picker("Clients", selection: $scope) {
                                ForEach(tracker.clients, id: \.id) { Text($0.name).tag(BrowseScope.client($0.id)) }
                            }
                        }
                        Button("New Folder", systemImage: "folder.badge.plus") {
                            scope = .folder(tracker.favorites.createFolder())
                        }
                    } label: {
                        Label("Browse", systemImage: "sidebar.left")
                    }
                }
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
