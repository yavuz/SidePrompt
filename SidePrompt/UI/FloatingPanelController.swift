import AppKit
import SwiftUI

/// Detached floating panel, separate from the menu bar.
@MainActor
final class FloatingPanelController: NSObject, NSWindowDelegate {
    /// Lets `KeyCommandRouter` tell the queue panel apart from detail / settings windows.
    static let panelIdentifier = NSUserInterfaceItemIdentifier("SidePrompt.QueuePanel")

    private var panel: NSPanel?
    private let store: QueueStore
    private let appModel: AppModel
    private let shortcuts: ShortcutSettings

    init(store: QueueStore, appModel: AppModel, shortcuts: ShortcutSettings) {
        self.store = store
        self.appModel = appModel
        self.shortcuts = shortcuts
        super.init()
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func show() {
        if panel == nil {
            panel = makePanel()
        }
        guard let panel else { return }

        if !isOnScreen(panel) {
            placeDefault(panel)
        }

        panel.alphaValue = 1
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        store.endEditing()
        panel?.orderOut(nil)
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    private func makePanel() -> NSPanel {
        let root = PanelRootView()
            .environment(store)
            .environment(appModel)
            .environment(shortcuts)

        let hosting = NSHostingController(rootView: root)
        hosting.view.frame = NSRect(x: 0, y: 0, width: 360, height: 540)

        let panel = NSPanel(
            contentRect: hosting.view.frame,
            styleMask: [.titled, .fullSizeContentView, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        panel.identifier = Self.panelIdentifier
        panel.title = "SidePrompt"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        // Native macOS window shadow — no custom SwiftUI halo.
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.minSize = NSSize(width: 300, height: 400)
        panel.delegate = self
        placeDefault(panel)
        return panel
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    private func isOnScreen(_ panel: NSPanel) -> Bool {
        let frame = panel.frame
        guard frame.width >= 260, frame.height >= 300 else { return false }
        return NSScreen.screens.contains { screen in
            screen.visibleFrame.intersects(frame.insetBy(dx: 40, dy: 40))
        }
    }

    private func placeDefault(_ panel: NSPanel) {
        let size = NSSize(width: 360, height: 540)
        if let screen = NSScreen.main {
            let x = screen.visibleFrame.maxX - size.width - 22
            let y = screen.visibleFrame.maxY - size.height - 18
            panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true)
        } else {
            panel.setContentSize(size)
            panel.center()
        }
    }
}
