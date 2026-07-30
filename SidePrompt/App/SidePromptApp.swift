import AppKit
import SwiftUI

extension Notification.Name {
    static let sidePromptShowPanel = Notification.Name("sidePromptShowPanel")
    static let sidePromptCapture = Notification.Name("sidePromptCapture")
}

@main
struct SidePromptApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environment(appDelegate.sharedStore)
                .environment(appDelegate.sharedAppModel)
                .environment(appDelegate.sharedShortcuts)
        }
    }
}

struct SettingsView: View {
    @Environment(QueueStore.self) private var store
    @Environment(ShortcutSettings.self) private var shortcuts

    var body: some View {
        @Bindable var shortcuts = shortcuts

        Form {
            Section("Shortcuts") {
                Picker("Capture selection", selection: $shortcuts.captureGesture) {
                    ForEach(ShortcutSettings.CaptureGesture.allCases) { gesture in
                        Text(gesture.label).tag(gesture)
                    }
                }
                Picker("Show panel", selection: $shortcuts.panelShortcut) {
                    ForEach(ShortcutSettings.PanelShortcut.allCases) { shortcut in
                        Text(shortcut.label).tag(shortcut)
                    }
                }
                Button("Reset shortcuts") {
                    shortcuts.reset()
                }
            }

            Section("Items") {
                Picker("Double-click item", selection: $shortcuts.itemActivateAction) {
                    ForEach(ShortcutSettings.ItemActivateAction.allCases) { action in
                        Text(action.label).tag(action)
                    }
                }
                Text("Single-click selects. Double-click opens with the action above. ⌘-click multi-selects; Shift-click selects a range.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("In-panel keys") {
                LabeledContent("Copy selected", value: "⌘C")
                LabeledContent("Copy as list", value: "⌘⇧C")
                LabeledContent("Select all", value: "⌘A")
                LabeledContent("Merge selected", value: "⌘⇧M")
                LabeledContent("Delete selected", value: "Delete")
                LabeledContent("Close editor / panel", value: "Esc")
            }

            Section("Updates") {
                if UpdateManager.shared.isConfigured {
                    Button("Check for Updates…") {
                        UpdateManager.shared.checkForUpdates()
                    }
                } else {
                    Text("Updater feed is not configured yet. Set SUFeedURL and SUPublicEDKey before shipping.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Templates") {
                Text("\(store.templates.count) saved templates")
                    .foregroundStyle(.secondary)
                Text("Open Templates from the ••• menu in the panel. Use {{variable}} placeholders.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Privacy") {
                Text("Notes stay in a local file on your Mac. Nothing syncs.")
                    .foregroundStyle(.secondary)
                Text(LocalStore().path)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 560)
    }
}
