//
//  Theme.swift
//  Replog
//
//  Design tokens from the spec, expressed as dynamic light/dark colors so SwiftUI
//  resolves them automatically per color scheme. (No asset catalog needed.)
//

import SwiftUI

extension Color {
    /// Builds a `Color` from a 6-digit hex string ("#RRGGBB" or "RRGGBB").
    init(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >> 8) & 0xFF) / 255
        let b = Double(v & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    /// A dynamic color that switches between light and dark values.
    init(light: String, dark: String) {
        self.init(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
    }
}

// MARK: - Tokens (named per the design system in README §3)

extension Color {
    static let bg          = Color(light: "#FBF7F2", dark: "#16120E")
    static let surface     = Color(light: "#FFFFFF", dark: "#211B15")
    static let surface2    = Color(light: "#F6EFE6", dark: "#2C241D")
    static let textPrimary = Color(light: "#2A2320", dark: "#F6EFE7")
    static let text2       = Color(light: "#8B7E72", dark: "#A99C8E")
    static let text3       = Color(light: "#B9AEA2", dark: "#6E635A")
    static let border      = Color(light: "#EFE6D9", dark: "#332A21")
    static let accent      = Color(light: "#FF6A3D", dark: "#FF7A4D")
    static let accentPress = Color(light: "#E85320", dark: "#E0673A")
    static let accentSoft  = Color(light: "#FFEAE0", dark: "#3A2417")
    static let up          = Color(light: "#2FA779", dark: "#43C08D")
    static let down        = Color(light: "#E5573F", dark: "#F0735A")
    static let track       = Color(light: "#EFE6DD", dark: "#332A21")
}

// MARK: - Shape & shadow tokens

enum Radius {
    static let card: CGFloat = 22
    static let cardLarge: CGFloat = 26
    static let chip: CGFloat = 11
    static let sheet: CGFloat = 28
    static let pill: CGFloat = 999
}

extension View {
    /// Standard card surface: rounded, bordered, subtle shadow.
    func cardSurface(radius: CGFloat = Radius.card, fill: Color = .surface) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.border, lineWidth: 1)
            )
            .shadow(color: Color(hex: "#261C14").opacity(0.05), radius: 11, x: 0, y: 3)
    }
}
