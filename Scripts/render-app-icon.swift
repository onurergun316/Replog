#!/usr/bin/env swift
//
//  render-app-icon.swift
//  Dev tool: renders the app icon from the onboarding logo's exact recipe — the
//  accent→accentPress gradient with a white dumbbell.fill at the same 30/72 glyph
//  proportion (Theme.swift hexes, OnboardingFlow.welcomeStep). Emits the three
//  1024×1024 PNGs (light / dark / tinted) into Assets.xcassets/AppIcon.appiconset.
//
//  Run from the repo root:  swift Scripts/render-app-icon.swift
//

import SwiftUI
import AppKit

extension Color {
    init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex.hasPrefix("#") ? String(hex.dropFirst()) : hex).scanHexInt64(&v)
        self.init(.sRGB, red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255, opacity: 1)
    }
}

struct IconView: View {
    let background: AnyShapeStyle
    let glyph: AnyShapeStyle

    var body: some View {
        ZStack {
            Rectangle().fill(background)
            // The onboarding logo: dumbbell.fill at 30 pt in a 72 pt tile → 30/72 of 1024.
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 1024.0 * 30.0 / 72.0))
                .foregroundStyle(glyph)
        }
        .frame(width: 1024, height: 1024)
    }
}

@MainActor
func render(_ view: IconView, to filename: String) {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1
    guard let cg = renderer.cgImage else { fatalError("render failed for \(filename)") }
    let rep = NSBitmapImageRep(cgImage: cg)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("png encode failed for \(filename)")
    }
    let dir = FileManager.default.currentDirectoryPath
        + "/Replog/Assets.xcassets/AppIcon.appiconset/"
    let path = dir + filename
    do { try data.write(to: URL(fileURLWithPath: path)) } catch { fatalError("\(error)") }
    print("wrote \(path) (\(cg.width)×\(cg.height))")
}

let accentLight = Color(hex: "#FF6A3D"), accentPressLight = Color(hex: "#E85320")
let accentDark = Color(hex: "#FF7A4D"), accentPressDark = Color(hex: "#E0673A")
let bgDark = Color(hex: "#16120E")

// Light: the logo verbatim — brand gradient, white glyph.
await render(IconView(
    background: AnyShapeStyle(LinearGradient(colors: [accentLight, accentPressLight],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)),
    glyph: AnyShapeStyle(.white)
), to: "icon-light.png")

// Dark: the app's dark warm background with the dark-mode accent gradient on the glyph.
await render(IconView(
    background: AnyShapeStyle(bgDark),
    glyph: AnyShapeStyle(LinearGradient(colors: [accentDark, accentPressDark],
                                        startPoint: .topLeading, endPoint: .bottomTrailing))
), to: "icon-dark.png")

// Tinted: grayscale as Apple requires — the system supplies the tint.
await render(IconView(
    background: AnyShapeStyle(.black),
    glyph: AnyShapeStyle(.white)
), to: "icon-tinted.png")
