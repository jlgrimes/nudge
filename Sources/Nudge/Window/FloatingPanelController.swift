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
        panel.animationBehavior = .utilityWindow
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: NudgePanelView(store: store))

        store.presentationDidChange = { [weak self] in
            self?.updatePresentation()
        }
        store.panelLayoutDidChange = { [weak self] in
            self?.updatePresentation()
        }
        store.debugScenarioDidRun = { [weak self] in
            self?.focusPanel()
        }

        position(size: initialSize, animated: false)
        panel.orderFrontRegardless()
    }

    func show() {
        updatePresentation()
        panel.orderFrontRegardless()
    }

    private func focusPanel() {
        panel.makeKeyAndOrderFront(nil)
    }

    private func updatePresentation() {
        let targetSize = Self.size(for: store)
        position(size: targetSize, animated: true)
        panel.contentView?.needsDisplay = true

        if store.presentation == .capture {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    private func position(size: NSSize, animated: Bool) {
        let mouseLocation = NSEvent.mouseLocation
        let pointerScreen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
        guard let screen = panel.screen ?? pointerScreen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let rightMargin: CGFloat = 18
        let topMargin: CGFloat = 54
        let origin = NSPoint(
            x: visible.maxX - size.width - rightMargin,
            y: max(visible.minY + 18, visible.maxY - topMargin - size.height)
        )
        let frame = NSRect(origin: origin, size: size)

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.24
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
            let contentHeight = CGFloat(store.activeNudges.count * 40)
            return NSSize(width: 372, height: min(540, max(56, contentHeight)))
        case .peek:
            return NSSize(width: 360, height: 86)
        case .expanded:
            let recapHeight: CGFloat = store.recapMessage == nil ? 0 : 64
            let upcomingHeaderHeight: CGFloat = store.futureNudges.isEmpty ? 0 : 26
            let visibleItemCount = store.activeNudges.count + store.futureNudges.count
            let contentHeight = CGFloat(146 + visibleItemCount * 40) + recapHeight + upcomingHeaderHeight
            return NSSize(width: 372, height: min(620, max(180, contentHeight)))
        case .capture:
            return NSSize(width: 420, height: store.capturePreview == nil ? 122 : 194)
        }
    }
}
