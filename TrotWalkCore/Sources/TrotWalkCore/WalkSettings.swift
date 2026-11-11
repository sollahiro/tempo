import Foundation

/// ユーザーが選べる設定。Watch と iPhone の間で同じものを使う。
public struct WalkSettings: Equatable, Codable, Sendable {
    /// 速歩の長さ（秒）。180 か 120。
    public var briskDuration: TimeInterval
    /// 緩歩の長さ（秒）
    public var easyDuration: TimeInterval
    /// セット数
    public var sets: Int
    /// 切り替え10秒前の予告
    public var switchWarningEnabled: Bool
    /// 歩調のテンポを振動で刻む
    public var tempoEnabled: Bool
    /// 心拍による強度ガイド。テンポがオンならテンポを自動調整し、オフなら合図で知らせる。
    public var intensityGuideEnabled: Bool

    public init(
        briskDuration: TimeInterval = 180,
        easyDuration: TimeInterval = 180,
        sets: Int = 5,
        switchWarningEnabled: Bool = true,
        tempoEnabled: Bool = true,
        intensityGuideEnabled: Bool = false
    ) {
        self.briskDuration = briskDuration
        self.easyDuration = easyDuration
        self.sets = sets
        self.switchWarningEnabled = switchWarningEnabled
        self.tempoEnabled = tempoEnabled
        self.intensityGuideEnabled = intensityGuideEnabled
    }

    public var plan: IntervalPlan {
        IntervalPlan(briskDuration: briskDuration, easyDuration: easyDuration, sets: sets)
    }

    public var cueSchedule: CueSchedule {
        CueSchedule(plan: plan, warningLead: switchWarningEnabled ? CueSchedule.defaultWarningLead : 0)
    }
}

// MARK: - 保存と同期

extension WalkSettings {
    public static let storageKey = "walkSettings"

    public static func load(from defaults: UserDefaults = .standard) -> WalkSettings {
        guard let data = defaults.data(forKey: storageKey),
              let settings = try? JSONDecoder().decode(WalkSettings.self, from: data)
        else { return WalkSettings() }
        return settings
    }

    public func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    /// WatchConnectivity の applicationContext 用
    public var contextDictionary: [String: Any] {
        guard let data = try? JSONEncoder().encode(self) else { return [:] }
        return [Self.storageKey: data]
    }

    public init?(contextDictionary: [String: Any]) {
        guard let data = contextDictionary[Self.storageKey] as? Data,
              let settings = try? JSONDecoder().decode(WalkSettings.self, from: data)
        else { return nil }
        self = settings
    }
}

// MARK: - 表示用

public enum DurationText {
    /// 例: 180 → "3:00"
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// 例: 900 → "15分"
    public static func minutes(_ seconds: TimeInterval) -> String {
        "\(Int((seconds / 60).rounded()))分"
    }
}
