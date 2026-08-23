import QuotaBarUI
import SwiftUI

@main
struct QuotaBarApp: App {
    @StateObject private var model: QuotaBarModel
    @StateObject private var updater: QuotaBarSparkleUpdater

    init() {
        _model = StateObject(wrappedValue: QuotaBarModel())
        _updater = StateObject(wrappedValue: QuotaBarSparkleUpdater())
    }

    var body: some Scene {
        MenuBarExtra {
            QuotaMonitorView(
                model: model,
                updateAction: updater.checkForUpdates
            )
        } label: {
            Label(
                model.menuTitle,
                systemImage: "gauge.with.dots.needle.33percent"
            )
        }
        .menuBarExtraStyle(.window)
    }
}
