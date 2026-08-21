import QuotaBarUI
import SwiftUI

@main
struct QuotaBarPreviewApp: App {
    @StateObject private var model = QuotaBarModel()

    var body: some Scene {
        WindowGroup("QuotaBar Preview") {
            QuotaMonitorView(model: model)
        }
        .defaultSize(width: 640, height: 720)

        Settings {
            QuotaSettingsView(model: model)
        }
    }
}
