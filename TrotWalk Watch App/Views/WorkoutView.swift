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

                    EndButton { workout.end() }
                }
                .padding(.top, 4)
                .disabled(workout.state == .ending)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(phase.color.opacity(isLuminanceReduced ? 0.25 : 0.8).ignoresSafeArea())
    }
}

/// 終了ボタン。押すと「終了しますか？」と確認し、「終了する」を選んだときだけ終える。
/// 「続ける」を選ぶか閉じれば、そのままワークアウトを続ける。
private struct EndButton: View {
    let action: () -> Void
    @State private var isConfirming = false

    var body: some View {
        Button {
            isConfirming = true
        } label: {
            Image(systemName: "xmark")
                .font(.body.bold())
        }
        .tint(.red)
        .accessibilityLabel("終了")
        .accessibilityHint("終了するか確認します。ここまでの記録は保存されます")
        .confirmationDialog("ワークアウトを終了しますか？", isPresented: $isConfirming, titleVisibility: .visible) {
            Button("終了する", role: .destructive) {
                WKInterfaceDevice.current().play(.success)
                action()
            }
            Button("続ける", role: .cancel) {}
        } message: {
            Text("ここまでの記録は保存されます")
        }
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
