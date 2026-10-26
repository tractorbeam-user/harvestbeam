import Foundation

/// A stretch of time in one app and window, like a row in Toggl's Timeline.
public struct ActivitySpan: Codable, Hashable, Sendable, Identifiable {
    public var app: String
    public var bundleID: String
    /// The front window's title; empty without Accessibility access.
    public var title: String
    /// The website, for browsers: "ads.google.com".
    public var host: String?
    public var start: Date
    public var end: Date
    /// The task whose timer was running meanwhile, if any.
    public var trackedKey: TaskKey?

    public init(app: String, bundleID: String, title: String, host: String? = nil, start: Date, end: Date, trackedKey: TaskKey? = nil) {
        self.app = app
        self.bundleID = bundleID
        self.title = title
        self.host = host
        self.start = start
        self.end = end
        self.trackedKey = trackedKey
    }

    public var id: String { "\(bundleID)@\(start.timeIntervalSince1970)" }
    public var seconds: TimeInterval { max(0, end.timeIntervalSince(start)) }
    /// "Figma · Pinstripes – Homepage v3", "Chrome · ads.google.com".
    public var label: String {
        let detail = [title, host ?? ""].first { !$0.isEmpty } ?? ""
        return detail.isEmpty ? app : "\(app) · \(detail)"
    }
}

/// Time spent with no timer running, grouped so it can be logged in one go.
public struct ActivityStretch: Identifiable, Hashable, Sendable {
    public let spans: [ActivitySpan]
    public var start: Date { spans.first?.start ?? .distantPast }
    public var end: Date { spans.last?.end ?? .distantPast }
    /// Time actually in apps, not counting short gaps between them.
    public var seconds: TimeInterval { spans.reduce(0) { $0 + $1.seconds } }
    public var id: String { "activity@\(Int(start.timeIntervalSince1970))" }

    /// The spans' labels, most time first; ties go to the earlier one.
    public var topLabels: [String] {
        var order: [String] = []
        var seconds: [String: TimeInterval] = [:]
        for span in spans {
            if seconds[span.label] == nil { order.append(span.label) }
            seconds[span.label, default: 0] += span.seconds
        }
        return order.enumerated().sorted { a, b in
            seconds[a.element]! != seconds[b.element]! ? seconds[a.element]! > seconds[b.element]! : a.offset < b.offset
        }.map(\.element)
    }

    /// As a meeting-shaped item, so it logs, matches and remembers like one.
    public var asMeeting: CalendarMeeting {
        CalendarMeeting(id: id, title: topLabels.first ?? "Activity", start: start,
                        end: start.addingTimeInterval(seconds), isActivity: true, context: mainContext)
    }

    /// The app and window this stretch spent the most time in.
    public var mainContext: ScreenContext? {
        guard let label = topLabels.first, let span = spans.first(where: { $0.label == label }) else { return nil }
        return ScreenContext(app: span.app, bundleID: span.bundleID, title: span.title, host: span.host)
    }
}

public enum Timeline {
    /// Toggl's Timeline keeps what you looked at for more than 10 seconds.
    public static let minimumSpan: TimeInterval = 10

    /// Untracked spans run together into stretches when they're less than
    /// `maxGap` apart; stretches under `minTotal` aren't worth logging.
    public static func untrackedStretches(_ spans: [ActivitySpan], maxGap: TimeInterval = 180, minTotal: TimeInterval = 300) -> [ActivityStretch] {
        var stretches: [[ActivitySpan]] = []
        for span in spans.sorted(by: { $0.start < $1.start }) where span.trackedKey == nil {
            if let last = stretches.last?.last, span.start.timeIntervalSince(last.end) <= maxGap {
                stretches[stretches.count - 1].append(span)
            } else {
                stretches.append([span])
            }
        }
        return stretches.map(ActivityStretch.init).filter { $0.seconds >= minTotal }
    }
}

/// The Timeline on disk: one JSON file per day in Application Support, kept
/// two weeks. Nothing here leaves the Mac.
@MainActor
public final class TimelineStore {
    public static let keepDays = 14
    private let folder: URL
    private var cache: [LocalDate: [ActivitySpan]] = [:]

    public init(folder: URL? = nil) {
        self.folder = folder ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Harvestbeam/Timeline", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.folder, withIntermediateDirectories: true)
    }

    public func spans(on day: LocalDate) -> [ActivitySpan] {
        if let cached = cache[day] { return cached }
        let loaded = (try? Data(contentsOf: file(for: day))).flatMap { try? JSONDecoder().decode([ActivitySpan].self, from: $0) } ?? []
        cache[day] = loaded
        return loaded
    }

    /// Adds a span, joining it to the last one when it's the same app and
    /// window carried on (a quick look away and back).
    public func append(_ span: ActivitySpan) {
        guard span.seconds > Timeline.minimumSpan else { return }
        let day = LocalDate(span.start)
        var spans = spans(on: day)
        if var last = spans.last, last.bundleID == span.bundleID, last.title == span.title, last.host == span.host,
           last.trackedKey == span.trackedKey, span.start.timeIntervalSince(last.end) < 30 {
            last.end = span.end
            spans[spans.count - 1] = last
        } else {
            spans.append(span)
        }
        cache[day] = spans
        if let data = try? JSONEncoder().encode(spans) { try? data.write(to: file(for: day), options: .atomic) }
    }

    /// Drops days past `keepDays`.
    public func prune(today: LocalDate = LocalDate()) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in names {
            guard let day = LocalDate(string: String(name.dropLast(5))), day.days(until: today) > Self.keepDays else { continue }
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
            cache[day] = nil
        }
    }

    public func deleteAll() {
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        cache = [:]
    }

    private func file(for day: LocalDate) -> URL {
        folder.appendingPathComponent("\(day).json")
    }
}
