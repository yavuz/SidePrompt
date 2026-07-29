import AppKit
import Observation

@MainActor
@Observable
final class AppModel {
    var toastMessage: String?
    var hasAccessibility: Bool = AccessibilityPermission.isTrusted
    var hasEventTap: Bool = false
    var appPath: String = Bundle.main.bundlePath

    /// Set by AppDelegate to restart hotkeys after the user grants permission.
    var onRecheck: (() -> Void)?

    private var toastTask: Task<Void, Never>?

    func showToast(_ message: String) {
        toastMessage = message
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2.2))
            if !Task.isCancelled {
                toastMessage = nil
            }
        }
    }

    func refreshAccessibilityStatus() {
        hasAccessibility = AccessibilityPermission.isTrusted
        appPath = Bundle.main.bundlePath
    }

    var needsPermissionHelp: Bool {
        !hasAccessibility || !hasEventTap
    }

    var permissionStatusText: String {
        let ax = hasAccessibility ? "on" : "off"
        let tap = hasEventTap ? "on" : "off"
        return "Accessibility \(ax) · Hotkeys \(tap)"
    }
}
