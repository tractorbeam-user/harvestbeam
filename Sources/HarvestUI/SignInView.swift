import HarvestKit
import SwiftUI

struct SignInView: View {
    @Environment(TimeTracker.self) private var tracker
    @State private var token = ""
    @State private var accounts: [HarvestAccount] = []
    @State private var selectedAccount: HarvestAccount?
    @State private var isWorking = false
    @State private var error: String?

    private static let tokenURL = URL(string: "https://id.getharvest.com/developers")!

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 12) {
                    Image(systemName: "timer")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 60, height: 60)
                        .background(Circle().fill(.harvestOrange))
                    Text("Connect to Harvest")
                        .font(.title2.weight(.semibold))
                    Text("Track time from anywhere with a personal access token. It stays in your Keychain.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 14) {
                    step(1) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Create a token in Harvest ID")
                            Link(destination: Self.tokenURL) {
                                Label("id.getharvest.com/developers", systemImage: "arrow.up.right")
                                    .labelStyle(TrailingIconLabelStyle())
                                    .font(.callout.weight(.medium))
                            }
                        }
                    }
                    step(2) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Paste it here")
                            SecureField("Personal access token", text: $token)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit(connect)
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                #endif
                        }
                    }
                    if accounts.count > 1 {
                        step(3) {
                            Picker("Account", selection: $selectedAccount) {
                                ForEach(accounts) { Text($0.name).tag(Optional($0)) }
                            }
                            .labelsHidden()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let error {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: connect) {
                    HStack {
                        if isWorking { ProgressView().controlSize(.small) }
                        Text(accounts.count > 1 ? "Use This Account" : "Connect")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
            }
            .padding(28)
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)
        }
        .onChange(of: token) { accounts = []; selectedAccount = nil }
    }

    private func step<Content: View>(_ number: Int, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.harvestOrange)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.harvestOrange.opacity(0.14)))
            content()
        }
    }

    private func connect() {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !isWorking else { return }
        isWorking = true
        error = nil
        Task {
            defer { isWorking = false }
            do {
                if let account = selectedAccount {
                    try await tracker.signIn(token: token, account: account)
                    return
                }
                let found = try await TimeTracker.harvestAccounts(for: token)
                switch found.count {
                case 0:
                    error = "That token doesn't have access to any Harvest accounts."
                case 1:
                    try await tracker.signIn(token: token, account: found[0])
                default:
                    accounts = found
                    selectedAccount = found[0]
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.title
            configuration.icon.imageScale(.small)
        }
    }
}
