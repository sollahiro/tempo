import SwiftUI

// MARK: - ページの中身

/// 使い方の1ページ。アニメーションの出どころは `animation` で差し替える。
struct HowToPage: Identifiable {
    let id: Int
    let title: String
    let body: String
    let animation: HowToAnimation

    static let all: [HowToPage] = [
        HowToPage(
            id: 0,
            title: "Apple Watch をつけて歩きます",
            body: "Trot&Walk のワークアウトには Apple Watch を使います。手首にしっかりつけてください。",
            animation: .native(.wearWatch)
        ),
        HowToPage(
            id: 1,
            title: "Watch で始めたら、腕をおろして",
            body: "Watch で「歩きはじめる」を押せば準備は完了です。あとは画面を見なくても、振動が合図します。",
            animation: .native(.startOnWatch)
        ),
        HowToPage(
            id: 2,
            title: "最初はゆっくり、振動に合わせて",
            body: "はじめの3分は緩歩です。振動は1歩ごと。ゆっくりした振動に足並みをそろえて歩きます。",
            animation: .native(.slowWalk)
        ),
        HowToPage(
            id: 3,
            title: "振動が速くなったら、速歩",
            body: "振動の間隔が短くなったら速歩です。息が上がって「ややきつい」と感じるくらいで3分歩きます。",
            animation: .native(.briskWalk)
        ),
        HowToPage(
            id: 4,
            title: "切り替えも振動でわかります",
            body: "速歩に入るときは上向きに2回、緩歩に戻るときは下向きに1回、手首が知らせます。時計を見る必要はありません。",
            animation: .native(.switchPace)
        ),
        HowToPage(
            id: 5,
            title: "速歩と緩歩をくり返します",
            body: "選んだ時間（たとえば30分）のあいだ、交互にくり返します。記録はフィットネスとヘルスケアに自動で保存されます。",
            animation: .native(.repeatSets)
        ),
    ]
}

/// アニメーションの出どころ。いまは SwiftUI で描いたものだけ。
/// After Effects で作り直すときは、ここに `case lottie(name: String)` を足し、
/// `HowToAnimationView` の switch で LottieView を返せば、ページ単位で差し替えられる。
enum HowToAnimation {
    case native(HowToScene)
}

struct HowToAnimationView: View {
    let animation: HowToAnimation
    /// 表示中のページだけ動かす。
    let isActive: Bool

    var body: some View {
        switch animation {
        case .native(let scene):
            HowToSceneView(scene: scene, isActive: isActive)
        }
    }
}

/// SwiftUI の Canvas で場面を描き、TimelineView で動かす。
struct HowToSceneView: View {
    let scene: HowToScene
    let isActive: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        let palette = HowToPalette(colorScheme)
        TimelineView(.animation(minimumInterval: nil, paused: !isActive || reduceMotion)) { timeline in
            let t = reduceMotion ? scene.stillTime : max(0, timeline.date.timeIntervalSince(start))
            Canvas { context, size in
                let s = min(size.width, size.height) / 300
                context.translateBy(x: (size.width - 300 * s) / 2, y: (size.height - 300 * s) / 2)
                context.scaleBy(x: s, y: s)
                scene.draw(context, t: t, p: palette)
            }
        }
        .background(palette.background)
        .onChange(of: isActive) { _, active in
            if active { start = Date() }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - 画面

struct HowToView: View {
    var startPage: Int = 0
    var onFinish: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var selection = 0

    private let pages = HowToPage.all

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $selection) {
                    ForEach(pages) { page in
                        HowToPageView(page: page, isActive: selection == page.id)
                            .tag(page.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                Button {
                    if selection < pages.count - 1 {
                        withAnimation { selection += 1 }
                    } else {
                        close()
                    }
                } label: {
                    Text(selection < pages.count - 1 ? "次へ" : "はじめる")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            .navigationTitle("使い方")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる", action: close)
                }
            }
        }
        .onAppear { selection = min(max(0, startPage), pages.count - 1) }
    }

    private func close() {
        onFinish()
        dismiss()
    }
}

private struct HowToPageView: View {
    let page: HowToPage
    let isActive: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HowToAnimationView(animation: page.animation, isActive: isActive)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .frame(maxWidth: 420)

                VStack(spacing: 10) {
                    Text(page.title)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text(page.body)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 8)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 56)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

#Preview("使い方") {
    HowToView()
}

#Preview("ダーク") {
    HowToView()
        .preferredColorScheme(.dark)
}
