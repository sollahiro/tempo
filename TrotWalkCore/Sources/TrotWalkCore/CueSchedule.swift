import Foundation

/// 手首に伝える合図。実際の振動パターンは watch 側の HapticPlayer が決める。
public enum HapticCue: String, Equatable, Sendable {
    /// 速歩に切り替え
    case briskStart
    /// 緩歩に切り替え
    case easyStart
    /// 切り替え5秒前（強い振動）
    case switchSoon
    /// おすすめの30分に届いた（一度だけ。強制ではなく、知らせるだけ）
    case recommendedReached
    /// 終了
    case finished
    /// 一時停止（立ち止まったときも）
    case paused
    /// 再開（歩き出したときも）
    case resumed
    /// 強度ガイド: もう少しペースを上げる（テンポがオフのとき）
    case speedUp
    /// 強度ガイド: ペースを落とす（テンポがオフのとき）
    case slowDown
}

/// プランの経過時間から、どの時点で何の合図を出すかを決める。終わりの時間はない。
public struct CueSchedule: Sendable {
    public struct Event: Equatable, Sendable {
        public let time: TimeInterval
        public let cue: HapticCue
    }

    /// 切り替えの予告を出す、切り替えまでの秒数
    public static let warningLead: TimeInterval = 5

    public let plan: IntervalPlan
    public let warningsEnabled: Bool
    /// この時間に一度だけ .recommendedReached を出す。nil なら出さない。
    public let milestone: TimeInterval?

    public init(plan: IntervalPlan, warningsEnabled: Bool = true, milestone: TimeInterval? = IntervalPlan.recommendedDuration) {
        self.plan = plan
        self.warningsEnabled = warningsEnabled
        self.milestone = milestone
    }

    /// 区間 index にまつわる合図（その区間の開始と、終わる前の予告）
    func events(forSegment index: Int) -> [Event] {
        let segment = plan.segment(index: index)
        var events: [Event] = []
        if index > 0 {
            events.append(Event(time: segment.start, cue: segment.phase == .brisk ? .briskStart : .easyStart))
        }
        if warningsEnabled {
            // 短すぎる区間では予告しない
            if segment.duration > Self.warningLead * 2 {
                events.append(Event(time: segment.end - Self.warningLead, cue: .switchSoon))
            }
        }
        return events
    }

    /// (previous, current] の間に来た合図。
    /// 複数をまたいだ場合（バックグラウンド復帰など）は、切り替え系はいちばん新しい1つだけにし、
    /// 30分の合図はその後ろに足す。
    public func cues(from previous: TimeInterval, to current: TimeInterval) -> [HapticCue] {
        guard current > previous, current >= 0 else { return [] }
        let first = plan.position(at: max(0, previous))?.segment.index ?? 0
        let last = (plan.position(at: current)?.segment.index ?? 0) + 1
        let crossed = (first...last)
            .flatMap { events(forSegment: $0) }
            .filter { $0.time > previous && $0.time <= current }
        var result: [HapticCue] = []
        if let latest = crossed.max(by: { $0.time < $1.time }) {
            result.append(latest.cue)
        }
        if let milestone, milestone > previous, milestone <= current {
            result.append(.recommendedReached)
        }
        return result
    }
}
