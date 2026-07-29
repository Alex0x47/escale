import EscaleCore
import SwiftUI

public struct OverviewView: View {
    public init() {}

    @EnvironmentObject private var store: WorkspaceStore
    @State private var pairingRequest: AppPairingRequest?
    @State private var newIOSVersionRequest: NewIOSVersionRequest?
    @State private var showingNewAndroidVersion = false

    private var localizationHealth: String {
        guard !store.selectedLocalizations.isEmpty else { return "—" }
        let average = store.selectedLocalizations
            .map { $0.completion(for: store.selectedEditingPlatforms) }
            .reduce(0, +) / Double(store.selectedLocalizations.count)
        return "\(Int((average * 100).rounded()))%"
    }

    private var incompleteLocalizationCount: Int {
        store.selectedLocalizations.filter { $0.completion(for: store.selectedEditingPlatforms) < 1 }.count
    }

    private var averageRating: String {
        guard !store.selectedReviews.isEmpty else { return "—" }
        let average = Double(store.selectedReviews.map(\.rating).reduce(0, +)) / Double(store.selectedReviews.count)
        return average.formatted(.number.precision(.fractionLength(1)))
    }

    private var unansweredReviewCount: Int {
        store.selectedReviews.filter { $0.response == nil }.count
    }

    private var pppMarketCount: Int {
        Set(store.selectedProducts.flatMap { $0.regions.map(\.code) }).count
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if let app = store.selectedApp {
                    header(app)
                    syncState
                    HStack(spacing: 14) {
                        MetricCard(
                            icon: "textformat",
                            label: "Localization health",
                            value: localizationHealth,
                            detail: store.selectedLocalizations.isEmpty
                                ? "No listing data loaded"
                                : "\(incompleteLocalizationCount) of \(store.selectedLocalizations.count) locales need copy",
                            color: Theme.accent
                        )
                        MetricCard(
                            icon: "star.fill",
                            label: "Average review rating",
                            value: averageRating,
                            detail: "\(store.selectedReviews.count) loaded reviews",
                            color: .orange
                        )
                        MetricCard(
                            icon: "bubble.left",
                            label: "Reviews to answer",
                            value: "\(unansweredReviewCount)",
                            detail: "From the connected stores",
                            color: .blue
                        )
                        MetricCard(
                            icon: "globe",
                            label: "PPP-ready products",
                            value: "\(store.selectedProducts.count)",
                            detail: "\(pppMarketCount) configured markets",
                            color: .green
                        )
                    }
                    HStack(alignment: .top, spacing: 16) {
                        releasePanel(app)
                        liveDataPanel
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 1280, alignment: .leading)
        }
        .background(Theme.canvas)
        .navigationTitle(store.selectedApp?.name ?? "Overview")
        .sheet(item: $pairingRequest) { request in
            AppPairingView(appID: request.appID)
                .environmentObject(store)
        }
        .sheet(item: $newIOSVersionRequest) { request in
            NewIOSVersionSheet(initialVersion: request.suggestedVersion)
                .environmentObject(store)
        }
        .sheet(isPresented: $showingNewAndroidVersion) {
            NewAndroidVersionSheet()
                .environmentObject(store)
        }
    }

    @ViewBuilder
    private var syncState: some View {
        if !store.isSelectedAppLoading, let issue = store.selectedAppSyncIssues.first {
            HStack(spacing: 11) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Some live data could not be loaded").font(.subheadline.weight(.semibold))
                    Text(issue).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
                Spacer()
                Button("Retry") { Task { await store.refreshSelectedApp() } }
                    .buttonStyle(.bordered)
            }
            .padding(14)
            .background(.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(.orange.opacity(0.18)))
        }
    }

    private func header(_ app: UnifiedApp) -> some View {
        HStack(spacing: 17) {
            AppMark(app: app, size: 66)
            VStack(alignment: .leading, spacing: 5) {
                Text("PRODUCT WORKSPACE")
                    .font(.caption2.weight(.bold)).tracking(0.9).foregroundStyle(Theme.accent)
                Text(app.name).font(.system(size: 31, weight: .bold, design: .rounded))
                HStack(spacing: 8) {
                    if let bundle = app.appStoreApp?.bundleID ?? app.playStoreApp?.bundleID {
                        Text(bundle).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    Text("·").foregroundStyle(.tertiary)
                    Text("\(app.linkedCount) stores linked").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if app.linkedCount == 1 {
                Button {
                    pairingRequest = AppPairingRequest(appID: app.id)
                } label: {
                    Label("Pair app", systemImage: "link")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .help("Pair this product with its record from the other store")
            }
            if let apple = app.appStoreApp, !apple.hasEditableMetadataVersion {
                Button {
                    newIOSVersionRequest = NewIOSVersionRequest(
                        suggestedVersion: suggestedNextAppStoreVersion(from: apple.version)
                    )
                } label: {
                    Label("New iOS version", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(StorePlatform.appStore.tint)
                .controlSize(.large)
                .help("Create a new editable App Store version")
            }
            if app.playStoreApp != nil {
                Button {
                    showingNewAndroidVersion = true
                } label: {
                    Label("New Android version", systemImage: "shippingbox.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(StorePlatform.playStore.tint)
                .controlSize(.large)
                .help("Upload a signed bundle and create a Google Play draft")
            }
            Button {
                store.selectedSection = .listing
            } label: {
                Label("Edit listing", systemImage: "pencil")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(store.isSelectedAppLoading && store.selectedLocalizations.isEmpty)
        }
    }

    private func releasePanel(_ app: UnifiedApp) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Release status").font(.headline)
                    Text("Latest version returned by each connected store").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("View listing") { store.selectedSection = .listing }
                    .buttonStyle(.plain).foregroundStyle(Theme.accent)
            }
            .padding(18)
            Divider()
            VStack(spacing: 0) {
                if let ios = app.appStoreApp { releaseRow(ios) }
                if app.appStoreApp != nil && app.playStoreApp != nil { Divider().padding(.leading, 64) }
                if let android = app.playStoreApp { releaseRow(android) }
            }
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    private func releaseRow(_ app: StoreApp) -> some View {
        HStack(spacing: 14) {
            Image(systemName: app.platform.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(app.platform.tint)
                .frame(width: 38, height: 38)
                .background(app.platform.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("\(app.platform.shortName) · Version \(app.version)").font(.subheadline.weight(.semibold))
                Text(app.version == "—" ? "Version details have not loaded yet" : "Live status from \(app.platform.rawValue)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            StatusPill(state: app.state)
        }
        .padding(18)
    }

    private var liveDataPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Loaded store data").font(.headline)
                Text(store.selectedAppHasLiveData ? "Current session" : "Waiting for the first refresh")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(18)
            Divider()
            VStack(alignment: .leading, spacing: 17) {
                dataRow(icon: "character.book.closed", color: Theme.accent, title: "Localizations", value: store.selectedLocalizations.count)
                dataRow(icon: "photo.on.rectangle", color: .purple, title: "Screenshots", value: store.selectedScreenshots.count)
                dataRow(icon: "tag", color: .green, title: "Products and subscriptions", value: store.selectedProducts.count)
                dataRow(icon: "bubble.left", color: .blue, title: "Customer reviews", value: store.selectedReviews.count)
            }
            .padding(18)
        }
        .frame(width: 365)
        .cardStyle()
    }

    private func dataRow(icon: String, color: Color, title: String, value: Int) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.caption.weight(.bold)).foregroundStyle(color)
                .frame(width: 26, height: 26).background(color.opacity(0.1), in: Circle())
            Text(title).font(.caption.weight(.semibold))
            Spacer()
            Text("\(value)").font(.caption.weight(.bold).monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}

private struct AndroidAppLinkView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    let appStoreAppID: UUID

    @State private var packageName = ""
    @State private var isFetching = false
    @State private var errorMessage: String?

    private var sourceApp: UnifiedApp? {
        store.workspace.apps.first(where: { $0.id == appStoreAppID })
    }

    private var availableAndroidApps: [UnifiedApp] {
        store.workspace.apps
            .filter { $0.id != appStoreAppID && $0.playStoreApp != nil && $0.appStoreApp == nil }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var isGoogleConnected: Bool {
        store.isDemoMode || store.workspace.connections.contains {
            $0.platform == .playStore && $0.state == .connected
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Link an Android app")
                        .font(.title2.weight(.bold))
                    Text("Pair the Google Play record with this product workspace.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 27, height: 27)
                        .background(Color.primary.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("Close")
                .accessibilityLabel("Close")
            }
            .padding(24)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let sourceApp {
                        HStack(spacing: 13) {
                            AppMark(app: sourceApp, size: 44)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(sourceApp.name).font(.headline)
                                Text(sourceApp.appStoreApp?.bundleID ?? "")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            PlatformBadge(platform: .appStore)
                        }
                        .padding(15)
                        .cardStyle(cornerRadius: 14)
                    }

                    if !availableAndroidApps.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("IMPORTED ANDROID APPS")
                                .font(.caption2.weight(.bold))
                                .tracking(0.8)
                                .foregroundStyle(.secondary)
                            ForEach(availableAndroidApps) { app in
                                HStack(spacing: 12) {
                                    AppMark(app: app, size: 36)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(app.name).font(.subheadline.weight(.semibold))
                                        Text(app.playStoreApp?.bundleID ?? "")
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Link") {
                                        store.link(appStoreApp: appStoreAppID, toPlayStoreApp: app.id)
                                        store.showToast(
                                            "Android app linked",
                                            detail: "\(app.name) is now part of this product workspace.",
                                            kind: .success
                                        )
                                        dismiss()
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(isFetching)
                                }
                                .padding(13)
                                .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 11) {
                        Text(availableAndroidApps.isEmpty ? "ADD FROM GOOGLE PLAY" : "OR ADD ANOTHER PACKAGE")
                            .font(.caption2.weight(.bold))
                            .tracking(0.8)
                            .foregroundStyle(.secondary)
                        Text("Google’s API cannot list every app in an account. Enter the exact package name and Escale will verify access, fetch its live data, and link it here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 10) {
                            TextField("com.company.androidapp", text: $packageName)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { fetchAndLink() }
                                .disabled(!isGoogleConnected || isFetching)
                            Button {
                                fetchAndLink()
                            } label: {
                                if isFetching {
                                    ProgressView().controlSize(.small).frame(width: 92)
                                } else {
                                    Text("Fetch & link")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(
                                !isGoogleConnected
                                    || packageName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    || isFetching
                            )
                        }

                        if !isGoogleConnected {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.circle.fill")
                                Text("Connect Google Play before fetching a package.")
                                Spacer()
                                Button("Open setup") {
                                    dismiss()
                                    Task { @MainActor in
                                        try? await Task.sleep(for: .milliseconds(250))
                                        store.isOnboardingPresented = true
                                    }
                                }
                                .buttonStyle(.link)
                            }
                            .font(.caption)
                            .foregroundStyle(.orange)
                        }

                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(16)
                    .cardStyle(cornerRadius: 14)
                }
                .padding(24)
            }
        }
        .background(Theme.canvas)
    }

    private func fetchAndLink() {
        let cleanPackage = packageName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPackage.isEmpty, isGoogleConnected, !isFetching else { return }
        isFetching = true
        errorMessage = nil
        Task {
            do {
                try await store.addAndLinkAndroidPackage(cleanPackage, to: appStoreAppID)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                store.track(.applicationLinked(result: .failure))
                store.showToast("Could not link Android app", detail: error.localizedDescription, kind: .error)
            }
            isFetching = false
        }
    }
}
