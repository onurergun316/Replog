//
//  PlanOptionRow.swift
//  Replog
//
//  One selectable plan on the paywall.
//
//  Geometry is `OptionCard`'s — same 2pt accent border when selected, same 24pt check circle,
//  same corner radius — because the athlete has already learned that shape choosing their goal
//  and their equipment during onboarding. A paywall that invents its own selection idiom reads
//  as a screen bolted on from somewhere else, which is exactly what a paywall must not read as.
//
//  Two differences earn themselves: the radio sits on the LEADING edge, because the eye should
//  land on the choice before the price, and the savings badge is a `Pill`, which is already how
//  this app labels a small piece of emphasis.
//

import SwiftUI

struct PlanOptionRow: View {
    let offer: PlanOffer
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                radio
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(offer.term.displayName)
                            .font(.rounded(17, .heavy)).foregroundStyle(Color.textPrimary)
                        if let badge = offer.savingsBadge {
                            Pill(text: badge, style: .accent)
                        }
                    }
                    Text(offer.priceLine)
                        .font(.rounded(13, .semibold)).foregroundStyle(Color.text2)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(isSelected ? Color.accentSoft : Color.surface2))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(isSelected ? Color.accent : Color.border,
                                  lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var radio: some View {
        ZStack {
            Circle().strokeBorder(isSelected ? Color.accent : Color.border, lineWidth: 2)
                .background(Circle().fill(isSelected ? Color.accent : Color.clear))
                .frame(width: 24, height: 24)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .black)).foregroundStyle(.white)
            }
        }
    }
}
