import QuotaBarUI
import SwiftUI

@main
struct QuotaBarApp: App {
    @StateObject private var model: QuotaBarModel

    init() {
        _model = StateObject(wrappedValue: QuotaBarModel())
    }

    var body: some Scene {
        MenuBarExtra {
            QuotaMonitorView(model: model)
        } label: {
            Label(
                model.menuTitle,
                systemImage: "gauge.with.dots.needle.33percent"
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            QuotaSettingsView(model: model)
        }
    }
}
