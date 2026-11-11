import SwiftUI
import TrotWalkCore

/// 終了画面。記録を淡々と見せるだけで、評価や目標は出さない。
struct SummaryView: View {
    @Environment(WorkoutManager.self) private var workout

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("今日のウォーキング")
                    .font(.headline)

                if let summary = workout.summary {
                    row("歩いた時間", DurationText.minutes(summary.totalTime))
                    row("うち速歩", DurationText.minutes(summary.briskTime))
                    if let meters = summary.distanceMeters {
                        row("距離", String(format: "%.2f km", meters / 1000))
                    }
                }

                if let message = workout.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Text("記録はフィットネスとヘルスケアに保存されました。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("閉じる") { workout.reset() }
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
    }
}
