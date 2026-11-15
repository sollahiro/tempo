import Foundation

/// 速歩（brisk）と緩歩（easy）のどちらのフェーズか。
public enum WalkPhase: String, Codable, Sendable, CaseIterable {
    case brisk
    case easy
}

/// 1区間（速歩または緩歩のひとかたまり）。
public struct IntervalSegment: Equatable, Sendable {
    public let index: Int
    public let setNumber: Int // 1 始まり
    public let phase: WalkPhase
    public let start: TimeInterval
    public let duration: TimeInterval

    public var end: TimeInterval { start + duration }
}

/// ワークアウト中のある時点の状態。
public struct IntervalPosition: Equatable, Sendable {
    public let segment: IntervalSegment
    public let elapsedInSegment: TimeInterval
    public var remainingInSegment: TimeInterval { max(0, segment.duration - elapsedInSegment) }
}

/// 「速歩 → 緩歩」を1セットとして、終えるまでくり返すプラン。終わりの時間は決めない。
public struct IntervalPlan: Equatable, Sendable {
    public static let briskOptions: [TimeInterval] = [180, 120]
    /// おすすめの目安（強制はしない）
    public static let recommendedDuration: TimeInterval = 30 * 60

    public var briskDuration: TimeInterval
    public var easyDuration: TimeInterval

    public init(briskDuration: TimeInterval = 180, easyDuration: TimeInterval = 180) {
        self.briskDuration = max(1, briskDuration)
        self.easyDuration = max(1, easyDuration)
    }

    public static let standard = IntervalPlan()

    public var setDuration: TimeInterval { briskDuration + easyDuration }

    /// index 番目の区間（0 始まり。偶数が速歩、奇数が緩歩）。
    public func segment(index: Int) -> IntervalSegment {
        let index = max(0, index)
        let setIndex = index / 2
        let isBrisk = index % 2 == 0
        let start = Double(setIndex) * setDuration + (isBrisk ? 0 : briskDuration)
        return IntervalSegment(
            index: index,
            setNumber: setIndex + 1,
            phase: isBrisk ? .brisk : .easy,
            start: start,
            duration: isBrisk ? briskDuration : easyDuration
        )
    }

    /// 経過時間に対応する区間。
    public func position(at elapsed: TimeInterval) -> IntervalPosition? {
        guard elapsed >= 0 else { return nil }
        let setIndex = Int(elapsed / setDuration)
        let inSet = elapsed - Double(setIndex) * setDuration
        let current = self.segment(index: setIndex * 2 + (inSet < briskDuration ? 0 : 1))
        return IntervalPosition(segment: current, elapsedInSegment: elapsed - current.start)
    }

    /// 経過時間までに歩いた速歩の合計。
    public func briskTime(upTo elapsed: TimeInterval) -> TimeInterval {
        guard elapsed > 0 else { return 0 }
        let fullSets = (elapsed / setDuration).rounded(.down)
        let remainder = elapsed - fullSets * setDuration
        return fullSets * briskDuration + min(remainder, briskDuration)
    }
}
