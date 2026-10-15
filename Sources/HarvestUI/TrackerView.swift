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
    @FocusState private var searchFocused: Bool

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    private func sections() -> [TaskSection] {
        if isSearching {
            return [TaskSection(
                id: "results", title: "Results", systemImage: "magnifyingglass",
                tasks: tracker.search(query), emptyHint: "No tasks match “\(query)”"
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
        let flat = sections.flatMap(\.tasks)
        return VStack(spacing: 0) {
            VStack(spacing: 12) {
                TimerHeader()
                searchField(flat)
            }
            .padding([.horizontal, .top], Metrics.padding)
            .padding(.bottom, 12)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 22) {
                        if !isSearching { DayView(selectedDay: $selectedDay) }
                        tileGrid(sections)
                    }
                    .padding(Metrics.padding)
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
            footer
        }
    }

    private func searchField(_ flat: [TrackableTask]) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(searchFocused ? AnyShapeStyle(.harvestOrange) : AnyShapeStyle(.secondary))
            TextField("Search projects and tasks", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($searchFocused)
                .onKeyPress(.downArrow) { moveSelection(by: columnCount, in: flat); return .handled }
                .onKeyPress(.upArrow) { moveSelection(by: -columnCount, in: flat); return .handled }
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
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.tileBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
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

    private var footer: some View {
        HStack(spacing: 2) {
            Text(tracker.accountName ?? "")
                .lineLimit(1)
            Text("·")
            Text("⌥H")
                .help("Press Option-H anywhere to show or hide")
            Spacer()

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
            .help("Settings")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.leading, Metrics.padding)
        .padding(.trailing, 8)
        .frame(height: 40)
    }
    #endif

    // MARK: iPhone and iPad

    #if os(iOS)
    private func platformBody(_ sections: [TaskSection]) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TimerHeader()
                    if let error = tracker.errorMessage {
                        ErrorBanner(message: error) { tracker.errorMessage = nil }
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    if !isSearching { DayView(selectedDay: $selectedDay) }
                    tileGrid(sections)
                }
                .padding(Metrics.padding)
                .frame(maxWidth: 960)
                .frame(maxWidth: .infinity)
            }
            .background(Color.panelBackground)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search projects and tasks")
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
