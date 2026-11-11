import SwiftUI

/// 開始前の 3・2・1。標準のワークアウトアプリと同じく、数字とリングが1秒ごとに進む。
/// タップするとすぐ始まる。
struct CountdownView: View {
    let count: Int
    @Environment(WorkoutManager.self) private var workout
    @State private var progress: CGFloat = 0

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color.orange.opacity(0.25), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Text("\(count)")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy, value: count)
            }
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
            .onTapGesture { workout.skipCountdown() }
            .accessibilityLabel("開始まで\(count)秒")
            .accessibilityHint("タップするとすぐに始まります")
            .accessibilityAddTraits(.isButton)

            Button("キャンセル") { workout.cancelCountdown() }
                .buttonStyle(.plain)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .onAppear(perform: animateRing)
        .onChange(of: count) { animateRing() }
    }

    /// 3秒で1周するように、数字が変わるたびにリングを1/3ずつ進める。
    private func animateRing() {
        let target = CGFloat(4 - count) / 3
        withAnimation(.linear(duration: 1)) {
            progress = target
        }
    }
}
