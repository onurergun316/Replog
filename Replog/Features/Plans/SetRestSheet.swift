//
//  SetRestSheet.swift
//  Replog
//
//  Bulk "set rest for all exercises / whole plan" — a +/- (and typeable) counter that
//  matches Profile's Rest duration control, instead of a preset dropdown.
//

import SwiftUI

struct SetRestSheet: View {
    let title: String
    let initialSeconds: Int
    /// `nil` = use the app default for every exercise.
    let onApply: (Int?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var seconds: Int

    init(title: String, initialSeconds: Int, onApply: @escaping (Int?) -> Void) {
        self.title = title
        self.initialSeconds = max(5, initialSeconds)
        self.onApply = onApply
        _seconds = State(initialValue: max(5, initialSeconds))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Sets the rest between sets for every exercise here. Overrides each exercise's own rest.")
                    .font(.rounded(13, .semibold)).foregroundStyle(Color.text3)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(Color.accent)
                        .frame(width: 36, height: 36)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.accentSoft))
                    Text("Rest duration").font(.rounded(15, .heavy)).foregroundStyle(Color.textPrimary)
                    Spacer()
                    NumericStepperField(display: "\(seconds)", keyboard: .numberPad,
                                        onMinus: { seconds = max(5, seconds - 15) },
                                        onPlus: { seconds = min(600, seconds + 15) },
                                        onCommit: { if let v = Int($0.filter(\.isNumber)) { seconds = min(600, max(5, v)) } })
                    Text("sec").font(.rounded(11, .bold)).foregroundStyle(Color.text3)
                }
                .padding(14)
                .cardSurface()

                PrimaryButton(title: "Apply to all") { onApply(seconds); dismiss() }
                Button("Use app default") { onApply(nil); dismiss() }
                    .font(.rounded(14, .heavy)).foregroundStyle(Color.text2)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }
            .padding(20)
            .background(Color.bg.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .hideKeyboardOnTap()
        }
        .presentationDetents([.height(340)])
        .presentationDragIndicator(.visible)
    }
}
