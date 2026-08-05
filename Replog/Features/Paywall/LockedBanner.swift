//
//  LockedBanner.swift
//  Replog
//
//  Says why a screen has gone quiet.
//
//  A locked athlete can still open their plans and read them; what they cannot do is change
//  them. Without a line of explanation that reads as the app being broken — controls that do
//  nothing, a keyboard that will not come up — which is a support email rather than a sale.
//
//  Deliberately small and calm. It is a statement of fact with a way out, not a second paywall.
//

import SwiftUI

struct LockedBanner: View {
    var message: String = "Read-only. Subscribe to make changes."
    let onUnlock: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 13, weight: .bold)).foregroundStyle(Color.accent)
            Text(message)
                .font(.rounded(13, .semibold)).foregroundStyle(Color.text2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Unlock", action: onUnlock)
                .font(.rounded(13, .heavy)).foregroundStyle(Color.accent)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
            .fill(Color.accentSoft))
        .accessibilityElement(children: .combine)
    }
}
