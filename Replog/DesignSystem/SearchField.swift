//
//  SearchField.swift
//  Replog
//
//  The app's one search field. Extracted from the Library so every list that grows past
//  a screenful looks and behaves identically — scrolling to find a movement is never
//  the answer.
//

import SwiftUI

struct SearchField: View {
    var placeholder: String = "Search"
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Color.text3)
            TextField(placeholder, text: $text)
                .font(.bodyText).textInputAutocapitalization(.never).autocorrectionDisabled()
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.text3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.surface2))
    }
}

/// A horizontally scrolling row of single-select filter chips.
struct FilterChipRow<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value?
    var allLabel: String = "All"

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(label: allLabel, isSelected: selection == nil) { selection = nil }
                ForEach(options, id: \.value) { option in
                    chip(label: option.label, isSelected: selection == option.value) {
                        // Tapping the active chip clears it — no need to hunt for "All".
                        selection = selection == option.value ? nil : option.value
                    }
                }
            }
            .padding(.horizontal, 1)   // keeps the selected chip's ring from clipping
        }
        .scrollClipDisabled()
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func chip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.rounded(12, .heavy))
                .foregroundStyle(isSelected ? .white : Color.textPrimary)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(isSelected ? Color.accent : Color.surface2))
        }
        .buttonStyle(.plain)
    }
}
