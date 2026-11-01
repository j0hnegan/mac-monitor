import AppKit
import SwiftUI

/// The dropdown panel under the menu bar icon: a borderless glass panel that stays pinned
/// to its top edge as rows expand, and slides in and out.
@MainActor
final class PanelController {
    private let engine: MonitorEngine
    private let panel: KeyablePanel
    private let hosting: SizeReportingHostingView
    private var clickOutsideMonitor: Any?
    private var escapeMonitor: Any?

    private static let width: CGFloat = 360
    private static let cornerRadius: CGFloat = 16
    private static let gapBelowMenuBar: CGFloat = 6
    /// How far the panel travels as it slides in or out.
    private static let slide: CGFloat = 8

    var isOpen: Bool { panel.isVisible }

    init(engine: MonitorEngine, openSettings: @escaping () -> Void) {
        self.engine = engine
        panel = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 300),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        hosting = SizeReportingHostingView(rootView: AnyView(PanelView(engine: engine, openSettings: openSettings)))
        // Report an intrinsic size for measuring, but don't let the hosting view resize the window:
        // it would grow from the bottom-left corner instead of keeping the top edge pinned.
        hosting.sizingOptions = [.intrinsicContentSize]

        hosting.onIntrinsicSizeChange = { [weak self] height in self?.resize(toHeight: height) }

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovable = false
        panel.contentView = Self.glassBackground(around: hosting, cornerRadius: Self.cornerRadius)
    }

    func toggle(below button: NSStatusBarButton) {
        isOpen ? close() : open(below: button)
    }

    func open(below button: NSStatusBarButton) {
        guard let buttonFrame = button.window?.frame, let screen = button.window?.screen else { return }
        engine.isPanelOpen = true

        let height = hosting.fittingSize.height
        let visible = screen.visibleFrame
        // Hang from the icon's left edge like a system menu, shifting left only if it would run off screen.
        let x = min(max(buttonFrame.minX, visible.minX + 8), visible.maxX - Self.width - 8)
        let top = buttonFrame.minY - Self.gapBelowMenuBar
        let frame = NSRect(x: x, y: top - height, width: Self.width, height: height)

        panel.setFrame(frame.offsetBy(dx: 0, dy: Self.slide), display: false)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
            panel.animator().alphaValue = 1
        } completionHandler: { [panel] in
            MainActor.assumeIsolated { panel.invalidateShadow() }
        }
        startMonitoringDismissal()
    }

    func close() {
        guard isOpen else { return }
        engine.isPanelOpen = false
        stopMonitoringDismissal()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(panel.frame.offsetBy(dx: 0, dy: Self.slide), display: true)
            panel.animator().alphaValue = 0
        } completionHandler: { [panel] in
            MainActor.assumeIsolated { panel.orderOut(nil) }
        }
    }

    /// Grows or shrinks from the bottom so the top edge stays under the menu bar.
    private func resize(toHeight height: CGFloat) {
        guard isOpen, height > 0, abs(panel.frame.height - height) > 0.5 else { return }
        var frame = panel.frame
        frame.origin.y = frame.maxY - height
        frame.size.height = height
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        } completionHandler: { [panel] in
            MainActor.assumeIsolated { panel.invalidateShadow() }
        }
    }

    private func startMonitoringDismissal() {
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event } // Escape
            self?.close()
            return nil
        }
    }

    private func stopMonitoringDismissal() {
        [clickOutsideMonitor, escapeMonitor].compactMap { $0 }.forEach(NSEvent.removeMonitor)
        clickOutsideMonitor = nil
        escapeMonitor = nil
    }

    /// Liquid Glass on macOS 26+. The 14.4 SDK this builds against doesn't declare NSGlassEffectView,
    /// so it's looked up at runtime; older systems get the standard popover blur instead.
    /// Both sit in a rounded, clipped container: the window shadow is traced from the window's shape,
    /// and without the clip it came out as a square outline around the rounded glass.
    static func glassBackground(around content: NSView, cornerRadius: CGFloat) -> NSView {
        let background: NSView
        if let glassClass = NSClassFromString("NSGlassEffectView") as? NSView.Type {
            background = glassClass.init(frame: .zero)
            background.setValue(content, forKey: "contentView")
            background.setValue(cornerRadius, forKey: "cornerRadius")
        } else {
            let blur = NSVisualEffectView()
            blur.material = .popover
            blur.state = .active
            content.autoresizingMask = [.width, .height]
            blur.addSubview(content)
            background = blur
        }

        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = cornerRadius
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        background.autoresizingMask = [.width, .height]
        container.addSubview(background)
        return container
    }
}

/// Tells the panel when the SwiftUI content's natural size changes (e.g. a row expanding).
private final class SizeReportingHostingView: NSHostingView<AnyView> {
    var onIntrinsicSizeChange: ((CGFloat) -> Void)?

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        // Read the new size after SwiftUI finishes the update that triggered this.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            onIntrinsicSizeChange?(fittingSize.height)
        }
    }
}

/// Borderless panels can't become key by default, which would break buttons, menus, and alerts.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
