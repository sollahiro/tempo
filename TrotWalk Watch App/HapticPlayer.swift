import TrotWalkCore
import WatchKit

/// 合図を手首の振動に変える。腕を下ろしたままでも分かるよう、強めの種類を選んでいる。
///
/// watchOS には振動の強さそのものを変える API がないので、強く感じる種類
/// （notification / start / directionUp など）を選び、長い振動は短い振動を詰めて並べて作る。
/// iPhone の Watch アプリ →「サウンドと触覚」→「はっきり」にすると、全体が強くなる。
///
/// | 合図                 | 振動                               |
/// |----------------------|------------------------------------|
/// | 切り替え5秒前        | 強く長い振動                       |
/// | 切り替え（速歩/緩歩）| 長い振動                           |
/// | 歩調テンポ           | 1歩ごとに強めのタップ、4歩鳴って4歩休む |
/// | 切り替え直後・再開後 | 最初の4歩はテンポをさらに強く      |
/// | 30分の目安           | 成功                               |
/// | 一時停止 / 再開      | 停止 / 開始                        |
/// | 終了                 | 成功                               |
@MainActor
final class HapticPlayer {
    struct Step {
        let haptic: WKHapticType
        /// この振動の前に置く間
        let delay: Duration
    }

    private var playback: Task<Void, Never>?
    private var cueEndsAt: ContinuousClock.Instant?
    /// 合図の前後はテンポを鳴らさない
    private let tempoQuietTime: Duration = .milliseconds(1200)

    nonisolated init() {}

    /// 合図を順に鳴らす（複数あれば少し間をあけて続ける）。
    func play(_ cues: [HapticCue]) {
        var steps: [Step] = []
        for (index, cue) in cues.enumerated() {
            var pattern = Self.pattern(for: cue)
            if index > 0, let first = pattern.first {
                pattern[0] = Step(haptic: first.haptic, delay: .milliseconds(900))
            }
            steps += pattern
        }
        guard !steps.isEmpty else { return }
        let total = steps.reduce(Duration.zero) { $0 + $1.delay }
        cueEndsAt = ContinuousClock.now + total

        playback?.cancel()
        playback = Task {
            for step in steps {
                if step.delay > .zero { try? await Task.sleep(for: step.delay) }
                if Task.isCancelled { return }
                WKInterfaceDevice.current().play(step.haptic)
            }
        }
    }

    func play(_ cue: HapticCue) {
        play([cue])
    }

    /// 開始前カウントダウンの1拍
    func countdownTick() {
        WKInterfaceDevice.current().play(.click)
    }

    /// 歩調テンポの1拍。合図と重なるときは鳴らさない。
    /// - Parameter accented: 切り替え直後・再開直後の、強く鳴らす拍か
    /// - Returns: 実際に鳴らしたか
    @discardableResult
    func tempoTick(accented: Bool = false) -> Bool {
        if let cueEndsAt, ContinuousClock.now < cueEndsAt + tempoQuietTime { return false }
        WKInterfaceDevice.current().play(accented ? Self.accentTempoHaptic : Self.tempoHaptic)
        return true
    }

    static let tempoHaptic: WKHapticType = .start
    /// 切り替え直後・再開直後の4歩。いちばん強く感じる種類を使う
    static let accentTempoHaptic: WKHapticType = .notification

    /// 長い振動: 強めの振動を短い間隔で詰めて並べる
    static let longBuzz: [Step] = [
        Step(haptic: .notification, delay: .zero),
        Step(haptic: .directionUp, delay: .milliseconds(250)),
        Step(haptic: .notification, delay: .milliseconds(250)),
    ]

    /// 強く長い振動（切り替え5秒前）: 強い振動を長い振動より多く、詰めて並べる
    static let strongBuzz: [Step] = [
        Step(haptic: .notification, delay: .zero),
        Step(haptic: .directionUp, delay: .milliseconds(220)),
        Step(haptic: .notification, delay: .milliseconds(220)),
        Step(haptic: .directionUp, delay: .milliseconds(220)),
        Step(haptic: .notification, delay: .milliseconds(220)),
    ]

    static func pattern(for cue: HapticCue) -> [Step] {
        switch cue {
        case .switchSoon: strongBuzz
        case .briskStart, .easyStart: longBuzz
        case .recommendedReached, .finished: [Step(haptic: .success, delay: .zero)]
        case .paused: [Step(haptic: .stop, delay: .zero)]
        case .resumed: [Step(haptic: .start, delay: .zero)]
        case .speedUp:
            [Step(haptic: .click, delay: .zero), Step(haptic: .directionUp, delay: .milliseconds(500))]
        case .slowDown:
            [Step(haptic: .click, delay: .zero), Step(haptic: .directionDown, delay: .milliseconds(500))]
        }
    }
}
