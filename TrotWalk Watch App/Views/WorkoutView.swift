import SwiftUI
import TrotWalkCore

/// ワークアウト中の画面。時間や数字は出さず、合図はすべて振動で伝える。
/// 画面に残すのは今のフェーズ名と、一時停止・終了の操作だけ。
struct WorkoutView: View {
    @Environment(WorkoutManager.self) private var workout
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @State private var confirmingEnd = false

    var body: some View {
        let phase = workout.phase

        VStack(spacing: 12) {
            Spacer()

            Text(workout.state == .paused ? "一時停止中" : phase.title)
                .font(.title3)
                .foregroundStyle(.secondary)

            Spacer()

            if !isLuminanceReduced {
                HStack {
                    Button {
                        workout.togglePause()
                    } label: {
                        Image(systemName: workout.state == .paused ? "play.fill" : "pause.fill")
                    }
                    .primaryHandGesture()
                    .accessibilityLabel(workout.state == .paused ? "再開" : "一時停止")

                    Button(role: .destructive) {
                        confirmingEnd = true
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("終了")
                }
                .disabled(workout.state == .ending)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(phase.color.opacity(isLuminanceReduced ? 0.1 : 0.3).ignoresSafeArea())
        .animation(.easeInOut(duration: 1), value: phase)
        .confirmationDialog("ワークアウトを終了しますか？", isPresented: $confirmingEnd) {
            Button("終了して保存", role: .destructive) { workout.end() }
            Button("続ける", role: .cancel) {}
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
