import HarvestKit
import SwiftUI

/// What the main area shows: the usual day + favorites view, or one slice
/// picked from the sidebar.
enum BrowseScope: Hashable {
    case everything
    case favorites
    case folder(String)
    case client(Int)
}

/// Stable, muted color per client so they're recognizable across the app.
func clientColor(_ id: Int?) -> Color {
    let palette: [Color] = [
        Color(red: 0.36, green: 0.42, blue: 0.94), Color(red: 0.07, green: 0.64, blue: 0.54),
        Color(red: 0.69, green: 0.36, blue: 0.84), Color(red: 0.86, green: 0.31, blue: 0.48),
        Color(red: 0.16, green: 0.56, blue: 0.86), Color(red: 0.42, green: 0.62, blue: 0.20),
        Color(red: 0.62, green: 0.47, blue: 0.33),
    ]
    guard let id else { return .gray }
    return palette[abs(id) % palette.count]
}

// MARK: Sidebar

struct SidebarView: View {
    @Environment(TimeTracker.self) private var tracker
    @Binding var scope: BrowseScope
    @State private var renaming: String?
    @State private var draftName = ""
    @State private var dropTarget: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        let favorites = tracker.favorites
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                row(.everything, title: "Everything", icon: "square.grid.2x2", count: nil)
                row(.favorites, title: "Favorites", icon: "star.fill", count: favorites.keys.count)

                header("Folders") {
                    Button {
                        let name = favorites.createFolder()
                        scope = .folder(name)
                        startRename(name)
                    } label: {
                        Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .help("New folder")
                }
                if favorites.folders.isEmpty {
                    Text("Make folders to group favorites, then drag tiles onto them.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(favorites.folders, id: \.self) { folder in
                    folderRow(folder)
                }

                header("Clients") { EmptyView() }
                ForEach(tracker.clients, id: \.id) { client in
                    row(.client(client.id), title: client.name, dot: clientColor(client.id),
                        count: tracker.tasks.lazy.filter { $0.client?.id == client.id }.count)
                }
            }
            .padding(8)
        }
        .frame(width: 190)
        .background(Color.panelBackground)
    }

    private func header<Accessory: View>(_ title: String, @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.6)
            Spacer()
            accessory()
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    private func row(_ target: BrowseScope, title: String, icon: String? = nil, dot: Color? = nil, count: Int?) -> some View {
        let selected = scope == target
        return Button {
            scope = target
        } label: {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selected ? AnyShapeStyle(.harvestOrange) : AnyShapeStyle(.secondary))
                        .frame(width: 16)
                }
                if let dot {
                    Circle().fill(dot).frame(width: 8, height: 8).frame(width: 16)
                }
                Text(title).lineLimit(1)
                Spacer(minLength: 4)
                if let count {
                    Text("\(count)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                }
            }
            .font(.system(size: 13, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? AnyShapeStyle(.harvestOrange) : AnyShapeStyle(.primary))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(selected ? Color.harvestOrange.opacity(0.14) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func folderRow(_ folder: String) -> some View {
        let favorites = tracker.favorites
        if renaming == folder {
            TextField("Folder name", text: $draftName)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .onSubmit { commitRename(folder) }
                .onExitCommand { renaming = nil }
                .onChange(of: nameFocused) { _, focused in if !focused { commitRename(folder) } }
                .padding(.horizontal, 4)
                .frame(height: 28)
        } else {
            row(.folder(folder), title: folder, icon: "folder.fill", count: favorites.keys(inFolder: folder).count)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.harvestOrange, lineWidth: dropTarget == folder ? 2 : 0)
                )
                .dropDestination(for: String.self) { items, _ in
                    for raw in items { if let key = TaskKey(raw) { favorites.file(key, in: folder) } }
                    return true
                } isTargeted: { dropTarget = $0 ? folder : (dropTarget == folder ? nil : dropTarget) }
                .contextMenu {
                    Button("Rename") { startRename(folder) }
                    Button("Delete Folder", role: .destructive) {
                        if scope == .folder(folder) { scope = .favorites }
                        favorites.deleteFolder(folder)
                    }
                }
                .simultaneousGesture(TapGesture(count: 2).onEnded { startRename(folder) })
        }
    }

    private func startRename(_ folder: String) {
        draftName = folder
        renaming = folder
        Task { nameFocused = true }
    }

    private func commitRename(_ folder: String) {
        guard renaming == folder else { return }
        renaming = nil
        tracker.favorites.renameFolder(folder, to: draftName)
        let newName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if scope == .folder(folder), tracker.favorites.folders.contains(newName) { scope = .folder(newName) }
    }
}

// MARK: Scoped content

/// The main area for a sidebar selection other than Everything.
struct ScopeContent: View {
    @Environment(TimeTracker.self) private var tracker
    let scope: BrowseScope

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.title3.weight(.semibold))
                Spacer()
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            switch scope {
            case .everything:
                EmptyView()
            case .favorites:
                grid(tracker.tasks(for: tracker.favorites.keys),
                     empty: "Star a task to add it here.")
            case .folder(let name):
                grid(tracker.tasks(for: tracker.favorites.keys(inFolder: name)),
                     empty: "Drag tiles onto this folder in the sidebar, or right-click a task and choose Move to Folder.")
            case .client(let id):
                let tasks = tracker.tasks(forClient: id)
                let projects = Dictionary(grouping: tasks, by: \.project.id)
                let order = tasks.map(\.project).reduce(into: [NamedRef]()) { if !$0.contains($1) { $0.append($1) } }
                ForEach(order, id: \.id) { project in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(projects[project.id]?.first?.projectCode.map { "[\($0)] \(project.name)" } ?? project.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                        grid(projects[project.id] ?? [], empty: "")
                    }
                }
            }
        }
    }

    private var title: String {
        switch scope {
        case .everything: return "Everything"
        case .favorites: return "Favorites"
        case .folder(let name): return name
        case .client(let id): return tracker.clients.first { $0.id == id }?.name ?? "Client"
        }
    }

    private var subtitle: String {
        switch scope {
        case .everything: return ""
        case .favorites: return "\(tracker.favorites.keys.count) starred"
        case .folder(let name): return "\(tracker.favorites.keys(inFolder: name).count) tasks"
        case .client(let id): return "\(tracker.tasks(forClient: id).count) tasks"
        }
    }

    @ViewBuilder private func grid(_ tasks: [TrackableTask], empty: String) -> some View {
        if tasks.isEmpty {
            Text(empty)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: 90)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.tileCorner, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                )
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Metrics.tileMinWidth), spacing: Metrics.spacing)], spacing: Metrics.spacing) {
                ForEach(tasks) { TaskTile(task: $0) }
            }
        }
    }
}
