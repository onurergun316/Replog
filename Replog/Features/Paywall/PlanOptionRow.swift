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
                // Guideline 3.1.2(c): the charge is the loudest thing in the row — largest,
                // heaviest, full contrast — and every other figure is subordinate to it in size
                // and sits below or beside it, never above. The per-month division draws at 12pt
                // in text3; the savings pill is smaller still. Ranking these by eye is what got
                // 1.0 rejected, so the order is written down.
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(offer.term.displayName)
                            .font(.rounded(15, .heavy)).foregroundStyle(Color.textPrimary)
                        if let badge = offer.savingsBadge {
                            Pill(text: badge, style: .accent)
                        }
                    }
                    Text(offer.price)
                        .font(.rounded(20, .heavy)).foregroundStyle(Color.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    if let perMonth = offer.perMonthEquivalent {
                        Text(perMonth)
                            .font(.rounded(12, .semibold)).foregroundStyle(Color.text3)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
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
        .accessibilityLabel(
            "\(offer.term.displayName), \(offer.spokenPrice)"
            + (offer.savingsBadge.map { ", \($0)" } ?? "")
        )
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
