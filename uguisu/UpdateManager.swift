import Cocoa
import Sparkle

class UpdateManager: NSObject {
    private var updaterController: SPUStandardUpdaterController

    override init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    var updater: SPUUpdater {
        updaterController.updater
    }

    @objc func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    func startAutomaticUpdateChecks() {
        updater.automaticallyChecksForUpdates = true
    }
}
