import AppKit
import EscaleCore
import SwiftUI
import UniformTypeIdentifiers

public struct OnboardingView: View {
    public init() {}

    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var appleConnected = false
    @State private var googleConnected = false
    @State private var isConnectingApple = false
    @State private var isConnectingGoogle = false
    @State private var androidPackage = ""
    @State private var issuerID = ""
    @State private var keyID = ""
    @State private var applePrivateKey = ""
    @State private var appleKeyName = "Choose .p8 key"
    @State private var googleServiceAccountData: Data?
    @State private var googleKeyName = "Choose service-account JSON"
    @State private var isAddingPackage = false
    @State private var showsGoogleConnectionRequired = false

    private let steps = ["Welcome", "Connect", "Pair apps", "Ready"]

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(steps.indices, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? Theme.accent : Color.primary.opacity(0.1))
                        .frame(width: index == step ? 40 : 18, height: 5)
                        .animation(.spring(response: 0.35), value: step)
                }
                Spacer()
                Text("\(step + 1) of \(steps.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 26, height: 26)
                        .background(Color.primary.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("Close setup")
                .accessibilityLabel("Close setup")
            }
            .padding(24)

            Group {
                switch step {
                case 0: welcome
                case 1:
                    ScrollView {
                        connections
                            .padding(.vertical, 8)
                    }
                case 2: pairing
                default: ready
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity.combined(with: .move(edge: .trailing)))
            .id(step)

            Divider()
            HStack {
                if step > 0 {
                    Button("Back") { withAnimation { step -= 1 } }
                }
                Spacer()
                if step == 0 {
                    Button("Explore with demo data") {
                        store.startDemoMode()
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                Button(step == steps.count - 1 ? "Open workspace" : "Continue") {
                    store.track(.onboardingStepCompleted(step: step + 1))
                    if step == steps.count - 1 {
                        store.completeOnboarding()
                        dismiss()
                    } else {
                        withAnimation { step += 1 }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(24)
        }
        .frame(width: 830, height: 650)
        .background(Theme.canvas)
        .onAppear {
            appleConnected = store.workspace.connections.first(where: { $0.platform == .appStore })?.state == .connected
            googleConnected = store.workspace.connections.first(where: { $0.platform == .playStore })?.state == .connected
        }
        .alert("Connect Google Play first", isPresented: $showsGoogleConnectionRequired) {
            Button("Go to connection setup") {
                withAnimation { step = 1 }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Escale needs your Google service account to verify that this package exists and fetch its live Play Console data.")
        }
    }

    private var welcome: some View {
        HStack(spacing: 46) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(LinearGradient(colors: [Theme.accent, Color(hex: 0x9B8DFF)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        Image(systemName: "helm").font(.system(size: 28, weight: .bold)).foregroundStyle(.white)
                    }
                    .frame(width: 58, height: 58)
                    Text("Escale").font(.system(size: 29, weight: .bold, design: .rounded))
                }
                Text("Your stores,\nfinally in sync.")
                    .font(.system(size: 43, weight: .bold, design: .rounded))
                    .tracking(-1.2)
                Text("Ship better listings, fairer prices, and thoughtful review replies across the App Store and Google Play—from one native workspace.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Label("Local-first", systemImage: "lock.shield")
                    Label("Two stores", systemImage: "rectangle.2.swap")
                    Label("AI assist", systemImage: "sparkles")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
            }
            .frame(maxWidth: 430, alignment: .leading)

            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.accent.opacity(0.12), Color.cyan.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
                VStack(spacing: 18) {
                    storeCard(platform: .appStore, offset: -12)
                    Image(systemName: "link")
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 46, height: 46)
                        .background(.regularMaterial, in: Circle())
                        .zIndex(2)
                        .padding(.vertical, -28)
                    storeCard(platform: .playStore, offset: 12)
                }
                .padding(34)
            }
            .frame(width: 280, height: 360)
        }
        .padding(.horizontal, 44)
    }

    private func storeCard(platform: StorePlatform, offset: CGFloat) -> some View {
        HStack(spacing: 12) {
            Image(systemName: platform.icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(platform.tint, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(platform.rawValue).font(.headline)
                Text("12 products synced").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        }
        .padding(15)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.border))
        .offset(x: offset)
        .shadow(color: .black.opacity(0.08), radius: 15, y: 8)
    }

    private var connections: some View {
        VStack(spacing: 22) {
            SectionTitle("Connect your stores", subtitle: "Credentials are validated against the live APIs, then stored in macOS Keychain.", eyebrow: "Step 2")
                .frame(maxWidth: 620, alignment: .leading)
            VStack(spacing: 12) {
                credentialCard(platform: .appStore, connected: appleConnected) {
                    VStack(spacing: 9) {
                        HStack {
                            TextField("Issuer ID", text: $issuerID).textFieldStyle(.roundedBorder)
                            TextField("Key ID", text: $keyID).textFieldStyle(.roundedBorder).frame(width: 145)
                        }
                        HStack {
                            Button(appleKeyName) { chooseApplePrivateKey() }.lineLimit(1)
                            Spacer()
                            Button {
                                isConnectingApple = true
                                Task {
                                    do {
                                        try await store.connectApple(issuerID: issuerID, keyID: keyID, privateKeyPEM: applePrivateKey)
                                        appleConnected = true
                                    } catch {
                                        store.track(.storeConnectionCompleted(
                                            platform: .appStore,
                                            result: .failure,
                                            appCountBucket: nil,
                                            failure: EscaleAnalyticsEvent.failureCategory(for: error)
                                        ))
                                        store.showToast("App Store connection failed", detail: error.localizedDescription, kind: .error)
                                    }
                                    isConnectingApple = false
                                }
                            } label: {
                                if isConnectingApple { ProgressView().controlSize(.small).frame(width: 76) }
                                else { Text("Connect") }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(issuerID.isEmpty || keyID.isEmpty || applePrivateKey.isEmpty || isConnectingApple)
                        }
                    }
                }
                credentialCard(platform: .playStore, connected: googleConnected) {
                    HStack {
                        Button(googleKeyName) { chooseGoogleServiceAccount() }.lineLimit(1)
                        Spacer()
                        Button {
                            guard let googleServiceAccountData else { return }
                            isConnectingGoogle = true
                            Task {
                                do {
                                    try await store.connectGoogle(serviceAccountData: googleServiceAccountData)
                                    googleConnected = true
                                } catch {
                                    store.track(.storeConnectionCompleted(
                                        platform: .playStore,
                                        result: .failure,
                                        appCountBucket: nil,
                                        failure: EscaleAnalyticsEvent.failureCategory(for: error)
                                    ))
                                    store.showToast("Google Play connection failed", detail: error.localizedDescription, kind: .error)
                                }
                                isConnectingGoogle = false
                            }
                        } label: {
                            if isConnectingGoogle { ProgressView().controlSize(.small).frame(width: 76) }
                            else { Text("Connect") }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(googleServiceAccountData == nil || isConnectingGoogle)
                    }
                }
            }
            .frame(maxWidth: 620)
            Text("App Store keys need App Manager access. The Google service account must be invited in Play Console with the app and feature permissions you intend to use.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 52)
    }

    private var pairing: some View {
        VStack(spacing: 24) {
            SectionTitle("Pair the same product", subtitle: "Matching identifiers are linked automatically. You can always override the match.", eyebrow: "Step 3")
                .frame(maxWidth: 660, alignment: .leading)
            VStack(spacing: 12) {
                if let firstApp = store.workspace.apps.first {
                    HStack(spacing: 15) {
                        AppMark(app: firstApp, size: 48)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(firstApp.name).font(.headline)
                            Text(firstApp.appStoreApp?.bundleID ?? firstApp.playStoreApp?.bundleID ?? "").font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if firstApp.appStoreApp != nil { PlatformBadge(platform: .appStore) }
                        if firstApp.linkedCount == 2 { Image(systemName: "link").foregroundStyle(Theme.accent) }
                        if firstApp.playStoreApp != nil { PlatformBadge(platform: .playStore) }
                        Text(firstApp.linkedCount == 2 ? "Matched" : "Imported").font(.caption.weight(.semibold)).foregroundStyle(firstApp.linkedCount == 2 ? .green : .secondary)
                    }
                    .padding(18)
                    .cardStyle()
                } else {
                    EmptyState(icon: "square.stack.3d.up", title: "No apps imported yet", message: "Connect App Store Connect, or add a Google Play package below.")
                        .frame(height: 155).cardStyle()
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Add a Google Play package").font(.subheadline.weight(.semibold))
                            Text("Google’s API needs a known package name before it can read an app.").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        TextField("com.company.app", text: $androidPackage)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 230)
                            .onSubmit { submitAndroidPackage() }
                        Button {
                            submitAndroidPackage()
                        } label: {
                            if isAddingPackage {
                                ProgressView().controlSize(.small).frame(width: 30)
                            } else {
                                Text("Add")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(androidPackage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAddingPackage)
                    }

                    if !googleConnected && !store.isDemoMode {
                        HStack(spacing: 7) {
                            Image(systemName: "exclamationmark.circle.fill")
                            Text("Google Play is not connected, so the package cannot be verified yet.")
                            Spacer()
                            Button("Connect Google Play") {
                                withAnimation { step = 1 }
                            }
                            .buttonStyle(.link)
                        }
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                }
                .padding(18)
                .cardStyle()
            }
            .frame(maxWidth: 660)
        }
        .padding(.horizontal, 50)
    }

    private var ready: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.1)).frame(width: 112, height: 112)
                Image(systemName: "checkmark.seal.fill").font(.system(size: 55)).foregroundStyle(Theme.accent)
            }
            Text("Your workspace is ready")
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text("\(store.workspace.connections.filter { $0.state == .connected }.count) stores connected · \(store.workspace.apps.count) products imported · \(store.workspace.apps.filter { $0.linkedCount == 2 }.count) paired")
                .font(.title3)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                readyItem(icon: "text.document", title: "Localize", detail: "Edit both listings")
                readyItem(icon: "globe.europe.africa", title: "Price fairly", detail: "Apply PPP tiers")
                readyItem(icon: "quote.bubble", title: "Stay close", detail: "Reply to reviews")
            }
            .frame(maxWidth: 650)
            if store.isAnalyticsAvailable {
                Toggle(
                    "Share anonymous usage analytics",
                    isOn: Binding(
                        get: { store.isAnalyticsEnabled },
                        set: { store.setAnalyticsEnabled($0) }
                    )
                )
                .toggleStyle(.checkbox)
                .font(.subheadline.weight(.medium))
                Text("Helps improve Escale through coarse feature and reliability events sent to \(store.analyticsServiceName). Store content, account and app identifiers, credentials, licence keys, reviews, screenshots, prices, file paths, and raw errors are never included. You can change this in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 650)
            }
        }
        .padding(.horizontal, 50)
    }

    private func readyItem(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 9) {
            Image(systemName: icon).font(.system(size: 21, weight: .semibold)).foregroundStyle(Theme.accent)
            Text(title).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .cardStyle()
    }

    private func credentialCard<Content: View>(platform: StorePlatform, connected: Bool, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: platform.icon)
                .font(.system(size: 23, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(platform.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(platform.rawValue).font(.headline)
                        Text(platform == .appStore ? "Issuer ID, Key ID, and private .p8 key" : "Google Cloud service-account JSON with Play Console access")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if connected { Label("Connected", systemImage: "checkmark.circle.fill").font(.caption.weight(.semibold)).foregroundStyle(.green) }
                }
                if !connected { content() }
                StoreCredentialSetupGuide(platform: platform)
            }
        }
        .padding(17)
        .cardStyle()
    }

    private func chooseApplePrivateKey() {
        let p8Type = UTType(filenameExtension: "p8") ?? .data
        guard let url = CredentialFilePicker.choose(
            title: "Choose App Store Connect private key",
            message: "Select the .p8 key downloaded from App Store Connect.",
            allowedContentTypes: [p8Type]
        ) else { return }

        do {
            let privateKey = try String(contentsOf: url, encoding: .utf8)
            guard privateKey.contains("-----BEGIN PRIVATE KEY-----") else {
                throw CredentialFileError.invalidApplePrivateKey
            }
            applePrivateKey = privateKey
            appleKeyName = url.lastPathComponent
        } catch {
            store.showToast("Could not read key", detail: error.localizedDescription, kind: .error)
        }
    }

    private func submitAndroidPackage() {
        let packageName = androidPackage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !packageName.isEmpty, !isAddingPackage else { return }
        guard googleConnected || store.isDemoMode else {
            showsGoogleConnectionRequired = true
            return
        }

        isAddingPackage = true
        Task {
            do {
                try await store.addAndroidPackage(packageName)
                androidPackage = ""
            } catch {
                store.showToast("Could not add package", detail: error.localizedDescription, kind: .error)
            }
            isAddingPackage = false
        }
    }

    private func chooseGoogleServiceAccount() {
        guard let url = CredentialFilePicker.choose(
            title: "Choose Google service account",
            message: "Select the service-account JSON downloaded from Google Cloud.",
            allowedContentTypes: [.json]
        ) else { return }

        do {
            let data = try Data(contentsOf: url)
            _ = try JSONSerialization.jsonObject(with: data)
            googleServiceAccountData = data
            googleKeyName = url.lastPathComponent
        } catch {
            store.showToast("Could not read credentials", detail: error.localizedDescription, kind: .error)
        }
    }

}

@MainActor
private enum CredentialFilePicker {
    static func choose(title: String, message: String, allowedContentTypes: [UTType]) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = message
        panel.prompt = "Choose"
        panel.allowedContentTypes = allowedContentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.resolvesAliases = true

        NSApplication.shared.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }
}

private enum CredentialFileError: LocalizedError {
    case invalidApplePrivateKey

    var errorDescription: String? {
        switch self {
        case .invalidApplePrivateKey:
            "The selected file is not an App Store Connect .p8 private key."
        }
    }
}

public struct SettingsView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.escaleCommercialActions) private var commercialActions
    @Environment(\.dismiss) private var dismiss

    public init() {}
    @State private var presentedSheet: SettingsSheet?
    @State private var openAIAPIKey = ""
    @State private var isTestingOpenAI = false
    @State private var openAIStatusMessage: String?
    @State private var openAIStatusIsError = false
    @State private var platformPendingDisconnect: StorePlatform?

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    SectionTitle("Plan", subtitle: "See which Escale capabilities are available on this Mac.")
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 26, height: 26)
                            .background(Color.primary.opacity(0.06), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .help("Close settings")
                    .accessibilityLabel("Close settings")
                }
                HStack(spacing: 13) {
                    Image(systemName: store.entitlements.plan == .pro ? "crown.fill" : "person.crop.circle")
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(
                            store.entitlements.plan == .pro ? Theme.accent : Color.secondary,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.entitlements.plan.displayName)
                            .font(.subheadline.weight(.semibold))
                        Text(
                            store.entitlements.plan == .pro
                                ? "Pro capabilities are unlocked."
                                : "Manual workflows and single-account tools are available."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let commercialActions {
                        Button(store.entitlements.plan == .pro ? "Manage licence" : "Unlock Pro") {
                            commercialActions.openLicenceManagement()
                        }
                    }
                }
                .padding(14)
                .cardStyle(cornerRadius: 13)
                if store.isAnalyticsAvailable {
                    Divider()
                    SectionTitle("Privacy", subtitle: "Control anonymous product analytics for this build.")
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(
                            "Share anonymous usage analytics",
                            isOn: Binding(
                                get: { store.isAnalyticsEnabled },
                                set: { store.setAnalyticsEnabled($0) }
                            )
                        )
                        Text("When enabled, Escale sends coarse feature, outcome, app-version, and system-version events to \(store.analyticsServiceName). It never sends store content, account or app identifiers, credentials, licence keys, reviews, screenshots, prices, file paths, or raw error messages.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .cardStyle(cornerRadius: 13)
                }
                Divider()
                SectionTitle("Connections", subtitle: "Manage access to your developer accounts.")
                ForEach(StorePlatform.allCases) { platform in
                    let connection = store.workspace.connections.first(where: { $0.platform == platform })
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 13) {
                            Image(systemName: platform.icon)
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .background(platform.tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(connection?.accountName ?? platform.rawValue).font(.subheadline.weight(.semibold))
                                Text(connection?.detail ?? "Not connected").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(connection?.state.label ?? "Not connected")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(connection?.state == .connected ? .green : .secondary)
                            if connection?.state == .connected && !store.isDemoMode {
                                Button("Disconnect") {
                                    platformPendingDisconnect = platform
                                }
                                .buttonStyle(.borderless)
                            } else if connection?.state != .connected {
                                Button(connection?.state == .attention ? "Reconnect" : "Connect") {
                                    presentedSheet = .connection(platform)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                        StoreCredentialSetupGuide(platform: platform)
                    }
                    .padding(14)
                    .cardStyle(cornerRadius: 13)
                }
                Divider()
                SectionTitle("OpenAI", subtitle: "Power translations and future AI tools with your own API key.")
                openAISettingsCard
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Setup assistant").font(.subheadline.weight(.semibold))
                        Text("Reconnect accounts or add packages.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open setup") { presentedSheet = .setup }
                }
                if canPairApps {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Manual app pairing").font(.subheadline.weight(.semibold))
                            Text("Link records when their identifiers do not match.").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Pair apps") { presentedSheet = .linker }
                    }
                }
                if store.isDemoMode {
                    Button("Leave demo workspace") { store.leaveDemoMode() }
                        .foregroundStyle(.red)
                }
            }
            .padding(28)
        }
        .background(Theme.canvas)
        .onAppear { store.refreshOpenAIConfigurationStatus() }
        .alert(item: $platformPendingDisconnect) { platform in
            Alert(
                title: Text("Disconnect \(platform.rawValue)?"),
                message: Text("Its credential will be removed from macOS Keychain. Cached app data will remain available locally."),
                primaryButton: .destructive(Text("Disconnect")) {
                    do {
                        try store.disconnect(platform)
                        store.showToast("\(platform.rawValue) disconnected", detail: "The saved credential was removed from Keychain.", kind: .success)
                    } catch {
                        store.showToast("Could not disconnect", detail: error.localizedDescription, kind: .error)
                    }
                },
                secondaryButton: .cancel()
            )
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .setup:
                OnboardingView()
                    .environmentObject(store)
            case .linker:
                ManualLinkView()
                    .environmentObject(store)
                    .frame(width: 560, height: 330)
            case .connection(let platform):
                StoreConnectionSheet(platform: platform)
                    .environmentObject(store)
            }
        }
    }

    private var canPairApps: Bool {
        store.workspace.apps.contains(where: { $0.appStoreApp != nil })
            && store.workspace.apps.contains(where: { $0.playStoreApp != nil })
    }

    private var openAISettingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("OpenAI API key").font(.subheadline.weight(.semibold))
                    Text("Model: \(OpenAIClient.model)").font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Spacer()
                Label(store.isOpenAIKeyConfigured ? "Configured" : "Not configured", systemImage: store.isOpenAIKeyConfigured ? "checkmark.circle.fill" : "circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(store.isOpenAIKeyConfigured ? .green : .secondary)
            }

            SecureField(store.isOpenAIKeyConfigured ? "Enter a new key to replace the saved key" : "sk-…", text: $openAIAPIKey)
                .textFieldStyle(.roundedBorder)
                .privacySensitive()

            HStack(spacing: 10) {
                Button(store.isOpenAIKeyConfigured ? "Replace key" : "Save securely") {
                    do {
                        try store.saveOpenAIAPIKey(openAIAPIKey)
                        openAIAPIKey = ""
                        openAIStatusMessage = "Saved in macOS Keychain."
                        openAIStatusIsError = false
                    } catch {
                        openAIStatusMessage = error.localizedDescription
                        openAIStatusIsError = true
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).count < 20)

                if store.isOpenAIKeyConfigured {
                    Button {
                        isTestingOpenAI = true
                        openAIStatusMessage = nil
                        Task {
                            do {
                                try await store.testOpenAIConnection()
                                openAIStatusMessage = "Connection successful. \(OpenAIClient.model) is available."
                                openAIStatusIsError = false
                            } catch {
                                openAIStatusMessage = error.localizedDescription
                                openAIStatusIsError = true
                            }
                            isTestingOpenAI = false
                        }
                    } label: {
                        if isTestingOpenAI {
                            ProgressView().controlSize(.small).frame(width: 92)
                        } else {
                            Text("Test connection")
                        }
                    }
                    .disabled(isTestingOpenAI)

                    Button("Remove", role: .destructive) {
                        do {
                            try store.removeOpenAIAPIKey()
                            openAIStatusMessage = nil
                            openAIAPIKey = ""
                        } catch {
                            openAIStatusMessage = error.localizedDescription
                            openAIStatusIsError = true
                        }
                    }
                    .buttonStyle(.borderless)
                }

                Spacer()
                Link("Create an API key", destination: URL(string: "https://platform.openai.com/api-keys")!)
                    .font(.caption)
            }

            if let openAIStatusMessage {
                Label(openAIStatusMessage, systemImage: openAIStatusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(openAIStatusIsError ? .red : .green)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Requests go directly from this Mac to api.openai.com over HTTPS. The key is never added to workspace data or logs. OpenAI API usage is billed to the account that owns the key.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .cardStyle(cornerRadius: 14)
    }
}

private enum SettingsSheet: Identifiable {
    case setup
    case linker
    case connection(StorePlatform)

    var id: String {
        switch self {
        case .setup: "setup"
        case .linker: "linker"
        case .connection(let platform): "connection-\(platform.id)"
        }
    }
}

private struct StoreConnectionSheet: View {
    let platform: StorePlatform

    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var issuerID = ""
    @State private var keyID = ""
    @State private var applePrivateKey = ""
    @State private var appleKeyName = "Choose .p8 private key"
    @State private var googleServiceAccountData: Data?
    @State private var googleKeyName = "Choose service-account JSON"
    @State private var isConnecting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SectionTitle(
                        "Credentials",
                        subtitle: platform == .appStore
                            ? "Use a Team API key with App Manager access."
                            : "Use a Google Cloud service account invited to your Play Console."
                    )

                    credentialForm
                        .padding(18)
                        .cardStyle(cornerRadius: 14)

                    StoreCredentialSetupGuide(platform: platform)
                        .padding(16)
                        .cardStyle(cornerRadius: 14)

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(24)
            }
            Divider()
            footer
        }
        .frame(width: 620, height: 600)
        .background(Theme.canvas)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: platform.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(platform.tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Connect \(platform.rawValue)")
                    .font(.title2.weight(.bold))
                Text("Validated live, then stored securely in macOS Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 26, height: 26)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close connection setup")
            .accessibilityLabel("Close connection setup")
        }
        .padding(22)
    }

    @ViewBuilder
    private var credentialForm: some View {
        switch platform {
        case .appStore:
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Issuer ID").font(.caption.weight(.semibold))
                        TextField("xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx", text: $issuerID)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Key ID").font(.caption.weight(.semibold))
                        TextField("XXXXXXXXXX", text: $keyID)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 170)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Private key").font(.caption.weight(.semibold))
                    Button {
                        chooseApplePrivateKey()
                    } label: {
                        HStack {
                            Image(systemName: applePrivateKey.isEmpty ? "key.horizontal" : "checkmark.circle.fill")
                                .foregroundStyle(applePrivateKey.isEmpty ? Color.secondary : Color.green)
                            Text(appleKeyName)
                                .lineLimit(1)
                            Spacer()
                            Text("Choose…")
                                .foregroundStyle(Theme.accent)
                        }
                        .padding(9)
                        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        case .playStore:
            VStack(alignment: .leading, spacing: 10) {
                Text("Service-account JSON").font(.caption.weight(.semibold))
                Button {
                    chooseGoogleServiceAccount()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: googleServiceAccountData == nil ? "doc.badge.plus" : "checkmark.circle.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(googleServiceAccountData == nil ? Color.secondary : Color.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(googleKeyName)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(googleServiceAccountData == nil ? "Select the JSON key downloaded from Google Cloud." : "Ready to validate with Google Play.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("Choose…")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Label("Credentials stay on this Mac", systemImage: "lock.shield.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Cancel") {
                dismiss()
            }
            Button {
                connect()
            } label: {
                if isConnecting {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.small)
                        Text("Connecting…")
                    }
                    .frame(minWidth: 92)
                } else {
                    Text("Connect \(platform.rawValue)")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canConnect || isConnecting)
        }
        .padding(20)
    }

    private var canConnect: Bool {
        switch platform {
        case .appStore:
            !issuerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !keyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !applePrivateKey.isEmpty
        case .playStore:
            googleServiceAccountData != nil
        }
    }

    private func connect() {
        guard canConnect, !isConnecting else { return }
        isConnecting = true
        errorMessage = nil

        Task {
            do {
                switch platform {
                case .appStore:
                    try await store.connectApple(
                        issuerID: issuerID,
                        keyID: keyID,
                        privateKeyPEM: applePrivateKey
                    )
                case .playStore:
                    guard let googleServiceAccountData else {
                        throw APIError.invalidCredentials("Choose a Google service-account JSON key.")
                    }
                    try await store.connectGoogle(serviceAccountData: googleServiceAccountData)
                }
                dismiss()
            } catch {
                store.track(.storeConnectionCompleted(
                    platform: platform,
                    result: .failure,
                    appCountBucket: nil,
                    failure: EscaleAnalyticsEvent.failureCategory(for: error)
                ))
                errorMessage = error.localizedDescription
            }
            isConnecting = false
        }
    }

    private func chooseApplePrivateKey() {
        let p8Type = UTType(filenameExtension: "p8") ?? .data
        guard let url = CredentialFilePicker.choose(
            title: "Choose App Store Connect private key",
            message: "Select the .p8 key downloaded from App Store Connect.",
            allowedContentTypes: [p8Type]
        ) else { return }

        do {
            let privateKey = try String(contentsOf: url, encoding: .utf8)
            guard privateKey.contains("-----BEGIN PRIVATE KEY-----") else {
                throw CredentialFileError.invalidApplePrivateKey
            }
            applePrivateKey = privateKey
            appleKeyName = url.lastPathComponent
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func chooseGoogleServiceAccount() {
        guard let url = CredentialFilePicker.choose(
            title: "Choose Google service account",
            message: "Select the service-account JSON downloaded from Google Cloud.",
            allowedContentTypes: [.json]
        ) else { return }

        do {
            let data = try Data(contentsOf: url)
            _ = try JSONSerialization.jsonObject(with: data)
            googleServiceAccountData = data
            googleKeyName = url.lastPathComponent
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct StoreCredentialSetupGuide: View {
    let platform: StorePlatform
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Label(
                        platform == .appStore ? "How to create an Apple API key" : "How to create a Google service account",
                        systemImage: "list.number"
                    )
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                VStack(alignment: .leading, spacing: 11) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 21, height: 21)
                                .background(platform.tint, in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(step.title).font(.caption.weight(.semibold))
                                Text(step.detail)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let linkTitle = step.linkTitle, let url = step.url {
                                    Link(destination: url) {
                                        Label(linkTitle, systemImage: "arrow.up.right")
                                            .font(.caption2.weight(.semibold))
                                    }
                                }
                            }
                        }
                    }
                    Label(
                        "Credential files are stored in macOS Keychain and are never written into the workspace cache.",
                        systemImage: "lock.shield.fill"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                }
                .padding(.top, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var steps: [CredentialSetupStep] {
        switch platform {
        case .appStore:
            [
                CredentialSetupStep(
                    title: "Enable App Store Connect API access",
                    detail: "As the Account Holder, open Users and Access → Integrations and request API access if it has not already been enabled.",
                    linkTitle: "Open Apple’s setup guide",
                    url: URL(string: "https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api")
                ),
                CredentialSetupStep(
                    title: "Generate a Team API key",
                    detail: "In Integrations → Team Keys, click Generate API Key (or +). Give it a recognizable name and select App Manager access. Account Holder or Admin access is required to create it.",
                    linkTitle: "Open App Store Connect API keys",
                    url: URL(string: "https://appstoreconnect.apple.com/access/integrations/api")
                ),
                CredentialSetupStep(
                    title: "Save all three credentials",
                    detail: "Copy the Issuer ID and Key ID, then download the .p8 private key. Apple allows that private key to be downloaded only once."
                ),
                CredentialSetupStep(
                    title: "Connect Escale",
                    detail: "Enter the Issuer ID and Key ID above, choose the matching .p8 file, then click Connect."
                )
            ]
        case .playStore:
            [
                CredentialSetupStep(
                    title: "Create or select a Google Cloud project",
                    detail: "Use a project owned by the same organization that operates the Play Console account.",
                    linkTitle: "Open Google Cloud projects",
                    url: URL(string: "https://console.cloud.google.com/projectselector2/home/dashboard")
                ),
                CredentialSetupStep(
                    title: "Enable the Android Publisher API",
                    detail: "Enable Google Play Android Developer API in that Cloud project.",
                    linkTitle: "Enable the API",
                    url: URL(string: "https://console.cloud.google.com/apis/library/androidpublisher.googleapis.com")
                ),
                CredentialSetupStep(
                    title: "Create a service account and JSON key",
                    detail: "Create a service account, open its Keys tab, choose Add key → Create new key → JSON, and keep the downloaded file private.",
                    linkTitle: "Open Service Accounts",
                    url: URL(string: "https://console.cloud.google.com/iam-admin/serviceaccounts")
                ),
                CredentialSetupStep(
                    title: "Invite it to Play Console",
                    detail: "Open Users and permissions, invite the service-account email found in the JSON file, and grant it access to the apps Escale should manage.",
                    linkTitle: "Open Play users and permissions",
                    url: URL(string: "https://play.google.com/console/users-and-permissions")
                ),
                CredentialSetupStep(
                    title: "Grant the feature permissions you need",
                    detail: "Include app-information access plus store-presence editing, releases, review replies, and product/subscription permissions when you want Escale to manage those areas. Missing feature permissions produce Google 403 errors.",
                    linkTitle: "Review Google’s permission reference",
                    url: URL(string: "https://support.google.com/googleplay/android-developer/answer/9844686")
                ),
                CredentialSetupStep(
                    title: "Connect and add package names",
                    detail: "Choose the JSON file above and click Connect. Then add each exact Android package name; Google’s publishing API cannot list every app in an account."
                )
            ]
        }
    }
}

private struct CredentialSetupStep {
    let title: String
    let detail: String
    var linkTitle: String? = nil
    var url: URL? = nil
}

private struct ManualLinkView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var appleID: UUID?
    @State private var googleID: UUID?

    private var appleApps: [UnifiedApp] { store.workspace.apps.filter { $0.appStoreApp != nil } }
    private var googleApps: [UnifiedApp] { store.workspace.apps.filter { $0.playStoreApp != nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SectionTitle("Pair store records", subtitle: "Choose the iOS and Android records that represent the same product.")
            VStack(spacing: 14) {
                Picker("App Store app", selection: $appleID) {
                    Text("Choose an app").tag(Optional<UUID>.none)
                    ForEach(appleApps) { Text($0.appStoreApp?.name ?? $0.name).tag(Optional($0.id)) }
                }
                Picker("Google Play app", selection: $googleID) {
                    Text("Choose an app").tag(Optional<UUID>.none)
                    ForEach(googleApps) { Text($0.playStoreApp?.name ?? $0.name).tag(Optional($0.id)) }
                }
            }
            Spacer()
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Pair apps") {
                    guard let appleID, let googleID else { return }
                    store.link(appStoreApp: appleID, toPlayStoreApp: googleID)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(appleID == nil || googleID == nil || appleID == googleID)
            }
        }
        .padding(26)
    }
}
