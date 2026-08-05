//
//  CoachReportView.swift
//  Replog
//
//  Renders a saved AI coach report (markdown) into a premium, readable card layout.
//  Lightweight line-based rendering: # / ## headings, "- " bullets, "> " callout, and
//  paragraphs. Used from the onboarding result screen and the Profile tab.
//
//  The eyebrow is a parameter rather than a constant because the renderer outlived its
//  original job: the legal documents go through it too, and stamping "Your AI Coach" on a
//  privacy policy would be both wrong and, given what the policy says about on-device
//  processing, faintly absurd.
//

import SwiftUI

struct CoachReportView: View {
    let title: String
    let markdown: String
    var showsDoneButton: Bool = false
    /// The small uppercase label above the content, and its SF Symbol.
    var eyebrow: String = "Your AI Coach"
    var eyebrowIcon: String = "sparkles"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: eyebrowIcon).foregroundStyle(Color.accent)
                    Text(eyebrow).eyebrow()
                }
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    block.view
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(Color.bg.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.rounded(15, .heavy)).foregroundStyle(Color.accent)
                }
            }
        }
    }

    // MARK: - Lightweight markdown blocks

    private struct Block: Identifiable {
        let id = UUID()
        let view: AnyView
    }

    private var blocks: [Block] {
        markdown
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { line in Block(view: AnyView(render(line))) }
    }

    @ViewBuilder
    private func render(_ line: String) -> some View {
        if line.hasPrefix("## ") {
            Text(line.dropFirst(3))
                .font(.rounded(18, .black)).foregroundStyle(Color.textPrimary)
                .padding(.top, 6)
        } else if line.hasPrefix("# ") {
            Text(line.dropFirst(2))
                .font(.screenTitle).foregroundStyle(Color.textPrimary)
        } else if line.hasPrefix("- ") {
            HStack(alignment: .top, spacing: 8) {
                Circle().fill(Color.accent).frame(width: 6, height: 6).padding(.top, 7)
                Text(inline(String(line.dropFirst(2))))
                    .font(.bodyText).foregroundStyle(Color.text2)
            }
        } else if line.hasPrefix("> ") {
            Text(inline(String(line.dropFirst(2))))
                .font(.rounded(15, .heavy)).foregroundStyle(Color.accent)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Color.accentSoft))
        } else {
            Text(inline(line))
                .font(.bodyText).foregroundStyle(Color.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Parses inline markdown (bold/italic) into an AttributedString, falling back to plain.
    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s)) ?? AttributedString(s)
    }
}
