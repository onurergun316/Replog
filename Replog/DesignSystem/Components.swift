//
//  Components.swift
//  Replog
//
//  Small reusable UI building blocks shared across screens, styled per the tokens.
//

import SwiftUI

// MARK: - Pills & chips

/// A rounded pill label. Variants cover muscle chips, tags, and day chips.
struct Pill: View {
    enum Style { case soft, accent, accentSoft, outline }
    let text: String
    var style: Style = .soft

    var body: some View {
        Text(text)
            .font(.rounded(12, .heavy))
            .foregroundStyle(fg)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(bg))
            .overlay(Capsule().strokeBorder(Color.border, lineWidth: style == .outline ? 1 : 0))
    }

    private var fg: Color {
        switch style {
        case .soft: return .text2
        case .accent: return .white
        case .accentSoft: return .accent
        case .outline: return .text2
        }
    }
    private var bg: Color {
        switch style {
        case .soft: return .surface2
        case .accent: return .accent
        case .accentSoft: return .accentSoft
        case .outline: return .clear
        }
    }
}

/// A colored difficulty badge (Library rows / detail tag grid).
struct LevelBadge: View {
    let level: Level
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(level.displayName)
                .font(.rounded(11, .bold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.12)))
    }
    private var color: Color {
        switch level {
        case .beginner: return .up
        case .intermediate: return .accent
        case .expert: return .down
        }
    }
}

// MARK: - Trend arrow (finance-style)

/// Direction of a logged value vs the same set last session.
enum Trend: Equatable {
    case up, down, flat, none

    var symbol: String {
        switch self {
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        case .flat: return "arrow.right"
        case .none: return ""
        }
    }
    var color: Color {
        switch self {
        case .up: return .up
        case .down: return .down
        case .flat: return .text3
        case .none: return .clear
        }
    }
}

/// A tiny up/down/flat arrow shown next to weight & reps when logging.
struct TrendArrow: View {
    let trend: Trend
    var body: some View {
        if trend != .none {
            Image(systemName: trend.symbol)
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(trend.color)
        }
    }
}

// MARK: - Stepper

/// A −/+ stepper for weight or reps, with a centered tabular value.
struct StepperControl: View {
    let value: String
    let onMinus: () -> Void
    let onPlus: () -> Void

    @State private var taps = 0

    var body: some View {
        HStack(spacing: 8) {
            stepButton("minus", action: onMinus)
            Text(value)
                .font(.rounded(17, .heavy))
                .tabularNumbers()
                .foregroundStyle(Color.textPrimary)
                .frame(minWidth: 44)
                .contentTransition(.numericText())
            stepButton("plus", action: onPlus)
        }
        .sensoryFeedback(.selection, trigger: taps)
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button { taps += 1; action() } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(Color.text2)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.surface2))
        }
        .buttonStyle(.plain)
    }
}

/// A −/+ stepper whose centre value is also directly typeable. The field mirrors the
/// external `display` value except while focused; on submit/blur it parses the typed
/// text via `onCommit`. Used for weight/reps entry so users can type or tap.
struct NumericStepperField: View {
    let display: String
    var keyboard: UIKeyboardType = .numberPad
    let onMinus: () -> Void
    let onPlus: () -> Void
    let onCommit: (String) -> Void

    @State private var draft = ""
    @State private var taps = 0
    @State private var selection: TextSelection?
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            stepButton("minus", action: onMinus)
            TextField("", text: $draft, selection: $selection)
                .keyboardType(keyboard)
                .multilineTextAlignment(.center)
                .font(.rounded(17, .heavy)).tabularNumbers()
                .foregroundStyle(Color.textPrimary)
                .frame(minWidth: 52)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit { commit() }
                .onAppear { draft = display }
                // Drop the selection before replacing the text from outside: TextSelection
                // holds String.Index values into the CURRENT string, and applying a stale
                // one against new text is an out-of-bounds trap.
                .onChange(of: display) { _, new in
                    if !focused { selection = nil; draft = new }
                }
                .onChange(of: focused) { _, isFocused in
                    if isFocused {
                        // Wherever the tap landed, the caret belongs after the number so a
                        // backspace immediately eats the last digit. Deferred one runloop
                        // so it wins over UIKit's tap-position placement.
                        Task { @MainActor in
                            selection = TextSelection(insertionPoint: draft.endIndex)
                        }
                    } else {
                        commit()
                    }
                }
                .toolbar {
                    // Number/decimal pads have no return key — give focus a way out.
                    if focused {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") { focused = false }
                                .font(.rounded(15, .heavy)).foregroundStyle(Color.accent)
                        }
                    }
                }
            stepButton("plus", action: onPlus)
        }
        .sensoryFeedback(.selection, trigger: taps)
    }

    private func commit() {
        selection = nil // about to replace the text — a stale index must never outlive it
        onCommit(draft)
        // Re-sync to canonical formatting (parent may clamp/round the value).
        draft = display
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button { taps += 1; action() } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(Color.text2)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.surface2))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Buttons

/// The primary accent CTA used across the app.
struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var filled: Bool = true
    let action: () -> Void

    @State private var taps = 0

    var body: some View {
        Button { taps += 1; action() } label: {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.rounded(16, .heavy))
            .foregroundStyle(filled ? Color.white : Color.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(filled ? Color.accent : Color.accentSoft)
            )
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .medium), trigger: taps)
    }
}

// MARK: - Segmented toggle (Guide | Progress)

struct SegmentedToggle<T: Hashable>: View {
    let options: [(value: T, label: String)]
    @Binding var selection: T

    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { opt in
                Button { withAnimation(.snappy) { selection = opt.value } } label: {
                    Text(opt.label)
                        .font(.rounded(14, .heavy))
                        .foregroundStyle(selection == opt.value ? Color.white : Color.text2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background {
                            if selection == opt.value {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.accent)
                                    .matchedGeometryEffect(id: "seg", in: ns)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.surface2))
        .sensoryFeedback(.selection, trigger: selection)
    }
}

// MARK: - Section eyebrow header

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title).eyebrow().frame(maxWidth: .infinity, alignment: .leading)
    }
}
