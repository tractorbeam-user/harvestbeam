import AppKit
import HarvestKit
import HarvestUI
import ServiceManagement
import SwiftUI

/// The first-run welcome: a few calm steps in their own window, one idea each.
/// Welcome, where the timer lives, the shortcut (try it), connect Harvest, done.
/// Shown at launch until it's finished once; `--onboarding` shows it again.
@MainActor
final class OnboardingWindowController: NSWindowController {
    static let completedKey = "onboarding.completed"
    static var isCompleted: Bool { UserDefaults.standard.bool(forKey: completedKey) }

    let model: OnboardingModel

    init(tracker: TimeTracker, shortcut: String?, needsAccessibility: Bool, finish: @escaping @MainActor () -> Void) {
        model = OnboardingModel(tracker: tracker, shortcut: shortcut, needsAccessibility: needsAccessibility)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: OnboardingView.size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Harvestbeam"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        super.init(window: window)
        model.finish = { [weak self] in
            UserDefaults.standard.set(true, forKey: Self.completedKey)
            self?.close()
            finish()
        }
        window.contentView = NSHostingView(rootView: OnboardingView().environment(model))
    }

    required init?(coder: NSCoder) { nil }

    var isVisible: Bool { window?.isVisible == true }

    func show() {
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// The global shortcut fired while the welcome is open: count it as a try.
    func shortcutPressed() { model.shortcutPressed() }
}

@MainActor @Observable
final class OnboardingModel {
    enum Step: Int, CaseIterable { case welcome, menuBar, shortcut, connect, done }

    let tracker: TimeTracker
    var step: Step = .welcome
    /// Which way the last move went, so pages slide the right way.
    var forward = true
    /// Bumped each time the shortcut fires; the keycaps animate on change.
    var shortcutPresses = 0
    /// The shortcut split into keycaps, e.g. ["⌥", "H"]. Empty if cleared.
    let shortcutKeys: [String]
    let needsAccessibility: Bool
    var finish: @MainActor () -> Void = {}

    // Connect
    var token = "" {
        didSet { if token != oldValue { accounts = []; selectedAccount = nil; error = nil } }
    }
    var accounts: [HarvestAccount] = []
    var selectedAccount: HarvestAccount?
    var isWorking = false
    var error: String?
    /// The step-by-step guide to making a token is open.
    var showsTokenHelp = false

    init(tracker: TimeTracker, shortcut: String?, needsAccessibility: Bool) {
        self.tracker = tracker
        self.needsAccessibility = needsAccessibility
        let modifiers = shortcut?.prefix { "⌃⌥⇧⌘".contains($0) } ?? ""
        let key = shortcut.map { String($0.dropFirst(modifiers.count)) } ?? ""
        shortcutKeys = modifiers.map(String.init) + (key.isEmpty ? [] : [key])
    }

    /// Already signed in (or demo): no need to connect again.
    var steps: [Step] {
        Step.allCases.filter { step in
            switch step {
            case .connect: tracker.phase == .signedOut || tracker.isDemo || self.step == .connect
            case .shortcut: !shortcutKeys.isEmpty
            default: true
            }
        }
    }

    var canContinue: Bool {
        step != .connect || (!token.trimmingCharacters(in: .whitespaces).isEmpty && !isWorking)
    }

    func next() {
        guard let index = steps.firstIndex(of: step) else { return }
        guard index + 1 < steps.count else { return finish() }
        move(to: steps[index + 1], forward: true)
    }

    func back() {
        guard let index = steps.firstIndex(of: step), index > 0 else { return }
        move(to: steps[index - 1], forward: false)
    }

    private func move(to target: Step, forward: Bool) {
        // Set the direction first, so the outgoing page already knows which
        // way to leave.
        self.forward = forward
        Task { @MainActor in
            withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) { step = target }
        }
    }

    func primaryAction() {
        if step == .connect { connect() } else { next() }
    }

    func shortcutPressed() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { shortcutPresses += 1 }
    }

    func connect() {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !isWorking else { return }
        isWorking = true
        error = nil
        Task {
            defer { isWorking = false }
            // Demo: any token connects, so the whole tour can be clicked through.
            if tracker.isDemo {
                try? await Task.sleep(for: .milliseconds(600))
                return next()
            }
            do {
                if let account = selectedAccount {
                    try await tracker.signIn(token: token, account: account)
                    return next()
                }
                let found = try await TimeTracker.harvestAccounts(for: token)
                switch found.count {
                case 0:
                    error = "That token doesn't have access to any Harvest accounts."
                case 1:
                    try await tracker.signIn(token: token, account: found[0])
                    next()
                default:
                    withAnimation(.snappy) {
                        accounts = found
                        selectedAccount = found[0]
                    }
                }
            } catch {
                withAnimation(.snappy) { self.error = error.localizedDescription }
            }
        }
    }
}

// MARK: - Views

struct OnboardingView: View {
    static let size = NSSize(width: 680, height: 540)

    @Environment(OnboardingModel.self) private var model

    var body: some View {
        ZStack {
            BeamBackground()

            VStack(spacing: 0) {
                page
                    .id(model.step)
                    .transition(.softSlide(forward: model.forward))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                footer
            }
            .padding(.top, 36)
            .padding(.bottom, 26)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .tint(.harvestOrange)
    }

    @ViewBuilder private var page: some View {
        switch model.step {
        case .welcome:
            OnboardingPage(
                title: "Meet Harvestbeam",
                message: "A calm little timer for Harvest. It sits in your menu bar and stays out of the way until you need it."
            ) {
                BeamMark(size: 76, columns: 4)
            }
        case .menuBar:
            OnboardingPage(
                title: "It lives up here",
                message: "Your timer and today's hours, always in view. Click the square to pause or resume, and the time to open your day."
            ) {
                MenuBarPreview()
            }
        case .shortcut:
            ShortcutPage()
        case .connect:
            ConnectPage()
        case .done:
            DonePage()
        }
    }

    private var footer: some View {
        VStack(spacing: 18) {
            Button(action: model.primaryAction) {
                HStack(spacing: 8) {
                    if model.isWorking { ProgressView().controlSize(.small).tint(.white) }
                    Text(primaryTitle)
                }
            }
            .buttonStyle(BeamButtonStyle())
            .keyboardShortcut(.defaultAction)
            .disabled(!model.canContinue)

            HStack {
                Button("Back", action: model.back)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .opacity(model.step == model.steps.first || model.step == .done ? 0 : 1)
                    .disabled(model.step == model.steps.first || model.step == .done)
                    .frame(width: 80, alignment: .leading)
                Spacer()
                ProgressDots(count: model.steps.count, current: model.steps.firstIndex(of: model.step) ?? 0)
                Spacer()
                Color.clear.frame(width: 80, height: 1)
            }
            .font(.callout)
            .padding(.horizontal, 28)
        }
    }

    private var primaryTitle: String {
        switch model.step {
        case .welcome: "Get Started"
        case .connect: model.accounts.count > 1 ? "Use This Account" : "Connect"
        case .done: "Start Tracking"
        default: "Continue"
        }
    }
}

/// Hero on top, a serif headline, one short paragraph, then anything extra.
private struct OnboardingPage<Hero: View, Extra: View>: View {
    let title: String
    let message: String
    /// 0 folds the hero away, to make room for more below.
    var heroHeight: CGFloat = 190
    @ViewBuilder var hero: Hero
    @ViewBuilder var extra: Extra

    init(title: String, message: String, heroHeight: CGFloat = 190,
         @ViewBuilder hero: () -> Hero, @ViewBuilder extra: () -> Extra = { EmptyView() }) {
        self.title = title
        self.message = message
        self.heroHeight = heroHeight
        self.hero = hero()
        self.extra = extra()
    }

    var body: some View {
        VStack(spacing: 0) {
            hero
                .frame(height: heroHeight)
                .opacity(heroHeight > 0 ? 1 : 0)
                .clipped()
            Text(title)
                .font(.system(size: 34, weight: .regular, design: .serif))
                .tracking(-0.4)
                .padding(.top, 18)
            Text(message)
                .font(.system(size: 15))
                .lineSpacing(3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)
                .padding(.top, 10)
            extra
                .padding(.top, 18)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 40)
    }
}

// MARK: Shortcut

private struct ShortcutPage: View {
    @Environment(OnboardingModel.self) private var model
    @State private var heldModifiers: NSEvent.ModifierFlags = []
    @State private var monitor: Any?

    private var tried: Bool { model.shortcutPresses > 0 }

    var body: some View {
        OnboardingPage(
            title: tried ? "That's the one" : "One shortcut, anywhere",
            message: tried
                ? "Press it from any app to jump straight to search. Press it again to tuck the window away."
                : "Press \(model.shortcutKeys.joined()) in any app to open Harvestbeam with search ready. Try it now."
        ) {
            HStack(spacing: 14) {
                ForEach(Array(model.shortcutKeys.enumerated()), id: \.offset) { index, key in
                    Keycap(label: key, held: isHeld(key), lit: tried)
                        .animation(.spring(response: 0.35, dampingFraction: 0.55).delay(Double(index) * 0.05), value: tried)
                }
            }
            .phaseAnimator([false, true], trigger: model.shortcutPresses) { content, pressed in
                content.scaleEffect(pressed ? 0.94 : 1)
            } animation: { _ in .spring(response: 0.18, dampingFraction: 0.5) }
        } extra: {
            if model.needsAccessibility {
                Button {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                } label: {
                    Label("macOS needs Accessibility access for this shortcut", systemImage: "lock.shield")
                        .font(.callout)
                }
                .buttonStyle(.link)
            }
        }
        .onAppear {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { event in
                heldModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                return event
            }
        }
        .onDisappear { monitor.map(NSEvent.removeMonitor) }
    }

    private func isHeld(_ key: String) -> Bool {
        switch key {
        case "⌃": heldModifiers.contains(.control)
        case "⌥": heldModifiers.contains(.option)
        case "⇧": heldModifiers.contains(.shift)
        case "⌘": heldModifiers.contains(.command)
        default: false
        }
    }
}

private struct Keycap: View {
    let label: String
    let held: Bool
    let lit: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(label)
            .font(.system(size: label.count > 1 ? 22 : 36, weight: .medium, design: .rounded))
            .foregroundStyle(lit ? Color.white : Color.primary.opacity(0.8))
            .frame(minWidth: 88, minHeight: 88)
            .padding(.horizontal, label.count > 1 ? 14 : 0)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(lit ? AnyShapeStyle(Color.harvestOrange) : AnyShapeStyle(scheme == .dark ? Color(white: 0.2) : Color.white))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.primary.opacity(lit ? 0 : 0.08))
                    )
                    // The cap's side, which shrinks as it's pressed down.
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(lit ? Color.beamDeep : Color.primary.opacity(scheme == .dark ? 0.25 : 0.12))
                            .offset(y: held ? 2 : 6)
                    )
            }
            .offset(y: held ? 4 : 0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: held)
    }
}

// MARK: Connect

private struct ConnectPage: View {
    @Environment(OnboardingModel.self) private var model
    @FocusState private var focused: Bool

    static let tokenURL = URL(string: "https://id.getharvest.com/developers")!

    var body: some View {
        @Bindable var model = model
        OnboardingPage(
            title: "Connect Harvest",
            message: "Paste a personal access token from Harvest ID. It's kept in your Keychain and only ever sent to Harvest.",
            heroHeight: model.showsTokenHelp ? 0 : 190
        ) {
            ConnectHero()
        } extra: {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "key.fill")
                        .foregroundStyle(.tertiary)
                    SecureField("Personal access token", text: $model.token)
                        .textFieldStyle(.plain)
                        .focused($focused)
                        .onSubmit(model.connect)
                    Link(destination: Self.tokenURL) {
                        HStack(spacing: 3) {
                            Text("Get a token")
                            Image(systemName: "arrow.up.right").imageScale(.small)
                        }
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Color.harvestOrange)
                    }
                }
                .font(.system(size: 14))
                .padding(.horizontal, 14)
                .frame(width: 400, height: 42)
                .background(.background.opacity(0.75), in: .rect(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(focused ? Color.harvestOrange.opacity(0.6) : Color.primary.opacity(0.1), lineWidth: focused ? 1.5 : 1)
                )
                .animation(.easeOut(duration: 0.15), value: focused)

                if model.accounts.count > 1 {
                    Picker("Account", selection: $model.selectedAccount) {
                        ForEach(model.accounts) { Text($0.name).tag(Optional($0)) }
                    }
                    .frame(width: 400)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if let error = model.error {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                        .transition(.opacity)
                }

                Button {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { model.showsTokenHelp.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text(model.showsTokenHelp ? "Hide the steps" : "How do I get a token?")
                        Image(systemName: "chevron.down")
                            .imageScale(.small)
                            .rotationEffect(.degrees(model.showsTokenHelp ? 180 : 0))
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if model.showsTokenHelp {
                    TokenGuide()
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .onAppear { focused = true }
    }
}

/// Making a token, step by step, for anyone who's never done it.
private struct TokenGuide: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            step(1) {
                HStack {
                    Text("Open the **Developers** page in Harvest ID and sign in.")
                    Spacer(minLength: 8)
                    Link(destination: ConnectPage.tokenURL) {
                        HStack(spacing: 3) {
                            Text("Open")
                            Image(systemName: "arrow.up.right").imageScale(.small)
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(Capsule().fill(Color.harvestOrange))
                    }
                }
            }
            step(2) { Text("Click **Create new personal access token** and name it Harvestbeam.") }
            step(3) { Text("Copy the long code under **Your Token** and paste it above.") }
            Text("The token signs in as you, with your access. You can revoke it on that page anytime.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 400, alignment: .leading)
        .background(.background.opacity(0.7), in: .rect(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }

    private func step<Content: View>(_ number: Int, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.harvestOrange)
                .frame(width: 20, height: 20)
                .overlay(Circle().strokeBorder(Color.harvestOrange.opacity(0.5)))
            content()
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The app's mark, a moving dotted line, and a key: your token, beamed across.
private struct ConnectHero: View {
    var body: some View {
        HStack(spacing: 18) {
            AppTile(size: 76)
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                let phase = context.date.timeIntervalSinceReferenceDate * 24
                Canvas { gc, size in
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: size.height / 2))
                    line.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                    gc.stroke(line, with: .color(.harvestOrange.opacity(0.7)),
                              style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [0.1, 10], dashPhase: -phase))
                }
            }
            .frame(width: 96, height: 10)
            Image(systemName: "lock.fill")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Color.harvestOrange)
                .frame(width: 76, height: 76)
                .background(.background.opacity(0.8), in: .rect(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        }
    }
}

// MARK: Done

private struct DonePage: View {
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        OnboardingPage(
            title: "You're all set",
            message: "Look for the square in your menu bar. Start a timer, and Harvestbeam keeps time while you work."
        ) {
            BeamMark(size: 76, columns: 4)
        } extra: {
            Toggle(isOn: $openAtLogin) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open at login")
                        .font(.system(size: 13, weight: .medium))
                    Text("So the timer's there when your day starts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(width: 340)
            .background(.background.opacity(0.7), in: .rect(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            .onChange(of: openAtLogin) { _, on in
                try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
            }
        }
    }
}

// MARK: - Brand pieces

extension Color {
    /// A deeper orange, for the side of a lit keycap.
    static let beamDeep = Color(red: 0.86, green: 0.27, blue: 0.10)
}

/// The Tractorbeam triangle, 26 × 22.
struct BeamTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

/// The app icon, drawn live so it stays crisp at any size.
private struct AppTile: View {
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            .fill(Color.harvestOrange)
            .overlay {
                BeamTriangle()
                    .fill(.white)
                    .frame(width: size * 0.485, height: size * 0.485 * 22 / 26)
                    // Matches the icon: 8pt above center on its 824pt tile.
                    .offset(y: -size * 8 / 824)
            }
            .frame(width: size, height: size)
    }
}

/// The triangle with rows of time entries rising into it, narrowing in
/// perspective as they go, like hours being gathered in. The rows draw the beam.
struct BeamMark: View {
    var size: CGFloat
    var columns: Int
    @State private var appeared = false
    @State private var clock = BeamClock()
    /// Where the pointer is over the beam, if it is.
    @State private var pointer: CGPoint?
    @State private var bursts = 0

    private static let entries = ["0:15", "1:30", "0:45", "2:10", "0:25", "3:00", "1:05", "0:50",
                                  "4:15", "0:30", "1:45", "2:40", "0:10", "1:20", "6:00", "0:55"]

    var body: some View {
        let height = size * 22 / 26
        VStack(spacing: 0) {
            BeamTriangle()
                .fill(Color.harvestOrange)
                .frame(width: size, height: height)
                // A little gulp as a burst of entries arrives.
                .phaseAnimator([false, true], trigger: bursts) { content, gulp in
                    content.scaleEffect(gulp ? 1.08 : 1, anchor: .bottom)
                } animation: { gulp in gulp ? .spring(response: 0.25, dampingFraction: 0.5).delay(0.35) : .spring(response: 0.4, dampingFraction: 0.6) }
                .offset(y: appeared ? 0 : -14)
                .opacity(appeared ? 1 : 0)
                .zIndex(1)
            TimelineView(.animation(minimumInterval: 1 / 60)) { context in
                Canvas { gc, canvas in
                    let t = context.date.timeIntervalSinceReferenceDate
                    // The stream eases to a crawl under the pointer, so the
                    // numbers can be read, and races after a click.
                    let target = pointer == nil ? 1.0 : 0.3
                    let phase = clock.advance(to: t, cruise: target)
                    let rows = 7
                    // Row width runs from the triangle's base down to the full beam.
                    let top = size * 0.8, bottom = canvas.width
                    let labels = Self.entries.map {
                        gc.resolve(Text($0)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.harvestOrange))
                    }
                    for row in 0..<rows {
                        let raw = phase + Double(row) / Double(rows)
                        let progress = raw.truncatingRemainder(dividingBy: 1)
                        let cycle = Int(raw.rounded(.down))
                        let width = bottom - (bottom - top) * progress
                        // Text shrinks with the row, so columns never collide.
                        let scale = width / bottom
                        let y = canvas.height * (1 - progress)
                        let fade = min(progress / 0.16, 1) * min((1 - progress) / 0.32, 1)
                        for column in 0..<columns {
                            let seed = abs(cycle &* 131 &+ row &* 17 &+ column &* 29)
                            let x = canvas.width / 2 + (Double(column) + 0.5 - Double(columns) / 2) * width / Double(columns)
                            // Entries near the pointer come forward.
                            let near = pointer.map { max(0, 1 - hypot($0.x - x, $0.y - y) / 46) } ?? 0
                            var layer = gc
                            // Most entries sit back; one in a few is brighter.
                            layer.opacity = fade * max(seed % 5 == 0 ? 0.95 : 0.42, near)
                            layer.translateBy(x: x, y: y)
                            layer.scaleBy(x: scale * (1 + 0.4 * near), y: scale * (1 + 0.4 * near))
                            layer.draw(labels[seed % labels.count], at: .zero, anchor: .center)
                        }
                    }
                }
            }
            .frame(width: size * 2.4, height: size * 1.25)
            .scaleEffect(x: 1, y: appeared ? 1 : 0.01, anchor: .top)
            .opacity(appeared ? 1 : 0)
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): pointer = location
                case .ended: pointer = nil
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            clock.burst()
            bursts += 1
        }
        .onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .help("Click to beam some hours up")
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { appeared = true }
        }
    }
}

/// Keeps the beam's position, so its speed can change without the rows
/// jumping: it eases toward a cruising speed and adds a decaying burst.
private final class BeamClock {
    private var phase = 0.0
    private var speed = 1.0
    private var boost = 0.0
    private var last: Double?

    /// Rows per second at cruising speed 1.
    private static let base = 0.055

    func advance(to time: Double, cruise: Double) -> Double {
        let dt = min(max(time - (last ?? time), 0), 0.1)
        last = time
        speed += (cruise - speed) * min(dt * 4, 1)
        boost *= exp(-dt * 2.2)
        phase += dt * Self.base * (speed + boost)
        return phase
    }

    func burst() { boost += 9 }
}

/// A slice of the menu bar with Harvestbeam's item in it, pausing and
/// resuming on its own.
private struct MenuBarPreview: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Spacer()
                item
                Image(systemName: "wifi")
                Image(systemName: "battery.75percent")
                Image(systemName: "magnifyingglass")
                Text("Mon 9:41")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.primary.opacity(0.85))
            .padding(.horizontal, 18)
            .frame(width: 560, height: 32)
            .background(.regularMaterial)
            .overlay(alignment: .bottom) { Rectangle().fill(.primary.opacity(0.06)).frame(height: 1) }
            .clipShape(.rect(cornerRadius: 8, style: .continuous))

            // The window it opens, sketched.
            WindowSketch()
                .padding(.top, 10)
                .offset(x: 26)
        }
    }

    @State private var running = true
    private let flip = Timer.publish(every: 2.2, on: .main, in: .common).autoconnect()

    private var item: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(running ? Color.harvestOrange : Color.gray.opacity(0.75))
                .frame(width: 21, height: 15)
                .overlay {
                    Image(systemName: running ? "pause.fill" : "play.fill")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(.white)
                }
            Text("1:24")
                .monospacedDigit()
            if running {
                Text("Design review")
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.primary.opacity(0.09)))
        .onReceive(flip) { _ in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { running.toggle() }
        }
    }
}

private struct WindowSketch: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.harvestOrange)
                .frame(height: 22)
            ForEach(0..<3) { row in
                HStack(spacing: 8) {
                    Circle().fill(Color.harvestOrange.opacity(row == 0 ? 0.9 : 0.25)).frame(width: 10, height: 10)
                    Capsule().fill(.primary.opacity(0.12)).frame(width: [92, 70, 82][row], height: 7)
                    Spacer()
                    Capsule().fill(.primary.opacity(0.08)).frame(width: 26, height: 7)
                }
            }
        }
        .padding(10)
        .frame(width: 210)
        .background(.background.opacity(0.85), in: .rect(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.primary.opacity(0.08)))
    }
}

/// Warm paper, flat.
private struct BeamBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        (scheme == .dark ? Color(red: 0.09, green: 0.075, blue: 0.065) : Color(red: 0.985, green: 0.97, blue: 0.95))
            .ignoresSafeArea()
    }
}

private struct ProgressDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? AnyShapeStyle(Color.harvestOrange) : AnyShapeStyle(.primary.opacity(0.16)))
                    .frame(width: index == current ? 18 : 6, height: 6)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: current)
    }
}

/// A wide, flat orange pill that grows a touch on hover.
private struct BeamButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(minWidth: 220, minHeight: 42)
            .padding(.horizontal, 8)
            .background(Capsule().fill(Color.harvestOrange))
            .scaleEffect(configuration.isPressed ? 0.97 : hovering ? 1.02 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
            .onHover { hovering = $0 }
            .contentShape(Capsule())
    }
}

/// Pages drift in from the side through a soft blur.
private struct SoftSlide: ViewModifier {
    let offset: CGFloat
    let amount: CGFloat

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .blur(radius: amount * 10)
            .opacity(1 - amount)
    }
}

private extension AnyTransition {
    static func softSlide(forward: Bool) -> AnyTransition {
        let distance: CGFloat = forward ? 36 : -36
        return .asymmetric(
            insertion: .modifier(active: SoftSlide(offset: distance, amount: 1), identity: SoftSlide(offset: 0, amount: 0)),
            removal: .modifier(active: SoftSlide(offset: -distance, amount: 1), identity: SoftSlide(offset: 0, amount: 0))
        )
    }
}
