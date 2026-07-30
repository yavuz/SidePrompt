import Foundation
import Observation

@MainActor
@Observable
final class ShortcutSettings {
    enum CaptureGesture: String, CaseIterable, Identifiable, Codable {
        case doubleShift
        case doubleOption
        case doubleControl

        var id: String { rawValue }

        var label: String {
            switch self {
            case .doubleShift: "Double-tap Shift"
            case .doubleOption: "Double-tap Option"
            case .doubleControl: "Double-tap Control"
            }
        }
    }

    enum PanelShortcut: String, CaseIterable, Identifiable, Codable {
        case commandShiftP
        case commandShiftSpace
        case optionSpace

        var id: String { rawValue }

        var label: String {
            switch self {
            case .commandShiftP: "⌘⇧P"
            case .commandShiftSpace: "⌘⇧Space"
            case .optionSpace: "⌥Space"
            }
        }
    }

    enum ItemActivateAction: String, CaseIterable, Identifiable, Codable {
        case inlineEdit
        case openWindow

        var id: String { rawValue }

        var label: String {
            switch self {
            case .inlineEdit: "Edit inline"
            case .openWindow: "Open in window"
            }
        }
    }

    var captureGesture: CaptureGesture {
        didSet { persist() }
    }

    var panelShortcut: PanelShortcut {
        didSet { persist() }
    }

    var itemActivateAction: ItemActivateAction {
        didSet { persist() }
    }

    private let defaults: UserDefaults
    private let key = "shortcutSettings.v1"
    var onChange: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(Stored.self, from: data) {
            captureGesture = decoded.captureGesture
            panelShortcut = decoded.panelShortcut
            itemActivateAction = decoded.itemActivateAction ?? .inlineEdit
        } else {
            captureGesture = .doubleShift
            panelShortcut = .commandShiftP
            itemActivateAction = .inlineEdit
        }
    }

    func reset() {
        captureGesture = .doubleShift
        panelShortcut = .commandShiftP
        itemActivateAction = .inlineEdit
    }

    private func persist() {
        let stored = Stored(
            captureGesture: captureGesture,
            panelShortcut: panelShortcut,
            itemActivateAction: itemActivateAction
        )
        if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: key)
        }
        onChange?()
    }

    private struct Stored: Codable {
        var captureGesture: CaptureGesture
        var panelShortcut: PanelShortcut
        var itemActivateAction: ItemActivateAction?

        enum CodingKeys: String, CodingKey {
            case captureGesture
            case panelShortcut
            case itemActivateAction
        }
    }
}
