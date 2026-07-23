import AppKit
import Foundation

@MainActor
final class AppContextMonitor {
    private var activationObserver: NSObjectProtocol?
    private let onContext: (ContextEvent) -> Void

    init(onContext: @escaping (ContextEvent) -> Void) {
        self.onContext = onContext

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                let bundleIdentifier = application.bundleIdentifier
            else { return }

            let name = application.localizedName ?? "An app"
            Task { @MainActor [weak self] in
                self?.handleActivation(bundleIdentifier: bundleIdentifier, name: name)
            }
        }
    }

    private func handleActivation(bundleIdentifier: String, name: String) {
        guard let context = ContextEvent.activatedApplication(
            bundleIdentifier: bundleIdentifier,
            name: name
        ) else { return }

        onContext(context)
    }
}
