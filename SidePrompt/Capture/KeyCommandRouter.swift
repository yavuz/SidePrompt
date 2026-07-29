import AppKit
import Carbon.HIToolbox

/// Shared keyboard commands for floating window and MenuBarExtra panel.
@MainActor
final class KeyCommandRouter {
    var store: QueueStore
    var appModel: AppModel
    var onHidePanel: (() -> Void)?

    init(store: QueueStore, appModel: AppModel) {
        self.store = store
        self.appModel = appModel
    }

    func handle(_ event: NSEvent) -> NSEvent? {
        guard NSApp.keyWindow != nil else { return event }

        let keyCode = event.keyCode
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let textFocused = isTextInputFocused

        // Escape — end edit first, otherwise hide panel
        if keyCode == UInt16(kVK_Escape) {
            if store.editingItemID != nil {
                store.endEditing()
                return nil
            }
            if !textFocused {
                onHidePanel?()
                return nil
            }
            return event
        }

        if textFocused {
            return event
        }

        // Delete / Forward Delete
        if keyCode == UInt16(kVK_Delete) || keyCode == UInt16(kVK_ForwardDelete) {
            guard !store.selectedItemIDs.isEmpty else { return event }
            let count = store.selectedItemIDs.count
            store.delete(ids: store.selectedItemIDs)
            appModel.showToast(count == 1 ? "Deleted" : "Deleted \(count) items")
            return nil
        }

        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""

        // ⌘C — copy selected
        if flags == .command, chars == "c" {
            guard let text = store.copySelectedItems() else {
                appModel.showToast("Select an item first")
                return nil
            }
            if PasteboardService.copy(text) {
                let count = store.selectedItemIDs.count
                appModel.showToast(count > 1 ? "Copied \(count) items" : "Copied")
            }
            return nil
        }

        // ⌘⇧C — copy as list
        if flags == [.command, .shift], chars == "c" {
            let text = store.copySelectedAsList()
            if PasteboardService.copy(text) {
                appModel.showToast(store.selectedItemIDs.isEmpty ? "Copied as List" : "Copied")
            }
            return nil
        }

        // ⌘A — select all filtered
        if flags == .command, chars == "a" {
            store.selectAllFiltered()
            appModel.showToast("Selected \(store.selectedItemIDs.count)")
            return nil
        }

        // ⌘⇧M — merge selected
        if flags == [.command, .shift], chars == "m" {
            if store.mergeSelected() != nil {
                appModel.showToast("Merged")
            } else {
                appModel.showToast("Select 2+ items to merge")
            }
            return nil
        }

        return event
    }

    private var isTextInputFocused: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        if responder is NSTextView || responder is NSTextField {
            return true
        }
        if let fieldEditor = responder as? NSText,
           fieldEditor.delegate is NSTextField {
            return true
        }
        return false
    }
}
