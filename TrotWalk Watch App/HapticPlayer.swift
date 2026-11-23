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
/// | 切り替え10秒前       | 長い振動                           |
/// | 切り替え5秒前        | 小刻みな振動                       |
/// | 切り替え（速歩/緩歩）| 長い振動                           |
/// | 歩調テンポ           | 1歩ごとに強めのタップ、4歩鳴って4歩休む |
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
    func tempoTick() {
        if let cueEndsAt, ContinuousClock.now < cueEndsAt + tempoQuietTime { return }
        WKInterfaceDevice.current().play(Self.tempoHaptic)
    }

    static let tempoHaptic: WKHapticType = .start

    /// 長い振動: 強めの振動を短い間隔で詰めて並べる
    static let longBuzz: [Step] = [
        Step(haptic: .notification, delay: .zero),
        Step(haptic: .directionUp, delay: .milliseconds(250)),
        Step(haptic: .notification, delay: .milliseconds(250)),
    ]

    /// 小刻みな振動: 短いタップを素早く5回
    static let rapidTaps: [Step] = [
        Step(haptic: .start, delay: .zero),
        Step(haptic: .start, delay: .milliseconds(160)),
        Step(haptic: .start, delay: .milliseconds(160)),
        Step(haptic: .start, delay: .milliseconds(160)),
        Step(haptic: .start, delay: .milliseconds(160)),
    ]

    static func pattern(for cue: HapticCue) -> [Step] {
        switch cue {
        case .switchSoon, .briskStart, .easyStart: longBuzz
        case .switchVerySoon: rapidTaps
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
