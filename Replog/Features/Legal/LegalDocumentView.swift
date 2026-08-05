//
//  LegalDocumentView.swift
//  Replog
//
//  The privacy policy and the terms, read inside the app.
//
//  They ship as bundled markdown rather than as links to a website, for the same reason the
//  rest of the app has no network code: an athlete in a basement gym with no signal can still
//  read what they agreed to. It also means the text can never silently drift from the version
//  the build was reviewed against.
//
//  Rendering is `CoachReportView`'s, which already handles the headings, bullets and inline
//  emphasis these documents use.
//
//  App Store Connect separately requires a HOSTED privacy policy URL. In-app text does not
//  satisfy that — the copy in `Resources/Legal/privacy-policy.md` is what should be published
//  there, so the two never disagree.
//

import SwiftUI

/// A bundled legal document.
enum LegalDocument: String, Identifiable, CaseIterable {
    case privacyPolicy = "privacy-policy"
    case termsOfUse = "terms-of-use"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privacyPolicy: return "Privacy Policy"
        case .termsOfUse:    return "Terms of Use"
        }
    }

    var icon: String {
        switch self {
        case .privacyPolicy: return "hand.raised.fill"
        case .termsOfUse:    return "doc.text.fill"
        }
    }

    /// The document text, or a short honest placeholder if the resource is missing.
    ///
    /// Failing soft matters more here than elsewhere: a build that somehow shipped without the
    /// file should still show the athlete something and a way to reach us, rather than an
    /// empty screen where their rights ought to be.
    func markdown(bundle: Bundle = .main) -> String {
        guard let url = bundle.url(forResource: rawValue, withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return """
            # \(title)

            This document could not be loaded. Please contact support and we will send it to you.
            """
        }
        return text
    }
}

struct LegalDocumentView: View {
    let document: LegalDocument
    var showsDoneButton: Bool = false

    var body: some View {
        CoachReportView(title: document.title,
                        markdown: document.markdown(),
                        showsDoneButton: showsDoneButton,
                        eyebrow: "Legal",
                        eyebrowIcon: document.icon)
    }
}
