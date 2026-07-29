import AppKit
import Carbon.HIToolbox

/// Listens for capture double-tap and panel toggle shortcuts.
final class HotKeyManager: @unchecked Sendable {
    var onCapture: (@MainActor () -> Void)?
    var onTogglePanel: (@MainActor () -> Void)?

    /// Kept for call-site compatibility.
    var onDoubleShift: (@MainActor () -> Void)? {
        get { onCapture }
        set { onCapture = newValue }
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var lastModifierUp: TimeInterval = 0
    private let doubleTapThreshold: TimeInterval = 0.35
    private var trackedModifierDown = false

    private var captureGesture: ShortcutSettings.CaptureGesture = .doubleShift
    private var panelShortcut: ShortcutSettings.PanelShortcut = .commandShiftP

    @discardableResult
    func update(
        captureGesture: ShortcutSettings.CaptureGesture,
        panelShortcut: ShortcutSettings.PanelShortcut
    ) -> Bool {
        self.captureGesture = captureGesture
        self.panelShortcut = panelShortcut
        return start()
    }

    @discardableResult
    func start() -> Bool {
        stop()

        let mask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userInfo).takeUnretainedValue()
            return manager.handle(event: event, type: type)
        }

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: userInfo
        ) else {
            NSLog("SidePrompt: failed to create event tap — grant Accessibility for /Applications/SidePrompt.app")
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func handle(event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown {
            if matchesPanelShortcut(event) {
                DispatchQueue.main.async { [weak self] in
                    let action = self?.onTogglePanel
                    Task { @MainActor in action?() }
                }
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .flagsChanged {
            handleModifierDoubleTap(event.flags)
        }

        return Unmanaged.passUnretained(event)
    }

    private func matchesPanelShortcut(_ event: CGEvent) -> Bool {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        switch panelShortcut {
        case .commandShiftP:
            return keyCode == Int64(kVK_ANSI_P)
                && flags.contains(.maskCommand)
                && flags.contains(.maskShift)
                && !flags.contains(.maskControl)
                && !flags.contains(.maskAlternate)
        case .commandShiftSpace:
            return keyCode == Int64(kVK_Space)
                && flags.contains(.maskCommand)
                && flags.contains(.maskShift)
                && !flags.contains(.maskControl)
                && !flags.contains(.maskAlternate)
        case .optionSpace:
            return keyCode == Int64(kVK_Space)
                && flags.contains(.maskAlternate)
                && !flags.contains(.maskCommand)
                && !flags.contains(.maskControl)
                && !flags.contains(.maskShift)
        }
    }

    private func handleModifierDoubleTap(_ flags: CGEventFlags) {
        let targetDown: Bool
        let othersHeld: Bool
        switch captureGesture {
        case .doubleShift:
            targetDown = flags.contains(.maskShift)
            othersHeld = flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate)
        case .doubleOption:
            targetDown = flags.contains(.maskAlternate)
            othersHeld = flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskShift)
        case .doubleControl:
            targetDown = flags.contains(.maskControl)
            othersHeld = flags.contains(.maskCommand) || flags.contains(.maskAlternate) || flags.contains(.maskShift)
        }

        if targetDown {
            trackedModifierDown = true
            return
        }

        guard trackedModifierDown else { return }
        trackedModifierDown = false
        guard !othersHeld else { return }

        let now = ProcessInfo.processInfo.systemUptime
        if now - lastModifierUp <= doubleTapThreshold {
            lastModifierUp = 0
            DispatchQueue.main.async { [weak self] in
                let action = self?.onCapture
                Task { @MainActor in action?() }
            }
        } else {
            lastModifierUp = now
        }
    }
}
