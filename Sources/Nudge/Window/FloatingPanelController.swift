import AppKit
import SwiftUI

@MainActor
final class NudgePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class GlassViewportHostingView<Content: View>: NSView {
    private let hostingView: NSHostingView<Content>
    private let interactionInset: CGFloat

    init(rootView: Content, interactionInset: CGFloat) {
        self.hostingView = NSHostingView(rootView: rootView)
        self.interactionInset = interactionInset
        super.init(frame: .zero)

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.insetBy(dx: interactionInset, dy: interactionInset).contains(point) else {
            return nil
        }
        return super.hitTest(point)
    }
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
        panel.contentView = GlassViewportHostingView(
            rootView: NudgePanelView(store: store),
            interactionInset: NudgePanelLayout.glassViewportInset
        )

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
        let rightMargin = NudgePanelLayout.surfaceRightMargin - NudgePanelLayout.glassViewportInset
        let topMargin = NudgePanelLayout.surfaceTopMargin - NudgePanelLayout.glassViewportInset
        let bottomMargin = 18 - NudgePanelLayout.glassViewportInset
        let origin = NSPoint(
            x: visible.maxX - size.width - rightMargin,
            y: max(visible.minY + bottomMargin, visible.maxY - topMargin - size.height)
        )
        let frame = NSRect(origin: origin, size: size)

        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.36
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private static func size(for store: NudgeStore) -> NSSize {
        let activeCount = store.activeNudges.count
        let glassInsets = NudgePanelLayout.glassViewportInset * 2
        let standardPanelWidth = NudgePanelLayout.standardContentWidth + glassInsets
        let capturePanelWidth = NudgePanelLayout.captureContentWidth + glassInsets

        switch store.presentation {
        case .collapsed:
            let contentHeight = max(
                56,
                CGFloat(activeCount * 40) + NudgePanelLayout.surfaceVerticalPadding * 2
            )
            return NSSize(
                width: standardPanelWidth,
                height: min(608, contentHeight) + glassInsets
            )
        case .peek:
            return NSSize(
                width: standardPanelWidth,
                height: 86 + glassInsets
            )
        case .expanded:
            let recapHeight: CGFloat = store.recapMessage == nil ? 0 : 64
            let upcomingHeaderHeight: CGFloat = store.futureNudges.isEmpty ? 0 : 26
            let itemCount = activeCount + store.futureNudges.count
            let listHeight = CGFloat(146 + itemCount * 40) + recapHeight + upcomingHeaderHeight
            let contentHeight = max(180, listHeight)
            return NSSize(width: standardPanelWidth, height: min(638, contentHeight) + glassInsets)
        case .capture:
            let contentHeight: CGFloat = store.capturePreview == nil ? 122 : 194
            return NSSize(width: capturePanelWidth, height: contentHeight + glassInsets)
        }
    }
}
