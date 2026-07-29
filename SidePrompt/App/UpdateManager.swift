import Foundation
import Sparkle

/// Thin wrapper around Sparkle. Disabled when the public key is still a placeholder.
@MainActor
final class UpdateManager: NSObject, SPUUpdaterDelegate {
    static let shared = UpdateManager()

    private var updaterController: SPUStandardUpdaterController?
    private(set) var isConfigured: Bool = false

    func start() {
        let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""

        guard !publicKey.isEmpty,
              !publicKey.contains("REPLACE_WITH"),
              !feed.isEmpty else {
            isConfigured = false
            NSLog("SidePrompt: Sparkle not configured yet (placeholder feed/key). Skipping updater.")
            return
        }

        #if DEBUG
        // Avoid noisy update checks while developing.
        isConfigured = true
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        #else
        isConfigured = true
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        #endif
    }

    func checkForUpdates() {
        guard isConfigured else { return }
        updaterController?.checkForUpdates(nil)
    }
}
