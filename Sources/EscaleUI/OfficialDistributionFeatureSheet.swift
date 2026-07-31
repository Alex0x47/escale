import SwiftUI

/// Describes official-distribution workflows without exposing their
/// implementations, entitlement state, or executable hooks to Community.
enum OfficialDistributionFeature: String, Identifiable {
    case bulkTranslations
    case releaseNoteTemplates
    case applyRegionalPricing
    case draftReviewReplies
    case uploadGooglePlayBundle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bulkTranslations:
            "Translate every locale at once"
        case .releaseNoteTemplates:
            "Reuse What’s New templates"
        case .applyRegionalPricing:
            "Apply regional pricing"
        case .draftReviewReplies:
            "Draft review replies with AI"
        case .uploadGooglePlayBundle:
            "Create an Android version"
        }
    }

    var detail: String {
        switch self {
        case .bulkTranslations:
            "Translate listing fields and release notes from the primary locale into every other locale in one operation."
        case .releaseNoteTemplates:
            "Save, manage, and reuse release-note copy across apps, stores, and locales."
        case .applyRegionalPricing:
            "Apply the regional prices you reviewed directly to App Store Connect and Google Play."
        case .draftReviewReplies:
            "Generate an editable response from the customer’s review, then approve it before publishing."
        case .uploadGooglePlayBundle:
            "Upload a signed Android App Bundle and create an editable Google Play draft release without submitting it for review."
        }
    }

    var icon: String {
        switch self {
        case .bulkTranslations: "character.book.closed.fill"
        case .releaseNoteTemplates: "doc.on.doc.fill"
        case .applyRegionalPricing: "arrow.up.circle.fill"
        case .draftReviewReplies: "sparkles"
        case .uploadGooglePlayBundle: "shippingbox.fill"
        }
    }
}

struct OfficialDistributionFeatureSheet: View {
    @Environment(\.dismiss) private var dismiss
    let feature: OfficialDistributionFeature

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: feature.icon)
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 54, height: 54)
                    .background(Theme.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 15, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text("ESCALE PRO")
                        .font(.caption2.weight(.bold))
                        .tracking(0.75)
                        .foregroundStyle(Theme.accent)
                    Text(feature.title)
                        .font(.title2.weight(.bold))
                }
            }

            Text("This feature is available in Escale Pro.")
                .font(.headline)

            Text(feature.detail)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Label("Official Developer ID-signed app", systemImage: "checkmark.seal.fill")
                Label("Automatic updates and maintained workflows", systemImage: "arrow.triangle.2.circlepath")
                Label("Licence management and support", systemImage: "person.crop.circle.badge.checkmark")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Text("The Community source intentionally does not contain the Pro implementation. Download the official app to use this workflow.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Continue with Community") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Link(destination: EscaleLinks.officialDownloadPage) {
                    Label("Download Escale Pro", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Theme.accent)
            }
        }
        .padding(26)
        .frame(width: 520)
    }
}
