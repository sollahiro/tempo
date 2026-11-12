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

/// 「速歩 → 緩歩」を1セットとして、選んだ時間いっぱいまでくり返すプラン。
///
/// 時間がセットの長さで割り切れないときは、最後に短いセットを足して時間ちょうどで終える。
/// 余りが2分未満なら、最後の緩歩をその分だけ延ばす（速歩で終わらないようにするため）。
public struct IntervalPlan: Equatable, Sendable {
    /// 選べる時間（秒）: 20〜60分、10分刻み
    public static let durationOptions: [TimeInterval] = [20, 30, 40, 50, 60].map { $0 * 60 }
    public static let briskOptions: [TimeInterval] = [180, 120]

    public var briskDuration: TimeInterval
    public var easyDuration: TimeInterval
    public let totalDuration: TimeInterval
    public let segments: [IntervalSegment]

    public init(briskDuration: TimeInterval = 180, easyDuration: TimeInterval = 180, totalDuration: TimeInterval = 30 * 60) {
        self.briskDuration = max(1, briskDuration)
        self.easyDuration = max(1, easyDuration)
        self.totalDuration = max(totalDuration, self.briskDuration + self.easyDuration)
        self.segments = Self.makeSegments(brisk: self.briskDuration, easy: self.easyDuration, total: self.totalDuration)
    }

    public static let standard = IntervalPlan()

    public var totalBriskDuration: TimeInterval {
        segments.filter { $0.phase == .brisk }.reduce(0) { $0 + $1.duration }
    }

    public var setCount: Int { segments.last?.setNumber ?? 0 }

    private static func makeSegments(brisk: TimeInterval, easy: TimeInterval, total: TimeInterval) -> [IntervalSegment] {
        var result: [IntervalSegment] = []
        var cursor: TimeInterval = 0
        var set = 0

        func append(_ phase: WalkPhase, _ duration: TimeInterval) {
            result.append(IntervalSegment(index: result.count, setNumber: set, phase: phase, start: cursor, duration: duration))
            cursor += duration
        }

        while total - cursor >= brisk + easy {
            set += 1
            append(.brisk, brisk)
            append(.easy, easy)
        }

        let remainder = total - cursor
        if remainder >= 120 {
            // 短いセットを足す。速歩は残りの半分まで（緩歩で終えるため）
            set += 1
            let shortBrisk = min(brisk, (remainder / 2).rounded(.down))
            append(.brisk, shortBrisk)
            append(.easy, remainder - shortBrisk)
        } else if remainder > 0, let last = result.popLast() {
            cursor -= last.duration
            append(last.phase, last.duration + remainder)
        }
        return result
    }

    /// 経過時間に対応する区間。プランが終わっていれば nil。
    public func position(at elapsed: TimeInterval) -> IntervalPosition? {
        guard elapsed >= 0, elapsed < totalDuration,
              let segment = segments.last(where: { $0.start <= elapsed })
        else { return nil }
        return IntervalPosition(segment: segment, elapsedInSegment: elapsed - segment.start)
    }

    public func isFinished(at elapsed: TimeInterval) -> Bool { elapsed >= totalDuration }

    /// 経過時間までに歩いた速歩の合計（途中で終えた場合の表示用）。
    public func briskTime(upTo elapsed: TimeInterval) -> TimeInterval {
        segments
            .filter { $0.phase == .brisk }
            .reduce(0) { $0 + min(max(0, elapsed - $1.start), $1.duration) }
    }
}
