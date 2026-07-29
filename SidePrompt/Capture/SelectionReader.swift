import AppKit
import ApplicationServices

enum SelectionReader {
    /// Reads the current text selection from the frontmost app.
    static func selectedText(excludingBundleID: String? = Bundle.main.bundleIdentifier) -> String? {
        if let axText = selectedTextViaAccessibility(excludingBundleID: excludingBundleID),
           !axText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return axText
        }
        return selectedTextViaClipboardFallback()
    }

    private static func selectedTextViaAccessibility(excludingBundleID: String?) -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        if let excludingBundleID, app.bundleIdentifier == excludingBundleID {
            return nil
        }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        var focusedObject: AnyObject?
        let focusedResult = AXUIElementCopyAttributeValue(
            axApp,
            kAXFocusedUIElementAttribute as CFString,
            &focusedObject
        )

        let focused: AXUIElement?
        if focusedResult == .success, let focusedObject {
            focused = (focusedObject as! AXUIElement)
        } else {
            focused = systemFocusedElement()
        }

        guard let element = focused else { return nil }

        if let selected = copyStringAttribute(element, kAXSelectedTextAttribute as CFString),
           !selected.isEmpty {
            return selected
        }

        if let ranged = selectedTextFromValueAndRange(element), !ranged.isEmpty {
            return ranged
        }

        // Some apps expose selection on a parent.
        if let parent = copyElementAttribute(element, kAXParentAttribute as CFString) {
            if let selected = copyStringAttribute(parent, kAXSelectedTextAttribute as CFString),
               !selected.isEmpty {
                return selected
            }
            if let ranged = selectedTextFromValueAndRange(parent), !ranged.isEmpty {
                return ranged
            }
        }

        return nil
    }

    private static func systemFocusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var focusedObject: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focusedObject
        )
        guard result == .success, let focusedObject else { return nil }
        return (focusedObject as! AXUIElement)
    }

    private static func selectedTextFromValueAndRange(_ element: AXUIElement) -> String? {
        var rangeValue: AnyObject?
        let rangeResult = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeValue
        )
        guard rangeResult == .success, let rangeValue else { return nil }

        var range = CFRange()
        // AXValueRef holding CFRange
        let axValue = rangeValue as! AXValue
        guard AXValueGetValue(axValue, .cfRange, &range), range.length > 0 else { return nil }

        guard let full = copyStringAttribute(element, kAXValueAttribute as CFString) else { return nil }
        let nsFull = full as NSString
        guard range.location >= 0,
              range.location + range.length <= nsFull.length else { return nil }
        return nsFull.substring(with: NSRange(location: range.location, length: range.length))
    }

    private static func copyStringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success else { return nil }
        if let string = value as? String { return string }
        if let attributed = value as? NSAttributedString { return attributed.string }
        return nil
    }

    private static func copyElementAttribute(_ element: AXUIElement, _ attribute: CFString) -> AXUIElement? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let value else { return nil }
        return (value as! AXUIElement)
    }

    /// Fallback: synthesize ⌘C, wait for pasteboard change, then restore previous contents.
    private static func selectedTextViaClipboardFallback() -> String? {
        let pasteboard = NSPasteboard.general
        let previousChangeCount = pasteboard.changeCount
        let savedItems = snapshotPasteboard(pasteboard)

        postCommandC()

        let deadline = Date().addingTimeInterval(0.45)
        while Date() < deadline {
            if pasteboard.changeCount != previousChangeCount {
                break
            }
            Thread.sleep(forTimeInterval: 0.02)
        }

        guard pasteboard.changeCount != previousChangeCount,
              let copied = pasteboard.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !copied.isEmpty else {
            restorePasteboard(pasteboard, items: savedItems)
            return nil
        }

        // Keep the captured text on the pasteboard briefly is fine;
        // restore previous clipboard so we don't clobber user history.
        restorePasteboard(pasteboard, items: savedItems)
        return copied
    }

    private static func postCommandC() {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.localEventsSuppressionInterval = 0

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)

        // Explicitly Command only — leftover Shift from double-tap must not stick.
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private static func snapshotPasteboard(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        guard let items = pasteboard.pasteboardItems else { return [] }
        return items.compactMap { item in
            let copy = NSPasteboardItem()
            var wrote = false
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                    wrote = true
                }
            }
            return wrote ? copy : nil
        }
    }

    private static func restorePasteboard(_ pasteboard: NSPasteboard, items: [NSPasteboardItem]) {
        pasteboard.clearContents()
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }
}

enum AccessibilityPermission {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func promptIfNeeded() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        if let url {
            NSWorkspace.shared.open(url)
        }
    }
}

// Carbon virtual key for 'C'
private let kVK_ANSI_C: Int = 0x08
