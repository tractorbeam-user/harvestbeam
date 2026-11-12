import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: Model

/// One stop on the first-run tour, in the order they're shown.
public enum TourStop: Int, CaseIterable, Sendable {
    case ask, days, entries, favorites, shortcut, settings

    /// For snapshot file names.
    public var name: String { String(describing: self) }
}

/// The first-run tour: after onboarding, the main window dims and a spotlight
/// walks through its main features one at a time. Each feature marks itself
/// with `.tourStop(_:)`, so the spotlight follows the real view's frame.
@MainActor @Observable
public final class TourModel {
    /// Set once the tour has been finished or skipped.
    public static let seenKey = "tour.seen"

    /// The stop on screen, or nil when the tour isn't running.
    public var current: TourStop?
    /// How the window's show/hide shortcut reads, like "⌥H"; nil when there isn't one.
    public var shortcut: String?

    public init(shortcut: String? = nil) {
        self.shortcut = shortcut
    }

    public static var hasBeenSeen: Bool { UserDefaults.standard.bool(forKey: seenKey) }

    /// Starts from the top, whether or not it's been seen.
    public func start() {
        current = TourStop.allCases.first
    }

    /// Starts unless it's been finished or skipped before.
    public func startIfUnseen() {
        guard !Self.hasBeenSeen, current == nil else { return }
        start()
    }

    public func next() {
        guard let current else { return }
        if let following = TourStop(rawValue: current.rawValue + 1) {
            self.current = following
        } else {
            finish()
        }
    }

    public func back() {
        guard let current, let previous = TourStop(rawValue: current.rawValue - 1) else { return }
        self.current = previous
    }

    /// Done or skipped: either way, don't show it again on its own.
    public func finish() {
        current = nil
        UserDefaults.standard.set(true, forKey: Self.seenKey)
    }
}

// MARK: Hooks

/// Every marked view's bounds, by stop. A stop can be marked on more than one
/// view (the day strip and the short-day nudge); the spotlight covers them all.
struct TourAnchorsKey: PreferenceKey {
    static let defaultValue: [TourStop: [Anchor<CGRect>]] = [:]
    static func reduce(value: inout [TourStop: [Anchor<CGRect>]], nextValue: () -> [TourStop: [Anchor<CGRect>]]) {
        value.merge(nextValue()) { $0 + $1 }
    }
}

extension View {
    /// Marks this view as (part of) a tour stop. Pass nil to mark nothing,
    /// for views that are a stop only some of the time.
    func tourStop(_ stop: TourStop?) -> some View {
        modifier(TourStopModifier(stop: stop))
    }

    /// Draws the tour over this view while it's running, spotlighting the
    /// views marked with `.tourStop(_:)` inside it.
    func tourOverlay(_ tour: TourModel?) -> some View {
        overlayPreferenceValue(TourAnchorsKey.self) { anchors in
            if let tour, let stop = tour.current {
                GeometryReader { proxy in
                    TourOverlay(tour: tour, stop: stop, spotlight: Self.spotlight(anchors[stop], in: proxy), size: proxy.size)
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: tour?.current == nil)
    }

    private static func spotlight(_ anchors: [Anchor<CGRect>]?, in proxy: GeometryProxy) -> CGRect? {
        guard let anchors, !anchors.isEmpty else { return nil }
        let bounds = CGRect(origin: .zero, size: proxy.size)
        let union = anchors.map { proxy[$0] }.reduce(CGRect.null) { $0.union($1) }
        // A little air around the view, but never past the window's edges
        // (a long list runs on below the fold).
        let padded = union.insetBy(dx: -6, dy: -6).intersection(bounds.insetBy(dx: 4, dy: 4))
        return padded.isNull || padded.isEmpty ? nil : padded
    }
}

private struct TourStopModifier: ViewModifier {
    let stop: TourStop?
    @Environment(TourModel.self) private var tour: TourModel?

    func body(content: Content) -> some View {
        content
            .anchorPreference(key: TourAnchorsKey.self, value: .bounds) { anchor in
                stop.map { [$0: [anchor]] } ?? [:]
            }
            #if os(macOS)
            .background {
                // Scroll the stop into view when it comes up, so the spotlight
                // isn't pointing below the fold.
                if let stop, tour?.current == stop {
                    ScrollIntoView()
                }
            }
            #endif
    }
}

#if os(macOS)
private struct ScrollIntoView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.allowsImplicitAnimation = true
                view.scrollToVisible(view.bounds.insetBy(dx: 0, dy: -16))
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif

// MARK: Overlay

private struct TourOverlay: View {
    let tour: TourModel
    let stop: TourStop
    let spotlight: CGRect?
    let size: CGSize

    @Environment(\.colorScheme) private var colorScheme
    private static let gap: CGFloat = 12
    private static let cardWidth: CGFloat = 300

    var body: some View {
        // With nothing to point at, the cutout shrinks to nothing in the middle.
        let hole = spotlight ?? CGRect(x: size.width / 2, y: size.height * 0.4, width: 0, height: 0)
        ZStack(alignment: .topLeading) {
            SpotlightShape(hole: hole, corner: spotlight == nil ? 0 : 12)
                .fill(Color.black.opacity(colorScheme == .dark ? 0.62 : 0.5), style: FillStyle(eoFill: true))
                // Clicks on the dimmed window do nothing while the tour is up.
                .contentShape(Rectangle())
                .onTapGesture {}
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.harvestOrange, lineWidth: 2)
                .frame(width: hole.width, height: hole.height)
                .offset(x: hole.minX, y: hole.minY)
                .opacity(spotlight == nil ? 0 : 1)
                .allowsHitTesting(false)
            card(below: spotlight)
        }
        .animation(.snappy(duration: 0.3), value: stop)
        .animation(.snappy(duration: 0.3), value: spotlight)
        #if os(macOS)
        .background(TourKeys(tour: tour))
        #endif
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    /// The caption sits on whichever side of the spotlight has more room, or
    /// in the middle when there's no spotlight.
    @ViewBuilder private func card(below spotlight: CGRect?) -> some View {
        let width = min(Self.cardWidth, size.width - 32)
        let caption = TourCard(tour: tour, stop: stop).frame(width: width)
        if let spotlight {
            // Near the spotlight sideways too, for small ones like the gear.
            let centerX = min(max(spotlight.midX, width / 2 + 16), size.width - width / 2 - 16)
            let nudge = centerX - size.width / 2
            let roomAbove = spotlight.minY
            let roomBelow = size.height - spotlight.maxY
            if roomBelow >= roomAbove {
                caption
                    .offset(x: nudge)
                    .frame(width: size.width, height: max(0, roomBelow - Self.gap), alignment: .top)
                    .offset(y: spotlight.maxY + Self.gap)
            } else {
                caption
                    .offset(x: nudge)
                    .frame(width: size.width, height: max(0, roomAbove - Self.gap), alignment: .bottom)
            }
        } else {
            caption.frame(width: size.width, height: size.height)
        }
    }
}

/// The whole window with a rounded hole cut out; animates between holes.
private struct SpotlightShape: Shape {
    var hole: CGRect
    var corner: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat>> {
        get { .init(.init(hole.minX, hole.minY), .init(.init(hole.width, hole.height), corner)) }
        set {
            hole = CGRect(x: newValue.first.first, y: newValue.first.second,
                          width: newValue.second.first.first, height: newValue.second.first.second)
            corner = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addRoundedRect(in: hole, cornerSize: CGSize(width: corner, height: corner), style: .continuous)
        return path
    }
}

private struct TourCard: View {
    let tour: TourModel
    let stop: TourStop

    var body: some View {
        let text = TourText(stop: stop, shortcut: tour.shortcut)
        let isLast = stop == TourStop.allCases.last
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: text.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.harvestOrange)
                Text(text.title)
                    .font(.system(size: 14, weight: .semibold))
            }
            Text(text.body)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                if !isLast {
                    Button("Skip") { tour.finish() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Skip the tour (esc)")
                }
                Spacer(minLength: 0)
                StepDots(current: stop)
                Spacer(minLength: 0)
                if stop.rawValue > 0 {
                    Button("Back") { tour.back() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Back (←)")
                }
                Button(isLast ? "Done" : "Next") { tour.next() }
                    .buttonStyle(TourButtonStyle())
                    .help(isLast ? "Finish the tour (return)" : "Next (return or →)")
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous).fill(Color.tileBackground))
        .overlay(RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous).strokeBorder(Color.hairline))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .id(stop)
        .transition(.opacity)
    }
}

/// Orange whether or not the window is key, unlike `.borderedProminent`.
private struct TourButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.harvestOrange.opacity(configuration.isPressed ? 0.8 : 1)))
            .contentShape(Capsule())
    }
}

private struct StepDots: View {
    let current: TourStop

    var body: some View {
        HStack(spacing: 5) {
            ForEach(TourStop.allCases, id: \.self) { stop in
                Circle()
                    .fill(stop == current ? AnyShapeStyle(.harvestOrange) : AnyShapeStyle(.quaternary))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(current.rawValue + 1) of \(TourStop.allCases.count)")
    }
}

/// What each stop says.
struct TourText {
    let symbol: String
    let title: String
    let body: String

    init(stop: TourStop, shortcut: String?) {
        switch stop {
        case .ask:
            symbol = "magnifyingglass"
            title = "What are you working on?"
            body = "Type to find any project or task and start its timer. Or write “20 min on website” to log time straight away."
        case .days:
            symbol = "calendar"
            title = "Your week at a glance"
            body = "Each day shows its total; click one to see its entries. Days that come up short turn amber, with a nudge to fill them in."
        case .entries:
            symbol = "play.circle"
            title = "The day’s entries"
            body = "Play picks an entry up again, and pause stops the running timer. One timer runs at a time."
        case .favorites:
            symbol = "star"
            title = "Favorites"
            body = "Star any task to keep it here, one click from a running timer. Drag tiles to put them in order."
        case .shortcut:
            symbol = shortcut == nil ? "menubar.arrow.up.rectangle" : "keyboard"
            if let shortcut {
                title = "\(shortcut) from anywhere"
                body = "Press \(shortcut) in any app to show or hide this window. The running timer shows in the menu bar; click it to pause or resume."
            } else {
                title = "Up in the menu bar"
                body = "Click \(AppInfo.name) in the menu bar to show or hide this window. The running timer shows there too; click it to pause or resume."
            }
        case .settings:
            symbol = "gearshape"
            title = "Settings and more"
            body = "This menu has Settings, what the menu bar shows, Keep on Top and Open at Login. You can take this tour again from Settings › Support."
        }
    }
}

// MARK: Keyboard

#if os(macOS)
/// Esc skips, Return or → goes on, ← goes back. Caught before the ask box
/// sees them, and other keys are held back while the tour is up.
private struct TourKeys: NSViewRepresentable {
    let tour: TourModel

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let coordinator = context.coordinator
        coordinator.tour = tour
        coordinator.view = view
        coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak coordinator] event in
            let windowNumber = event.windowNumber
            let keyCode = Int(event.keyCode)
            let command = event.modifierFlags.contains(.command)
            let handled = MainActor.assumeIsolated {
                coordinator?.handle(keyCode: keyCode, command: command, windowNumber: windowNumber) ?? false
            }
            return handled ? nil : event
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.tour = tour
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor { NSEvent.removeMonitor(monitor) }
        coordinator.monitor = nil
    }

    @MainActor final class Coordinator {
        var tour: TourModel?
        weak var view: NSView?
        var monitor: Any?

        /// True when the tour took the key.
        func handle(keyCode: Int, command: Bool, windowNumber: Int) -> Bool {
            guard let tour, tour.current != nil, let window = view?.window, windowNumber == window.windowNumber else { return false }
            // ⌘ shortcuts (⌘Q, ⌘W) still work.
            if command { return false }
            switch keyCode {
            case 53: tour.finish()                 // esc
            case 36, 76, 124, 49: tour.next()      // return, enter, →, space
            case 123: tour.back()                  // ←
            default: break
            }
            return true
        }
    }
}
#endif
