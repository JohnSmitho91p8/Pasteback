import AppKit
import Observation
import Sparkle

/// Sparkle owns the download, signature verification, replacement and relaunch.
/// Manual checks only: no background requests or clipboard data are sent.
@MainActor @Observable final class UpdateChecker {
    static let shared = UpdateChecker()
    private(set) var checking = false
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observation: NSKeyValueObservation?
    var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }

    func start() {
        guard controller == nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            Task { @MainActor in self?.checking = !updater.canCheckForUpdates }
        }
        controller.startUpdater()
    }

    func check() async {
        start()
        guard let controller, controller.updater.canCheckForUpdates else { return }
        // The floating history panel must not obscure Sparkle's update window.
        if let delegate = NSApp.delegate as? AppDelegate { delegate.panel?.orderOut(nil) }
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}
