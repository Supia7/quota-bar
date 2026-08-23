import AppKit
import QuotaBarUI
import SwiftUI

@MainActor
@main
final class QuotaBarAppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let model = QuotaBarModel()
    private let updater = QuotaBarSparkleUpdater()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var hostingController: NSHostingController<QuotaMonitorView>?

    static func main() {
        let application = NSApplication.shared
        let delegate = QuotaBarAppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        configurePopover()
        scheduleVisibilityFallbackCheck()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = item.button else {
            return
        }

        let image = NSImage(
            systemSymbolName: "gauge.with.dots.needle.33percent",
            accessibilityDescription: "QuotaBar"
        )
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageOnly
        button.toolTip = "QuotaBar"
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp])
        statusItem = item
    }

    private func configurePopover() {
        let rootView = QuotaMonitorView(
            model: model,
            updateAction: updater.checkForUpdates
        )
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        self.hostingController = hostingController

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = hostingController
        popover.contentSize = NSSize(width: 620, height: 240)
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else {
            return
        }

        if popover.isShown {
            popover.performClose(sender)
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        popover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .minY
        )
        hostingController?.view.window?.initialFirstResponder = hostingController?.view
    }

    func popoverDidClose(_ notification: Notification) {
        statusItem?.button?.state = .off
    }

    private func scheduleVisibilityFallbackCheck() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, let statusItem else { return }
            guard !statusItem.isVisible else { return }

            // macOS can hide a Menu Bar item from System Settings. Keep a Dock
            // entry available instead of leaving the user with no entry point.
            NSApp.setActivationPolicy(.regular)
        }
    }

}
