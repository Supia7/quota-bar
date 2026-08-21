import Foundation
import QuotaBarCore

@main
enum QuotaBarChecks {
    static func main() async throws {
        try check(
            QuotaWindow(
                id: "over",
                title: "Over",
                remainingFraction: 1.4,
                resetAt: nil
            ).remainingFraction == 1,
            "remaining fraction must clamp its upper bound"
        )
        try check(
            QuotaWindow(
                id: "under",
                title: "Under",
                remainingFraction: -0.2,
                resetAt: nil
            ).remainingFraction == 0,
            "remaining fraction must clamp its lower bound"
        )
        try check(
            QuotaWindow(
                id: "weekly",
                title: "Weekly",
                remainingFraction: 0.876,
                resetAt: nil
            ).remainingPercentage == 88,
            "remaining percentage must round for display"
        )

        let accounts = try await SampleQuotaProvider().snapshot(
            at: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try check(accounts.count == 3, "sample provider must return three accounts")
        try check(
            accounts.allSatisfy(\.isSampleData),
            "sample accounts must be explicitly marked"
        )
        try check(
            accounts.map(\.provider) == [.claude, .codex, .kimi],
            "sample providers must be stable"
        )
        try check(
            accounts.allSatisfy { !$0.windows.isEmpty },
            "sample accounts must contain quota windows"
        )

        print("QuotaBarChecks: all checks passed")
    }

    private static func check(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        guard condition() else {
            throw CheckFailure(message)
        }
    }
}

private struct CheckFailure: Error, CustomStringConvertible {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var description: String {
        "QuotaBarChecks failed: \(message)"
    }
}
