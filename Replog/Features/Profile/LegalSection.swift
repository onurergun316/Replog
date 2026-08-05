//
//  LegalSection.swift
//  Replog
//
//  The privacy policy and the terms, reachable without hunting.
//
//  They are also linked from the paywall, which is what App Store review checks. This exists
//  because somebody who has already subscribed should not have to open a purchase screen to
//  re-read what they agreed to.
//

import SwiftUI

struct LegalSection: View {
    @State private var document: LegalDocument?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Legal")
            VStack(spacing: 0) {
                ForEach(Array(LegalDocument.allCases.enumerated()), id: \.element.id) { index, doc in
                    row(doc)
                    if index < LegalDocument.allCases.count - 1 {
                        Divider().padding(.leading, 14)
                    }
                }
            }
            .cardSurface()
        }
        .sheet(item: $document) { doc in
            NavigationStack { LegalDocumentView(document: doc, showsDoneButton: true) }
        }
    }

    private func row(_ doc: LegalDocument) -> some View {
        Button { document = doc } label: {
            HStack(spacing: 12) {
                SettingsRowIcon(systemName: doc.icon)
                Text(doc.title)
                    .font(.rounded(15, .heavy)).foregroundStyle(Color.textPrimary)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Color.text3)
            }
            .padding(14)
        }
        .buttonStyle(.plain)
    }
}
