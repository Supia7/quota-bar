import Foundation

public protocol QuotaProvider: Sendable {
    var id: String { get }

    func snapshot(at date: Date) async throws -> [QuotaAccount]
}

public struct SampleQuotaProvider: QuotaProvider {
    public let id = "sample"

    public init() {}

    public func snapshot(at date: Date) async throws -> [QuotaAccount] {
        let weeklyReset = date.addingTimeInterval(3 * 24 * 60 * 60)
        let shortReset = date.addingTimeInterval(2 * 60 * 60)

        return [
            QuotaAccount(
                provider: .claude,
                displayName: "Work",
                windows: [
                    QuotaWindow(
                        id: "claude-short",
                        title: "5-hour window",
                        remainingFraction: 0.72,
                        resetAt: shortReset
                    ),
                    QuotaWindow(
                        id: "claude-weekly",
                        title: "Weekly",
                        remainingFraction: 0.41,
                        resetAt: weeklyReset
                    )
                ],
                isSampleData: true
            ),
            QuotaAccount(
                provider: .codex,
                displayName: "Personal",
                windows: [
                    QuotaWindow(
                        id: "codex-short",
                        title: "5-hour window",
                        remainingFraction: 0.88,
                        resetAt: shortReset
                    ),
                    QuotaWindow(
                        id: "codex-weekly",
                        title: "Weekly",
                        remainingFraction: 0.64,
                        resetAt: weeklyReset
                    )
                ],
                isSampleData: true
            ),
            QuotaAccount(
                provider: .kimi,
                displayName: "Research",
                windows: [
                    QuotaWindow(
                        id: "kimi-weekly",
                        title: "Weekly",
                        remainingFraction: 0.26,
                        resetAt: weeklyReset
                    )
                ],
                isSampleData: true
            )
        ]
    }
}
