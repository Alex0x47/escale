import EscaleCore
import SwiftUI

public struct EscaleRootView: View {
    @EnvironmentObject private var store: WorkspaceStore

    public init() {}

    public var body: some View {
        ZStack(alignment: .top) {
            NavigationSplitView {
                SidebarView()
                    .navigationSplitViewColumnWidth(min: 260, ideal: 286, max: 320)
            } detail: {
                MainDetailView()
            }
            .background(Theme.canvas)

            if let toast = store.toast {
                ToastView(toast: toast)
                    .padding(.top, 52)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(5)
            }
        }
        .sheet(isPresented: $store.isOnboardingPresented) {
            OnboardingView()
                .environmentObject(store)
        }
        .tint(Theme.accent)
    }
}

private struct MainDetailView: View {
    @EnvironmentObject private var store: WorkspaceStore

    var body: some View {
        VStack(spacing: 0) {
            if let progress = store.selectedAppRefreshProgress {
                AppRefreshProgressView(progress: progress)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Group {
                if store.selectedApp != nil {
                    switch store.selectedSection {
                    case .overview: OverviewView()
                    case .listing: ListingEditorView()
                    case .screenshots: ScreenshotsView()
                    case .pricing: PricingView()
                    case .reviews: ReviewsView()
                    }
                } else {
                    EmptyState(icon: "square.stack.3d.up.slash", title: "No app selected", message: "Choose a linked app from the sidebar to begin.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.easeInOut(duration: 0.2), value: store.selectedAppRefreshProgress?.fraction)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("Store", selection: $store.platformFilter) {
                    ForEach(PlatformFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 142)

                Button {
                    Task { await store.refreshSelectedApp() }
                } label: {
                    if store.isSelectedAppLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
                .help("Refresh the selected app from its connected stores")
                .disabled(store.isSelectedAppLoading || store.selectedApp == nil)
            }
        }
    }
}

private struct AppRefreshProgressView: View {
    let progress: AppRefreshProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: progress.platform.icon)
                    .foregroundStyle(progress.platform.tint)
                Text(progress.platform.rawValue)
                    .font(.caption.weight(.bold))
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(progress.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(progress.fraction, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress.fraction, total: 1)
                .progressViewStyle(.linear)
                .tint(progress.platform.tint)
                .animation(.easeOut(duration: 0.25), value: progress.fraction)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Refreshing \(progress.platform.rawValue): \(progress.detail)")
        .accessibilityValue(progress.fraction.formatted(.percent.precision(.fractionLength(0))))
    }
}
