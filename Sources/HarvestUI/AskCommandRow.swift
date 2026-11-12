import HarvestKit
import SwiftUI

/// The ask box's preview of a command ("Move 0:20 from Admin to Website ·
/// leaves 0:27"): Return applies it, Escape clears it. When it can't work,
/// it says why, with the tasks a name could mean.
struct AskCommandRow: View {
    let preview: AskCommandPreview
    let apply: () -> Void
    @State private var isHovered = false

    private var isReady: Bool { preview.plan.isReady }

    private var icon: String {
        guard isReady else { return "exclamationmark.triangle.fill" }
        switch preview.command {
        case .move: return "arrow.left.arrow.right.circle.fill"
        case .setHours: return "clock.fill"
        case .note: return "text.bubble.fill"
        case .pause: return "pause.circle.fill"
        }
    }

    var body: some View {
        Button(action: apply) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(isReady ? AnyShapeStyle(.white) : AnyShapeStyle(.harvestOrange))
                VStack(alignment: .leading, spacing: 1) {
                    Text(preview.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail = preview.detail {
                        Text(detail)
                            .font(.system(size: 11.5))
                            .opacity(0.75)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 6)
                Text(isReady ? "⏎ apply · esc" : "esc")
                    .font(.system(size: 11, weight: .medium))
                    .opacity(0.8)
                    .fixedSize()
            }
            .foregroundStyle(isReady ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isReady ? Color.harvestOrange.opacity(isHovered ? 0.9 : 1) : Color.tileBackground))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(isReady ? Color.clear : Color.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .onHover { isHovered = $0 }
        #endif
        .accessibilityHint(isReady ? "Applies the change" : "")
    }
}

/// Shown after starting a retired bucket: where that time goes now.
struct RetiredBucketNote: View {
    let task: TrackableTask
    let definition: TaskDefinition
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "arrow.uturn.right.circle.fill").foregroundStyle(.harvestOrange)
            Text("The \(definition.name) bucket is retired. ").font(.callout.weight(.semibold))
                + Text(definition.replacement.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? "").font(.callout)
            Spacer()
            Button(action: dismiss) { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Dismiss")
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.harvestOrange.opacity(0.12))
    }
}

extension TrackableTask {
    /// The team policy's definition for this task, if it has one.
    var definition: TaskDefinition? { TaskDefinitions.definition(for: self) }

    /// A tooltip: client and code, then what the policy says goes here.
    var helpText: String {
        let head = [client?.name, projectCode].compactMap { $0 }.joined(separator: " · ")
        guard let definition else { return head }
        return [head, "\(definition.title): \(definition.detail)"].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
