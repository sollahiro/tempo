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
            } footer: {
                Text("終わりの時間は決めません。目安は30分以上ですが、いつ終えても大丈夫です。")
            }

            Section {
                Toggle("切り替え前の予告", isOn: $settings.value.switchWarningEnabled)
                Toggle("歩調テンポ", isOn: $settings.value.tempoEnabled)
                Toggle("心拍で自動調整", isOn: $settings.value.intensityGuideEnabled)
                Toggle("止まったら一時停止", isOn: $settings.value.autoPauseEnabled)
                Toggle("30分で知らせる", isOn: $settings.value.recommendedNoticeEnabled)
            } footer: {
                Text(guideFooter)
            }

            Section("振動を試す") {
                ForEach(HapticSample.all, id: \.title) { sample in
                    Button(sample.title) { haptics.play(sample.cue) }
                }
                Button("歩調テンポ") { haptics.tempoTick() }
                Text("振動が弱いときは、iPhone の Watch アプリ →「サウンドと触覚」で「はっきり」を選ぶと強くなります。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("設定")
        .task(id: settings.value.intensityGuideEnabled) {
            guard settings.value.intensityGuideEnabled else { return }
            await workout.requestAuthorization()
            zones = await HealthProfile.zones(
                store: workout.healthStore,
                briskReserve: PersonalCalibration.load().briskReserve
            )
        }
    }

    private var guideFooter: String {
        let tempo = settings.value.tempoEnabled
        guard settings.value.intensityGuideEnabled else {
            return tempo
                ? "接地のタイミングで振動します。4歩鳴って4歩休む、をくり返します。心拍で自動調整をオンにすると、テンポが心拍に合わせて変わります。"
                : "心拍で自動調整をオンにすると、心拍が目安から外れたときだけ振動で知らせます。"
        }
        guard let zones else {
            return "ヘルスケアに誕生日を登録すると、心拍の目安を計算できます。"
        }
        let how = tempo ? "心拍が目安より低ければテンポを上げ、高ければ下げます。" : "目安から外れたときだけ振動で知らせます。"
        let learn = "終了後に「楽だった / きつかった」と答えると、次回の目安が少し変わります。"
        return "速歩の目安は心拍\(Int(zones.briskLowerBound))以上、緩歩は\(Int(zones.easyUpperBound))以下です（推定）。\(how)\(learn)息が上がって「ややきつい」と感じる体感を優先してください。"
    }
}

struct HapticSample {
    let title: String
    let cue: HapticCue

    static let all: [HapticSample] = [
        HapticSample(title: "切り替え10秒前・切り替え", cue: .switchSoon),
        HapticSample(title: "切り替え5秒前", cue: .switchVerySoon),
        HapticSample(title: "30分の目安", cue: .recommendedReached),
        HapticSample(title: "一時停止", cue: .paused),
        HapticSample(title: "再開", cue: .resumed),
    ]
}
