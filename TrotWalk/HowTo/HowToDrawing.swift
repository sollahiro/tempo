import SwiftUI

// 使い方アニメーションの描画部品。すべて 300×300 の設計座標で描く。

enum Ease {
    static func clamp(_ x: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double { min(max(x, lo), hi) }
    static func lerp(_ a: Double, _ b: Double, _ u: Double) -> Double { a + (b - a) * u }
    /// 0...1 の区間 [from, to] での進み具合。
    static func progress(_ t: Double, _ from: Double, _ to: Double) -> Double { clamp((t - from) / (to - from)) }
    static func inOut(_ u: Double) -> Double { u < 0.5 ? 2 * u * u : 1 - pow(-2 * u + 2, 2) / 2 }
    static func outBack(_ u: Double) -> Double {
        let c1 = 1.70158, c3 = c1 + 1
        return 1 + c3 * pow(u - 1, 3) + c1 * pow(u - 1, 2)
    }
}

/// 角度 a（ラジアン。0 が真下、正が前＝右）の方向に長さ len 進んだ点。
func polar(_ p: CGPoint, _ a: Double, _ len: Double) -> CGPoint {
    CGPoint(x: Double(p.x) + len * sin(a), y: Double(p.y) + len * cos(a))
}

extension GraphicsContext {
    func line(_ a: CGPoint, _ b: CGPoint, _ color: Color, width: CGFloat) {
        var path = Path()
        path.move(to: a)
        path.addLine(to: b)
        stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    func polyline(_ points: [CGPoint], _ color: Color, width: CGFloat) {
        guard let first = points.first else { return }
        var path = Path()
        path.move(to: first)
        for p in points.dropFirst() { path.addLine(to: p) }
        stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    func circle(_ c: CGPoint, _ r: CGFloat, _ color: Color) {
        fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(color))
    }

    func ring(_ c: CGPoint, _ r: CGFloat, _ color: Color, width: CGFloat) {
        stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(color), lineWidth: width)
    }

    func roundedRect(center c: CGPoint, size: CGSize, radius: CGFloat, _ color: Color) {
        let rect = CGRect(x: c.x - size.width / 2, y: c.y - size.height / 2, width: size.width, height: size.height)
        fill(Path(roundedRect: rect, cornerRadius: radius), with: .color(color))
    }

    /// 円弧（0...1 の割合）。時間の経過を文字なしで見せるのに使う。
    func arc(_ c: CGPoint, _ r: CGFloat, fraction: Double, _ color: Color, width: CGFloat) {
        guard fraction > 0 else { return }
        var path = Path()
        path.addArc(center: c, radius: r, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * min(fraction, 1)), clockwise: false)
        stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    /// 振動を表す「〃」のような短い線。強さ alpha が 0 なら描かない。
    func buzz(at c: CGPoint, _ color: Color, alpha: Double, radius: CGFloat = 16, length: CGFloat = 8) {
        guard alpha > 0.01 else { return }
        var ctx = self
        ctx.opacity = alpha
        for deg in [-140.0, -90.0, -40.0] {
            let a = deg * .pi / 180
            let r0 = Double(radius) + (1 - alpha) * 4
            let r1 = r0 + Double(length)
            let p0 = CGPoint(x: Double(c.x) + r0 * cos(a), y: Double(c.y) + r0 * sin(a))
            let p1 = CGPoint(x: Double(c.x) + r1 * cos(a), y: Double(c.y) + r1 * sin(a))
            ctx.line(p0, p1, color, width: 3.5)
        }
    }

    /// 横に揺れるジグザグ。手首の振動を強調する。
    func zigzag(from a: CGPoint, height: CGFloat, _ color: Color, alpha: Double) {
        guard alpha > 0.01 else { return }
        var ctx = self
        ctx.opacity = alpha
        let steps = 4
        var pts: [CGPoint] = []
        for i in 0...steps {
            let y = a.y + height * CGFloat(i) / CGFloat(steps)
            pts.append(CGPoint(x: a.x + (i.isMultiple(of: 2) ? -4 : 4), y: y))
        }
        ctx.polyline(pts, color, width: 3.5)
    }

    /// 背景の大きな丸と、メンフィス風の小さな飾り（点・三角・波線）。
    func memphisBackdrop(_ p: HowToPalette, blobs: [(CGPoint, CGFloat, Bool)], seed: Int) {
        for (c, r, isA) in blobs { circle(c, r, isA ? p.blobA : p.blobB) }
        var ctx = self
        ctx.opacity = 0.55
        let spots: [CGPoint] = [
            CGPoint(x: 34, y: 40), CGPoint(x: 268, y: 34), CGPoint(x: 40, y: 270), CGPoint(x: 262, y: 268),
        ]
        for (i, s) in spots.enumerated() {
            switch (i + seed) % 3 {
            case 0:
                ctx.circle(s, 5, p.decor)
            case 1:
                var tri = Path()
                tri.move(to: CGPoint(x: s.x, y: s.y - 7))
                tri.addLine(to: CGPoint(x: s.x + 7, y: s.y + 5))
                tri.addLine(to: CGPoint(x: s.x - 7, y: s.y + 5))
                tri.closeSubpath()
                ctx.fill(tri, with: .color(p.cap))
            default:
                var wave = Path()
                wave.move(to: CGPoint(x: s.x - 12, y: s.y))
                wave.addCurve(to: CGPoint(x: s.x + 12, y: s.y),
                              control1: CGPoint(x: s.x - 4, y: s.y - 10),
                              control2: CGPoint(x: s.x + 4, y: s.y + 10))
                ctx.stroke(wave, with: .color(p.decor), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
    }

    /// Apple Watch 本体。角度 angle は腕の向き（0 が真下）。
    func watch(at c: CGPoint, angle: Double, scale: CGFloat = 1, screen: Color, p: HowToPalette, bandWidth: CGFloat = 60) {
        var ctx = self
        ctx.translateBy(x: c.x, y: c.y)
        ctx.rotate(by: .radians(-angle))
        ctx.scaleBy(x: scale, y: scale)
        // バンドは腕に直交する向きに巻く。
        if bandWidth > 0 {
            ctx.roundedRect(center: .zero, size: CGSize(width: bandWidth, height: 30), radius: 10, p.band)
        }
        ctx.roundedRect(center: .zero, size: CGSize(width: 46, height: 54), radius: 13, p.bezel)
        ctx.roundedRect(center: .zero, size: CGSize(width: 42, height: 50), radius: 11, p.watchBody)
        ctx.roundedRect(center: .zero, size: CGSize(width: 32, height: 40), radius: 8, screen)
    }
}

// MARK: - 歩く人

struct WalkerPose {
    /// 歩行周期の位相（ラジアン）。2π で2歩。
    var phase: Double
    /// 脚の振り幅（ラジアン）。
    var stride: Double
    var armSwing: Double
    /// 肘の曲げ。速歩では大きく曲げる。
    var elbowBend: Double
    /// 上半身の前傾。
    var lean: Double

    static func slow(phase: Double) -> WalkerPose {
        WalkerPose(phase: phase, stride: 0.32, armSwing: 0.32, elbowBend: 0.3, lean: 0.03)
    }

    static func brisk(phase: Double) -> WalkerPose {
        WalkerPose(phase: phase, stride: 0.55, armSwing: 0.8, elbowBend: 1.45, lean: 0.12)
    }

    /// 2つの姿勢の間を補間する（緩歩→速歩の切り替え用）。
    static func blend(_ a: WalkerPose, _ b: WalkerPose, _ u: Double) -> WalkerPose {
        WalkerPose(
            phase: a.phase,
            stride: Ease.lerp(a.stride, b.stride, u),
            armSwing: Ease.lerp(a.armSwing, b.armSwing, u),
            elbowBend: Ease.lerp(a.elbowBend, b.elbowBend, u),
            lean: Ease.lerp(a.lean, b.lean, u)
        )
    }

    /// 1歩ごとの接地の瞬間に 1、すぐ減衰する値。手首の振動表現に使う。
    var stepPulse: Double {
        let frac = phase.truncatingRemainder(dividingBy: .pi) / .pi
        return max(0, 1 - frac * 3)
    }
}

struct WalkerColors {
    var skin, skinShade, shirt, shirtShade, pants, pantsShade, cap, shoe: Color

    init(_ p: HowToPalette) {
        skin = p.skin; skinShade = p.skinShade
        shirt = p.shirt; shirtShade = p.shirtShade
        pants = p.pants; pantsShade = p.pantsShade
        cap = p.cap; shoe = p.watchBody
    }

    /// 一色のシルエット（ブロックの中の小さな人など）。
    init(mono: Color) {
        skin = mono; skinShade = mono.opacity(0.75)
        shirt = mono; shirtShade = mono.opacity(0.75)
        pants = mono; pantsShade = mono.opacity(0.75)
        cap = mono; shoe = mono
    }
}

enum Walker {
    static let thigh = 40.0, shin = 40.0, torso = 62.0
    static let upperArm = 32.0, forearm = 30.0, headR = 16.0

    struct Result {
        var wrist: CGPoint
        var forearmAngle: Double
    }

    /// 右向きに歩く人を、足元 ground（地面の点）を基準に描く。手前の腕の手首位置を返す。
    @discardableResult
    static func draw(
        _ ctx: GraphicsContext,
        colors c: WalkerColors,
        ground: CGPoint,
        pose: WalkerPose,
        watch: (screen: Color, p: HowToPalette)? = nil
    ) -> Result {
        func leg(_ legPhase: Double) -> (thigh: Double, shin: Double) {
            let th = pose.stride * sin(legPhase)
            let bend = pose.stride * 1.4 * max(0, cos(legPhase))
            return (th, th - bend)
        }
        let near = leg(pose.phase)
        let far = leg(pose.phase + .pi)
        func drop(_ l: (thigh: Double, shin: Double)) -> Double { thigh * cos(l.thigh) + shin * cos(l.shin) }
        let hip = CGPoint(x: ground.x, y: ground.y - max(drop(near), drop(far)) - 6)
        let shoulder = polar(hip, .pi - pose.lean, torso)

        func drawLeg(_ l: (thigh: Double, shin: Double), pants: Color) {
            let knee = polar(hip, l.thigh, thigh)
            let ankle = polar(knee, l.shin, shin)
            ctx.polyline([hip, knee, ankle], pants, width: 17)
            ctx.line(ankle, CGPoint(x: ankle.x + 11, y: ankle.y + 1), c.shoe, width: 12)
        }

        func drawArm(_ upper: Double, skin: Color, sleeve: Color) -> Result {
            let elbow = polar(shoulder, upper, upperArm)
            let fore = upper + pose.elbowBend
            let hand = polar(elbow, fore, forearm)
            ctx.line(shoulder, polar(shoulder, upper, upperArm * 0.55), sleeve, width: 16)
            ctx.polyline([polar(shoulder, upper, upperArm * 0.5), elbow, hand], skin, width: 12)
            ctx.circle(hand, 7.5, skin)
            return Result(wrist: polar(elbow, fore, forearm * 0.72), forearmAngle: fore)
        }

        let swing = pose.armSwing * sin(pose.phase)
        // 奥の腕・奥の脚
        _ = drawArm(swing, skin: c.skinShade, sleeve: c.shirtShade)
        drawLeg(far, pants: c.pantsShade)
        // 胴体・腰
        ctx.line(hip, shoulder, c.shirt, width: 36)
        ctx.circle(hip, 16, c.pants)
        // 手前の脚
        drawLeg(near, pants: c.pants)
        // 頭とキャップ
        let head = polar(shoulder, .pi - pose.lean * 0.5, 30)
        ctx.circle(head, headR, c.skin)
        var capCtx = ctx
        capCtx.clip(to: Path(CGRect(x: head.x - 30, y: head.y - 30, width: 60, height: 27)))
        capCtx.circle(head, headR + 1.5, c.cap)
        ctx.line(CGPoint(x: head.x + 4, y: head.y - 3.5), CGPoint(x: head.x + headR + 9, y: head.y - 3), c.cap, width: 5)
        // 手前の腕と時計
        let result = drawArm(-swing, skin: c.skin, sleeve: c.shirt)
        if let w = watch {
            ctx.watch(at: result.wrist, angle: result.forearmAngle, scale: 0.32, screen: w.screen, p: w.p)
        }
        return result
    }
}
