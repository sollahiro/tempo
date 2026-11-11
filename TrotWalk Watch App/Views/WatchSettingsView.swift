import SwiftUI
import TrotWalkCore

struct WatchSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(WorkoutManager.self) private var workout
    @State private var zones: HeartRateZones?
    private let haptics = HapticPlayer()

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Picker("速歩", selection: $settings.value.briskDuration) {
                    ForEach(IntervalPlan.briskOptions, id: \.self) { seconds in
                        Text(DurationText.minutes(seconds)).tag(seconds)
                    }
                }
                Stepper(value: $settings.value.sets, in: IntervalPlan.setRange) {
                    Text("\(settings.value.sets)セット")
                }
            } footer: {
                Text("速歩の合計 \(DurationText.minutes(settings.value.plan.totalBriskDuration))")
            }

            Section {
                Toggle("切り替え10秒前に予告", isOn: $settings.value.switchWarningEnabled)
                Toggle("歩調テンポ", isOn: $settings.value.tempoEnabled)
                Toggle("心拍で自動調整", isOn: $settings.value.intensityGuideEnabled)
            } footer: {
                Text(guideFooter)
            }

            Section("振動を試す") {
                ForEach(HapticSample.all, id: \.title) { sample in
                    Button(sample.title) { haptics.play(sample.cue) }
                }
                Button("歩調テンポ") { haptics.tempoTick() }
            }
        }
        .navigationTitle("設定")
        .task(id: settings.value.intensityGuideEnabled) {
            guard settings.value.intensityGuideEnabled else { return }
            await workout.requestAuthorization()
            zones = await HealthProfile.zones(store: workout.healthStore)
        }
    }

    private var guideFooter: String {
        let tempo = settings.value.tempoEnabled
        guard settings.value.intensityGuideEnabled else {
            return tempo
                ? "2歩に1回、軽い振動でテンポを刻みます。心拍で自動調整をオンにすると、テンポが心拍に合わせて変わります。"
                : "心拍で自動調整をオンにすると、心拍が目安から外れたときだけ振動で知らせます。"
        }
        guard let zones else {
            return "ヘルスケアに誕生日を登録すると、心拍の目安を計算できます。"
        }
        let how = tempo ? "心拍が目安より低ければテンポを上げ、高ければ下げます。" : "目安から外れたときだけ振動で知らせます。"
        return "速歩の目安は心拍\(Int(zones.briskLowerBound))以上、緩歩は\(Int(zones.easyUpperBound))以下です（推定）。\(how)息が上がって「ややきつい」と感じる体感を優先してください。"
    }
}

struct HapticSample {
    let title: String
    let cue: HapticCue

    static let all: [HapticSample] = [
        HapticSample(title: "速歩の開始", cue: .briskStart),
        HapticSample(title: "緩歩の開始", cue: .easyStart),
        HapticSample(title: "切り替え予告", cue: .switchSoon),
        HapticSample(title: "もう少し速く", cue: .speedUp),
        HapticSample(title: "少しゆるめて", cue: .slowDown),
        HapticSample(title: "完了", cue: .finished),
    ]
}
