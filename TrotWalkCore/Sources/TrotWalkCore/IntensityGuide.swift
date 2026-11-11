import Foundation

/// 心拍数から速歩・緩歩の目安を計算する。
///
/// 研究で使われる「最大体力の70%以上 / 40%以下」は酸素摂取量で測ったものなので、
/// ここでは心拍予備能（カルボーネン法）で近似する。あくまで推定で、体感
/// （息が上がって「ややきつい」）を優先する前提の補助機能。
public struct HeartRateZones: Equatable, Sendable {
    public let restingHeartRate: Double
    public let maxHeartRate: Double

    /// 速歩の下限（心拍予備能 70%）
    public var briskLowerBound: Double { heartRate(atReserve: 0.70) }
    /// 速歩でこれを超えたら少し落とす（心拍予備能 85%）
    public var briskUpperBound: Double { heartRate(atReserve: 0.85) }
    /// 緩歩の上限（心拍予備能 40%）
    public var easyUpperBound: Double { heartRate(atReserve: 0.40) }

    public init(restingHeartRate: Double, maxHeartRate: Double) {
        self.restingHeartRate = restingHeartRate
        self.maxHeartRate = max(maxHeartRate, restingHeartRate + 1)
    }

    /// 年齢から最大心拍数を推定する（Tanaka式: 208 - 0.7 × 年齢）。
    public init(age: Int, restingHeartRate: Double) {
        self.init(restingHeartRate: restingHeartRate, maxHeartRate: 208 - 0.7 * Double(age))
    }

    public func heartRate(atReserve fraction: Double) -> Double {
        restingHeartRate + fraction * (maxHeartRate - restingHeartRate)
    }
}

/// 強度ガイド。心拍が目安から外れた状態が続いたときだけ、控えめに合図する。
public struct IntensityCoach: Sendable {
    /// 区間が始まってから判定しない時間（心拍の追従待ち）。
    /// 緩歩では心拍が下がるまで時間がかかるので長めにとる。
    public var briskGracePeriod: TimeInterval = 60
    public var easyGracePeriod: TimeInterval = 90
    /// 目安から外れた状態がこれだけ続いたら合図する
    public var sustainDuration: TimeInterval = 20
    /// 合図の最短間隔
    public var minimumInterval: TimeInterval = 60

    public let zones: HeartRateZones

    private var outOfRangeSince: TimeInterval?
    private var pendingCue: HapticCue?
    private var lastCueAt: TimeInterval?
    private var lastSegmentIndex: Int?

    public init(zones: HeartRateZones) {
        self.zones = zones
    }

    /// - Parameters:
    ///   - heartRate: 最新の心拍数（bpm）
    ///   - position: プラン上の現在位置
    ///   - now: プランの経過時間
    /// - Returns: 今鳴らすべき合図。なければ nil。
    public mutating func evaluate(heartRate: Double, position: IntervalPosition, now: TimeInterval) -> HapticCue? {
        if lastSegmentIndex != position.segment.index {
            lastSegmentIndex = position.segment.index
            reset()
        }

        guard position.elapsedInSegment >= gracePeriod(for: position.segment.phase),
              position.remainingInSegment > CueSchedule.defaultWarningLead,
              let wanted = desiredCue(heartRate: heartRate, phase: position.segment.phase)
        else {
            reset()
            return nil
        }

        if pendingCue != wanted {
            pendingCue = wanted
            outOfRangeSince = now
        }

        guard let since = outOfRangeSince, now - since >= sustainDuration else { return nil }
        if let last = lastCueAt, now - last < minimumInterval { return nil }

        lastCueAt = now
        outOfRangeSince = now
        return wanted
    }

    private func gracePeriod(for phase: WalkPhase) -> TimeInterval {
        phase == .brisk ? briskGracePeriod : easyGracePeriod
    }

    private func desiredCue(heartRate: Double, phase: WalkPhase) -> HapticCue? {
        switch phase {
        case .brisk:
            if heartRate < zones.briskLowerBound { return .speedUp }
            if heartRate > zones.briskUpperBound { return .slowDown }
            return nil
        case .easy:
            return heartRate > zones.easyUpperBound ? .slowDown : nil
        }
    }

    private mutating func reset() {
        outOfRangeSince = nil
        pendingCue = nil
    }
}
