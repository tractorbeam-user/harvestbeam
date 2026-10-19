import AppKit
import Observation
import Sparkle
import SwiftUI

/// What the update window is showing.
enum UpdatePhase: Equatable {
    case checking
    case found(UpdateInfo)
    case upToDate(String)
    case downloading(received: UInt64, expected: UInt64)
    /// Unpacking and checking the download; nil while Sparkle hasn't said how far along it is.
    case preparing(Double?)
    case installing
    /// Downloaded already: one click relaunches into it.
    case ready(UpdateInfo)
    case failed(UpdateFailure)
}

struct UpdateInfo: Equatable {
    var version: String
    var current: String
    var notes: AttributedString?
}

struct UpdateFailure: Equatable {
    /// True when it went wrong looking for an update, false while downloading or installing one.
    var whileChecking: Bool
    var detail: String
}

/// The update window's state and the replies Sparkle is waiting for. Each
/// reply is called once: by a button, or by closing the window.
@MainActor @Observable
final class UpdatePrompt {
    var phase: UpdatePhase = .checking
    var version = ""

    @ObservationIgnored var onChoice: ((SPUUserUpdateChoice) -> Void)?
    @ObservationIgnored var onCancel: (() -> Void)?
    @ObservationIgnored var onAcknowledge: (() -> Void)?
    @ObservationIgnored var onRetry: (() -> Void)?

    func choose(_ choice: SPUUserUpdateChoice) {
        let reply = onChoice
        clearReplies()
        reply?(choice)
    }

    func cancel() {
        let reply = onCancel
        clearReplies()
        reply?()
    }

    func acknowledge() {
        let reply = onAcknowledge
        clearReplies()
        reply?()
    }

    func retry() {
        acknowledge()
        onRetry?()
    }

    /// The window closed: answer whatever Sparkle is still waiting on as "not now".
    func windowClosed() {
        if onChoice != nil { choose(.dismiss) } else if onCancel != nil { cancel() } else { acknowledge() }
    }

    func clearReplies() {
        onChoice = nil
        onCancel = nil
        onAcknowledge = nil
    }
}

/// Sparkle's user interface, drawn by Harvestbeam: one small window that
/// moves through checking, found, downloading, ready and so on.
@MainActor
final class UpdateDriver: NSObject, SPUUserDriver, NSWindowDelegate {
    let prompt = UpdatePrompt()
    private weak var updates: Updates?
    private var window: NSWindow?
    /// Set once the user chooses Install, so the download goes straight on to
    /// relaunching instead of asking a second time.
    private var installChosen = false

    init(updates: Updates) {
        self.updates = updates
        super.init()
        prompt.onRetry = { [weak updates] in
            DispatchQueue.main.async { updates?.checkForUpdates(nil) }
        }
    }

    // MARK: Window

    private func show(activate: Bool) {
        let window = self.window ?? makeWindow()
        self.window = window
        if !window.isVisible { window.center() }
        if activate {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        } else {
            // A background check shouldn't take focus from what you're doing.
            window.orderFrontRegardless()
        }
    }

    private func makeWindow() -> NSWindow {
        let host = NSHostingController(rootView: UpdateView().environment(prompt).environment(updates))
        host.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.title = "Software Update"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.delegate = self
        return window
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated { prompt.windowClosed() }
    }

    private func close() {
        window?.delegate = nil
        window?.close()
        window?.delegate = self
    }

    // MARK: SPUUserDriver

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        // Info.plist turns automatic checks on, so Sparkle shouldn't ask; if it does, say yes.
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        installChosen = false
        prompt.clearReplies()
        prompt.onCancel = cancellation
        prompt.phase = .checking
        show(activate: true)
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        installChosen = false
        let info = UpdateInfo(version: appcastItem.displayVersionString, current: Self.currentVersion, notes: Self.notes(from: appcastItem))
        prompt.version = info.version
        prompt.clearReplies()
        prompt.onChoice = { [weak self] choice in
            if choice == .install { self?.installChosen = true }
            reply(choice)
        }
        prompt.phase = state.stage == .notDownloaded ? .found(info) : .ready(info)
        show(activate: state.userInitiated)
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        // Only used when an appcast item links to notes instead of embedding them.
        guard let notes = Self.html(downloadData.data) else { return }
        switch prompt.phase {
        case .found(var info): info.notes = notes; prompt.phase = .found(info)
        case .ready(var info): info.notes = notes; prompt.phase = .ready(info)
        default: break
        }
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        prompt.clearReplies()
        prompt.onAcknowledge = acknowledgement
        prompt.phase = .upToDate(Self.currentVersion)
        show(activate: true)
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        let whileChecking: Bool
        switch prompt.phase {
        case .downloading, .preparing, .installing, .ready: whileChecking = false
        default: whileChecking = true
        }
        prompt.clearReplies()
        prompt.onAcknowledge = acknowledgement
        prompt.phase = .failed(UpdateFailure(whileChecking: whileChecking, detail: error.localizedDescription))
        show(activate: true)
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        prompt.clearReplies()
        prompt.onCancel = cancellation
        prompt.phase = .downloading(received: 0, expected: 0)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        prompt.phase = .downloading(received: 0, expected: expectedContentLength)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        guard case let .downloading(received, expected) = prompt.phase else { return }
        prompt.phase = .downloading(received: received + length, expected: max(expected, received + length))
    }

    func showDownloadDidStartExtractingUpdate() {
        prompt.clearReplies()
        prompt.phase = .preparing(nil)
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        prompt.phase = .preparing(progress)
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        if installChosen {
            // They already said Install and Relaunch; don't ask again.
            reply(.install)
            return
        }
        prompt.clearReplies()
        prompt.onChoice = reply
        prompt.phase = .ready(UpdateInfo(version: prompt.version, current: Self.currentVersion, notes: nil))
        show(activate: true)
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        prompt.clearReplies()
        prompt.phase = .installing
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    func showUpdateInFocus() {
        show(activate: true)
    }

    func dismissUpdateInstallation() {
        installChosen = false
        prompt.clearReplies()
        close()
    }

    // MARK: Helpers

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }

    /// The appcast item's embedded notes: Markdown (or plain text) or HTML.
    static func notes(from item: SUAppcastItem) -> AttributedString? {
        guard let text = item.itemDescription?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if item.itemDescriptionFormat == "markdown" || item.itemDescriptionFormat == "plain-text" {
            return markdownNotes(text)
        }
        return html(Data(text.utf8))
    }

    /// Light Markdown: **bold**, _italic_, links, and "- " lines as bullets.
    static func markdownNotes(_ text: String) -> AttributedString {
        let text = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.hasPrefix("- ") || $0.hasPrefix("* ") ? "•  " + $0.dropFirst(2) : String($0) }
            .joined(separator: "\n")
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    private static func html(_ data: Data) -> AttributedString? {
        guard let parsed = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
            documentAttributes: nil
        ) else { return nil }
        // Keep the words, drop the web page's fonts and colors.
        let text = parsed.string.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : AttributedString(text)
    }
}

// MARK: View

struct UpdateView: View {
    static let width: CGFloat = 460

    @Environment(UpdatePrompt.self) private var prompt
    @Environment(Updates.self) private var updates

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            Text(title)
                .font(.system(size: 26, weight: .regular, design: .serif))
                .tracking(-0.3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            if let message {
                Text(message)
                    .font(.system(size: 13))
                    .lineSpacing(2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
            detail
            footer
        }
        .padding(.horizontal, 36)
        .padding(.top, 34)
        .padding(.bottom, 24)
        .frame(width: Self.width)
        .background(UpdatePaper())
        .tint(.harvestOrange)
    }

    private var title: String {
        switch prompt.phase {
        case .checking: "Checking for updates"
        case .found(let info): "Harvestbeam \(info.version) is here"
        case .upToDate: "You're up to date"
        case .downloading: "Downloading \(prompt.version)"
        case .preparing: "Getting \(prompt.version) ready"
        case .installing: "Installing \(prompt.version)"
        case .ready: "Relaunch to finish"
        case .failed(let failure): failure.whileChecking ? "Couldn't check for updates" : "The update didn't finish"
        }
    }

    private var message: String? {
        switch prompt.phase {
        case .checking: "Looking for a newer version on GitHub."
        case .found(let info): "You have \(info.current)"
        case .upToDate(let version): "You're on the latest version, \(version)."
        case .downloading: nil
        case .preparing: "Checking the download and unpacking it."
        case .installing: "Harvestbeam reopens in a moment."
        case .ready(let info): "Harvestbeam \(info.version) is downloaded. It installs when you relaunch, or the next time you quit."
        case .failed(let failure):
            failure.whileChecking
                ? "Harvestbeam couldn't reach the update server. Check your internet connection, then try again."
                : "Something went wrong while getting the new version ready. The version you have still works."
        }
    }

    @ViewBuilder private var detail: some View {
        switch prompt.phase {
        case .found(let info):
            if let notes = info.notes { ReleaseNotes(notes: notes).padding(.top, 18) }
        case .ready(let info):
            if let notes = info.notes { ReleaseNotes(notes: notes).padding(.top, 18) }
        case .checking, .installing:
            FlatProgressBar(fraction: nil).padding(.top, 20)
        case .preparing(let fraction):
            FlatProgressBar(fraction: fraction).padding(.top, 20)
        case let .downloading(received, expected):
            VStack(spacing: 8) {
                FlatProgressBar(fraction: expected > 0 ? Double(received) / Double(expected) : nil)
                Text(expected > 0 ? "\(Self.bytes(received)) of \(Self.bytes(expected))" : "Starting the download")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 18)
        case .failed(let failure):
            Text(failure.detail)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        case .upToDate:
            EmptyView()
        }
    }

    @ViewBuilder private var footer: some View {
        switch prompt.phase {
        case .found:
            VStack(spacing: 16) {
                HStack(spacing: 10) {
                    Button("Not Now") { prompt.choose(.dismiss) }
                        .buttonStyle(QuietButtonStyle())
                        .keyboardShortcut(.cancelAction)
                    Button("Install and Relaunch") { prompt.choose(.install) }
                        .buttonStyle(BeamButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
                autoInstallRow(skip: true)
            }
            .padding(.top, 22)
        case .ready:
            VStack(spacing: 16) {
                HStack(spacing: 10) {
                    Button("Later") { prompt.choose(.dismiss) }
                        .buttonStyle(QuietButtonStyle())
                        .keyboardShortcut(.cancelAction)
                    Button("Relaunch Now") { prompt.choose(.install) }
                        .buttonStyle(BeamButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
                autoInstallRow(skip: false)
            }
            .padding(.top, 22)
        case .checking, .downloading:
            Button("Cancel") { prompt.cancel() }
                .buttonStyle(QuietButtonStyle())
                .keyboardShortcut(.cancelAction)
                .padding(.top, 22)
        case .upToDate:
            Button("Done") { prompt.acknowledge() }
                .buttonStyle(BeamButtonStyle())
                .keyboardShortcut(.defaultAction)
                .padding(.top, 22)
        case .failed:
            HStack(spacing: 10) {
                Button("Close") { prompt.acknowledge() }
                    .buttonStyle(QuietButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Try Again") { prompt.retry() }
                    .buttonStyle(BeamButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 22)
        case .preparing, .installing:
            // Nothing to press while Sparkle works; keep the window's height steady.
            Color.clear.frame(height: 42).padding(.top, 22)
        }
    }

    private func autoInstallRow(skip: Bool) -> some View {
        @Bindable var updates = updates
        return HStack {
            Toggle("Install updates automatically", isOn: $updates.installsAutomatically)
                .toggleStyle(.switch)
                .controlSize(.mini)
            Spacer()
            if skip {
                Button("Skip This Version") { prompt.choose(.skip) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12))
    }

    private static func bytes(_ count: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
}

/// The appcast's notes in a short, quiet scrolling box.
private struct ReleaseNotes: View {
    let notes: AttributedString

    var body: some View {
        ScrollView {
            Text(notes)
                .font(.system(size: 13))
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
        }
        .frame(maxHeight: 132)
        .fixedSize(horizontal: false, vertical: true)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.primary.opacity(0.08)))
    }
}

/// A thin, flat orange bar. With no fraction, a short segment slides along it.
private struct FlatProgressBar: View {
    let fraction: Double?
    @State private var sliding = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.09))
                if let fraction {
                    Capsule()
                        .fill(Color.harvestOrange)
                        .frame(width: max(6, width * min(max(fraction, 0), 1)))
                        .animation(.easeOut(duration: 0.2), value: fraction)
                } else {
                    Capsule()
                        .fill(Color.harvestOrange)
                        .frame(width: width * 0.28)
                        .offset(x: sliding ? width * 0.72 : 0)
                        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: sliding)
                        .onAppear { sliding = true }
                }
            }
        }
        .frame(width: 280, height: 6)
        .clipShape(Capsule())
    }
}

/// Warm paper, flat, as in the welcome window.
private struct UpdatePaper: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        (scheme == .dark ? Color(red: 0.09, green: 0.075, blue: 0.065) : Color(red: 0.985, green: 0.97, blue: 0.95))
            .ignoresSafeArea()
    }
}

/// The flat orange pill from the welcome window.
private struct BeamButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(minWidth: 170, minHeight: 42)
            .padding(.horizontal, 14)
            .background(Capsule().fill(Color.harvestOrange))
            .scaleEffect(configuration.isPressed ? 0.97 : hovering ? 1.02 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
            .onHover { hovering = $0 }
            .contentShape(Capsule())
    }
}

/// The secondary choice next to the pill: same shape, no color.
private struct QuietButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.primary)
            .frame(minWidth: 110, minHeight: 42)
            .padding(.horizontal, 14)
            .background(Capsule().fill(.primary.opacity(configuration.isPressed ? 0.12 : hovering ? 0.09 : 0.06)))
            .onHover { hovering = $0 }
            .contentShape(Capsule())
    }
}
