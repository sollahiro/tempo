import SwiftUI

/// 使い方アニメーションの配色。コーポレート・メンフィス風に、平面的で強い色を使う。
/// 緩歩は青、速歩はオレンジ（ラフの色分けのまま）。
struct HowToPalette {
    let background: Color
    let blobA: Color
    let blobB: Color
    let decor: Color
    let skin: Color
    let skinShade: Color
    let shirt: Color
    let shirtShade: Color
    let pants: Color
    let pantsShade: Color
    let cap: Color
    let band: Color
    let watchBody: Color
    let bezel: Color
    let screenOff: Color
    let ground: Color
    let slow: Color
    let brisk: Color

    init(_ scheme: ColorScheme) {
        if scheme == .dark {
            background = Color(hex: 0x1C1A29)
            blobA = Color(hex: 0x3E2A44)
            blobB = Color(hex: 0x1F3B36)
            decor = Color(hex: 0x9D91FF)
            skin = Color(hex: 0x9C8DF5)
            skinShade = Color(hex: 0x7F6EE0)
            shirt = Color(hex: 0xFFC93C)
            shirtShade = Color(hex: 0xDDA81C)
            pants = Color(hex: 0x4A5A9A)
            pantsShade = Color(hex: 0x3A487F)
            cap = Color(hex: 0xFF6B8B)
            band = Color(hex: 0xFF6B8B)
            watchBody = Color(hex: 0x0E0C17)
            bezel = Color(hex: 0x5A5478)
            screenOff = Color(hex: 0x2A2640)
            ground = Color(hex: 0xCFC8F0)
            slow = Color(hex: 0x4DA3FF)
            brisk = Color(hex: 0xFF9A3D)
        } else {
            background = Color(hex: 0xFFF5EA)
            blobA = Color(hex: 0xFFD6E0)
            blobB = Color(hex: 0xCDEFE3)
            decor = Color(hex: 0x6C5CE7)
            skin = Color(hex: 0x8C7BF0)
            skinShade = Color(hex: 0x7462DA)
            shirt = Color(hex: 0xFFC93C)
            shirtShade = Color(hex: 0xE9B020)
            pants = Color(hex: 0x23305E)
            pantsShade = Color(hex: 0x1A2448)
            cap = Color(hex: 0xFF6B8B)
            band = Color(hex: 0xFF6B8B)
            watchBody = Color(hex: 0x221D3A)
            bezel = Color(hex: 0x221D3A)
            screenOff = Color(hex: 0x3A3458)
            ground = Color(hex: 0x221D3A)
            slow = Color(hex: 0x2D8CFF)
            brisk = Color(hex: 0xFF8A1F)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
