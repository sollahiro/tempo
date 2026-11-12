import Foundation

/// ワークアウト後に聞く「速歩はどうでしたか？」の答え。
public enum EffortFeedback: String, Codable, Sendable, CaseIterable {
    case easy      // 楽だった
    case justRight // ちょうどいい
    case hard      // きつかった
}

/// 本人に合わせて少しずつ調整する値。Watch に保存して次回に使う。
///
/// - 速歩の目安心拍（心拍予備能の割合）: 楽なら上げ、きついなら下げる
/// - 速歩の開始テンポ: 前回最後に落ち着いたテンポから始める。きついなら少し下げる
public struct PersonalCalibration: Equatable, Codable, Sendable {
    public static let defaultBriskReserve: Double = 0.70
    public static let briskReserveRange: ClosedRange<Double> = 0.60...0.80
    public static let reserveStep: Double = 0.03
    public static let cadenceStep: Double = 4

    public var briskReserve: Double
    public var briskStartCadence: Double?

    public init(briskReserve: Double = PersonalCalibration.defaultBriskReserve, briskStartCadence: Double? = nil) {
        self.briskReserve = briskReserve
        self.briskStartCadence = briskStartCadence
    }

    /// ワークアウトの結果を反映した次回の値。
    /// - Parameters:
    ///   - feedback: 終了後の回答。答えなかったら nil
    ///   - finalBriskCadence: 最後の速歩テンポ。テンポがオフなら nil
    public func updated(feedback: EffortFeedback?, finalBriskCadence: Double?) -> PersonalCalibration {
        var next = self
        if let finalBriskCadence {
            next.briskStartCadence = finalBriskCadence
        }
        switch feedback {
        case .easy:
            next.briskReserve += Self.reserveStep
        case .hard:
            next.briskReserve -= Self.reserveStep
            if let cadence = next.briskStartCadence {
                next.briskStartCadence = cadence - Self.cadenceStep
            }
        case .justRight, nil:
            break
        }
        next.briskReserve = min(max(next.briskReserve, Self.briskReserveRange.lowerBound), Self.briskReserveRange.upperBound)
        if let cadence = next.briskStartCadence {
            let range = TempoCoach.Configuration().briskRange
            next.briskStartCadence = min(max(cadence, range.lowerBound), range.upperBound)
        }
        return next
    }
}

extension PersonalCalibration {
    public static let storageKey = "personalCalibration"

    public static func load(from defaults: UserDefaults = .standard) -> PersonalCalibration {
        guard let data = defaults.data(forKey: storageKey),
              let value = try? JSONDecoder().decode(PersonalCalibration.self, from: data)
        else { return PersonalCalibration() }
        return value
    }

    public func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
