import HarvestKit
import SwiftUI

/// The team's time-tracking glossary: what each code is for, one division
/// at a time. Digital Products is written up; the others are on the way.
struct GuideView: View {
    enum Division: String, CaseIterable, Identifiable {
        case digitalProducts = "DP", digitalMarketing = "DM", creativeServices = "CS"
        var id: String { rawValue }
        var name: String {
            switch self {
            case .digitalProducts: return "Digital Products"
            case .digitalMarketing: return "Digital Marketing"
            case .creativeServices: return "Creative Services"
            }
        }
        var isReady: Bool { self == .digitalProducts }
    }

    @State private var division = Division.digitalProducts
    @State private var filter = ""

    private var current: [TaskDefinition] {
        TaskDefinitions.all.filter { !$0.isRetired && matches($0) }
    }
    private var retired: [TaskDefinition] {
        TaskDefinitions.all.filter { $0.isRetired && matches($0) }
    }

    private func matches(_ d: TaskDefinition) -> Bool {
        let q = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        return [d.title, d.summary, d.replacement ?? ""].contains { $0.lowercased().contains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "book.closed")
                    .foregroundStyle(.harvestOrange)
                Text("Time Tracking Guide")
                    .font(.system(size: 14, weight: .semibold))
            }
            HStack(spacing: 6) {
                ForEach(Division.allCases) { item in
                    Button { division = item } label: {
                        VStack(spacing: 1) {
                            Text(item.rawValue).font(.system(size: 12, weight: .semibold))
                            Text(item.isReady ? item.name : "Coming soon")
                                .font(.system(size: 10))
                                .opacity(0.7)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .foregroundStyle(division == item ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(division == item ? Color.harvestOrange : Color.primary.opacity(0.06)))
                        .opacity(item.isReady || division == item ? 1 : 0.6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if division.isReady {
                TextField("Filter codes", text: $filter)
                    .textFieldStyle(.roundedBorder)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(current, id: \.self) { GuideRow(definition: $0) }
                        if !retired.isEmpty {
                            Text("RETIRED")
                                .font(.system(size: 10.5, weight: .semibold))
                                .tracking(0.6)
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                            ForEach(retired, id: \.self) { GuideRow(definition: $0) }
                        }
                        if current.isEmpty && retired.isEmpty {
                            Text("Nothing matches “\(filter)”").foregroundStyle(.secondary).font(.callout)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 340)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                    Text("\(division.name) codes are coming soon")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Until then, ask your lead which bucket to use.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .padding(14)
        .frame(width: 340)
    }
}

private struct GuideRow: View {
    let definition: TaskDefinition

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if let code = definition.code {
                    Text(code)
                        .font(.system(size: 10.5, weight: .semibold).monospaced())
                        .foregroundStyle(.harvestOrange)
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(Capsule().fill(Color.harvestOrange.opacity(0.14)))
                }
                Text(definition.name)
                    .font(.system(size: 13, weight: .semibold))
                    .strikethrough(definition.isRetired)
            }
            Text(definition.isRetired ? "Retired: \(definition.replacement ?? "")" : definition.summary)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .textSelection(.enabled)
    }
}

/// For debug snapshots.
public func debugGuide() -> some View { GuideView() }
