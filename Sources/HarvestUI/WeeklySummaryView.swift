import HarvestKit
import SwiftUI
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#else
import UIKit
#endif

/// Which week the Weekly Summary shows, so the Mac window can be pointed at
/// another week when it's opened again.
@MainActor @Observable
public final class WeeklySummaryNavigator {
    /// Nil until something picks a week: then it opens on `defaultWeek`.
    public var weekStart: LocalDate?

    public init(weekStart: LocalDate? = nil) {
        self.weekStart = weekStart
    }

    /// For Monday planning: on the week's first day there's nothing in it
    /// yet, so open on last week; otherwise this week.
    public static func defaultWeek(today: LocalDate = LocalDate(), firstWeekday: Int) -> LocalDate {
        let start = today.startOfWeek(firstWeekday: firstWeekday)
        return today == start ? start.adding(days: -7) : start
    }
}

/// Where your time went this week: the summary card with ‹ › between weeks
/// above it, and Copy as Text and Save as Image below.
public struct WeeklySummaryView: View {
    @Environment(TimeTracker.self) private var tracker
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var navigator: WeeklySummaryNavigator
    @State private var copied = false

    public init(navigator: WeeklySummaryNavigator) {
        self.navigator = navigator
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let today = LocalDate(context.date)
            let thisWeek = today.startOfWeek(firstWeekday: tracker.firstWeekday)
            let start = navigator.weekStart ?? WeeklySummaryNavigator.defaultWeek(today: today, firstWeekday: tracker.firstWeekday)
            let summary = WeeklySummary.make(entries: tracker.entries, weekStart: start, today: today, now: context.date)
            VStack(spacing: 0) {
                header(summary, thisWeek: thisWeek)
                Rectangle().fill(Color.hairline).frame(height: 1)
                ScrollView {
                    WeeklySummaryCard(summary: summary, today: today)
                        .padding(18)
                }
                Rectangle().fill(Color.hairline).frame(height: 1)
                footer(summary)
            }
            // Earlier weeks, and the few before them for the usual week,
            // load once as you page back; the tracker keeps what it has.
            .task(id: start) {
                await tracker.ensureLoaded(from: start.adding(days: -7 * WeeklySummary.usualWeeks))
                await tracker.ensureLoaded(through: start.adding(days: 6))
            }
        }
        .background(Color.panelBackground)
        .tint(.harvestOrange)
    }

    private func header(_ summary: WeeklySummary, thisWeek: LocalDate) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Weekly Summary")
                    .font(.system(size: 17, weight: .semibold))
                Text(summary.rangeTitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 0) {
                Button { move(summary.weekStart, by: -7) } label: { Image(systemName: "chevron.left").frame(width: 28, height: 26) }
                    .keyboardShortcut("[", modifiers: .command)
                    .help("Previous week (⌘[)")
                    .accessibilityLabel("Previous week")
                Button { move(summary.weekStart, by: 7) } label: { Image(systemName: "chevron.right").frame(width: 28, height: 26) }
                    .keyboardShortcut("]", modifiers: .command)
                    .help("Next week (⌘])")
                    .accessibilityLabel("Next week")
                    .disabled(summary.weekStart >= thisWeek)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12, weight: .semibold))
            Button("This Week") { navigator.weekStart = thisWeek }
                .buttonStyle(PillButtonStyle(prominent: false))
                .keyboardShortcut("t", modifiers: .command)
                .disabled(summary.weekStart == thisWeek)
                .help("Back to this week (⌘T)")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func footer(_ summary: WeeklySummary) -> some View {
        HStack(spacing: 10) {
            if copied {
                Label("Copied", systemImage: "checkmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            Spacer()
            Button { copyText(summary) } label: { Label("Copy as Text", systemImage: "doc.on.doc") }
                .buttonStyle(PillButtonStyle(prominent: false))
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .help("Copy a plain-text summary, for pasting into Slack (⇧⌘C)")
            Button { saveImage(summary) } label: { Label("Save as Image", systemImage: "square.and.arrow.down") }
                .buttonStyle(PillButtonStyle(prominent: true))
                .keyboardShortcut("s", modifiers: .command)
                .help("Save the summary card as a PNG (⌘S)")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func move(_ start: LocalDate, by days: Int) {
        withAnimation(.snappy(duration: 0.2)) { navigator.weekStart = start.adding(days: days) }
    }

    private func copyText(_ summary: WeeklySummary) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary.plainText, forType: .string)
        #else
        UIPasteboard.general.string = summary.plainText
        #endif
        withAnimation { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { copied = false }
        }
    }

    private func saveImage(_ summary: WeeklySummary) {
        guard let png = WeeklySummaryCard.png(summary, colorScheme: colorScheme) else { return }
        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Weekly Summary \(summary.weekStart).png"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? png.write(to: url)
        #else
        if let image = UIImage(data: png) { UIPasteboard.general.image = image }
        #endif
    }
}

/// The summary itself, as a card: also what Save as Image renders.
struct WeeklySummaryCard: View {
    let summary: WeeklySummary
    var today = LocalDate()
    /// Laid out for the window and for the saved image alike.
    static let width: CGFloat = 560

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                totals.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).tile()
                days.frame(maxWidth: .infinity, maxHeight: .infinity).tile()
            }
            .fixedSize(horizontal: false, vertical: true)
            billableSplit.tile()
            if !summary.clients.isEmpty { clients.tile() }
            if !summary.topTasks.isEmpty { topTasks.tile() }
        }
        .frame(width: Self.width)
    }

    // MARK: Totals

    private var totals: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(summary.comparesThrough == nil ? "Total" : "So far this week")
            Text(TimeFormat.hoursMinutes(summary.total))
                .font(.system(size: 40, weight: .light).monospacedDigit())
                .foregroundStyle(.harvestOrange)
            VStack(alignment: .leading, spacing: 4) {
                comparison(
                    summary.change,
                    against: summary.comparesThrough.map { "last week by \($0.date().formatted(.dateTime.weekday(.wide)))" } ?? "last week",
                    reference: summary.previousTotal
                )
                if let usual = summary.usualTotal {
                    if summary.comparesThrough == nil, let change = summary.changeFromUsual {
                        comparison(change, against: "a usual week", reference: usual)
                    } else {
                        // Part of a week against a whole one says nothing; just
                        // give the yardstick.
                        HStack(spacing: 5) {
                            Image(systemName: "calendar")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Text("A usual week is \(TimeFormat.hoursMinutes(usual))")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func comparison(_ change: TimeInterval, against label: String, reference: TimeInterval) -> some View {
        let minutes = (change / 60).rounded()
        let arrow = minutes > 0 ? "arrow.up" : minutes < 0 ? "arrow.down" : "equal"
        return HStack(spacing: 5) {
            Image(systemName: arrow)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(minutes > 0 ? AnyShapeStyle(.harvestOrange) : AnyShapeStyle(.secondary))
            Text(TimeFormat.hoursMinutes(abs(change)))
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
            Text("vs \(label) (\(TimeFormat.hoursMinutes(reference)))")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }

    // MARK: Days

    private var days: some View {
        let most = max(summary.days.map(\.seconds).max() ?? 0, 8 * 3600)
        return VStack(alignment: .leading, spacing: 8) {
            sectionTitle("By day")
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(summary.days) { day in
                    let isToday = day.date == today
                    VStack(spacing: 3) {
                        Text(day.seconds > 0 ? TimeFormat.hoursMinutes(day.seconds) : "–")
                            .font(.system(size: 9, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize()
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(day.seconds > 0 ? AnyShapeStyle(Color.harvestOrange.opacity(isToday ? 1 : 0.75)) : AnyShapeStyle(Color.primary.opacity(0.07)))
                            .frame(height: max(3, 64 * day.seconds / most))
                        Text(Calendar.current.veryShortStandaloneWeekdaySymbols[day.date.weekday - 1])
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(isToday ? AnyShapeStyle(.harvestOrange) : AnyShapeStyle(.secondary))
                    }
                    .frame(maxWidth: .infinity, alignment: .bottom)
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(height: 100, alignment: .bottom)
        }
    }

    // MARK: Billable

    private var billableSplit: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Billable vs internal")
            GeometryReader { geo in
                HStack(spacing: summary.billable > 0 && summary.internal > 0 ? 2 : 0) {
                    if summary.billable > 0 {
                        Rectangle().fill(Color.harvestOrange)
                            .frame(width: geo.size.width * summary.share(summary.billable))
                    }
                    if summary.internal > 0 {
                        Rectangle().fill(Color.internalTime)
                    }
                    if summary.isEmpty { Rectangle().fill(Color.primary.opacity(0.07)) }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .frame(height: 12)
            HStack(spacing: 16) {
                legend("Billable", color: .harvestOrange, seconds: summary.billable)
                legend("Internal", color: .internalTime, seconds: summary.internal)
                Spacer()
            }
        }
    }

    private func legend(_ label: String, color: Color, seconds: TimeInterval) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.system(size: 12))
            Text(TimeFormat.hoursMinutes(seconds))
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
            Text(Self.percent(summary.share(seconds)))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Clients

    private var clients: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("By client and project")
            ForEach(summary.clients) { client in
                VStack(alignment: .leading, spacing: 5) {
                    barRow(client.name, seconds: client.seconds, weight: .semibold, barHeight: 8, color: .harvestOrange)
                    ForEach(client.projects) { project in
                        barRow(project.name, seconds: project.seconds, weight: .regular, barHeight: 5,
                               color: Color.harvestOrange.opacity(0.45))
                            .padding(.leading, 14)
                    }
                }
            }
        }
    }

    private func barRow(_ name: String, seconds: TimeInterval, weight: Font.Weight, barHeight: CGFloat, color: Color) -> some View {
        let share = summary.share(seconds)
        return HStack(spacing: 10) {
            Text(name)
                .font(.system(size: 12, weight: weight))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 180, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.06))
                    Capsule().fill(color).frame(width: max(barHeight, geo.size.width * share))
                }
            }
            .frame(height: barHeight)
            Text(TimeFormat.hoursMinutes(seconds))
                .font(.system(size: 12, weight: weight).monospacedDigit())
                .frame(width: 48, alignment: .trailing)
            Text(Self.percent(share))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Top tasks

    private var topTasks: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Top tasks")
            ForEach(Array(summary.topTasks.enumerated()), id: \.element.id) { index, task in
                HStack(spacing: 10) {
                    Text("\(index + 1)")
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundStyle(.harvestOrange)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.orangeSoft))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(task.task).font(.system(size: 12, weight: .semibold))
                        Text([task.project, task.client].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    Spacer()
                    Text(TimeFormat.hoursMinutes(task.seconds))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    Text(Self.percent(summary.share(task.seconds)))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: Pieces

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }

    static func percent(_ share: Double) -> String { "\(Int((share * 100).rounded()))%" }

    /// The card on the window's background, as PNG data at 2×, in the
    /// appearance you're looking at.
    @MainActor
    static func png(_ summary: WeeklySummary, colorScheme: ColorScheme) -> Data? {
        let content = VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Weekly Summary").font(.system(size: 17, weight: .semibold))
                Spacer()
                Text(summary.rangeTitle).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            WeeklySummaryCard(summary: summary)
        }
        .padding(20)
        .background(Color.panelBackground)
        .environment(\.colorScheme, colorScheme)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        #if os(macOS)
        // Adaptive colors resolve against the drawing appearance.
        var data: Data?
        NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            guard let cgImage = renderer.cgImage else { return }
            data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
        }
        return data
        #else
        return renderer.uiImage?.pngData()
        #endif
    }
}

private extension View {
    func tile() -> some View {
        padding(14)
            .background(RoundedRectangle(cornerRadius: Metrics.tileCorner, style: .continuous).fill(Color.tileBackground))
            .overlay(RoundedRectangle(cornerRadius: Metrics.tileCorner, style: .continuous).strokeBorder(Color.hairline))
    }
}

extension Color {
    /// Internal time next to billable orange: a warm grey.
    static var internalTime: Color {
        #if os(macOS)
        .adaptive(light: 0xB9B1A9, dark: 0x6E655D)
        #else
        Color.secondary.opacity(0.5)
        #endif
    }
}

#if DEBUG
/// For offscreen snapshots: a finished week of demo data.
@MainActor public func debugWeeklySummary(weekStart: LocalDate) -> some View {
    WeeklySummaryView(navigator: WeeklySummaryNavigator(weekStart: weekStart))
}

/// The card exactly as Save as Image renders it.
@MainActor public func debugWeeklySummaryPNG(_ tracker: TimeTracker, weekStart: LocalDate, dark: Bool) -> Data? {
    WeeklySummaryCard.png(WeeklySummary.make(entries: tracker.entries, weekStart: weekStart), colorScheme: dark ? .dark : .light)
}
#endif

/// "Summary", by the week total in the Mac window's orange title bar.
struct WeeklySummaryButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text("Summary")
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 7)
                .frame(height: 20)
                .background(Capsule().fill(Color.white.opacity(isHovered ? 0.3 : 0.18)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
        .help("Weekly Summary: where this week's time went")
    }
}

/// Where there's no Mac window to open (iPhone and iPad), the summary comes
/// up as a sheet from the week strip.
struct WeeklySummarySheetButton: View {
    let day: LocalDate
    @Environment(TimeTracker.self) private var tracker
    @Environment(\.windowActions) private var windowActions
    @State private var navigator: WeeklySummaryNavigator?

    var body: some View {
        Button {
            if let open = windowActions?.openWeeklySummary {
                open(day)
            } else {
                navigator = WeeklySummaryNavigator(weekStart: day.startOfWeek(firstWeekday: tracker.firstWeekday))
            }
        } label: {
            Image(systemName: "chart.bar.xaxis")
        }
        .buttonStyle(.borderless)
        .help("Weekly Summary")
        .accessibilityLabel("Weekly Summary")
        .sheet(isPresented: Binding(get: { navigator != nil }, set: { if !$0 { navigator = nil } })) {
            if let navigator {
                WeeklySummaryView(navigator: navigator).environment(tracker)
            }
        }
    }
}
