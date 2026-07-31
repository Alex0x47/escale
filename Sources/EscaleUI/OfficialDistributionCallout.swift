import SwiftUI

/// A marketing-only link to workflows shipped in the official distribution.
///
/// Keep this view informational: Community must not use it as an entitlement
/// gate or attach commercial operations to it.
struct OfficialDistributionCallout: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Theme.accent)
                Text("ESCALE PRO · OFFICIAL DISTRIBUTION")
                    .font(.caption2.weight(.bold))
                    .tracking(0.65)
                    .foregroundStyle(Theme.accent)
            }

            Text(title)
                .font(.subheadline.weight(.semibold))

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Link(destination: EscaleLinks.officialDownloadPage) {
                Label("Download the official app", systemImage: "arrow.down.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(Theme.accent)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Theme.accent.opacity(0.11), Theme.accent.opacity(0.045)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Theme.accent.opacity(0.2))
        )
    }
}
