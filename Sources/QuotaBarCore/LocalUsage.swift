import Foundation

public struct LocalUsageSummary: Equatable, Sendable {
    public let provider: QuotaProviderID
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheReadTokens: Int
    public let cacheWriteTokens: Int
    public let requestCount: Int
    public let sessionCount: Int

    public init(
        provider: QuotaProviderID,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cacheReadTokens: Int = 0,
        cacheWriteTokens: Int = 0,
        requestCount: Int = 0,
        sessionCount: Int = 0
    ) {
        self.provider = provider
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.requestCount = requestCount
        self.sessionCount = sessionCount
    }

    public var totalTokens: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens
    }

    public var isEmpty: Bool {
        requestCount == 0 && totalTokens == 0
    }
}

public struct LocalUsageScanner: Sendable {
    private static let maxFileBytes = 20 * 1024 * 1024
    private let homeDirectory: URL

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    public func scanToday(
        at now: Date = Date(),
        calendar: Calendar = .current
    ) -> [QuotaProviderID: LocalUsageSummary] {
        let start = calendar.startOfDay(for: now)
        let claudeFiles = recentJSONLFiles(
            in: homeDirectory.appendingPathComponent(".claude/projects", isDirectory: true),
            modifiedSince: start
        )
        let codexDay = codexDayDirectory(start: start, calendar: calendar)
        let codexFiles = recentJSONLFiles(in: codexDay, modifiedSince: start)
            + recentJSONLFiles(
                in: homeDirectory.appendingPathComponent(".codex/archived_sessions", isDirectory: true),
                modifiedSince: start
            )

        var result: [QuotaProviderID: LocalUsageSummary] = [:]
        if let claude = try? scan(
            files: claudeFiles,
            provider: .claude,
            now: now,
            calendar: calendar
        ), !claude.isEmpty {
            result[.claude] = claude
        }
        if let codex = try? scan(
            files: codexFiles,
            provider: .codex,
            now: now,
            calendar: calendar
        ), !codex.isEmpty {
            result[.codex] = codex
        }
        return result
    }

    public func scan(
        files: [URL],
        provider: QuotaProviderID,
        now: Date,
        calendar: Calendar = .current
    ) throws -> LocalUsageSummary {
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            return LocalUsageSummary(provider: provider)
        }
        let formatter = ISO8601DateFormatter()
        var inputTokens = 0
        var outputTokens = 0
        var cacheReadTokens = 0
        var cacheWriteTokens = 0
        var requestCount = 0
        var sessionIDs = Set<String>()

        for file in files {
            let values = try FileManager.default.attributesOfItem(atPath: file.path)
            if let size = values[.size] as? NSNumber,
               size.intValue > Self.maxFileBytes {
                continue
            }
            let data = try Data(contentsOf: file, options: .mappedIfSafe)
            for line in data.split(separator: 0x0A) {
                guard
                    let json = try? JSONSerialization.jsonObject(
                        with: Data(line),
                        options: [.fragmentsAllowed]
                    ),
                    let record = json as? [String: Any],
                    let timestamp = parseDate(record["timestamp"], formatter: formatter),
                    timestamp >= start,
                    timestamp < end
                else {
                    continue
                }

                let parsed: TokenDelta?
                switch provider {
                case .claude:
                    parsed = claudeDelta(record)
                case .codex:
                    parsed = codexDelta(record)
                }
                guard let parsed else { continue }

                inputTokens += parsed.inputTokens
                outputTokens += parsed.outputTokens
                cacheReadTokens += parsed.cacheReadTokens
                cacheWriteTokens += parsed.cacheWriteTokens
                requestCount += 1
                sessionIDs.insert(
                    sessionID(in: record, fallback: file.deletingPathExtension().lastPathComponent)
                )
            }
        }

        return LocalUsageSummary(
            provider: provider,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheReadTokens,
            cacheWriteTokens: cacheWriteTokens,
            requestCount: requestCount,
            sessionCount: sessionIDs.count
        )
    }

    private func recentJSONLFiles(in directory: URL, modifiedSince: Date) -> [URL] {
        let manager = FileManager.default
        guard manager.fileExists(atPath: directory.path) else { return [] }
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        guard let enumerator = manager.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []
        for case let file as URL in enumerator {
            guard file.pathExtension.lowercased() == "jsonl" else { continue }
            guard let values = try? file.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate,
                  modified >= modifiedSince
            else {
                continue
            }
            files.append(file)
        }
        return files.sorted { $0.path < $1.path }
    }

    private func codexDayDirectory(start: Date, calendar: Calendar) -> URL {
        let components = calendar.dateComponents([.year, .month, .day], from: start)
        let year = String(format: "%04d", components.year ?? 0)
        let month = String(format: "%02d", components.month ?? 0)
        let day = String(format: "%02d", components.day ?? 0)
        return homeDirectory
            .appendingPathComponent(".codex/sessions", isDirectory: true)
            .appendingPathComponent(year, isDirectory: true)
            .appendingPathComponent(month, isDirectory: true)
            .appendingPathComponent(day, isDirectory: true)
    }

    private func claudeDelta(_ record: [String: Any]) -> TokenDelta? {
        guard record["type"] as? String == "assistant",
              let message = record["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any]
        else {
            return nil
        }
        return TokenDelta(
            inputTokens: int(usage["input_tokens"]),
            outputTokens: int(usage["output_tokens"]),
            cacheReadTokens: int(usage["cache_read_input_tokens"]),
            cacheWriteTokens: int(usage["cache_creation_input_tokens"])
        )
    }

    private func codexDelta(_ record: [String: Any]) -> TokenDelta? {
        guard record["type"] as? String == "event_msg",
              let payload = record["payload"] as? [String: Any],
              payload["type"] as? String == "token_count",
              let info = payload["info"] as? [String: Any],
              let usage = info["last_token_usage"] as? [String: Any]
        else {
            return nil
        }
        return TokenDelta(
            inputTokens: int(usage["input_tokens"]),
            outputTokens: int(usage["output_tokens"]),
            cacheReadTokens: int(usage["cached_input_tokens"]),
            cacheWriteTokens: int(usage["cache_write_input_tokens"])
        )
    }

    private func sessionID(in record: [String: Any], fallback: String) -> String {
        if let value = record["sessionId"] as? String, !value.isEmpty { return value }
        if let value = record["session_id"] as? String, !value.isEmpty { return value }
        if let payload = record["payload"] as? [String: Any],
           let value = payload["session_id"] as? String,
           !value.isEmpty {
            return value
        }
        return fallback
    }

    private func parseDate(_ value: Any?, formatter: ISO8601DateFormatter) -> Date? {
        guard let value = value as? String else { return nil }
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    private func int(_ value: Any?) -> Int {
        if let value = value as? Int { return max(0, value) }
        if let value = value as? NSNumber { return max(0, value.intValue) }
        return 0
    }

    private struct TokenDelta {
        let inputTokens: Int
        let outputTokens: Int
        let cacheReadTokens: Int
        let cacheWriteTokens: Int
    }
}

public enum LocalUsageFormatter {
    public static func tokenCount(_ count: Int) -> String {
        if count >= 1_000_000_000 { return String(format: "%.1fB", Double(count) / 1_000_000_000) }
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }
}
