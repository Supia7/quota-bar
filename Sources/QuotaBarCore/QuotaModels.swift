import Foundation

public enum QuotaProviderID: String, CaseIterable, Codable, Sendable, Hashable {
    case claude
    case codex

    public var displayName: String {
        switch self {
        case .claude:
            "Claude"
        case .codex:
            "Codex"
        }
    }
}

public enum QuotaWindowKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case fiveHour = "five-hour"
    case weekly
    case fableWeekly = "fable-weekly"

    public var id: String { rawValue }

    public var defaultTitle: String {
        switch self {
        case .fiveHour:
            "5-hour window"
        case .weekly:
            "Weekly"
        case .fableWeekly:
            "Fable weekly"
        }
    }

    public var compactLabel: String {
        switch self {
        case .fiveHour:
            "5h"
        case .weekly:
            "W"
        case .fableWeekly:
            "F"
        }
    }
}

public struct QuotaWindow: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let kind: QuotaWindowKind
    public let title: String
    public let remainingFraction: Double?
    public let resetAt: Date?

    public init(
        id: String,
        kind: QuotaWindowKind,
        title: String,
        remainingFraction: Double?,
        resetAt: Date?
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        if let remainingFraction {
            self.remainingFraction = min(max(remainingFraction, 0), 1)
        } else {
            self.remainingFraction = nil
        }
        self.resetAt = resetAt
    }

    public var remainingPercentage: Int? {
        guard let remainingFraction else { return nil }
        return Int((remainingFraction * 100).rounded())
    }
}

public struct QuotaAccount: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let provider: QuotaProviderID
    public let alias: String
    public let email: String
    public let isEmailHidden: Bool
    public let windows: [QuotaWindow]
    public let isSampleData: Bool

    public init(
        id: UUID = UUID(),
        provider: QuotaProviderID,
        alias: String,
        email: String,
        isEmailHidden: Bool = false,
        windows: [QuotaWindow],
        isSampleData: Bool
    ) {
        self.id = id
        self.provider = provider
        self.alias = alias
        self.email = email
        self.isEmailHidden = isEmailHidden
        self.windows = windows
        self.isSampleData = isSampleData
    }

    public var displayName: String {
        let normalizedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedAlias.isEmpty {
            return normalizedAlias
        }

        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedEmail.isEmpty {
            return normalizedEmail
        }

        return "\(provider.displayName) account"
    }

    public var visibleEmail: String? {
        guard !isEmailHidden else { return nil }
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedEmail.isEmpty ? nil : normalizedEmail
    }

    public var withEmailHidden: QuotaAccount {
        QuotaAccount(
            id: id,
            provider: provider,
            alias: alias,
            email: email,
            isEmailHidden: true,
            windows: windows,
            isSampleData: isSampleData
        )
    }
}

public enum UsageViewMode: String, CaseIterable, Codable, Sendable {
    case account
    case limitType

    public var title: String {
        switch self {
        case .account:
            "Accounts"
        case .limitType:
            "Limit types"
        }
    }
}

public struct QuotaGroupRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let accountID: UUID
    public let accountName: String
    public let visibleEmail: String?
    public let provider: QuotaProviderID
    public let window: QuotaWindow

    public init(account: QuotaAccount, window: QuotaWindow) {
        id = "\(account.id.uuidString)-\(window.id)"
        accountID = account.id
        accountName = account.displayName
        visibleEmail = account.visibleEmail
        provider = account.provider
        self.window = window
    }
}

public struct QuotaGroup: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let kind: QuotaWindowKind?
    public let account: QuotaAccount?
    public let rows: [QuotaGroupRow]

    public init(
        id: String,
        title: String,
        kind: QuotaWindowKind?,
        account: QuotaAccount?,
        rows: [QuotaGroupRow]
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.account = account
        self.rows = rows
    }
}

public enum QuotaGrouping {
    public static func groups(
        accounts: [QuotaAccount],
        mode: UsageViewMode
    ) -> [QuotaGroup] {
        switch mode {
        case .account:
            return accounts.map { account in
                QuotaGroup(
                    id: "account-\(account.id.uuidString)",
                    title: account.displayName,
                    kind: nil,
                    account: account,
                    rows: account.windows.map { QuotaGroupRow(account: account, window: $0) }
                )
            }

        case .limitType:
            return QuotaWindowKind.allCases.compactMap { kind in
                let matching = accounts.flatMap { account in
                    account.windows
                        .filter { $0.kind == kind }
                        .map { QuotaGroupRow(account: account, window: $0) }
                }
                guard !matching.isEmpty else { return nil }
                return QuotaGroup(
                    id: "limit-\(kind.rawValue)",
                    title: kind.defaultTitle,
                    kind: kind,
                    account: nil,
                    rows: matching
                )
            }
        }
    }
}
