import HarvestKit
import SwiftUI

/// The ask box's preview of a command ("Move 0:20 from Admin to Website ·
/// leaves 0:27"): Return applies it, Escape clears it. When it can't work,
/// it says why, with the tasks a name could mean.
struct AskCommandRow: View {
    let preview: AskCommandPreview
    let apply: () -> Void
    /// Replaces the ask box's text with one of the preview's fixes.
    var rewrite: (String) -> Void = { _ in }
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
        VStack(alignment: .leading, spacing: 6) {
            row
            if !preview.fixes.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(preview.fixes) { fix in
                        FixButton(fix: fix) { rewrite(fix.text) }
                    }
                }
                .padding(.leading, 30)
            }
        }
    }

    private var row: some View {
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
                Text(isReady ? "↩ apply · esc" : "esc")
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

/// One of a command problem's fixes: "Dallas Art Fair · Design".
private struct FixButton: View {
    let fix: AskCommandFix
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(fix.label)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.harvestOrange.opacity(isHovered ? 0.2 : 0.12)))
                .foregroundStyle(Color.harvestOrange)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .onHover { isHovered = $0 }
        #endif
        .help(fix.text)
    }
}

/// Lays chips out left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: min(width, proposal.width ?? width), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + extra > width {
                rows.append(Row())
            }
            let added = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += added
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}
