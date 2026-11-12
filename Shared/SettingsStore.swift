import Foundation
import Observation
import TrotWalkCore
import WatchConnectivity

/// 設定を保存し、iPhone と Apple Watch の間で同期する。
/// どちらで変えても、もう一方に applicationContext で届く。
@MainActor
@Observable
final class SettingsStore: NSObject {
    var value: WalkSettings {
        didSet {
            guard value != oldValue else { return }
            value.save()
            if !isApplyingRemote { push() }
        }
    }

    @ObservationIgnored private var isApplyingRemote = false

    override init() {
        value = WalkSettings.load()
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func push() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        try? WCSession.default.updateApplicationContext(value.contextDictionary)
    }

    fileprivate func applyRemote(_ settings: WalkSettings) {
        isApplyingRemote = true
        value = settings
        isApplyingRemote = false
    }
}

extension SettingsStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let settings = WalkSettings(contextDictionary: applicationContext) else { return }
        Task { @MainActor in self.applyRemote(settings) }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif
}
