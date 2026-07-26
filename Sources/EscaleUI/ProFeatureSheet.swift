import EscaleCore
import SwiftUI

public struct ProFeatureSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let feature: EscaleFeature

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
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .frame(width: 500)
    }
}
