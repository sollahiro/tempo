import SwiftUI

/// SwiftUI で描く使い方アニメーションの各場面。300×300 の設計座標で、t 秒の時点を描く。
/// どの場面もループする。文字は入れない（説明は画面のキャプションで出す）。
enum HowToScene: CaseIterable {
    case wearWatch
    case startOnWatch
    case slowWalk
    case briskWalk
    case pullBack
    case repeatSets

    /// 「視差効果を減らす」がオンのときに止めて見せる時点。
    var stillTime: Double {
        switch self {
        case .wearWatch: 1.6
        case .startOnWatch: 2.2
        case .slowWalk: 0.1
        case .briskWalk: 0.1
        case .pullBack: 4.0
        case .repeatSets: 0.2
        }
    }

    func draw(_ ctx: GraphicsContext, t: Double, p: HowToPalette) {
        switch self {
        case .wearWatch: Self.drawWearWatch(ctx, t, p)
        case .startOnWatch: Self.drawStartOnWatch(ctx, t, p)
        case .slowWalk: Self.drawWalk(ctx, t, p, brisk: false)
        case .briskWalk: Self.drawWalk(ctx, t, p, brisk: true)
        case .pullBack: Self.drawPullBack(ctx, t, p)
        case .repeatSets: Self.drawRepeatSets(ctx, t, p)
        }
    }

    // 歩調（見た目用に実際の差より少し誇張している）。歩行周期の角速度。
    static let slowOmega = 2 * Double.pi * 0.62
    static let briskOmega = 2 * Double.pi * 1.05
    static let groundY = 250.0

    // MARK: ① Apple Watch をつける

    private static func drawWearWatch(_ ctx: GraphicsContext, _ time: Double, _ p: HowToPalette) {
        let loop = 3.6
        let t = time.truncatingRemainder(dividingBy: loop)
        ctx.memphisBackdrop(p, blobs: [(CGPoint(x: 95, y: 105), 72, true), (CGPoint(x: 232, y: 215), 52, false)], seed: 0)

        var c = ctx
        c.opacity = 1 - Ease.progress(t, 3.2, 3.6)

        // 横に伸ばした前腕と手（ラフ①の構図）
        let armY = 178.0
        c.line(CGPoint(x: -20, y: armY), CGPoint(x: 205, y: armY), p.skin, width: 62)
        c.line(CGPoint(x: -20, y: armY), CGPoint(x: 38, y: armY), p.shirt, width: 72)
        c.circle(CGPoint(x: 226, y: armY + 4), 36, p.skin)
        c.line(CGPoint(x: 222, y: armY - 26), CGPoint(x: 252, y: armY - 34), p.skin, width: 18)
        c.circle(CGPoint(x: 226, y: armY + 4), 36 * 0.55, p.skinShade.opacity(0.35))

        // 時計が上から降りてきて手首におさまる
        let u = Ease.progress(t, 0.2, 0.85)
        let y = Ease.lerp(-50, armY, Ease.outBack(u))
        let lit = Ease.progress(t, 1.0, 1.3)
        let screen = lit > 0 ? p.slow.opacity(0.25 + 0.75 * lit) : p.screenOff
        c.watch(at: CGPoint(x: 140, y: y), angle: .pi / 2, scale: 1.25, screen: screen, p: p, bandWidth: 64)

        // 画面が点いたら、軽く振動
        if t > 1.4 {
            let k = (t - 1.4).truncatingRemainder(dividingBy: 0.6) / 0.6
            c.buzz(at: CGPoint(x: 140, y: armY), p.slow, alpha: max(0, 1 - k * 2.5), radius: 44, length: 12)
        }
    }

    // MARK: ② Watch で始めて、腕をおろす

    private static func drawStartOnWatch(_ ctx: GraphicsContext, _ time: Double, _ p: HowToPalette) {
        let loop = 4.4
        let t = time.truncatingRemainder(dividingBy: loop)
        ctx.memphisBackdrop(p, blobs: [(CGPoint(x: 210, y: 95), 70, false), (CGPoint(x: 80, y: 225), 55, true)], seed: 1)

        var c = ctx
        c.opacity = 1 - Ease.progress(t, 4.0, 4.4)

        let pivot = CGPoint(x: 105, y: -25)
        let lower = Ease.inOut(Ease.progress(t, 1.2, 1.9))
        let buzzing = t > 2.0 ? max(0, 1 - ((t - 2.0).truncatingRemainder(dividingBy: 0.7) / 0.7) * 2.5) : 0
        let shake = 0.025 * sin(t * 60) * buzzing
        let angle = Ease.lerp(0.95, 0.04, lower) + shake

        // 腕（肩は画面の外）
        var arm = c
        arm.translateBy(x: pivot.x, y: pivot.y)
        arm.rotate(by: .radians(-angle))
        arm.line(CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 190), p.skin, width: 56)
        arm.line(CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 70), p.shirt, width: 66)
        arm.circle(CGPoint(x: 0, y: 222), 32, p.skin)
        arm.circle(CGPoint(x: 0, y: 222), 18, p.skinShade.opacity(0.35))

        // 画面: 開始前は再生マーク、タップで点灯
        let watchAt = polar(pivot, angle, 160)
        let tapped = t > 0.6
        let screen = tapped ? p.slow : p.screenOff
        c.watch(at: watchAt, angle: angle, scale: 1.15, screen: screen, p: p, bandWidth: 62)
        if !tapped {
            var tri = Path()
            tri.move(to: CGPoint(x: watchAt.x - 6, y: watchAt.y - 9))
            tri.addLine(to: CGPoint(x: watchAt.x + 9, y: watchAt.y))
            tri.addLine(to: CGPoint(x: watchAt.x - 6, y: watchAt.y + 9))
            tri.closeSubpath()
            c.fill(tri, with: .color(p.slow))
        }
        // タップの波紋
        let tap = Ease.progress(t, 0.45, 1.05)
        if tap > 0, tap < 1 {
            var r = c
            r.opacity = c.opacity * (1 - tap)
            r.ring(watchAt, 10 + 34 * tap, p.cap, width: 4)
        }

        // 腕をおろしたら、手首に振動
        if buzzing > 0 {
            c.zigzag(from: CGPoint(x: watchAt.x - 46, y: watchAt.y - 18), height: 36, p.slow, alpha: buzzing)
            c.zigzag(from: CGPoint(x: watchAt.x + 46, y: watchAt.y - 18), height: 36, p.slow, alpha: buzzing)
        }
    }

    // MARK: ③④ 振動に合わせて歩く（緩歩・速歩）

    private static func drawWalk(_ ctx: GraphicsContext, _ t: Double, _ p: HowToPalette, brisk: Bool) {
        let color = brisk ? p.brisk : p.slow
        let omega = brisk ? briskOmega : slowOmega
        ctx.memphisBackdrop(
            p,
            blobs: brisk
                ? [(CGPoint(x: 150, y: 140), 92, true), (CGPoint(x: 250, y: 60), 30, false)]
                : [(CGPoint(x: 150, y: 140), 92, false), (CGPoint(x: 55, y: 70), 30, true)],
            seed: brisk ? 2 : 3
        )

        let phase = omega * t
        let pose = brisk ? WalkerPose.brisk(phase: phase) : WalkerPose.slow(phase: phase)
        drawGround(ctx, p, offset: t * (brisk ? 70 : 32), leftColor: p.ground, rightColor: p.ground, split: 0)

        if brisk {
            // 後ろに流れるスピード線
            for (i, y) in [120.0, 150.0, 180.0].enumerated() {
                let k = (t * 2.2 + Double(i) * 0.33).truncatingRemainder(dividingBy: 1)
                var s = ctx
                s.opacity = 1 - k
                let x = 92 - k * 30
                s.line(CGPoint(x: x, y: y), CGPoint(x: x - 22, y: y), color, width: 4)
            }
        }

        let screen = color
        let r = Walker.draw(ctx, colors: WalkerColors(p), ground: CGPoint(x: 145, y: groundY), pose: pose, watch: (screen: screen, p: p))
        ctx.buzz(at: r.wrist, color, alpha: pose.stepPulse, radius: 14)

        // 3分を文字なしで: 右上の円が満ちていく
        let loop = brisk ? 5.0 : 6.0
        let ringCenter = CGPoint(x: 248, y: 58)
        ctx.ring(ringCenter, 22, color.opacity(0.22), width: 8)
        ctx.arc(ringCenter, 22, fraction: t.truncatingRemainder(dividingBy: loop) / loop, color, width: 8)
    }

    // MARK: ⑤ ④からカメラが引いて、隣の緩歩が見えてくる

    private static func drawPullBack(_ ctx: GraphicsContext, _ time: Double, _ p: HowToPalette) {
        let loop = 6.8
        let t = time.truncatingRemainder(dividingBy: loop)
        ctx.memphisBackdrop(p, blobs: [(CGPoint(x: 150, y: 140), 92, true), (CGPoint(x: 250, y: 60), 30, false)], seed: 4)

        var c = ctx
        c.opacity = 1 - Ease.progress(t, 6.4, 6.8)

        // 最初は④と同じ構図。そこから引いて、左隣の緩歩の区間まで見せる。
        let zoom = Ease.inOut(Ease.progress(t, 1.0, 3.2))
        let scale = Ease.lerp(1, 0.5, zoom)
        let focus = CGPoint(x: Ease.lerp(150, 0, zoom), y: Ease.lerp(150, 120, zoom))
        c.translateBy(x: 150, y: 150)
        c.scaleBy(x: scale, y: scale)
        c.translateBy(x: -focus.x, y: -focus.y)

        // 地面: 左が緩歩（青）、右が速歩（オレンジ）
        c.line(CGPoint(x: -290, y: groundY), CGPoint(x: -4, y: groundY), p.slow, width: 5)
        c.line(CGPoint(x: 4, y: groundY), CGPoint(x: 288, y: groundY), p.brisk, width: 5)
        func dashes(from x0: Double, to x1: Double, offset: Double) {
            let spacing = 46.0
            var x = x0 + 6 - offset.truncatingRemainder(dividingBy: spacing)
            while x < x1 - 16 {
                if x > x0 + 2 {
                    c.line(CGPoint(x: x, y: groundY + 18), CGPoint(x: x + 16, y: groundY + 18), p.ground.opacity(0.35), width: 4)
                }
                x += spacing
            }
        }
        dashes(from: -290, to: 0, offset: t * 32)
        dashes(from: 0, to: 290, offset: t * 70)

        // 区切りの点線と旗
        var y = 60.0
        while y < groundY + 30 {
            c.line(CGPoint(x: 0, y: y), CGPoint(x: 0, y: y + 8), p.ground.opacity(0.5), width: 3)
            y += 16
        }
        c.line(CGPoint(x: 0, y: 60), CGPoint(x: 0, y: groundY), p.ground, width: 4)
        var flag = Path()
        flag.move(to: CGPoint(x: 2, y: 60))
        flag.addLine(to: CGPoint(x: 36, y: 74))
        flag.addLine(to: CGPoint(x: 2, y: 88))
        flag.closeSubpath()
        c.fill(flag, with: .color(p.cap))

        // 2人がそれぞれの区間を歩く
        let slowPose = WalkerPose.slow(phase: slowOmega * t)
        let briskPose = WalkerPose.brisk(phase: briskOmega * t)
        let rs = Walker.draw(c, colors: WalkerColors(p), ground: CGPoint(x: -150, y: groundY), pose: slowPose, watch: (screen: p.slow, p: p))
        c.buzz(at: rs.wrist, p.slow, alpha: slowPose.stepPulse, radius: 14)
        let rb = Walker.draw(c, colors: WalkerColors(p), ground: CGPoint(x: 145, y: groundY), pose: briskPose, watch: (screen: p.brisk, p: p))
        c.buzz(at: rb.wrist, p.brisk, alpha: briskPose.stepPulse, radius: 14)

        // 時間の円も④と同じ位置から
        for (center, color, length) in [(CGPoint(x: 248, y: 58), p.brisk, 5.0), (CGPoint(x: -52, y: 58), p.slow, 6.0)] {
            c.ring(center, 22, color.opacity(0.22), width: 8)
            c.arc(center, 22, fraction: t.truncatingRemainder(dividingBy: length) / length, color, width: 8)
        }
    }

    // MARK: ⑥ くり返す

    private static func drawRepeatSets(_ ctx: GraphicsContext, _ t: Double, _ p: HowToPalette) {
        ctx.memphisBackdrop(p, blobs: [(CGPoint(x: 150, y: 150), 110, false)], seed: 5)

        let columns = 5, rows = 2
        let size = CGSize(width: 46, height: 74)
        let gap = 8.0
        let originX = (300 - (Double(columns) * size.width + Double(columns - 1) * gap)) / 2
        let rowY = [95.0, 200.0]
        let step = 0.75
        let count = columns * rows
        let active = Int(t / step) % count

        for i in 0..<count {
            let col = i % columns, row = i / columns
            let center = CGPoint(
                x: originX + Double(col) * (size.width + gap) + size.width / 2,
                y: rowY[row]
            )
            let isBrisk = !i.isMultiple(of: 2)
            let color = isBrisk ? p.brisk : p.slow
            let isActive = i == active

            var b = ctx
            b.opacity = isActive ? 1 : 0.5
            let s: CGFloat = isActive ? 1.1 : 1
            b.roundedRect(center: center, size: CGSize(width: size.width * s, height: size.height * s), radius: 12, color)

            // ブロックの中の小さな人（いまのブロックだけ歩く）
            var fig = b
            fig.translateBy(x: center.x, y: center.y + size.height * s / 2 - 6)
            fig.scaleBy(x: 0.3 * s, y: 0.3 * s)
            let phase = isActive ? (isBrisk ? briskOmega : slowOmega) * t : 0.6
            let pose = isBrisk ? WalkerPose.brisk(phase: phase) : WalkerPose.slow(phase: phase)
            Walker.draw(fig, colors: WalkerColors(mono: .white), ground: .zero, pose: pose)

            // いまのブロックの上に振動の印（ラフ⑥）
            if isActive {
                let pulse = pose.stepPulse
                ctx.buzz(at: CGPoint(x: center.x, y: center.y - size.height * s / 2 + 2), color, alpha: max(0.35, pulse), radius: 8, length: 9)
            }
        }
    }

    // MARK: 地面

    /// 地面の線と、流れる短い線。split より左を leftColor、右を rightColor で塗る。
    private static func drawGround(_ ctx: GraphicsContext, _ p: HowToPalette, offset: Double, leftColor: Color, rightColor: Color, split: Double) {
        if split <= 0 {
            ctx.line(CGPoint(x: 12, y: groundY), CGPoint(x: 288, y: groundY), rightColor, width: 5)
        } else if split >= 300 {
            ctx.line(CGPoint(x: 12, y: groundY), CGPoint(x: 288, y: groundY), leftColor, width: 5)
        } else {
            ctx.line(CGPoint(x: 12, y: groundY), CGPoint(x: max(12, split), y: groundY), leftColor, width: 5)
            ctx.line(CGPoint(x: min(288, split), y: groundY), CGPoint(x: 288, y: groundY), rightColor, width: 5)
        }
        let spacing = 46.0
        let shift = offset.truncatingRemainder(dividingBy: spacing)
        var x = 20 - shift
        while x < 290 {
            if x > 14 {
                ctx.line(CGPoint(x: x, y: groundY + 18), CGPoint(x: x + 16, y: groundY + 18), p.ground.opacity(0.35), width: 4)
            }
            x += spacing
        }
    }
}
