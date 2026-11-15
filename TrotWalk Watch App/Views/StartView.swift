import SwiftUI
import TrotWalkCore

struct StartView: View {
    @Environment(WorkoutManager.self) private var workout
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    Button {
                        Task { await workout.start(with: settings.value) }
                    } label: {
                        Label("歩きはじめる", systemImage: "figure.walk")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)

                    Text(planText)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)

                    if let message = workout.errorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    NavigationLink {
                        WatchSettingsView()
                    } label: {
                        Label("設定", systemImage: "slider.horizontal.3")
                    }
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle("Trot&Walk")
        }
    }

    private var planText: String {
        let plan = settings.value.plan
        return "速歩\(DurationText.minutes(plan.briskDuration))と緩歩\(DurationText.minutes(plan.easyDuration))を、終えるまでくり返します。"
    }
}
