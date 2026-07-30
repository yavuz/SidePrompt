import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let sharedStore = QueueStore()
    let sharedAppModel = AppModel()
    let sharedShortcuts = ShortcutSettings()

    private var hotKeys: HotKeyManager!
    private var keyRouter: KeyCommandRouter!
    private var keyMonitor: Any?
    private var permissionPollTask: Task<Void, Never>?
    private var floatingPanel: FloatingPanelController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        sharedAppModel.onRecheck = { [weak self] in
            self?.recheckPermissions(userInitiated: true)
        }

        floatingPanel = FloatingPanelController(
            store: sharedStore,
            appModel: sharedAppModel,
            shortcuts: sharedShortcuts
        )

        ItemWindowManager.shared.configure(store: sharedStore, appModel: sharedAppModel)
        sharedAppModel.onOpenItemWindow = { itemID in
            ItemWindowManager.shared.open(itemID: itemID)
        }

        keyRouter = KeyCommandRouter(store: sharedStore, appModel: sharedAppModel)
        keyRouter.onHidePanel = { [weak self] in
            self?.floatingPanel?.hide()
        }
        installKeyMonitor()
        setupStatusItem()

        setupHotKeys()
        recheckPermissions(userInitiated: false)
        startPermissionPolling()
        UpdateManager.shared.start()

        NotificationCenter.default.addObserver(
            forName: .sidePromptShowPanel,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.floatingPanel?.show()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .sidePromptCapture,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.performCapture(delay: 0)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.floatingPanel?.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Writes are debounced — force anything still owed out to disk before we go.
        sharedStore.flushPendingWrites()
        permissionPollTask?.cancel()
        hotKeys?.stop()
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        sharedStore.flushPendingWrites()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        recheckPermissions(userInitiated: false)
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(
                systemSymbolName: "text.badge.plus",
                accessibilityDescription: "SidePrompt"
            )
            image?.isTemplate = true
            button.image = image
            button.toolTip = "SidePrompt"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showStatusMenu(from: sender)
            return
        }
        // Left click — open the floating panel directly (toggle if already open).
        floatingPanel?.toggle()
    }

    private func showStatusMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        menu.addItem(withTitle: "Show SidePrompt", action: #selector(showPanel), keyEquivalent: "")
        menu.addItem(withTitle: "Capture Selection", action: #selector(captureFromMenu), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit SidePrompt", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 2), in: button)
    }

    @objc private func showPanel() {
        floatingPanel?.show()
    }

    @objc private func captureFromMenu() {
        performCapture(delay: 0)
    }

    @objc private func checkForUpdates() {
        UpdateManager.shared.checkForUpdates()
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.keyRouter.handle(event)
        }
    }

    private func setupHotKeys() {
        hotKeys = HotKeyManager()
        hotKeys.onCapture = { [weak self] in
            self?.performCapture(delay: 0.12)
        }
        hotKeys.onTogglePanel = { [weak self] in
            self?.floatingPanel?.toggle()
        }
        sharedShortcuts.onChange = { [weak self] in
            guard let self else { return }
            self.sharedAppModel.hasEventTap = self.hotKeys.update(
                captureGesture: self.sharedShortcuts.captureGesture,
                panelShortcut: self.sharedShortcuts.panelShortcut
            )
        }
        _ = hotKeys.update(
            captureGesture: sharedShortcuts.captureGesture,
            panelShortcut: sharedShortcuts.panelShortcut
        )
    }

    @discardableResult
    private func recheckPermissions(userInitiated: Bool) -> Bool {
        sharedAppModel.refreshAccessibilityStatus()
        let tapOK = hotKeys.update(
            captureGesture: sharedShortcuts.captureGesture,
            panelShortcut: sharedShortcuts.panelShortcut
        )
        sharedAppModel.hasEventTap = tapOK

        if userInitiated {
            if sharedAppModel.hasAccessibility && tapOK {
                sharedAppModel.showToast("Ready — select text, then Shift×2")
            } else if !sharedAppModel.hasAccessibility {
                sharedAppModel.showToast("Not trusted yet — Settings’te SidePrompt’u kapat/aç")
            } else {
                sharedAppModel.showToast("Hotkeys failed — quit & reopen SidePrompt")
            }
        }

        if sharedAppModel.hasAccessibility && tapOK {
            permissionPollTask?.cancel()
            permissionPollTask = nil
        }

        return sharedAppModel.hasAccessibility && tapOK
    }

    private func startPermissionPolling() {
        permissionPollTask?.cancel()
        permissionPollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                if Task.isCancelled { break }
                if sharedAppModel.needsPermissionHelp {
                    recheckPermissions(userInitiated: false)
                } else {
                    break
                }
            }
        }
    }

    private func performCapture(delay: TimeInterval) {
        Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }

            recheckPermissions(userInitiated: false)

            guard sharedAppModel.hasAccessibility else {
                sharedAppModel.showToast("Accessibility kapalı — Settings’te SidePrompt’u aç")
                floatingPanel?.show()
                return
            }

            guard let selection = await SelectionReader.captureSelection() else {
                sharedAppModel.showToast("Nothing selected")
                return
            }

            if sharedStore.capture(selection) != nil {
                sharedAppModel.showToast("Captured")
            }
        }
    }
}
