import AppKit
import SwiftUI

@MainActor
final class NudgePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class FloatingPanelController {
    private let panel: NudgePanel
    private let store: NudgeStore

    init(store: NudgeStore) {
        self.store = store
        let initialSize = Self.size(for: store)
        panel = NudgePanel(
            contentRect: NSRect(origin: .zero, size: initialSize),
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
        panel.contentView = NSHostingView(rootView: NudgePanelView(store: store))

        store.presentationDidChange = { [weak self] in
            self?.updatePresentation()
        }

        position(size: initialSize, animated: false)
        panel.orderFrontRegardless()
    }

    func show() {
        updatePresentation()
        panel.orderFrontRegardless()
    }

    private func updatePresentation() {
        let targetSize = Self.size(for: store)
        // Animating a transparent NSPanel's frame while Liquid Glass is sampling
        // the desktop can leave a stale blur region behind on some displays.
        // SwiftUI still animates the content; resize the compositor surface atomically.
        position(size: targetSize, animated: false)
        panel.contentView?.needsDisplay = true

        if store.presentation == .capture {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    private func position(size: NSSize, animated: Bool) {
        guard let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let rightMargin: CGFloat = 18
        let centerY = visible.minY + (visible.height * 0.54)
        let origin = NSPoint(
            x: visible.maxX - size.width - rightMargin,
            y: min(max(centerY - size.height / 2, visible.minY + 18), visible.maxY - size.height - 18)
        )
        let frame = NSRect(origin: origin, size: size)

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.28
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private static func size(for store: NudgeStore) -> NSSize {
        switch store.presentation {
        case .collapsed:
            NSSize(width: 72, height: 72)
        case .peek:
            NSSize(width: 390, height: 112)
        case .expanded:
            NSSize(width: 410, height: min(650, CGFloat(190 + store.activeNudges.count * 92)))
        case .capture:
            NSSize(width: 430, height: store.capturePreview == nil ? 180 : 254)
        }
    }
}
