import TrotWalkCore
import WatchKit

/// 合図を手首の振動に変える。画面を見なくても区別できるよう、向きと回数で分ける。
///
/// | 合図         | 振動                     |
/// |--------------|--------------------------|
/// | 速歩の開始   | 上向き × 2               |
/// | 緩歩の開始   | 下向き × 1               |
/// | 切り替え予告 | 通知（10秒前）           |
/// | 歩調テンポ   | 軽いクリック（2歩に1回） |
/// | もう少し速く | クリック → 上向き        |
/// | 少しゆるめて | クリック → 下向き        |
///
/// テンポのクリックは、ほかの合図が鳴っている間とその直後は止める。
/// | 一時停止     | 停止                     |
/// | 再開         | 開始                     |
/// | 完了         | 成功                     |
@MainActor
final class HapticPlayer {
    private var playback: Task<Void, Never>?
    private let gap: Duration = .milliseconds(500)

    private var cueEndsAt: ContinuousClock.Instant?
    private let tempoQuietTime: Duration = .milliseconds(1200)

    nonisolated init() {}

    /// 歩調テンポの1拍。合図と重なるときは鳴らさない。
    func tempoTick() {
        if let cueEndsAt, ContinuousClock.now < cueEndsAt + tempoQuietTime { return }
        WKInterfaceDevice.current().play(.click)
    }

    func play(_ cue: HapticCue) {
        let pattern = Self.pattern(for: cue)
        cueEndsAt = ContinuousClock.now + gap * (pattern.count - 1)
        playback?.cancel()
        playback = Task { [gap] in
            for (index, haptic) in pattern.enumerated() {
                if index > 0 { try? await Task.sleep(for: gap) }
                if Task.isCancelled { return }
                WKInterfaceDevice.current().play(haptic)
            }
        }
    }

    static func pattern(for cue: HapticCue) -> [WKHapticType] {
        switch cue {
        case .briskStart: [.directionUp, .directionUp]
        case .easyStart: [.directionDown]
        case .switchSoon: [.notification]
        case .speedUp: [.click, .directionUp]
        case .slowDown: [.click, .directionDown]
        case .paused: [.stop]
        case .resumed: [.start]
        case .finished: [.success]
        }
    }
}
