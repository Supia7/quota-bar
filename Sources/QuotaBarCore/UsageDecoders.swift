import Foundation

public enum UsageDecoderError: Error, Equatable {
    case invalidJSON
    case invalidPayload
}

public enum ClaudeUsageDecoder {
    public static func decode(_ data: Data) throws -> [QuotaWindow] {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw UsageDecoderError.invalidJSON
        }

        var windows: [QuotaWindow] = []
        if let fiveHour = object(in: root["five_hour"]),
           let window = window(
               id: "claude-five-hour",
               kind: .fiveHour,
               title: "5-hour window",
               object: fiveHour
           ) {
            windows.append(window)
        }
        if let weekly = object(in: root["seven_day"]),
           let window = window(
               id: "claude-weekly",
               kind: .weekly,
               title: "Weekly",
               object: weekly
           ) {
            windows.append(window)
        }
        if let fable = object(in: root["seven_day_fable"]),
           let window = window(
               id: "claude-fable-weekly",
               kind: .fableWeekly,
               title: "Fable weekly",
               object: fable
           ) {
            windows.append(window)
        }

        if let limits = root["limits"] as? [[String: Any]] {
            for limit in limits {
                let kind = (limit["kind"] as? String)?.lowercased() ?? ""
                let modelName = modelDisplayName(in: limit)?.lowercased() ?? ""
                let isFable = kind.contains("weekly") && modelName.contains("fable")
                let isSession = kind == "session" || kind == "five_hour"
                let isWeekly = kind == "weekly" || kind == "seven_day"

                let windowKind: QuotaWindowKind
                let id: String
                let title: String
                if isFable {
                    windowKind = .fableWeekly
                    id = "claude-fable-weekly"
                    title = "Fable weekly"
                } else if isSession {
                    windowKind = .fiveHour
                    id = "claude-five-hour"
                    title = "5-hour window"
                } else if isWeekly {
                    windowKind = .weekly
                    id = "claude-weekly"
                    title = "Weekly"
                } else {
                    continue
                }

                guard let parsed = window(
                    id: id,
                    kind: windowKind,
                    title: title,
                    object: limit
                ) else {
                    continue
                }
                if !windows.contains(where: { $0.id == parsed.id }) {
                    windows.append(parsed)
                }
            }
        }

        if !windows.contains(where: { $0.kind == .fableWeekly }) {
            windows.append(
                QuotaWindow(
                    id: "claude-fable-weekly",
                    kind: .fableWeekly,
                    title: "Fable weekly",
                    remainingFraction: nil,
                    resetAt: nil
                )
            )
        }

        guard !windows.isEmpty else {
            throw UsageDecoderError.invalidPayload
        }
        return windows
    }

    private static func window(
        id: String,
        kind: QuotaWindowKind,
        title: String,
        object: [String: Any]
    ) -> QuotaWindow? {
        guard let usedPercent = number(in: object, keys: ["utilization", "percent", "used_percent"]) else {
            return nil
        }
        return QuotaWindow(
            id: id,
            kind: kind,
            title: title,
            remainingFraction: 1 - usedPercent / 100,
            resetAt: date(in: object, keys: ["resets_at", "reset_at"])
        )
    }

    private static func object(in value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    private static func number(
        in object: [String: Any],
        keys: [String]
    ) -> Double? {
        for key in keys {
            if let value = object[key] as? NSNumber {
                return value.doubleValue
            }
            if let value = object[key] as? String, let number = Double(value) {
                return number
            }
        }
        return nil
    }

    private static func date(
        in object: [String: Any],
        keys: [String]
    ) -> Date? {
        for key in keys {
            if let value = object[key] as? NSNumber {
                return Date(timeIntervalSince1970: value.doubleValue)
            }
            if let value = object[key] as? String {
                if let date = ISO8601DateFormatter().date(from: value) {
                    return date
                }
            }
        }
        return nil
    }

    private static func modelDisplayName(in object: [String: Any]) -> String? {
        guard
            let scope = object["scope"] as? [String: Any],
            let model = scope["model"] as? [String: Any]
        else {
            return nil
        }
        return model["display_name"] as? String ?? model["name"] as? String
    }
}

public enum CodexUsageDecoder {
    public static func decode(_ data: Data) throws -> [QuotaWindow] {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rateLimit = root["rate_limit"] as? [String: Any]
        else {
            throw UsageDecoderError.invalidPayload
        }

        // Codex has returned the weekly window as `secondary_window` in older
        // responses and as `primary_window` in newer responses. Prefer the
        // secondary window when present, then fall back to primary.
        let window = (rateLimit["secondary_window"] as? [String: Any])
            ?? (rateLimit["primary_window"] as? [String: Any])
        guard let window,
              let usedPercent = number(in: window, keys: ["used_percent", "utilization"])
        else {
            throw UsageDecoderError.invalidPayload
        }

        return [
            QuotaWindow(
                id: "codex-weekly",
                kind: .weekly,
                title: "Weekly",
                remainingFraction: 1 - usedPercent / 100,
                resetAt: date(in: window, keys: ["reset_at", "resets_at"])
            )
        ]
    }

    private static func number(
        in object: [String: Any],
        keys: [String]
    ) -> Double? {
        for key in keys {
            if let value = object[key] as? NSNumber {
                return value.doubleValue
            }
            if let value = object[key] as? String, let number = Double(value) {
                return number
            }
        }
        return nil
    }

    private static func date(
        in object: [String: Any],
        keys: [String]
    ) -> Date? {
        for key in keys {
            if let value = object[key] as? NSNumber {
                return Date(timeIntervalSince1970: value.doubleValue)
            }
            if let value = object[key] as? String,
               let date = ISO8601DateFormatter().date(from: value) {
                return date
            }
        }
        return nil
    }
}
