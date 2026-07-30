import EscaleCore
import SwiftUI

public struct ProFeatureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.escaleCommercialActions) private var commercialActions
    @Environment(\.openURL) private var openURL

    private let feature: EscaleFeature
    @State private var isShowingAllFeatures = false

    public init(feature: EscaleFeature) {
        self.feature = feature
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 15) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(
                        LinearGradient(
                            colors: [Theme.accent, Color(hex: 0x978BFF)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text("ESCALE PRO")
                        .font(.caption.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(Theme.accent)
                    Text(feature.displayName)
                        .font(.title2.weight(.bold))
                }
            }

            Text(feature.upgradeDescription)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("$99")
                    .font(.title.weight(.bold))
                    .foregroundStyle(Theme.accent)
                Text("per year")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    isShowingAllFeatures = true
                } label: {
                    HStack(spacing: 4) {
                        Text("All Pro features")
                            .foregroundStyle(.secondary)
                        Image(systemName: "info.circle")
                            .foregroundStyle(Theme.accent)
                    }
                    .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .help("View everything included with Escale Pro")
            }
            .padding(16)
            .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Label(
                "The Community edition remains fully available for manual workflows.",
                systemImage: "checkmark.circle.fill"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Continue with Community") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                if let commercialActions {
                    Button("Unlock Escale Pro") {
                        dismiss()
                        commercialActions.openLicenceManagement()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        dismiss()
                        openURL(EscaleLinks.officialDownloadPage)
                    } label: {
                        Label("Download Escale Pro", systemImage: "arrow.down.circle.fill")
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(28)
        .frame(width: 500)
        .sheet(isPresented: $isShowingAllFeatures) {
            ProBenefitsSheet()
        }
    }
}

private struct ProBenefit: Identifiable {
    let feature: EscaleFeature
    let icon: String
    let detail: String

    var id: EscaleFeature { feature }
}

private struct ProBenefitsSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let benefits = [
        ProBenefit(
            feature: .bulkTranslations,
            icon: "character.book.closed.fill",
            detail: "Translate fields and release notes across every locale."
        ),
        ProBenefit(
            feature: .draftReviewReplies,
            icon: "sparkles",
            detail: "Draft editable responses to customer reviews with AI."
        ),
        ProBenefit(
            feature: .releaseNoteTemplates,
            icon: "doc.on.doc.fill",
            detail: "Save and reuse What’s New copy across apps and locales."
        ),
        ProBenefit(
            feature: .applyRegionalPricing,
            icon: "globe",
            detail: "Apply reviewed PPP prices directly to both stores."
        ),
        ProBenefit(
            feature: .uploadGooglePlayBundle,
            icon: "shippingbox.fill",
            detail: "Upload Android bundles and create editable draft releases."
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 38, height: 38)
                    .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Everything in Escale Pro")
                        .font(.title3.weight(.bold))
                    Text("Less repetitive work across App Store and Google Play.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("Close")
            }

            VStack(spacing: 0) {
                ForEach(benefits) { benefit in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: benefit.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 28, height: 28)
                            .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(benefit.feature.displayName)
                                .font(.subheadline.weight(.semibold))
                            Text(benefit.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 10)

                    if benefit.id != benefits.last?.id {
                        Divider()
                            .padding(.leading, 40)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}
