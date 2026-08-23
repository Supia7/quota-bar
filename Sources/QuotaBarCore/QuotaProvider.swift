import Foundation

public protocol QuotaProvider: Sendable {
    var id: String { get }

    func snapshot(at date: Date) async throws -> [QuotaAccount]
}

public struct EmptyQuotaProvider: QuotaProvider {
    public let id = "empty"

    public init() {}

    public func snapshot(at _: Date) async throws -> [QuotaAccount] {
        []
    }
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
                alias: "Work Claude",
                email: "work@example.com",
                windows: [
                    QuotaWindow(
                        id: "claude-five-hour",
                        kind: .fiveHour,
                        title: "5-hour window",
                        remainingFraction: 0.72,
                        resetAt: shortReset
                    ),
                    QuotaWindow(
                        id: "claude-weekly",
                        kind: .weekly,
                        title: "Weekly",
                        remainingFraction: 0.41,
                        resetAt: weeklyReset
                    ),
                    QuotaWindow(
                        id: "claude-fable",
                        kind: .fableWeekly,
                        title: "Fable weekly",
                        remainingFraction: 0.63,
                        resetAt: weeklyReset
                    )
                ],
                isSampleData: true
            ),
            QuotaAccount(
                provider: .codex,
                alias: "Personal Codex",
                email: "personal@example.com",
                windows: [
                    QuotaWindow(
                        id: "codex-weekly",
                        kind: .weekly,
                        title: "Weekly",
                        remainingFraction: 0.64,
                        resetAt: weeklyReset
                    )
                ],
                isSampleData: true
            )
        ]
    }
}
