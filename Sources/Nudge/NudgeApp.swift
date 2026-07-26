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
    private var runtimeController: NudgeRuntimeController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if NudgeRuntime.debugToolsEnabled {
            NudgeStore.shared.resetDemo()
            debugPanelController = DebugPanelController(store: .shared)
        } else {
            runtimeController = NudgeRuntimeController(store: .shared)
        }

        panelController = FloatingPanelController(store: .shared)
        hotKeyManager = GlobalHotKeyManager {
            NudgeStore.shared.showCapture()
        }
        appContextMonitor = AppContextMonitor { context in
            NudgeStore.shared.receive(context: context)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        runtimeController?.flush()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
