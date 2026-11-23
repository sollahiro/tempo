import SwiftUI
import TrotWalkCore

/// iPhone 側は設定と使い方だけ。ワークアウトは Apple Watch で行う。
struct ContentView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                Section {
                    Text("Apple Watch で「歩きはじめる」を押したら、あとは振動の合図に合わせて歩くだけ。画面を見る必要はありません。")
                } header: {
                    Text("Trot&Walk")
                }

                Section {
                    Picker("速歩の長さ", selection: $settings.value.briskDuration) {
                        ForEach(IntervalPlan.briskOptions, id: \.self) { seconds in
                            Text(DurationText.minutes(seconds)).tag(seconds)
                        }
                    }
                    Toggle("切り替え前の予告（10秒前・5秒前）", isOn: $settings.value.switchWarningEnabled)
                    Toggle("歩調テンポの振動", isOn: $settings.value.tempoEnabled)
                    Toggle("心拍で自動調整", isOn: $settings.value.intensityGuideEnabled)
                    Toggle("立ち止まったら自動で一時停止", isOn: $settings.value.autoPauseEnabled)
                    Toggle("30分たったら振動で知らせる", isOn: $settings.value.recommendedNoticeEnabled)
                } header: {
                    Text("設定")
                } footer: {
                    Text("終わりの時間は決めません。目安は30分以上ですが、いつ終えても大丈夫です。終えるときは Watch の ✕ を長押しします。設定は Apple Watch にも反映されます。")
                }

                Section("振動の合図") {
                    HapticRow(title: "切り替え10秒前", pattern: "長い振動")
                    HapticRow(title: "切り替え5秒前", pattern: "小刻みな振動")
                    HapticRow(title: "切り替え", pattern: "長い振動")
                    HapticRow(title: "歩調テンポ", pattern: "1歩ごとに振動、4歩鳴って4歩休む")
                    HapticRow(title: "立ち止まった / 歩き出した", pattern: "停止 / 開始の振動")
                    HapticRow(title: "30分の目安", pattern: "成功の振動")
                    Text("振動が弱いときは、Watch アプリ →「サウンドと触覚」で「はっきり」を選ぶと強くなります。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("歩き方の目安") {
                    Text("速歩は、息が上がって「ややきつい」と感じるくらい。緩歩は、会話が楽にできるくらいのゆっくり歩きです。")
                    Text("3分ずつが基本ですが、速歩は2分にしても構いません。終わりの時間は決めず、好きなところで終えられます。")
                    Text("歩調テンポは、速歩で毎分116歩、緩歩で96歩から始まります。心拍で自動調整をオンにすると、速歩で心拍が低ければテンポが上がり、高すぎたり緩歩で下がらなかったりすると下がります。上げた速歩のテンポは次のセットにも引き継ぎます。")
                    Text("ワークアウトの終わりに「速歩はどうでしたか？」と一度だけ聞きます。「楽だった」なら次回の目安を少し上げ、「きつかった」なら少し下げます。答えなくても大丈夫です。")
                    Text("心拍の目安は、年齢と安静時心拍から推定します。体感と違うときは体感を優先してください。")
                }

                Section("記録") {
                    Text("ワークアウトは屋外ウォーキングとして、歩いたルート（GPS）と一緒にフィットネスとヘルスケアに保存されます。立ち止まっていた時間は記録から除かれます。")
                }
            }
            .navigationTitle("Trot&Walk")
        }
    }
}

private struct HapticRow: View {
    let title: String
    let pattern: String

    var body: some View {
        LabeledContent(title, value: pattern)
    }
}

#Preview {
    ContentView()
        .environment(SettingsStore())
}
