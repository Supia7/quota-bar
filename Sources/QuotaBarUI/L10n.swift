import Foundation
import QuotaBarCore

public enum L10n {
    public static func string(_ key: String) -> String {
        Bundle.module.localizedString(forKey: key, value: key, table: "Localizable")
    }

    public static func windowTitle(_ kind: QuotaWindowKind) -> String {
        string("quota.window.\(kind.rawValue)")
    }

    public static func updateAvailable(_ version: String) -> String {
        String(format: string("update.available_format"), version)
    }

    public static func updateUpToDate(_ version: String) -> String {
        String(format: string("update.up_to_date_format"), version)
    }

    public static func accountCount(_ count: Int) -> String {
        String(format: string("limit.accounts_format"), count)
    }

    public static func localUsageTokens(_ count: Int) -> String {
        String(format: string("usage.tokens_format"), LocalUsageFormatter.tokenCount(count))
    }

    public static func localUsageSessions(_ count: Int) -> String {
        String(format: string("usage.sessions_format"), count)
    }

    public static func viewTitle(_ mode: UsageViewMode) -> String {
        string(mode == .account ? "view.accounts" : "view.limit_types")
    }

    public static func resetNotice(_ event: QuotaResetEvent) -> String {
        String(format: string("monitor.reset_detected_format"),
            event.provider.displayName,
            windowTitle(event.windowKind),
            event.currentRemainingPercentage
        )
    }
}
