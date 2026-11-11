import Foundation

/// 手首に伝える合図。実際の振動パターンは watch 側の HapticPlayer が決める。
public enum HapticCue: String, Equatable, Sendable {
    /// 速歩を始める
    case briskStart
    /// 緩歩に切り替える
    case easyStart
    /// まもなく切り替え（10秒前）
    case switchSoon
    /// プラン完了
    case finished
    /// 一時停止
    case paused
    /// 再開
    case resumed
    /// 強度ガイド: もう少しペースを上げる
    case speedUp
    /// 強度ガイド: ペースを落とす
    case slowDown
}

/// プランの経過時間から、どの時点で何の合図を出すかを決める。
public struct CueSchedule: Sendable {
    public struct Event: Equatable, Sendable {
        public let time: TimeInterval
        public let cue: HapticCue
    }

    public static let defaultWarningLead: TimeInterval = 10

    public let plan: IntervalPlan
    public let events: [Event]

    public init(plan: IntervalPlan, warningLead: TimeInterval = CueSchedule.defaultWarningLead) {
        self.plan = plan
        var events: [Event] = []
        for segment in plan.segments {
            if segment.index > 0 {
                events.append(Event(time: segment.start, cue: segment.phase == .brisk ? .briskStart : .easyStart))
            }
            // 短すぎる区間では予告しない
            if warningLead > 0, segment.duration > warningLead * 2 {
                events.append(Event(time: segment.end - warningLead, cue: .switchSoon))
            }
        }
        events.append(Event(time: plan.totalDuration, cue: .finished))
        self.events = events.sorted { $0.time < $1.time }
    }

    /// (previous, current] の間に来た合図。
    /// バックグラウンド復帰などで複数をまたいだ場合は、いちばん新しい1つだけを返す
    /// （古い合図をまとめて鳴らすと混乱するため）。
    public func cue(from previous: TimeInterval, to current: TimeInterval) -> HapticCue? {
        guard current > previous else { return nil }
        events.last { $0.time > previous && $0.time <= current }?.cue
    }
}
