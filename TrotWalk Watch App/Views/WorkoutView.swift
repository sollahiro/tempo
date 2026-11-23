import SwiftUI
import TrotWalkCore
import WatchKit

/// ワークアウト中の画面。基本は見なくてよいが、見たときは色だけで分かるようにする。
struct WorkoutView: View {
    @Environment(WorkoutManager.self) private var workout
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        let position = workout.position
        let phase = position?.segment.phase ?? .easy

        VStack(spacing: 4) {
            Text(workout.state == .paused ? (workout.isAutoPaused ? "止まっています" : "一時停止中") : phase.title)
                .font(.title3.bold())

            Text(DurationText.clock(position?.remainingInSegment ?? 0))
                .font(.system(size: 46, weight: .semibold, design: .rounded))
                .monospacedDigit()

            HStack(spacing: 10) {
                if let position {
                    Text("\(position.segment.setNumber)セット目")
                }
                if let heartRate = workout.heartRate {
                    Label("\(Int(heartRate))", systemImage: "heart.fill")
                }
                if let cadence = workout.cadence {
                    Label("\(Int(cadence))", systemImage: "metronome")
                        .accessibilityLabel("テンポ 毎分\(Int(cadence))歩")
                }
            }
            .font(.footnote)

            if !isLuminanceReduced {
                HStack {
                    Button {
                        workout.togglePause()
                    } label: {
                        Image(systemName: workout.state == .paused ? "play.fill" : "pause.fill")
                    }
                    .primaryHandGesture()
                    .accessibilityLabel(workout.state == .paused ? "再開" : "一時停止")

                    HoldToEndButton { workout.end() }
                }
                .padding(.top, 4)
                .disabled(workout.state == .ending)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(phase.color.opacity(isLuminanceReduced ? 0.25 : 0.8).ignoresSafeArea())
    }
}

/// 長押しで終える終了ボタン。押し間違いだけ防げればよいので、確認画面は出さない。
/// 押している間リングが満ちて、満ちたら終了する（途中で離せば何も起きない）。
private struct HoldToEndButton: View {
    let action: () -> Void
    private let holdDuration: Double = 0.8
    @State private var isPressing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.red.opacity(0.25))
            Circle()
                .trim(from: 0, to: isPressing ? 1 : 0)
                .stroke(Color.red, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(isPressing ? .linear(duration: holdDuration) : .easeOut(duration: 0.15), value: isPressing)
            Image(systemName: "xmark")
                .font(.body.bold())
        }
        .frame(width: 44, height: 44)
        .contentShape(Circle())
        .onLongPressGesture(minimumDuration: holdDuration) {
            WKInterfaceDevice.current().play(.success)
            action()
        } onPressingChanged: { pressing in
            isPressing = pressing
        }
        .accessibilityElement()
        .accessibilityLabel("終了")
        .accessibilityHint("長押しで終了します。ここまでの記録は保存されます")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }
}

extension WalkPhase {
    var title: String {
        switch self {
        case .brisk: "速歩"
        case .easy: "緩歩"
        }
    }

    var color: Color {
        switch self {
        case .brisk: .orange
        case .easy: .blue
        }
    }
}

extension View {
    /// watchOS 11 以降では、ダブルタップ（指をつまむ動作）でこのボタンを押せる。
    @ViewBuilder
    func primaryHandGesture() -> some View {
        if #available(watchOS 11.0, *) {
            handGestureShortcut(.primaryAction)
        } else {
            self
        }
    }
}
