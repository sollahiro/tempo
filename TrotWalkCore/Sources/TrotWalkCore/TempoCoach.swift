import Foundation

/// 歩調（1分あたりの歩数）のテンポを決め、心拍に合わせて少しずつ調整する。
///
/// 振動は2歩に1回（片足が着くたび）鳴らすので、間隔は 120 / 歩調 秒になる。
/// 心拍の目安がないとき（誕生日が未登録など）は、テンポは固定のまま。
public struct TempoCoach: Sendable {
    public struct Configuration: Sendable {
        public var briskStart: Double = 116
        public var easyStart: Double = 96
        public var briskRange: ClosedRange<Double> = 100...140
        public var easyRange: ClosedRange<Double> = 80...112
        /// 1回の調整幅（歩/分）
        public var step: Double = 4
        /// 調整の最短間隔
        public var adjustInterval: TimeInterval = 30
        /// 区間が始まってから調整しない時間（心拍の追従待ち）
        public var briskGracePeriod: TimeInterval = 60
        public var easyGracePeriod: TimeInterval = 90

        public init() {}
    }

    public let configuration: Configuration
    public let zones: HeartRateZones?

    /// 速歩のテンポ。調整した値は次のセットにも引き継ぐ。
    public private(set) var briskCadence: Double
    /// 緩歩のテンポ
    public private(set) var easyCadence: Double

    private var lastAdjustAt: TimeInterval?
    private var lastSegmentIndex: Int?

    public init(zones: HeartRateZones?, configuration: Configuration = Configuration()) {
        self.zones = zones
        self.configuration = configuration
        briskCadence = configuration.briskStart
        easyCadence = configuration.easyStart
    }

    public func cadence(for phase: WalkPhase) -> Double {
        phase == .brisk ? briskCadence : easyCadence
    }

    /// 振動の間隔（秒）。2歩に1回。
    public func pulseInterval(for phase: WalkPhase) -> TimeInterval {
        120 / cadence(for: phase)
    }

    /// 心拍を見てテンポを調整する。
    /// - Returns: 調整した場合は新しいテンポの向き（速く: .speedUp / 遅く: .slowDown）。
    @discardableResult
    public mutating func update(heartRate: Double?, position: IntervalPosition, now: TimeInterval) -> HapticCue? {
        if lastSegmentIndex != position.segment.index {
            lastSegmentIndex = position.segment.index
            lastAdjustAt = now
        }

        guard let zones, let heartRate else { return nil }
        let phase = position.segment.phase
        let grace = phase == .brisk ? configuration.briskGracePeriod : configuration.easyGracePeriod
        guard position.elapsedInSegment >= grace else { return nil }
        if let last = lastAdjustAt, now - last < configuration.adjustInterval { return nil }

        let direction: Double
        switch phase {
        case .brisk:
            if heartRate < zones.briskLowerBound {
                direction = 1
            } else if heartRate > zones.briskUpperBound {
                direction = -1
            } else {
                return nil
            }
        case .easy:
            guard heartRate > zones.easyUpperBound else { return nil }
            direction = -1
        }

        let before = cadence(for: phase)
        let range = phase == .brisk ? configuration.briskRange : configuration.easyRange
        let after = min(max(before + direction * configuration.step, range.lowerBound), range.upperBound)
        lastAdjustAt = now
        guard after != before else { return nil }

        switch phase {
        case .brisk: briskCadence = after
        case .easy: easyCadence = after
        }
        return direction > 0 ? .speedUp : .slowDown
    }
}
