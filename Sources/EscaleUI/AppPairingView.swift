import EscaleCore
import SwiftUI

struct AppPairingRequest: Identifiable {
    let appID: UUID
    var id: UUID { appID }
}

struct AppPairingView: View {
    let appID: UUID

    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var connectionPlatform: StorePlatform?
    @State private var packageName = ""
    @State private var isFetching = false
    @State private var errorMessage: String?

    private var sourceApp: UnifiedApp? {
        store.workspace.apps.first(where: { $0.id == appID })
    }

    private var missingPlatform: StorePlatform? {
        guard let sourceApp else { return nil }
        if sourceApp.appStoreApp == nil, sourceApp.playStoreApp != nil { return .appStore }
        if sourceApp.playStoreApp == nil, sourceApp.appStoreApp != nil { return .playStore }
        return nil
    }

    private var availableCounterparts: [UnifiedApp] {
        guard let missingPlatform else { return [] }
        return store.workspace.apps
            .filter { app in
                guard app.id != appID else { return false }
                switch missingPlatform {
                case .appStore:
                    return app.appStoreApp != nil && app.playStoreApp == nil
                case .playStore:
                    return app.playStoreApp != nil && app.appStoreApp == nil
                }
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var isMissingStoreConnected: Bool {
        guard let missingPlatform else { return true }
        return store.isDemoMode || store.workspace.connections.contains {
            $0.platform == missingPlatform && $0.state == .connected
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let sourceApp {
                        sourceAppCard(sourceApp)
                    }

                    if let missingPlatform {
                        if !isMissingStoreConnected {
                            connectionCard(platform: missingPlatform)
                        }

                        if !availableCounterparts.isEmpty {
                            counterpartList(platform: missingPlatform)
                        }

                        if missingPlatform == .playStore {
                            googlePackageCard
                        } else if availableCounterparts.isEmpty, isMissingStoreConnected {
                            noAppleAppsCard
                        }
                    } else if sourceApp?.linkedCount == 2 {
                        Label("This app is already paired across both stores.", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.green)
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .cardStyle(cornerRadius: 14)
                    } else {
                        Label("This app is no longer available in the workspace.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .cardStyle(cornerRadius: 14)
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(24)
            }
            Divider()
            HStack {
                Text("Pairing combines both store records into one product workspace.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(sourceApp?.linkedCount == 2 ? "Done" : "Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)
        }
        .frame(width: 620, height: 580)
        .background(Theme.canvas)
        .escaleToastOverlay()
        .sheet(item: $connectionPlatform) { platform in
            StoreConnectionSheet(platform: platform)
                .environmentObject(store)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Pair this app")
                    .font(.title2.weight(.bold))
                Text(missingPlatform.map { "Add the matching \($0.rawValue) record to this product workspace." }
                    ?? "Manage this product’s store pairing.")
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
            .accessibilityLabel("Close app pairing")
        }
        .padding(24)
    }

    private func sourceAppCard(_ app: UnifiedApp) -> some View {
        HStack(spacing: 13) {
            AppMark(app: app, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(app.name).font(.headline)
                Text(app.appStoreApp?.bundleID ?? app.playStoreApp?.bundleID ?? "")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if app.appStoreApp != nil { PlatformBadge(platform: .appStore) }
            if app.playStoreApp != nil { PlatformBadge(platform: .playStore) }
        }
        .padding(15)
        .cardStyle(cornerRadius: 14)
    }

    private func connectionCard(platform: StorePlatform) -> some View {
        HStack(spacing: 13) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 38, height: 38)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text("\(platform.rawValue) is not connected")
                    .font(.subheadline.weight(.semibold))
                Text("Connect the store here, then continue pairing without leaving this window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Connect") {
                connectionPlatform = platform
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(Color.orange.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.2)))
    }

    private func counterpartList(platform: StorePlatform) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("IMPORTED \(platform.shortName.uppercased()) APPS")
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            ForEach(availableCounterparts) { app in
                HStack(spacing: 12) {
                    AppMark(app: app, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name).font(.subheadline.weight(.semibold))
                        Text(app.appStoreApp?.bundleID ?? app.playStoreApp?.bundleID ?? "")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Pair") {
                        pair(with: app, missingPlatform: platform)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isFetching)
                }
                .padding(13)
                .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var googlePackageCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(availableCounterparts.isEmpty ? "ADD FROM GOOGLE PLAY" : "OR ADD ANOTHER PACKAGE")
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Text("Google’s API cannot list every app in an account. Enter its exact package name and Escale will verify access, fetch its live data, and pair it here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                TextField("com.company.androidapp", text: $packageName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { fetchAndPairGooglePackage() }
                    .disabled(!isMissingStoreConnected || isFetching)
                Button {
                    fetchAndPairGooglePackage()
                } label: {
                    if isFetching {
                        ProgressView().controlSize(.small).frame(width: 92)
                    } else {
                        Text("Fetch & pair")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    !isMissingStoreConnected
                        || packageName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || isFetching
                )
            }
        }
        .padding(16)
        .cardStyle(cornerRadius: 14)
    }

    private var noAppleAppsCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("No unpaired App Store apps found", systemImage: "apple.logo")
                .font(.subheadline.weight(.semibold))
            Text("The connected account did not return an available iOS record. Make sure the app belongs to this App Store Connect account.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(cornerRadius: 14)
    }

    private func pair(with counterpart: UnifiedApp, missingPlatform: StorePlatform) {
        switch missingPlatform {
        case .playStore:
            store.link(appStoreApp: appID, toPlayStoreApp: counterpart.id)
        case .appStore:
            store.link(appStoreApp: counterpart.id, toPlayStoreApp: appID)
        }
        store.showToast(
            "Apps paired",
            detail: "\(counterpart.name) is now part of this product workspace.",
            kind: .success
        )
        dismiss()
    }

    private func fetchAndPairGooglePackage() {
        let cleanPackage = packageName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPackage.isEmpty, isMissingStoreConnected, !isFetching else { return }
        isFetching = true
        errorMessage = nil
        Task {
            do {
                try await store.addAndLinkAndroidPackage(cleanPackage, to: appID)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                store.track(.applicationLinked(result: .failure))
                store.showToast("Could not pair Android app", detail: error.localizedDescription, kind: .error)
            }
            isFetching = false
        }
    }
}
