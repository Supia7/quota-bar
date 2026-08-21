import Foundation

public enum QuotaProviderID: String, CaseIterable, Codable, Sendable {
    case claude
    case codex
    case kimi

    public var displayName: String {
        switch self {
        case .claude:
            "Claude"
        case .codex:
            "Codex"
        case .kimi:
            "Kimi"
        }
    }
}

public struct QuotaWindow: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    private let rawRemainingFraction: Double
    public let resetAt: Date?

    public init(
        id: String,
        title: String,
        remainingFraction: Double,
        resetAt: Date?
    ) {
        self.id = id
        self.title = title
        rawRemainingFraction = remainingFraction
        self.resetAt = resetAt
    }

    public var remainingFraction: Double {
        min(max(rawRemainingFraction, 0), 1)
    }

    public var remainingPercentage: Int {
        Int((remainingFraction * 100).rounded())
    }
}

public struct QuotaAccount: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let provider: QuotaProviderID
    public let displayName: String
    public let windows: [QuotaWindow]
    public let isSampleData: Bool

    public init(
        id: UUID = UUID(),
        provider: QuotaProviderID,
        displayName: String,
        windows: [QuotaWindow],
        isSampleData: Bool
    ) {
        self.id = id
        self.provider = provider
        self.displayName = displayName
        self.windows = windows
        self.isSampleData = isSampleData
    }
}
