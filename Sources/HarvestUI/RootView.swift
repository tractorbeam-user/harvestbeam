import HarvestKit
import SwiftUI

/// Entry point for both platforms: sign-in, first load, or the tracker.
public struct RootView: View {
    @Environment(TimeTracker.self) private var tracker
    private let onClose: (() -> Void)?

    /// `onClose` dismisses the menu bar panel (Esc). Leave nil on iOS.
    public init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
    }

    public var body: some View {
        Group {
            switch tracker.phase {
            case .signedOut: SignInView()
            case .loading: LoadingView()
            case .ready: TrackerView(onClose: onClose)
            }
        }
        .tint(.harvestOrange)
        #if os(macOS)
        .frame(width: 380, height: 560)
        #endif
    }
}

struct LoadingView: View {
    @Environment(TimeTracker.self) private var tracker

    var body: some View {
        VStack(spacing: 14) {
            if let error = tracker.errorMessage {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 30))
                    .foregroundStyle(.secondary)
                Text(error)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Sign Out") { tracker.signOut() }
                    Button("Try Again") { Task { await tracker.refresh(force: true) } }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView()
                Text("Loading your projects…")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await tracker.refresh(force: true) }
    }
}
