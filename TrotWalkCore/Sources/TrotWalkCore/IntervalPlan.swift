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

/// 「速歩 → 緩歩」を1セットとして、指定セット数くり返すプラン。
public struct IntervalPlan: Equatable, Codable, Sendable {
    public static let setRange = 1...10
    public static let briskOptions: [TimeInterval] = [180, 120]

    public var briskDuration: TimeInterval
    public var easyDuration: TimeInterval
    public var sets: Int

    public init(briskDuration: TimeInterval = 180, easyDuration: TimeInterval = 180, sets: Int = 5) {
        self.briskDuration = max(1, briskDuration)
        self.easyDuration = max(1, easyDuration)
        self.sets = min(max(sets, Self.setRange.lowerBound), Self.setRange.upperBound)
    }

    public static let standard = IntervalPlan()

    public var totalDuration: TimeInterval { Double(sets) * (briskDuration + easyDuration) }
    public var totalBriskDuration: TimeInterval { Double(sets) * briskDuration }

    public var segments: [IntervalSegment] {
        var result: [IntervalSegment] = []
        var cursor: TimeInterval = 0
        for set in 1...sets {
            for phase in WalkPhase.allCases {
                let duration = phase == .brisk ? briskDuration : easyDuration
                result.append(IntervalSegment(index: result.count, setNumber: set, phase: phase, start: cursor, duration: duration))
                cursor += duration
            }
        }
        return result
    }

    /// 経過時間に対応する区間。プランが終わっていれば nil。
    public func position(at elapsed: TimeInterval) -> IntervalPosition? {
        guard elapsed >= 0, elapsed < totalDuration else { return nil }
        let setLength = briskDuration + easyDuration
        let setIndex = Int(elapsed / setLength)
        let inSet = elapsed - Double(setIndex) * setLength
        let isBrisk = inSet < briskDuration
        let segmentIndex = setIndex * 2 + (isBrisk ? 0 : 1)
        let segmentStart = Double(setIndex) * setLength + (isBrisk ? 0 : briskDuration)
        let segment = IntervalSegment(
            index: segmentIndex,
            setNumber: setIndex + 1,
            phase: isBrisk ? .brisk : .easy,
            start: segmentStart,
            duration: isBrisk ? briskDuration : easyDuration
        )
        return IntervalPosition(segment: segment, elapsedInSegment: elapsed - segmentStart)
    }

    public func isFinished(at elapsed: TimeInterval) -> Bool { elapsed >= totalDuration }

    /// 経過時間までに歩いた速歩の合計（途中で終えた場合の表示用）。
    public func briskTime(upTo elapsed: TimeInterval) -> TimeInterval {
        segments
            .filter { $0.phase == .brisk }
            .reduce(0) { $0 + min(max(0, elapsed - $1.start), $1.duration) }
    }
}
