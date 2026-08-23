import AppKit
import Combine
import Sparkle

@MainActor
final class QuotaBarSparkleUpdater: ObservableObject {
    private let controller: SPUStandardUpdaterController
    private var updaterStarted = false

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        // Let the manually managed status item finish launching before presenting an installation hint.
        Task { @MainActor [weak self] in
            self?.startUpdaterIfPossible()
        }
    }

    func checkForUpdates() {
        guard startUpdaterIfPossible() else { return }
        controller.checkForUpdates(nil)
    }

    @discardableResult
    private func startUpdaterIfPossible() -> Bool {
        // `swift run QuotaBar` is a development executable, not an installable app.
        guard Self.isApplicationBundle else { return false }

        guard Self.isUpdateCapableLocation else {
            showInstallationPrompt()
            return false
        }

        if !updaterStarted {
            controller.startUpdater()
            updaterStarted = true
        }
        return true
    }

    private static var isApplicationBundle: Bool {
        Bundle.main.bundleURL.pathExtension.lowercased() == "app"
    }

    private static var userApplicationsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
    }

    private static var isUpdateCapableLocation: Bool {
        let bundleURL = Bundle.main.bundleURL.standardizedFileURL
        let bundlePath = bundleURL.path
        let applicationRoots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true).standardizedFileURL.path,
            userApplicationsURL.standardizedFileURL.path
        ]
        let isInsideApplications = applicationRoots.contains {
            bundlePath.hasPrefix($0 + "/")
        }
        guard isInsideApplications else { return false }

        guard let resourceValues = try? bundleURL.resourceValues(
            forKeys: [.volumeIsReadOnlyKey]
        ) else {
            return false
        }
        return resourceValues.volumeIsReadOnly != true
    }

    private func showInstallationPrompt() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Move QuotaBar to Applications"
        alert.informativeText = "Automatic updates require QuotaBar to run from /Applications or ~/Applications. The current app was opened from a disk image, Downloads, or another temporary location."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Open Applications Folder")
        alert.addButton(withTitle: "Not Now")

        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            installInUserApplications()
        case .alertSecondButtonReturn:
            openApplicationsFolder()
        default:
            break
        }
    }

    private func openApplicationsFolder() {
        let directory = Self.userApplicationsURL
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        NSWorkspace.shared.open(directory)
    }

    private func installInUserApplications() {
        let fileManager = FileManager.default
        let source = Bundle.main.bundleURL.standardizedFileURL
        let directory = Self.userApplicationsURL
        let destination = directory.appendingPathComponent(source.lastPathComponent)

        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: source, to: destination)

            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(
                at: destination,
                configuration: configuration
            ) { [weak self] _, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let error {
                        self.showInstallationError(error)
                    } else {
                        NSApp.terminate(nil)
                    }
                }
            }
        } catch {
            showInstallationError(error)
        }
    }

    private func showInstallationError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Could not move QuotaBar"
        alert.informativeText = "Copy QuotaBar to the Applications folder in Finder, relaunch it there, and try the update again.\n\n\(error.localizedDescription)"
        alert.addButton(withTitle: "Open Applications Folder")
        alert.addButton(withTitle: "Close")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            openApplicationsFolder()
        }
    }
}
