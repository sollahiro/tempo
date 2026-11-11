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
                    Stepper(value: $settings.value.sets, in: IntervalPlan.setRange) {
                        LabeledContent("セット数", value: "\(settings.value.sets)セット")
                    }
                    Toggle("切り替え10秒前に予告", isOn: $settings.value.switchWarningEnabled)
                    Toggle("歩調テンポの振動", isOn: $settings.value.tempoEnabled)
                    Toggle("心拍で自動調整", isOn: $settings.value.intensityGuideEnabled)
                } header: {
                    Text("設定")
                } footer: {
                    Text("約\(DurationText.minutes(settings.value.plan.totalDuration))、うち速歩\(DurationText.minutes(settings.value.plan.totalBriskDuration))。設定は Apple Watch にも反映されます。")
                }

                Section("振動の合図") {
                    HapticRow(title: "速歩の開始", pattern: "上向きに2回")
                    HapticRow(title: "緩歩の開始", pattern: "下向きに1回")
                    HapticRow(title: "切り替え予告", pattern: "通知の振動（10秒前）")
                    HapticRow(title: "歩調テンポ", pattern: "2歩に1回の軽いクリック")
                    HapticRow(title: "もう少し速く", pattern: "クリック → 上向き（テンポがオフのとき）")
                    HapticRow(title: "少しゆるめて", pattern: "クリック → 下向き（テンポがオフのとき）")
                    HapticRow(title: "完了", pattern: "成功の振動")
                }

                Section("歩き方の目安") {
                    Text("速歩は、息が上がって「ややきつい」と感じるくらい。緩歩は、会話が楽にできるくらいのゆっくり歩きです。")
                    Text("3分ずつが基本ですが、速歩は2分にしても構いません。週に1回15分でも、歩けたら十分です。")
                    Text("歩調テンポは、速歩で毎分116歩、緩歩で96歩から始まります。心拍で自動調整をオンにすると、速歩で心拍が低ければテンポが上がり、高すぎたり緩歩で下がらなかったりすると下がります。上げた速歩のテンポは次のセットにも引き継ぎます。")
                    Text("心拍の目安は、年齢と安静時心拍から推定します。体感と違うときは体感を優先してください。")
                }

                Section("記録") {
                    Text("ワークアウトは屋外ウォーキングとして、フィットネスとヘルスケアに保存されます。")
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
