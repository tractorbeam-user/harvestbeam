import HarvestKit
import SwiftUI
import UniformTypeIdentifiers
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
    #if os(macOS)
    /// Today's meetings, for "meeting at 2:00" suggestions; absent in previews.
    @Environment(CalendarStore.self) private var calendar: CalendarStore?
    /// What you were in before opening the window, for on-screen suggestions.
    @Environment(ActivityRecorder.self) private var recorder: ActivityRecorder?
    @AppStorage(ActivityRecorder.suggestionsKey) private var suggestsFromScreen = false
    #endif

    @State private var query = ""
    @State private var selection: TaskKey?
    /// Search is two steps: pick a project, then one of its tasks.
    @State private var pickedProject: Int?
    @State private var isAddingEntry = false
    @State private var isPlanning = false
    /// What the ask box hands the planner ("I did the LP site and a call").
    @State private var planText = ""
    /// Search starts as an icon and opens into a field when you need it.
    @State private var isSearchOpen = false
    /// The Favorites or group panel something is dragged over.
    @State private var targetedPanel: String?
    /// Recent and Suggested drop down from the empty ask box while it's focused.
    @State private var askListOpen = false
    /// Keeps the list up while the pointer is on it: a click there takes
    /// focus out of the box before the row's button sees it.
    @State private var isHoveringAskList = false
    /// Classic with the big "What are you working on?" box is the one layout.
    /// Tiles and List were tried and set aside; flip this to bring them back.
    private static let showsLayoutSwitcher = false
    private static let showsAskBox = true
    /// The landing page's feedback form, told which version it came from.
    static var feedbackURL: URL {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        return URL(string: "https://harvestbeam.vercel.app/?from=app&v=\(version)#feedback")!
    }
    @AppStorage("windowLayout") private var layoutRaw = WindowLayout.classic.rawValue
    private var layout: WindowLayout {
        Self.showsLayoutSwitcher ? WindowLayout(rawValue: layoutRaw) ?? .classic : .classic
    }
    private var asksFirst: Bool { Self.showsAskBox && layout == .classic }
    @State private var dimmer = PopoverDimmer()
    /// Folded sections (Favorites, Recent, Suggested), remembered between launches.
    @AppStorage("collapsedSections") private var collapsedRaw = ""
    @AppStorage(FavoritesStyle.key) private var favoritesStyleRaw = FavoritesStyle.classic.rawValue
    @AppStorage(AppAppearance.key) private var appearanceRaw = AppAppearance.system.rawValue
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
    /// "move 20 min from X to Y", "note: …", "stop": a change to today's
    /// time, previewed in the ask box until Return.
    /// What the ask box's text means, worked out once per keystroke: a body
    /// pass reads these several times, and each one searches every task.
    @State private var askCache = AskCache()
    private let tileOrder = TileOrder.shared
    private let groups = TaskGroups.shared
    @State private var renameText = ""
    @State private var deletingGroup: TaskGroups.Group?
    @State private var showingGuide = false
    @State private var hoveredHeader: String?
    /// The section being dragged by its title, and where it would land.
    @State private var draggingSection: String?
    @State private var sectionDrop: SectionDrop?
    private var askReading: AskCache.Reading { askCache.reading(query, isSearching: isSearching, tracker: tracker) }
    private var askCommand: AskCommandPreview? { askReading.command }
    /// "10 min on tb corporate": what typing a duration in the ask box would add.
    /// A sentence about the day rather than a search: Return opens the planner.
    private var describesDay: Bool { askReading.describesDay }
    private var quickPlan: [PlannedEntry] { askReading.quickPlan }
    /// "How do I split an entry?": answers about the app instead of results.
    private var helpAnswers: [HelpTopic] { askReading.help }
    /// Shown after starting a retired bucket from search.
    @State private var retiredPick: TrackableTask?

    private func sections() -> [TaskSection] {
        // A command shows only its preview, so ↑↓ and Return stay with it.
        if isSearching, askCommand != nil || describesDay || !helpAnswers.isEmpty {
            return [TaskSection(id: "results", title: "Results", systemImage: "magnifyingglass", tasks: [])]
        }
        if isSearching {
            // One row per matching project; the open one lists its tasks right
            // below it, like an accordion.
            var seen = Set<Int>()
            var tasks: [TrackableTask] = []
            // The best 40 projects are plenty, and keep a one-letter search
            // from building hundreds of rows on every keystroke.
            for match in Self.groupedByClient(askReading.results) where seen.insert(match.project.id).inserted {
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
        let byKey = Dictionary(tracker.tasks.map { ($0.key.description, $0) }, uniquingKeysWith: { first, _ in first })
        return groups.order.compactMap { id -> TaskSection? in
            switch id {
            case TaskGroups.favoritesID:
                return TaskSection(
                    id: "favorites", title: "Favorites", systemImage: "star.fill",
                    tasks: tracker.favoriteTasks, emptyHint: "Drag a task here, or star it, to keep it handy"
                )
            case "recent":
                return TaskSection(id: "recent", title: "Recent", systemImage: "clock.arrow.circlepath",
                                   tasks: tileOrder.arranged(tracker.recentTasks, in: "recent"))
            case "suggested":
                return TaskSection(id: "suggested", title: "Suggested", systemImage: "sparkles",
                                   tasks: tileOrder.arranged(tracker.suggestedTasks, in: "suggested"))
            default:
                guard let group = groups.group(forSection: id) else { return nil }
                return TaskSection(id: id, title: group.name, systemImage: "folder.fill",
                                   tasks: group.keys.compactMap { byKey[$0] },
                                   emptyHint: "Drag tasks here")
            }
        }
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
        if let command = askCommand {
            AskCommandRow(preview: command) { applyCommand(command) }
        } else if !helpAnswers.isEmpty {
            VStack(spacing: 6) {
                ForEach(helpAnswers) { HelpAnswerRow(topic: $0) }
            }
        } else if describesDay {
            PlanSentenceRow(day: selectedDay) { openPlanner(with: query) }
        } else if isSearching {
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
                selection = isSearching && quickPlan.isEmpty && askCommand == nil && !describesDay && helpAnswers.isEmpty ? sections.first?.tasks.first?.key : nil
                if isSearching { retiredPick = nil }
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
                // The list waits to be asked for: a click in the box, or ↓.
                askListOpen = false
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
            #if os(macOS)
            // A click in the ask box opens Recent and Suggested; just opening
            // the window, which also puts you in the box, doesn't.
            .onAppear {
                // Escape closes the ask box's list first, wherever focus is.
                EscapeRouter.closeInnermost = {
                    guard askListOpen else { return false }
                    askListOpen = false
                    selection = nil
                    return true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .askFieldClicked)) { _ in
                guard asksFirst, !isSearching else { return }
                selection = nil
                askListOpen = true
            }
            #endif
            .onChange(of: searchFocused) { _, focused in
                if !focused && query.isEmpty { withAnimation(.snappy(duration: 0.2)) { isSearchOpen = false } }
                if focused {
                    if !isSearching { selection = nil }
                } else if !isHoveringAskList {
                    askListOpen = false
                }
            }
    }

    // MARK: Shared grid

    private var columnCount: Int {
        max(1, Int((gridWidth + Metrics.spacing) / (Metrics.tileMinWidth + Metrics.spacing)))
    }

    /// A tile dropped on another: Favorites keeps its own order; Recent and
    /// Suggested remember yours. Tiles from another section are ignored here
    /// (dropping on Favorites' panel adds them).
    private func dropTile(_ key: TaskKey, before target: TaskKey, in section: TaskSection) -> Bool {
        if section.id == "favorites" {
            tracker.favorites.place(key, before: target)
            return true
        }
        if let group = groups.group(forSection: section.id) {
            groups.place(key, before: target, in: group.id)
            return true
        }
        guard section.tasks.contains(where: { $0.key == key }) else { return false }
        tileOrder.place(key, before: target, in: section.id, current: section.tasks.map(\.key))
        return true
    }

    /// Right-click on Favorites' or a group's title.
    @ViewBuilder private func panelMenu(_ section: TaskSection) -> some View {
        let group = groups.group(forSection: section.id)
        if let group {
            Button("Rename…", systemImage: "pencil") { groups.renaming = group.id }
        }
        Button(groups.isHalf(section.id) ? "Full Width" : "Half Width",
               systemImage: groups.isHalf(section.id) ? "rectangle" : "rectangle.split.2x1") {
            withAnimation(.snappy(duration: 0.25)) { groups.toggleHalf(section.id) }
        }
        Button("Move Up", systemImage: "arrow.up") { withAnimation(.snappy(duration: 0.2)) { groups.move(section.id, by: -1) } }
            .disabled(!groups.canMove(section.id, by: -1))
        Button("Move Down", systemImage: "arrow.down") { withAnimation(.snappy(duration: 0.2)) { groups.move(section.id, by: 1) } }
            .disabled(!groups.canMove(section.id, by: 1))
        Divider()
        if TaskGroups.customGroupsEnabled {
            Button("New Group", systemImage: "folder.badge.plus") { withAnimation(.snappy(duration: 0.2)) { _ = groups.create() } }
        }
        if let group {
            Button("Delete Group…", systemImage: "trash", role: .destructive) {
                if group.keys.isEmpty { withAnimation { groups.delete(group.id) } } else { deletingGroup = group }
            }
        }
    }

    private func toggleCollapsed(_ id: String) {
        var set = collapsed
        if !set.insert(id).inserted { set.remove(id) }
        withAnimation(.snappy(duration: 0.2)) { collapsedRaw = set.sorted().joined(separator: ",") }
    }

    /// Sections in rows: two half-width ones in a row share it as columns.
    private func moduleRows(_ sections: [TaskSection]) -> [[TaskSection]] {
        guard !isSearching else { return sections.map { [$0] } }
        var rows: [[TaskSection]] = []
        var index = 0
        while index < sections.count {
            let section = sections[index]
            if groups.isHalf(section.id), index + 1 < sections.count, groups.isHalf(sections[index + 1].id) {
                rows.append([section, sections[index + 1]])
                index += 2
            } else {
                rows.append([section])
                index += 1
            }
        }
        return rows
    }

    /// Tiles across: one in a half-width column, two at full width.
    private func tilesAcross(_ id: String) -> Int {
        groups.isHalf(id) ? 1 : 2
    }

    /// Each section's own look. Favorites keeps the one in Preferences.
    private func sectionStyle(_ id: String) -> FavoritesStyle {
        // Tiles everywhere for now; the other looks are parked.
        .classic
    }

    private func sectionDropAlignment(_ id: String) -> Alignment {
        guard let drop = sectionDrop, drop.target == id else { return .top }
        if groups.isHalf(id) { return drop.after ? .trailing : .leading }
        return drop.after ? .bottom : .top
    }

    /// Starts a section drag. A drag let go somewhere else never says so, so
    /// this watches for the mouse button coming up to tidy away.
    private func beginSectionDrag(_ id: String) {
        draggingSection = id
        #if os(macOS)
        func check() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                guard draggingSection != nil else { return }
                if NSEvent.pressedMouseButtons & 1 == 0 {
                    draggingSection = nil
                    sectionDrop = nil
                } else {
                    check()
                }
            }
        }
        check()
        #endif
    }

    nonisolated static func draggedSection(_ payload: String) -> String? {
        payload.hasPrefix("section:") ? String(payload.dropFirst("section:".count)) : nil
    }

    /// A section's title: click to fold it, drag it to move the section. On
    /// hover, a width switch and a menu show at the right.
    private func sectionHeader(_ section: TaskSection, isPanel: Bool, isCollapsed: Bool) -> some View {
        let isHalf = groups.isHalf(section.id)
        return HStack(spacing: 6) {
            HStack(spacing: 6) {
                Label(section.title, systemImage: section.systemImage)
                    .labelStyle(SectionLabelStyle(isPanel: isPanel))
                    .lineLimit(1)
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
            .contentShape(Rectangle())
            .onTapGesture { toggleCollapsed(section.id) }
            .onDrag {
                beginSectionDrag(section.id)
                return NSItemProvider(object: ("section:" + section.id) as NSString)
            } preview: {
                Label(section.title, systemImage: section.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(Color.harvestOrange))
                    .foregroundStyle(.white)
            }
            .help(isCollapsed ? "Show \(section.title)" : "Hide \(section.title). Drag to move it.")
            Spacer(minLength: 4)
            // Always there (faded in on hover), so a click never lands while
            // they're still appearing.
            HStack(spacing: 2) {
                Button {
                    withAnimation(.snappy(duration: 0.25)) { groups.toggleHalf(section.id) }
                } label: {
                    Image(systemName: isHalf ? "rectangle" : "rectangle.split.2x1")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isHalf ? "Full width" : "Half width: sits beside another half-width section")
                Menu {
                    panelMenu(section)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 18)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .opacity(hoveredHeader == section.id ? 1 : 0)
            .animation(.easeOut(duration: 0.12), value: hoveredHeader == section.id)
        }
        .padding(.leading, 4)
        .frame(height: 20)
        .contentShape(Rectangle())
        .onHover { hoveredHeader = $0 ? section.id : (hoveredHeader == section.id ? nil : hoveredHeader) }
        .contextMenu { panelMenu(section) }
    }

    private func panelFill(_ id: String, isPanel: Bool, isGroup: Bool) -> Color {
        if !isPanel { return .clear }
        if targetedPanel == id { return Color.harvestOrange.opacity(0.18) }
        // Only Favorites is orange; the rest sit on a quiet gray.
        return id == "favorites" ? .orangeSoft : Color.primary.opacity(0.045)
    }

    @ViewBuilder private func sectionBlock(_ section: TaskSection) -> some View {
        let isCollapsed = !isSearching && collapsed.contains(section.id)
        // Every section is the same kind of panel; only Favorites and your
        // groups take tasks dropped on them.
        let isPanel = true
        let takesTasks = section.id == "favorites" || groups.group(forSection: section.id) != nil
        let group = groups.group(forSection: section.id)
        VStack(alignment: .leading, spacing: 5) {
            if let group, groups.renaming == group.id {
                GroupNameField(text: $renameText) {
                    groups.rename(group.id, to: renameText)
                    groups.renaming = nil
                }
                .onAppear { renameText = group.name }
            } else {
            sectionHeader(section, isPanel: isPanel, isCollapsed: isCollapsed)
            }

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
                let style = sectionStyle(section.id)
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: Metrics.spacing),
                                   count: tilesAcross(section.id)),
                    spacing: Metrics.spacing
                ) {
                    ForEach(section.tasks) { task in
                        TaskTile(
                            task: task, isSelected: tileSelected(task.key), showsStar: section.id != "favorites",
                            onRemove: section.id == "suggested"
                                ? { withAnimation(.snappy(duration: 0.2)) { tracker.hideSuggestion(task.key) } }
                                : nil,
                            dropBefore: { key in dropTile(key, before: task.key, in: section) },
                            style: style,
                            groupID: group?.id
                        )
                            .id(task.key)
                    }
                }
            }
        }
        // Drop anywhere in Favorites (even when empty) to add at the end.
        .dropDestination(for: String.self) { items, _ in
            if let id = items.first.flatMap(Self.draggedSection) {
                withAnimation(.snappy(duration: 0.25)) { groups.placeSection(id, before: section.id) }
                return true
            }
            guard takesTasks, let key = items.first.flatMap(TaskKey.init) else { return false }
            withAnimation(.snappy(duration: 0.2)) {
                if let group { groups.place(key, before: nil, in: group.id) } else { tracker.favorites.place(key, before: nil) }
            }
            return true
        } isTargeted: { targeted in
            if targeted { targetedPanel = section.id } else if targetedPanel == section.id { targetedPanel = nil }
        }
        // Favorites sit on their own soft orange panel, brighter while
        // something is dragged over it.
        .padding(isPanel ? 7 : 0)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Metrics.panelCorner, style: .continuous)
                .fill(panelFill(section.id, isPanel: isPanel, isGroup: group != nil))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.panelCorner, style: .continuous)
                .strokeBorder(Color.harvestOrange.opacity(targetedPanel == section.id ? 0.5 : 0), lineWidth: 1.5)
        )
        // While a section is dragged, every other section shows where it
        // would land: a line on the side it'll go (left or right of a
        // half-width one, above or below a full-width one).
        .overlay {
            if let dragged = draggingSection, dragged != section.id {
                GeometryReader { proxy in
                    Color.clear
                        .contentShape(Rectangle())
                        .onDrop(of: [.text], delegate: SectionDropDelegate(
                            target: section.id, size: proxy.size, sideBySide: groups.isHalf(section.id),
                            dragged: dragged, drop: $sectionDrop,
                            perform: { after in
                                withAnimation(.snappy(duration: 0.25)) {
                                    groups.placeSection(dragged, nextTo: section.id, after: after)
                                }
                                draggingSection = nil
                                sectionDrop = nil
                            }
                        ))
                }
            }
        }
        .overlay(alignment: sectionDropAlignment(section.id)) {
            if let drop = sectionDrop, drop.target == section.id {
                let sideBySide = groups.isHalf(section.id)
                Capsule()
                    .fill(Color.harvestOrange)
                    .frame(width: sideBySide ? 3 : nil, height: sideBySide ? nil : 3)
                    .offset(x: sideBySide ? (drop.after ? 6 : -6) : 0, y: sideBySide ? 0 : (drop.after ? 7 : -7))
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .tourStop(section.id == "favorites" ? .favorites : nil)
    }

    private func tileGrid(_ sections: [TaskSection]) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            ForEach(moduleRows(sections), id: \.first!.id) { row in
                if row.count == 2 {
                    HStack(alignment: .top, spacing: Metrics.spacing + 3) {
                        sectionBlock(row[0])
                        sectionBlock(row[1])
                    }
                } else {
                    sectionBlock(row[0])
                }
            }
            if !isSearching {
                if TaskGroups.customGroupsEnabled { NewGroupDrop() }
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
        .confirmationDialog("Delete “\(deletingGroup?.name ?? "")”?", isPresented: Binding(
            get: { deletingGroup != nil }, set: { if !$0 { deletingGroup = nil } }
        )) {
            Button("Delete Group", role: .destructive) {
                if let id = deletingGroup?.id { withAnimation { groups.delete(id) } }
                deletingGroup = nil
            }
        } message: {
            Text("Its tasks stay in Harvest; only the group goes.")
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
        .weekReviewSheet(selectedDay: $selectedDay)
        .onChange(of: selectedDay.dayTitle(today: LocalDate()), initial: true) { _, title in
            windowActions?.setTitle(title)
        }
    }

    /// A tile shows the keyboard selection, except while the ask box's list
    /// is open: that selection belongs to the list.
    private func tileSelected(_ key: TaskKey) -> Bool {
        selection == key && !(asksFirst && askListOpen && !isSearching)
    }

    private func mainColumn(_ sections: [TaskSection]) -> some View {
        // Only the empty box shows Recent and Suggested; skip them while typing.
        let askRecent = isSearching ? [] : askRecentItems
        let askSuggested = isSearching ? [] : askSuggestedItems(excluding: Set(askRecent.map(\.id)))
        let showsAskList = asksFirst && askListOpen && !isSearching && !(askRecent.isEmpty && askSuggested.isEmpty)
        // Keyboard selection walks the ask box's list when it's open, and
        // otherwise skips folded sections.
        let flat = showsAskList
            ? (askRecent + askSuggested).map(\.task)
            : sections.filter { isSearching || !collapsed.contains($0.id) }.flatMap(\.tasks)
        return VStack(spacing: 0) {
            if asksFirst {
                // Ask first: the big box is always there, focused when the window opens.
                searchField(flat, large: true, listsTasks: showsAskList)
                    .tourStop(.ask)
                    .background {
                        #if os(macOS)
                        GeometryReader { geometry in
                            let frame = geometry.frame(in: .global)
                            Color.clear
                                .onAppear { AskFieldGeometry.frame = frame }
                                .onChange(of: frame) { _, new in AskFieldGeometry.frame = new }
                                .onDisappear { AskFieldGeometry.frame = .zero }
                        }
                        #endif
                    }
                    .popover(isPresented: $isPlanning, arrowEdge: .bottom) {
                        PlanDayView(day: selectedDay, initialText: planText)
                    }
                    .overlay(alignment: .top) {
                        if showsAskList {
                            AskDropdown(
                                recent: askRecent, suggested: askSuggested, selection: selection,
                                runningKey: tracker.running?.key, pick: pick
                            )
                            .fixedSize(horizontal: false, vertical: true)
                            .offset(y: 50)
                            .onHover { hovering in
                                isHoveringAskList = hovering
                                if !hovering && !searchFocused { askListOpen = false }
                            }
                            .transition(.opacity.combined(with: .offset(y: -4)))
                        }
                    }
                    .animation(.easeOut(duration: 0.12), value: showsAskList)
                    .padding(.horizontal, Metrics.padding)
                    .padding(.top, 14)
                    .padding(.bottom, 2)
                    .zIndex(1)
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
                    // Right under the ask box, the day strip sits a little closer.
                    .padding(.top, isSearching ? 10 : (asksFirst ? 6 : Metrics.padding))
                    .padding(.bottom, isSearching ? 10 : Metrics.padding)
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
                    // The ask list's selection is its own; the window behind stays put.
                    guard let key, !showsAskList else { return }
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(key) }
                }
            }
            .opacity(showsAskList ? 0.35 : 1)
            .animation(.easeOut(duration: 0.12), value: showsAskList)
            .overlay(alignment: .bottom) {
                if let toast = tracker.toast {
                    UndoToastView(toast: toast)
                        .padding(.horizontal, Metrics.padding)
                        .padding(.bottom, 12)
                        .transition(.opacity.combined(with: .offset(y: 8)))
                }
            }
            .animation(.snappy(duration: 0.2), value: tracker.toast)

            if let error = tracker.errorMessage {
                ErrorBanner(message: error) { tracker.errorMessage = nil }
            }
            if let picked = retiredPick, let definition = picked.definition {
                RetiredBucketNote(task: picked, definition: definition) { retiredPick = nil }
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
                // The planner, with whatever's in the ask box.
                Button("") { openPlanner(with: query) }
                    .keyboardShortcut("p", modifiers: .command)
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
    /// `listsTasks`: the ask box's list is open, so ↑↓ go row by row.
    private func searchField(_ flat: [TrackableTask], large: Bool = false, listsTasks: Bool = false) -> some View {
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
                .onKeyPress(.downArrow) {
                    // ↓ in the empty box opens the list.
                    if large, !isSearching, !listsTasks {
                        selection = nil
                        askListOpen = true
                        return .handled
                    }
                    // The list highlights its first row before you press anything.
                    if listsTasks, selection == nil { selection = flat.dropFirst().first?.key ?? flat.first?.key; return .handled }
                    moveSelection(by: isSearching || listsTasks ? 1 : columnCount, in: flat)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    // From the first result, up goes back to the "Add …" row.
                    if isSearching, !quickPlan.isEmpty, selection == flat.first?.key { selection = nil; return .handled }
                    if listsTasks, selection == nil { return .handled }
                    moveSelection(by: isSearching || listsTasks ? -1 : -columnCount, in: flat)
                    return .handled
                }
                .onKeyPress(.rightArrow) {
                    guard selection != nil, !listsTasks else { return .ignored }
                    moveSelection(by: 1, in: flat)
                    return .handled
                }
                .onKeyPress(.leftArrow) {
                    guard selection != nil, !listsTasks else { return .ignored }
                    moveSelection(by: -1, in: flat)
                    return .handled
                }
                .onSubmit {
                    if let command = askCommand { return applyCommand(command) }
                    if describesDay { return openPlanner(with: query) }
                    if !helpAnswers.isEmpty { return }
                    let plan = quickPlan
                    if selection == nil, !plan.isEmpty { return addQuickPlan(plan) }
                    guard let key = selection ?? (isSearching || listsTasks ? flat.first?.key : nil),
                          let task = flat.first(where: { $0.key == key }) else { return }
                    pick(task)
                }
                .onExitCommand {
                    if pickedProject != nil {
                        backToProjects()
                    } else if !query.isEmpty {
                        query = ""
                    } else if listsTasks {
                        // The list first; the next Escape puts the window away.
                        askListOpen = false
                        selection = nil
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
        // A click anywhere in the big box, not only on its text, puts you in
        // it with Recent and Suggested open.
        .contentShape(Rectangle())
        .onTapGesture {
            guard large else { return }
            searchFocused = true
            if asksFirst && !isSearching { selection = nil; askListOpen = true }
        }
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
        askListOpen = false
        retiredPick = task.definition?.isRetired == true && tracker.running?.key != task.key ? task : nil
        Task { await tracker.toggle(task) }
    }

    /// Return on a command's preview: does it, if it can.
    private func applyCommand(_ command: AskCommandPreview) {
        guard command.plan.isReady else { return }
        query = ""
        selection = nil
        Task { await tracker.perform(command.plan) }
    }

    #if os(macOS)
    /// Recent work for the ask box's list, with when you last did it. Not the
    /// running timer: Return on the first row should start something, never
    /// pause what you're doing.
    private var askRecentItems: [AskItem] {
        tracker.recentTasks.filter { $0.key != tracker.running?.key && tracker.isAvailable($0.key) }
            .map { AskItem(task: $0, reason: tracker.lastTrackedLabel($0.key), isSuggestion: false) }
    }

    /// Up to four suggestions: what's on screen first (Toggl's Smart
    /// Suggestions), then a matched meeting coming up today, then habits.
    private func askSuggestedItems(excluding shown: Set<TaskKey>) -> [AskItem] {
        var seen = shown
        var items: [AskItem] = []
        if suggestsFromScreen, let context = recorder?.lastExternal, let match = tracker.suggestion(for: context),
           match.task.key != tracker.running?.key {
            // Shown even if it's also a recent task: it's the best guess.
            seen.insert(match.task.key)
            items.append(AskItem(task: match.task, reason: "in \(context.app)", isSuggestion: true))
        }
        for (task, reason) in upcomingMeetingTasks() where seen.insert(task.key).inserted {
            items.append(AskItem(task: task, reason: reason, isSuggestion: true))
        }
        for task in tracker.suggestedTasks where seen.insert(task.key).inserted {
            items.append(AskItem(task: task, reason: tracker.habitLabel(task.key), isSuggestion: true))
        }
        return Array(items.prefix(4))
    }

    /// Matched meetings happening now or in the next three hours, not yet logged.
    private func upcomingMeetingTasks() -> [(TrackableTask, String)] {
        guard let calendar, calendar.access == .granted else { return [] }
        let now = Date()
        let today = LocalDate(now)
        return calendar.meetings(from: today, through: today)
            .filter { $0.end > now && $0.start < now.addingTimeInterval(3 * 3600) }
            .compactMap { meeting -> (TrackableTask, String)? in
                guard case .upcoming(let suggestion?) = tracker.status(of: meeting, at: now) else { return nil }
                let when = meeting.start <= now ? "meeting now" : "meeting at \(meeting.start.formatted(date: .omitted, time: .shortened))"
                return (suggestion.task, when)
            }
            .prefix(2)
            .map { $0 }
    }
    #endif

    /// What the ask box suggests you can type: a search, then a few entries
    /// built from your own recent work.
    private var askExamples: [String] {
        let recent = tracker.recentTasks.filter { tracker.isAvailable($0.key) }.prefix(3)
        var out = ["What are you working on?"]
        let minutes = ["10 min", "an hour", "30 min"]
        for (i, task) in recent.enumerated() {
            out.append("\(minutes[i % minutes.count]) on \(task.projectNameParts.name)")
            if i == 0 { out.append("Search a project, client or code") }
        }
        if out.count == 1 { out += ["10 min on Website Redesign", "Search a project, client or code"] }
        return out
    }

    /// Hands the ask box's sentence to the planner, which matches each piece
    /// of work to a task and lets you check them before anything's added.
    private func openPlanner(with text: String) {
        planText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        query = ""
        selection = nil
        askListOpen = false
        isPlanning = true
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
                        Text(task.projectNameParts.name + " · " + task.task.name + (tracker.isAvailable(task.key) ? "" : " (Archived)"))
                    } icon: {
                        Image(systemName: isRunning ? "pause.fill" : "play.fill")
                    }
                }
                .disabled(!tracker.isAvailable(task.key))
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
            favoritesMenu
                .padding(.trailing, 2)
            if asksFirst {
                Spacer()
            } else if isSearchOpen || !query.isEmpty {
                searchField(flat)
                    .popover(isPresented: $isPlanning, arrowEdge: .top) {
                        PlanDayView(day: selectedDay, initialText: planText)
                    }
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

            FooterButton(systemImage: "book.closed", help: "Guide: what each time-tracking code is for") {
                showingGuide.toggle()
            }
            .popover(isPresented: $showingGuide, arrowEdge: .bottom) { GuideView() }
            FooterButton(systemImage: "bubble.left", help: "Send feedback: a bug, a question or an idea") {
                openURL(Self.feedbackURL)
            }
            FooterButton(help: "Open Harvest", action: { if let url = tracker.harvestWebURL { openURL(url) } }) {
                HarvestMark()
            }

            Menu {
                if let windowActions {
                    Toggle("Keep on Top", isOn: Binding(
                        get: { windowActions.isKeptOnTop() },
                        set: { windowActions.setKeptOnTop($0) }
                    ))
                    Button("Move Below Menu Bar Icon") { windowActions.snapToMenuBar() }
                    Button("Reset Window Size") { windowActions.resetSize() }
                    Divider()
                }
                Picker("Appearance", selection: Binding(get: { appearanceRaw }, set: {
                    appearanceRaw = $0
                    AppAppearance.set(AppAppearance(rawValue: $0) ?? .system)
                })) {
                    ForEach(AppAppearance.allCases) { Text($0.label).tag($0.rawValue) }
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
                Button("Review Week…") { WeekReviewPresenter.shared.isPresented = true }
                if TaskGroups.customGroupsEnabled {
                    Button("New Group") { withAnimation(.snappy(duration: 0.2)) { _ = TaskGroups.shared.create() } }
                }
                if let openSummary = windowActions?.openWeeklySummary {
                    Button("Weekly Summary…") { openSummary(nil) }
                }
                if let open = windowActions?.openPreferences {
                    Button("Preferences…") { open() }
                        .keyboardShortcut(",", modifiers: .command)
                }
                Button("Sign Out of \(tracker.accountName ?? "Harvest")") { tracker.signOut() }
                Divider()
                Button("Quit \(AppInfo.name)") { NSApplication.shared.terminate(nil) }
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
            .tourStop(.settings)
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
                    if let toast = tracker.toast {
                        UndoToastView(toast: toast)
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
/// Where a dragged section would land: before or after `target`.
struct SectionDrop: Equatable {
    var target: String
    var after: Bool
}

private struct SectionDropDelegate: DropDelegate {
    let target: String
    let size: CGSize
    /// Half-width targets split left/right; full-width ones top/bottom.
    let sideBySide: Bool
    let dragged: String
    @Binding var drop: SectionDrop?
    let perform: (_ after: Bool) -> Void

    private func after(_ info: DropInfo) -> Bool {
        sideBySide ? info.location.x > size.width / 2 : info.location.y > size.height / 2
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let next = SectionDrop(target: target, after: after(info))
        if drop != next { withAnimation(.easeOut(duration: 0.12)) { drop = next } }
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if drop?.target == target { withAnimation(.easeOut(duration: 0.12)) { drop = nil } }
    }

    func performDrop(info: DropInfo) -> Bool {
        perform(after(info))
        return true
    }
}

/// "+ New Group" under the sections: click to make one and name it, or drop
/// a task on it to start a group with that task.
private struct NewGroupDrop: View {
    @State private var isTargeted = false
    @State private var isHovered = false

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { _ = TaskGroups.shared.create() }
        } label: {
            Label(isTargeted ? "Drop to start a new group" : "New Group", systemImage: "plus")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isTargeted || isHovered ? AnyShapeStyle(.harvestOrange) : AnyShapeStyle(.tertiary))
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.tileCorner, style: .continuous)
                        .strokeBorder(Color.harvestOrange.opacity(isTargeted ? 0.6 : isHovered ? 0.35 : 0.15),
                                      style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Make a group of your own, like Active Projects. Drop a task here to start one with it.")
        .dropDestination(for: String.self) { items, _ in
            guard let key = items.first.flatMap(TaskKey.init) else { return false }
            withAnimation(.snappy(duration: 0.2)) { _ = TaskGroups.shared.create(with: key) }
            return true
        } isTargeted: { isTargeted = $0 }
    }
}

/// A group's name being typed, in place of its title. Return or clicking
/// away saves it; Escape keeps the old one.
private struct GroupNameField: View {
    @Binding var text: String
    let done: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.harvestOrange)
            TextField("Group name", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .focused($focused)
                .onSubmit(done)
                .onExitCommand { TaskGroups.shared.renaming = nil }
        }
        .padding(.leading, 4)
        .onAppear { DispatchQueue.main.async { focused = true } }
        .onChange(of: focused) { _, isFocused in if !isFocused { done() } }
    }
}

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

/// "Moved 0:20 to Dallas Art Fair · Undo", after any change to time, so
/// nothing needs asking first. Redo after an undo. Goes away on its own.
private struct UndoToastView: View {
    @Environment(TimeTracker.self) private var tracker
    let toast: UndoToast

    var body: some View {
        HStack(spacing: 10) {
            Text(toast.message)
                .font(.system(size: 12.5))
                .lineLimit(1)
                .truncationMode(.middle)
            Button(toast.action == .undo ? "Undo" : "Redo") {
                Task { toast.action == .undo ? await tracker.undo() : await tracker.redo() }
            }
            .buttonStyle(SoftPillButtonStyle())
            .disabled(toast.action == .undo ? !tracker.canUndo : !tracker.canRedo)
            .help(toast.action == .undo ? "Undo (⌘Z)" : "Redo (⇧⌘Z)")
            Button { tracker.dismissToast() } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Dismiss")
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
        .background {
            Capsule().fill(Color.tileBackground)
                .shadow(color: .black.opacity(0.16), radius: 10, y: 3)
        }
        .overlay(Capsule().strokeBorder(Color.hairline))
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .task(id: toast.id) {
            try? await Task.sleep(for: .seconds(8))
            if tracker.toast?.id == toast.id { tracker.dismissToast() }
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
private struct FooterButton<Icon: View>: View {
    let help: String
    let action: () -> Void
    @ViewBuilder var icon: Icon
    @State private var isHovered = false

    init(systemImage: String, help: String, action: @escaping () -> Void) where Icon == Image {
        self.help = help
        self.action = action
        self.icon = Image(systemName: systemImage)
    }

    init(help: String, action: @escaping () -> Void, @ViewBuilder icon: () -> Icon) {
        self.help = help
        self.action = action
        self.icon = icon()
    }

    var body: some View {
        Button(action: action) {
            icon
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
    @Environment(\.windowActions) private var windowActions
    @Binding var selectedDay: LocalDate
    /// The Time Summary, shown while the pointer rests on the week total.
    @State private var showingSummary = false
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        let today = LocalDate()
        TimelineView(.periodic(from: .now, by: 30)) { context in
            ZStack {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(selectedDay.dayTitle(today: today))
                        .font(.system(size: 13, weight: .semibold))
                    let week = "Week \(TimeFormat.hoursMinutes(tracker.weekSeconds(containing: selectedDay, at: context.date)))"
                    if let openSummary = windowActions?.openWeeklySummary {
                        // The week total opens the Weekly Summary.
                        WeeklySummaryButton(title: week) {
                            showingSummary = false
                            openSummary(selectedDay)
                        }
                        .onHover(perform: hoverWeek)
                        .popover(isPresented: $showingSummary, arrowEdge: .bottom) { TimeSummary() }
                    } else {
                        Text(week)
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .opacity(0.8)
                            .onHover(perform: hoverWeek)
                            .popover(isPresented: $showingSummary, arrowEdge: .bottom) { TimeSummary() }
                    }
                }
                .lineLimit(1)

                HStack(spacing: 2) {
                    Spacer()
                    if let openWeek = windowActions?.openWeekCalendar {
                        Button { openWeek() } label: {
                            Image(systemName: "rectangle.split.3x1")
                        }
                        .buttonStyle(TitleBarButtonStyle())
                        .keyboardShortcut("k", modifiers: .command)
                        .help("Week calendar, with your meetings (⌘K)")
                        .accessibilityLabel("Week calendar")
                    }
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

                }
                .padding(.trailing, 10)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Self.barColor)
    }
}

extension TitleBar {
    /// Today, yesterday, this week and this month, after the pointer rests
    /// on the week total for a moment; gone when it leaves.
    func hoverWeek(_ inside: Bool) {
        hoverTask?.cancel()
        if inside {
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(450))
                if !Task.isCancelled { showingSummary = true }
            }
        } else {
            showingSummary = false
        }
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
/// "Turn this into entries": the ask box read a sentence about your day.
/// Return opens the planner with it, already matched.
private struct PlanSentenceRow: View {
    let day: LocalDate
    let open: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 8) {
                Image(systemName: "text.badge.plus")
                    .font(.system(size: 14))
                VStack(alignment: .leading, spacing: 1) {
                    Text(day == LocalDate() ? "Turn this into entries for today" : "Turn this into entries for \(day.dayTitle(today: LocalDate()))")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Matches each part to a task. You check them before anything's added.")
                        .font(.system(size: 11.5))
                        .opacity(0.8)
                        .lineLimit(2)
                }
                Spacer(minLength: 6)
                Text("⏎").font(.system(size: 11, weight: .medium)).opacity(0.8)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.harvestOrange.opacity(isHovered ? 0.9 : 1)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .onHover { isHovered = $0 }
        #endif
    }
}

/// One answer to a question about the app, typed into the ask box.
private struct HelpAnswerRow: View {
    let topic: HelpTopic

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.harvestOrange)
            VStack(alignment: .leading, spacing: 2) {
                Text(topic.question)
                    .font(.system(size: 13, weight: .semibold))
                Text(topic.answer)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}

/// Remembers what the ask box's text means for one keystroke: the command
/// preview, whether it's a sentence for the planner, the quick "30m on X"
/// plan, and the search results. A plain class, so filling it doesn't
/// redraw anything. It starts over when the text or the day's data changes.
final class AskCache {
    struct Reading {
        var command: AskCommandPreview?
        var describesDay = false
        var help: [HelpTopic] = []
        var quickPlan: [PlannedEntry] = []
        var results: [TrackableTask] = []
    }

    private var key: [AnyHashable] = []
    private var cached = Reading()

    @MainActor func reading(_ query: String, isSearching: Bool, tracker: TimeTracker) -> Reading {
        guard isSearching else { return Reading() }
        let key: [AnyHashable] = [query, tracker.tasks.count, tracker.todayEntries.map(\.id), tracker.running?.id,
                                  tracker.favorites.set, Int(Date().timeIntervalSince1970 / 30)]
        if key == self.key { return cached }
        var reading = Reading()
        reading.command = tracker.askCommand(query)
        if reading.command == nil, AppHelp.isQuestion(query) {
            reading.help = AppHelp.answers(for: query)
        }
        if reading.command == nil, reading.help.isEmpty {
            reading.describesDay = DayPlanner.describesWork(query)
            if !reading.describesDay {
                reading.quickPlan = tracker.quickPlan(query)
                reading.results = tracker.search(query)
            }
        }
        self.key = key
        cached = reading
        return reading
    }
}

/// Harvest's mark for "Open Harvest": its three rounded strokes, in one
/// color like the other footer icons, so it follows light and dark.
private struct HarvestMark: View {
    var body: some View {
        Canvas { context, size in
            // Drawn on a 32 × 60 grid, then scaled to fit.
            let scale = min(size.width / 32, size.height / 60)
            let dx = (size.width - 32 * scale) / 2, dy = (size.height - 60 * scale) / 2
            func bar(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
                Path(roundedRect: CGRect(x: dx + x * scale, y: dy + y * scale, width: w * scale, height: h * scale),
                     cornerRadius: w * scale / 2)
            }
            var path = Path()
            path.addPath(bar(0, 22, 8, 26))      // short left stroke
            path.addRect(CGRect(x: dx + 6 * scale, y: dy + 30 * scale, width: 9 * scale, height: 7 * scale))
            path.addPath(bar(13, 15, 8, 45))     // middle stroke
            path.addPath(bar(24, 0, 8, 60))      // tall right stroke
            context.fill(path, with: .foreground)
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }
}

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
