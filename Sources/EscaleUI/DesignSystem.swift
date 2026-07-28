import EscaleCore
import SwiftUI

enum Theme {
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let sidebar = Color(nsColor: .controlBackgroundColor).opacity(0.78)
    static let card = Color(nsColor: .textBackgroundColor)
    static let border = Color.primary.opacity(0.09)
    static let muted = Color.secondary.opacity(0.72)
    static let accent = Color(hex: 0x6B5CE7)
}

struct AppMark: View {
    let app: UnifiedApp
    var size: CGFloat = 48

    private var iconURL: URL? {
        (app.appStoreApp?.iconURL ?? app.playStoreApp?.iconURL).flatMap(URL.init(string:))
    }

    var body: some View {
        Group {
            if let iconURL {
                AsyncImage(url: iconURL, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: size, height: size)
                            .clipped()
                    } else {
                        fallbackMark
                    }
                }
            } else {
                fallbackMark
            }
        }
        .frame(width: size, height: size)
        .fixedSize()
        .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
        .accessibilityHidden(true)
    }

    private var fallbackMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [app.tint.opacity(0.95), app.tint.opacity(0.62)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .fill(.white.opacity(0.13))
                .frame(width: size * 0.8)
                .offset(x: -size * 0.2, y: -size * 0.25)
            Image(systemName: app.symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

struct PlatformBadge: View {
    let platform: StorePlatform
    var showsName = true

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: platform.icon)
                .font(.system(size: 11, weight: .semibold))
            if showsName {
                Text(platform.shortName)
                    .font(.caption.weight(.semibold))
            }
        }
        .foregroundStyle(platform.tint)
        .padding(.horizontal, showsName ? 9 : 7)
        .padding(.vertical, 5)
        .background(platform.tint.opacity(0.1), in: Capsule())
    }
}

struct StatusPill: View {
    let state: ReleaseState

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(state.color).frame(width: 7, height: 7)
            Text(state.rawValue).font(.caption.weight(.semibold))
        }
        .foregroundStyle(state.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(state.color.opacity(0.1), in: Capsule())
    }
}

struct SectionTitle: View {
    let eyebrow: String?
    let title: String
    let subtitle: String

    init(_ title: String, subtitle: String, eyebrow: String? = nil) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.accent)
            }
            Text(title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 64, height: 64)
                .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(40)
    }
}

struct ToastView: View {
    let toast: ToastMessage

    var body: some View {
        HStack(spacing: 12) {
            Group {
                switch toast.kind {
                case .success:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .progress:
                    ProgressView().controlSize(.small)
                case .neutral:
                    Image(systemName: "info.circle.fill").foregroundStyle(Theme.accent)
                case .error:
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
            }
            .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title).font(.subheadline.weight(.semibold))
                Text(toast.detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border))
        .shadow(color: .black.opacity(0.14), radius: 20, y: 8)
    }
}

private struct EscaleToastOverlayModifier: ViewModifier {
    @EnvironmentObject private var store: WorkspaceStore
    let topPadding: CGFloat

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let toast = store.toast {
                ToastView(toast: toast)
                    .padding(.horizontal, 20)
                    .padding(.top, topPadding)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(100)
                    .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    func escaleToastOverlay(topPadding: CGFloat = 16) -> some View {
        modifier(EscaleToastOverlayModifier(topPadding: topPadding))
    }
}

struct MetricCard: View {
    let icon: String
    let label: String
    let value: String
    let detail: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 32, height: 32)
                    .background(color.opacity(0.11), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(value).font(.system(size: 25, weight: .bold, design: .rounded))
                Text(label).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(17)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border))
    }
}

extension View {
    func cardStyle(cornerRadius: CGFloat = 16) -> some View {
        self
            .background(Theme.card, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(Theme.border))
    }
}
