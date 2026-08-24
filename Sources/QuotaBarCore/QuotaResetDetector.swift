import Foundation

public struct QuotaResetObservation: Codable, Equatable, Sendable {
    public let accountID: UUID
    public let provider: QuotaProviderID
    public let windowID: String
    public let remainingFraction: Double?
    public let resetAt: Date?

    public init(
        accountID: UUID,
        provider: QuotaProviderID,
        windowID: String,
        remainingFraction: Double?,
        resetAt: Date?
    ) {
        self.accountID = accountID
        self.provider = provider
        self.windowID = windowID
        self.remainingFraction = remainingFraction
        self.resetAt = resetAt
    }
}

public struct QuotaResetEvent: Identifiable, Equatable, Sendable {
    public let accountID: UUID
    public let provider: QuotaProviderID
    public let accountLabel: String
    public let windowID: String
    public let windowKind: QuotaWindowKind
    public let windowTitle: String
    public let previousRemainingFraction: Double
    public let currentRemainingFraction: Double
    public let resetAt: Date?
    public let detectedAt: Date

    public init(
        accountID: UUID,
        provider: QuotaProviderID,
        accountLabel: String,
        windowID: String,
        windowKind: QuotaWindowKind,
        windowTitle: String,
        previousRemainingFraction: Double,
        currentRemainingFraction: Double,
        resetAt: Date?,
        detectedAt: Date
    ) {
        self.accountID = accountID
        self.provider = provider
        self.accountLabel = accountLabel
        self.windowID = windowID
        self.windowKind = windowKind
        self.windowTitle = windowTitle
        self.previousRemainingFraction = previousRemainingFraction
        self.currentRemainingFraction = currentRemainingFraction
        self.resetAt = resetAt
        self.detectedAt = detectedAt
    }

    public var id: String {
        let marker = resetAt.map { String(Int($0.timeIntervalSince1970)) }
            ?? String(Int(detectedAt.timeIntervalSince1970))
        return "\(accountID.uuidString)-\(windowID)-\(marker)"
    }

    public var currentRemainingPercentage: Int {
        Int((currentRemainingFraction * 100).rounded())
    }
}

public enum QuotaResetDetector {
    public static let fullQuotaThreshold = 0.98
    public static let depletedQuotaThreshold = 0.85
    public static let minimumRecoveryDelta = 0.20

    public static func observations(from accounts: [QuotaAccount]) -> [QuotaResetObservation] {
        accounts.flatMap { account in
            account.windows.map { window in
                QuotaResetObservation(
                    accountID: account.id,
                    provider: account.provider,
                    windowID: window.id,
                    remainingFraction: window.remainingFraction,
                    resetAt: window.resetAt
                )
            }
        }
    }

    public static func detect(
        previous: [QuotaResetObservation],
        current: [QuotaAccount],
        at date: Date = Date()
    ) -> [QuotaResetEvent] {
        let previousByKey = Dictionary(
            previous.map { (key(accountID: $0.accountID, windowID: $0.windowID), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return current.flatMap { account in
            account.windows.compactMap { window in
                guard
                    let currentFraction = window.remainingFraction,
                    currentFraction >= fullQuotaThreshold,
                    let previousObservation = previousByKey[key(accountID: account.id, windowID: window.id)],
                    let previousFraction = previousObservation.remainingFraction
                else {
                    return nil
                }

                let recoveryDelta = currentFraction - previousFraction
                let recoveredFromDepletion = previousFraction <= depletedQuotaThreshold
                let recoveredByLargeJump = recoveryDelta >= minimumRecoveryDelta
                guard recoveredFromDepletion || recoveredByLargeJump else {
                    return nil
                }

                let label = account.alias.trimmingCharacters(in: .whitespacesAndNewlines)
                return QuotaResetEvent(
                    accountID: account.id,
                    provider: account.provider,
                    accountLabel: label.isEmpty ? account.provider.displayName : label,
                    windowID: window.id,
                    windowKind: window.kind,
                    windowTitle: window.title,
                    previousRemainingFraction: previousFraction,
                    currentRemainingFraction: currentFraction,
                    resetAt: window.resetAt,
                    detectedAt: date
                )
            }
        }
    }

    private static func key(accountID: UUID, windowID: String) -> String {
        "\(accountID.uuidString)-\(windowID)"
    }
}

public struct JSONQuotaResetObservationStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL = JSONQuotaResetObservationStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public func load() throws -> [QuotaResetObservation] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        return try JSONDecoder().decode(
            [QuotaResetObservation].self,
            from: Data(contentsOf: fileURL)
        )
    }

    public func save(_ observations: [QuotaResetObservation]) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(observations).write(to: fileURL, options: .atomic)
    }

    public static func defaultFileURL(
        fileManager: FileManager = .default
    ) -> URL {
        let supportDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
        return supportDirectory
            .appendingPathComponent("QuotaBar", isDirectory: true)
            .appendingPathComponent("reset-observations.json")
    }
}
