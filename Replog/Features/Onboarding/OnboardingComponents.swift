//
//  OnboardingComponents.swift
//  Replog
//
//  Shared building blocks for the quiz: selectable option cards and choice chips.
//

import SwiftUI

/// A tappable option card. Selected = 2px accent border + filled check.
struct OptionCard: View {
    let title: String
    var subtitle: String? = nil
    var emoji: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let emoji { Text(emoji).font(.system(size: 22)) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.rounded(16, .heavy)).foregroundStyle(Color.textPrimary)
                    if let subtitle {
                        Text(subtitle).font(.rounded(12, .semibold)).foregroundStyle(Color.text2)
                    }
                }
                Spacer()
                ZStack {
                    Circle().strokeBorder(isSelected ? Color.accent : Color.border, lineWidth: 2)
                        .background(Circle().fill(isSelected ? Color.accent : Color.clear))
                        .frame(width: 24, height: 24)
                    if isSelected {
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .black)).foregroundStyle(.white)
                    }
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.surface))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(isSelected ? Color.accent : Color.border, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

/// A selectable pill chip (used for days/week and similar quick picks).
struct ChoiceChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.rounded(15, .heavy))
                .foregroundStyle(isSelected ? .white : Color.text2)
                .frame(minWidth: 48)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(Capsule().fill(isSelected ? Color.accent : Color.surface2))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

/// A step scaffold: eyebrow + question + content.
struct OnboardingStepScaffold<Content: View>: View {
    let eyebrow: String
    let question: String
    var caption: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow).eyebrow()
            Text(question)
                .font(.rounded(26, .black)).foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .minimumScaleFactor(0.8)
                .lineLimit(2)
            if let caption {
                Text(caption).font(.bodyText).foregroundStyle(Color.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content().padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
