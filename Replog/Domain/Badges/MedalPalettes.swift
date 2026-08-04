//
//  MedalPalettes.swift
//  Replog
//
//  The medal colour tokens, as data.
//
//  Curated two and three colour combinations rather than colours picked one badge at a
//  time, which is what stops fifty medals on one grid looking like fifty separate ideas.
//  Each is checked to stay legible on both the warm cream background and the near-black one.
//
//  The hex strings live here, in the domain, so `BadgeCatalog` can be validated without
//  SwiftUI: a badge naming a palette that does not exist would otherwise fall back to a
//  default colour silently. `MedalPalette` in the DesignSystem turns these into `Color`s.
//
//  Order within a triple is fixed: plate, device, highlight.
//

import Foundation

nonisolated enum MedalPalettes {

    /// Palette id to (plate, device, highlight) hex.
    static let hex: [String: (body: String, accent: String, detail: String)] = [
        // Bronze and copper — entry tiers.
        "bronzeForged":  ("#A97142", "#6E3A06", "#B08D57"),
        "bronzeOlympic": ("#A77044", "#824A02", "#C89A6A"),
        "bronzePlate":   ("#BD9566", "#937453", "#E4CBA8"),
        "bronzeMatte":   ("#A87143", "#7F4A00", "#905921"),
        "copperBrass":   ("#CD6E53", "#B6A644", "#F0C9A0"),
        // Steel and silver — the middle.
        "steelBrushed":  ("#6F767E", "#353736", "#AEB1B0"),
        "steelChrome":   ("#4B505A", "#B0C4DE", "#D1E1F6"),
        "silverNavy":    ("#A8A9AC", "#000063", "#E3E4E6"),
        "steelBlue":     ("#4682B4", "#606B73", "#CBD1D4"),
        // Gold and brass — the high tiers.
        "goldMetallic":  ("#C18700", "#8A5A00", "#EABF14"),
        "goldOlympic":   ("#D6AF36", "#824A02", "#F2D98A"),
        "goldAntique":   ("#AF9500", "#6A3805", "#C9B037"),
        "brassGradient": ("#B4A642", "#7A5310", "#D8CB7A"),
        "brassBronze":   ("#B49900", "#854D00", "#D7B137"),
        // Jewels.
        "emerald":       ("#1B842C", "#046306", "#4FC879"),
        "sapphire":      ("#0067A5", "#001C3D", "#30BFBF"),
        "rubyDeep":      ("#A31116", "#5A0E12", "#D9575C"),
        "rubyGold":      ("#9A0D1B", "#C18834", "#E7B36A"),
        "rubyRose":      ("#980D4B", "#C18834", "#BB2052"),
        "jade":          ("#085650", "#043330", "#77D5CA"),
        "tealDeep":      ("#005660", "#003238", "#57C3AD"),
        // Elite.
        "gunmetal":      ("#5B676D", "#1F262A", "#AAA9AD"),
        "obsidian":      ("#3E4A57", "#1A2029", "#E6E0E6"),
        "violetDeep":    ("#6A359C", "#3A1B57", "#B589D6"),
        "amethyst":      ("#5A46A7", "#361D61", "#AEAAF6"),
    ]

    /// Used when a palette id is unknown, so a medal is never invisible.
    static let fallback = (body: "#A97142", accent: "#6E3A06", detail: "#B08D57")

    static func triple(_ id: String) -> (body: String, accent: String, detail: String) {
        hex[id] ?? fallback
    }

    static var ids: Set<String> { Set(hex.keys) }
}
