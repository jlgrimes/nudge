import AppKit
import SwiftUI

@MainActor
final class DebugPanelController {
    private let panel: NudgePanel

    init(store: NudgeStore) {
        let size = NSSize(width: 730, height: 64)
        panel = NudgePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: DebugPanelView(store: store))

        position(size: size)
        panel.orderFrontRegardless()
    }

    private func position(size: NSSize) {
        let mouseLocation = NSEvent.mouseLocation
        let pointerScreen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
        guard let screen = pointerScreen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.minY + 18
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}
