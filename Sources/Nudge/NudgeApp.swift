import AppKit
import SwiftUI

@main
struct NudgeApp: App {
    @NSApplicationDelegateAdaptor(NudgeAppDelegate.self) private var appDelegate
    private let store = NudgeStore.shared

    var body: some Scene {
        MenuBarExtra("Nudge", systemImage: "sparkles") {
            NudgeMenuView(store: store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            NudgeSettingsView(store: store)
        }
    }
}

@MainActor
final class NudgeAppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: FloatingPanelController?
    private var debugPanelController: DebugPanelController?
    private var hotKeyManager: GlobalHotKeyManager?
    private var appContextMonitor: AppContextMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panelController = FloatingPanelController(store: .shared)
        debugPanelController = DebugPanelController(store: .shared)
        hotKeyManager = GlobalHotKeyManager {
            NudgeStore.shared.showCapture()
        }
        appContextMonitor = AppContextMonitor { context in
            NudgeStore.shared.receive(context: context)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
