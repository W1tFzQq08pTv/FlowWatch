import Foundation
import Sparkle

@MainActor
final class FlowWatchUpdateUserDriver: NSObject, SPUUserDriver {
    private weak var manager: UpdateManager?

    init(manager: UpdateManager) {
        self.manager = manager
        super.init()
    }

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        manager?.showPermissionRequest(reply: reply)
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        manager?.userInitiatedUpdateCheckDidStart()
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        manager?.showUpdateFound(item: appcastItem, state: state, reply: reply)
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {
        LogManager.shared.log("Unable to download update release notes: \(error.localizedDescription)", level: .error)
    }

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        manager?.updateNotFound(error: error, acknowledgement: acknowledgement)
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        manager?.updaterFailed(error: error, acknowledgement: acknowledgement)
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        manager?.downloadStarted()
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        manager?.setExpectedDownloadLength(expectedContentLength)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        manager?.receiveDownloadData(length: length)
    }

    func showDownloadDidStartExtractingUpdate() {
        manager?.extractionStarted()
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        manager?.extractionProgress(progress)
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        manager?.readyToInstall(reply: reply)
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        manager?.installingUpdate()
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        manager?.updateInstallationDidFinish(acknowledgement: acknowledgement)
    }

    func dismissUpdateInstallation() {
        manager?.dismissUpdateInstallation()
    }

    func showUpdateInFocus() {
        manager?.showCurrentUpdateInFocus()
    }
}
