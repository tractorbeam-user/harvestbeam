import HarvestKit
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// "What are you working on?" Type (or dictate) the day in plain words; the
/// on-device model proposes entries, you adjust them, and they're added in one
/// go. Entries without hours start a timer when the day is today.
struct PlanDayView: View {
    @Environment(TimeTracker.self) private var tracker
    @Environment(\.dismiss) private var dismiss
    let day: LocalDate

    @State private var text = ""
    @State private var proposals: [PlannedEntry] = []
    @State private var excluded: Set<UUID> = []
    @State private var hours: [UUID: String] = [:]
    @State private var engine: DayPlanner.Engine?
    @State private var isThinking = false
    @State private var isSaving = false
    @FocusState private var textFocused: Bool

    private var isToday: Bool { day == LocalDate() }
    private var included: [PlannedEntry] { proposals.filter { !excluded.contains($0.id) } }

    /// Included entries that would be logged (with hours) or timed (without, today only).
    private var ready: [(entry: PlannedEntry, hours: Double?)] {
        included.compactMap { entry in
            let typed = hours[entry.id]?.trimmingCharacters(in: .whitespaces) ?? ""
            if typed.isEmpty { return isToday ? (entry, nil) : nil }
            return EntryEditor.parseHours(typed).map { (entry, $0) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isToday ? "What are you working on today?" : "What did you work on · \(day.dayTitle(today: LocalDate()))")
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity)

            TextField("Plan", text: $text, prompt: Text("e.g. Context design all morning, an hour on the LP Analyst site, then a client call"), axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($textFocused)
                .padding(10)
                .padding(.trailing, 26)
                .background(field)
                .overlay(alignment: .bottomTrailing) { micButton }

            Label(DayPlanner.modelAvailable
                  ? "Matched on your Mac with Apple Intelligence."
                  : "Keyword matching. Turn on Apple Intelligence in System Settings for smarter matches.",
                  systemImage: DayPlanner.modelAvailable ? "sparkles" : "text.magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Color.secondary)

            if isThinking {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Matching your tasks…").font(.system(size: 12)).foregroundStyle(Color.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            } else if engine != nil {
                if proposals.isEmpty {
                    Text("Couldn't match that to your tasks. Try naming the project.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                } else {
                    VStack(spacing: 0) {
                        ForEach($proposals) { $entry in
                            row($entry)
                            if entry.id != proposals.last?.id { Divider().padding(.leading, 34) }
                        }
                    }
                    .background(field)
                }
            }

            HStack(spacing: 8) {
                if engine != nil, !proposals.isEmpty {
                    Button("Try Again") { suggest() }
                        .buttonStyle(.borderless)
                        .font(.system(size: 12))
                        .disabled(isThinking)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(PillButtonStyle(prominent: false))
                if engine == nil || proposals.isEmpty {
                    Button("Suggest Entries") { suggest() }
                        .keyboardShortcut(.return, modifiers: .command)
                        .buttonStyle(PillButtonStyle(prominent: true))
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isThinking)
                } else {
                    Button(addLabel) { add() }
                        .keyboardShortcut(.return, modifiers: .command)
                        .buttonStyle(PillButtonStyle(prominent: true))
                        .disabled(ready.isEmpty || isSaving)
                }
            }
        }
        .padding(16)
        .frame(width: 400)
        .foregroundStyle(Color.primary)
        .presentationBackground(Color.tileBackground)
        .onAppear { textFocused = true }
    }

    private var addLabel: String {
        let timers = ready.filter { $0.hours == nil }.count
        let logged = ready.count - timers
        switch (logged, timers) {
        case (0, _): return "Start Timer"
        case (_, 0): return logged == 1 ? "Add Entry" : "Add \(logged) Entries"
        default: return "Add \(logged) & Start Timer"
        }
    }

    private func row(_ entry: Binding<PlannedEntry>) -> some View {
        let id = entry.wrappedValue.id
        let task = entry.wrappedValue.task
        let isIncluded = !excluded.contains(id)
        let (code, name) = task.projectNameParts
        return HStack(spacing: 10) {
            Button {
                if isIncluded { excluded.insert(id) } else { excluded.remove(id) }
            } label: {
                Image(systemName: isIncluded ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(isIncluded ? AnyShapeStyle(.harvestOrange) : AnyShapeStyle(.tertiary))
            }
            .buttonStyle(.plain)
            .help(isIncluded ? "Leave this one out" : "Include it")

            VStack(alignment: .leading, spacing: 1) {
                if let code {
                    Text(code).font(.system(size: 10, weight: .medium).monospaced()).foregroundStyle(Color.secondary)
                }
                Text(name).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                // Same project, different task.
                Menu {
                    ForEach(tracker.tasks.filter { $0.project.id == task.project.id }.sorted { $0.task.name < $1.task.name }) { other in
                        Button(other.task.name) { entry.wrappedValue.task = other }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(task.task.name).lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondary)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .opacity(isIncluded ? 1 : 0.45)

            Spacer(minLength: 6)

            TextField("Hours", text: Binding(get: { hours[id] ?? "" }, set: { hours[id] = $0 }),
                      prompt: Text(isToday ? "timer" : "0:00"))
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .frame(width: 52)
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.12)))
                .help(isToday ? "h:mm or decimal. Leave empty to start a timer." : "h:mm or decimal")
                .disabled(!isIncluded)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    /// Starts the Mac's own dictation in the text box, same as pressing fn
    /// twice (macOS offers to turn dictation on if it's off).
    private var micButton: some View {
        Button {
            textFocused = true
            #if os(macOS)
            DispatchQueue.main.async {
                NSApp.sendAction(Selector(("startDictation:")), to: nil, from: nil)
            }
            #endif
        } label: {
            Image(systemName: "mic.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.harvestOrange)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.harvestOrange.opacity(0.13)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(6)
        .help("Dictate (or press fn twice)")
        .accessibilityLabel("Start dictation")
    }

    private var field: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.panelBackground.opacity(0.5))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
    }

    private func suggest() {
        let text = text
        isThinking = true
        Task {
            let result = await tracker.planDay(text)
            proposals = result.entries
            engine = result.engine
            excluded = []
            hours = Dictionary(uniqueKeysWithValues: result.entries.map { ($0.id, $0.hours.map { TimeFormat.hoursMinutes($0 * 3600) } ?? "") })
            isThinking = false
        }
    }

    /// Logs the entries with hours, then starts the first timer one (today).
    private func add() {
        let items = ready
        isSaving = true
        Task {
            for item in items where item.hours != nil {
                await tracker.addEntry(task: item.entry.task, on: day, notes: item.entry.notes, hours: item.hours)
            }
            if let timer = items.first(where: { $0.hours == nil }) {
                await tracker.addEntry(task: timer.entry.task, on: day, notes: timer.entry.notes, hours: nil)
            }
            isSaving = false
            dismiss()
        }
    }
}
