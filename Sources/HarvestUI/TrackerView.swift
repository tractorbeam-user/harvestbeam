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

/// Search, Favorites, Suggested and Recent. Laid out as a compact keyboard-
/// driven panel on the Mac and as a native inset list on iPhone and iPad.
struct TrackerView: View {
    @Environment(TimeTracker.self) private var tracker
    @Environment(\.openURL) private var openURL
    let onClose: (() -> Void)?

    @State private var query = ""
    @State private var selection: TaskKey?
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
                tasks: tracker.favoriteTasks, emptyHint: "Star a task to keep it here"
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

    // MARK: Mac

    #if os(macOS)
    private func platformBody(_ sections: [TaskSection]) -> some View {
        let flat = sections.flatMap(\.tasks)
        return VStack(spacing: 0) {
            TimerHeader()
                .padding([.horizontal, .top], 12)

            searchField(flat)
                .padding(12)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(sections) { section in
                            sectionHeader(section)
                            if section.tasks.isEmpty, let hint = section.emptyHint {
                                Text(hint)
                                    .font(.callout)
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                            }
                            ForEach(section.tasks) { task in
                                TaskRow(task: task, isSelected: selection == task.key)
                                    .id(task.key)
                            }
                        }
                        if !isSearching {
                            Text("Type to search all \(tracker.tasks.count) tasks")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 14)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 10)
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
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(searchFocused ? AnyShapeStyle(.harvestOrange) : AnyShapeStyle(.secondary))
            TextField("Search projects and tasks", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($searchFocused)
                .onKeyPress(.downArrow) { moveSelection(by: 1, in: flat); return .handled }
                .onKeyPress(.upArrow) { moveSelection(by: -1, in: flat); return .handled }
                .onSubmit {
                    guard let key = selection ?? (isSearching ? flat.first?.key : nil),
                          let task = flat.first(where: { $0.key == key }) else { return }
                    query = ""
                    Task { await tracker.toggle(task) }
                }
                .onExitCommand {
                    if query.isEmpty { onClose?() } else { query = "" }
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
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary.opacity(0.7)))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.harvestOrange.opacity(searchFocused ? 0.55 : 0), lineWidth: 1.5)
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

    private func sectionHeader(_ section: TaskSection) -> some View {
        Label(section.title, systemImage: section.systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .labelStyle(SectionLabelStyle())
            .padding(.horizontal, 10)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    private var footer: some View {
        HStack(spacing: 2) {
            Text(tracker.accountName ?? "")
                .lineLimit(1)
            Text("·")
            Text("⌥H")
                .help("Press Option-H anywhere to open")
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
                onClose?()
            }

            Menu {
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
            .frame(width: 28, height: 28)
            .help("Settings")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(height: 38)
    }
    #endif

    // MARK: iPhone and iPad

    #if os(iOS)
    private func platformBody(_ sections: [TaskSection]) -> some View {
        NavigationStack {
            List {
                Section {
                    TimerHeader()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                if let error = tracker.errorMessage {
                    Section {
                        ErrorBanner(message: error) { tracker.errorMessage = nil }
                            .listRowInsets(EdgeInsets())
                    }
                }

                ForEach(sections) { section in
                    Section {
                        if section.tasks.isEmpty, let hint = section.emptyHint {
                            Text(hint).foregroundStyle(.secondary)
                        }
                        ForEach(section.tasks) { task in
                            TaskRow(task: task)
                                .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                                .listRowBackground(
                                    tracker.running?.key == task.key ? Color.harvestOrange.opacity(0.08) : nil
                                )
                                .swipeActions(edge: .leading) {
                                    let favorite = tracker.favorites.contains(task.key)
                                    Button(favorite ? "Unfavorite" : "Favorite", systemImage: favorite ? "star.slash" : "star.fill") {
                                        tracker.favorites.toggle(task.key)
                                    }
                                    .tint(.harvestOrange)
                                }
                        }
                        .onMove(perform: section.id == "favorites" ? { tracker.favorites.move(fromOffsets: $0, toOffset: $1) } : nil)
                    } header: {
                        Label(section.title, systemImage: section.systemImage)
                            .labelStyle(SectionLabelStyle())
                    }
                }
            }
            .listStyle(.insetGrouped)
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
        HStack(spacing: 5) {
            configuration.icon.foregroundStyle(.harvestOrange).imageScale(.small)
            configuration.title.textCase(.uppercase).tracking(0.4)
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
        .background(Color.harvestOrange.opacity(0.1))
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
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(isHovered ? 0.08 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
    }
}
#endif
