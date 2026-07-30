import AppKit
import Observation
import ServiceManagement

/// Wraps `SMAppService.mainApp`. The system owns the real state — the user can
/// flip it in System Settings at any time — so every read goes back to the
/// service instead of caching a local boolean.
@MainActor
@Observable
final class LaunchAtLogin {
    private(set) var status: SMAppService.Status = .notRegistered
    private(set) var lastError: String?

    init() {
        refresh()
    }

    var isEnabled: Bool {
        status == .enabled
    }

    /// The user disabled it in System Settings; registering again won't stick
    /// until they re-approve there.
    var needsApproval: Bool {
        status == .requiresApproval
    }

    func refresh() {
        let current = SMAppService.mainApp.status
        if status != current { status = current }
    }

    func setEnabled(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                guard service.status != .enabled else { return }
                try service.register()
            } else {
                guard service.status != .notRegistered else { return }
                try service.unregister()
            }
            if lastError != nil { lastError = nil }
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    func toggle() {
        setEnabled(!isEnabled)
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Whether the running copy is the one macOS would launch. Registering a
    /// build that lives in DerivedData works, but pointing at a throwaway path.
    var isInApplicationsFolder: Bool {
        Bundle.main.bundlePath.hasPrefix("/Applications/")
    }
}
