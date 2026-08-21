import Combine
import QuotaBarCore
import SwiftUI

@MainActor
public final class QuotaBarModel: ObservableObject {
    @Published public private(set) var accounts: [QuotaAccount] = []
    @Published public private(set) var lastUpdated: Date?
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var errorMessage: String?

    private let provider: any QuotaProvider

    public init(provider: any QuotaProvider = SampleQuotaProvider()) {
        self.provider = provider
    }

    public var menuTitle: String {
        guard let tightest = accounts
            .flatMap(\.windows)
            .min(by: { $0.remainingFraction < $1.remainingFraction })
        else {
            return "QuotaBar"
        }
        return "\(tightest.remainingPercentage)%"
    }

    public var isSampleData: Bool {
        !accounts.isEmpty && accounts.allSatisfy(\.isSampleData)
    }

    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        errorMessage = nil
        defer { isRefreshing = false }

        do {
            accounts = try await provider.snapshot(at: Date())
            lastUpdated = Date()
        } catch {
            errorMessage = "Could not refresh quota data."
        }
    }
}

public struct QuotaMonitorView: View {
    @ObservedObject public var model: QuotaBarModel

    public init(model: QuotaBarModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()

            if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }

            if model.accounts.isEmpty {
                ContentUnavailableView(
                    "No quota data",
                    systemImage: "chart.bar.xaxis",
                    description: Text("Refresh to load the monitor.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.accounts) { account in
                            AccountQuotaCard(account: account)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            Divider()
            footer
        }
        .padding(16)
        .frame(minWidth: 380, maxWidth: 380, minHeight: 280, maxHeight: 620)
        .task {
            await model.refresh()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("QuotaBar")
                    .font(.title2.weight(.semibold))
                if model.isSampleData {
                    Text("SAMPLE DATA")
                        .font(.caption2.weight(.bold))
                        .tracking(1.1)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            Button {
                Task { await model.refresh() }
            } label: {
                Image(systemName: model.isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh quota data")
            .disabled(model.isRefreshing)
        }
    }

    private var footer: some View {
        HStack {
            if let lastUpdated = model.lastUpdated {
                Text("Updated \(lastUpdated, style: .relative)")
            } else {
                Text("Not updated yet")
            }
            Spacer()
            Text("No credentials connected")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct AccountQuotaCard: View {
    let account: QuotaAccount

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(account.provider.tint)
                    .frame(width: 8, height: 8)
                Text(account.provider.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(account.displayName)
                    .font(.headline)
            }

            ForEach(account.windows) { window in
                QuotaWindowRow(window: window, tint: account.provider.tint)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct QuotaWindowRow: View {
    let window: QuotaWindow
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(window.title)
                    .font(.subheadline)
                Spacer()
                Text("\(window.remainingPercentage)%")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
            }

            ProgressView(value: window.remainingFraction)
                .tint(tint)

            HStack {
                Text("remaining")
                Spacer()
                if let resetAt = window.resetAt {
                    Text("resets \(resetAt, style: .relative)")
                } else {
                    Text("reset unavailable")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}

public struct QuotaSettingsView: View {
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("QuotaBar")
                .font(.title2.weight(.semibold))
            Text("Provider connections are intentionally not included in this MVP.")
                .foregroundStyle(.secondary)
            Label("No network requests", systemImage: "network.slash")
            Label("No credentials stored", systemImage: "key.slash")
            Label("Sample data is always marked", systemImage: "checkmark.shield")
        }
        .padding(28)
        .frame(width: 360, alignment: .leading)
    }
}

private extension QuotaProviderID {
    var tint: Color {
        switch self {
        case .claude:
            .orange
        case .codex:
            .green
        case .kimi:
            .blue
        }
    }
}
