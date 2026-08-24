import QuotaBarCore
import QuotaBarUI
import SwiftUI

@main
struct QuotaBarPreviewApp: App {
    @StateObject private var model = QuotaBarModel(
        provider: SampleQuotaProvider(),
        localUsageScanner: LocalUsageScanner(
            homeDirectory: URL(fileURLWithPath: "/tmp/QuotaBarPreview-no-user-data")
        )
    )

    var body: some Scene {
        WindowGroup("QuotaBar Preview") {
            QuotaMonitorView(model: model)
        }
        .defaultSize(width: 420, height: 500)
    }
}
