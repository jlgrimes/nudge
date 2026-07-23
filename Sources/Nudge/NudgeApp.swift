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
    private var hotKeyManager: GlobalHotKeyManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panelController = FloatingPanelController(store: .shared)
        hotKeyManager = GlobalHotKeyManager {
            NudgeStore.shared.showCapture()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
