import Foundation
import SwiftUI

@MainActor
public final class WorkspaceStore: ObservableObject {
    @Published public var workspace: Workspace
    @Published public var selectedAppID: UUID? {
        didSet {
            if let selectedAppID { UserDefaults.standard.set(selectedAppID.uuidString, forKey: selectedAppKey) }
            else { UserDefaults.standard.removeObject(forKey: selectedAppKey) }
        }
    }
    @Published public var selectedSection: AppSection = .overview
    @Published public var platformFilter: PlatformFilter = .both
    @Published public var isOnboardingPresented: Bool
    @Published public var isSyncing = false
    @Published public var toast: ToastMessage?
    @Published public private(set) var isDemoMode: Bool
    @Published public private(set) var loadingAppIDs: Set<UUID> = []
    @Published public private(set) var loadedAppIDs: Set<UUID> = []
    @Published public private(set) var appSyncIssues: [UUID: [String]] = [:]
    @Published public private(set) var appRefreshProgressByID: [UUID: AppRefreshProgress] = [:]
    @Published public private(set) var isOpenAIKeyConfigured = false
    @Published public private(set) var calculatingProductIDs: Set<UUID> = []
    @Published public private(set) var pricingApplyProgressByProductID: [UUID: PricingApplyProgress] = [:]
    @Published public private(set) var isAnalyticsEnabled: Bool

    public let entitlements: any EscaleEntitlementProviding
    public let analytics: any EscaleAnalyticsProviding

    private let persistenceKey = "escale.workspace.v2"
    private let onboardingKey = "escale.onboarding.complete.v2"
    private let demoKey = "escale.demo-mode"
    private let selectedAppKey = "escale.selected-app.v1"
    private let legacyPersistenceKey = "gouvernail.workspace.v2"
    private let legacyOnboardingKey = "gouvernail.onboarding.complete.v2"
    private let legacyDemoKey = "gouvernail.demo-mode"
    private let legacySelectedAppKey = "gouvernail.selected-app.v1"
    private let legacyDefaultsDomain = "app.gouvernail.mac"
    private var pendingEditorPersistence: Task<Void, Never>?

    public init(
        entitlements: any EscaleEntitlementProviding = CommunityEntitlements(),
        analytics: any EscaleAnalyticsProviding = NoOpEscaleAnalytics()
    ) {
        self.entitlements = entitlements
        self.analytics = analytics
        isAnalyticsEnabled = analytics.isEnabled
        let defaults = UserDefaults.standard
        let legacyDomain = defaults.persistentDomain(forName: legacyDefaultsDomain) ?? [:]
        let persistedWorkspace = defaults.data(forKey: persistenceKey)
            ?? defaults.data(forKey: legacyPersistenceKey)
            ?? legacyDomain[legacyPersistenceKey] as? Data
        var loadedWorkspace: Workspace
        if let data = persistedWorkspace,
           let saved = try? JSONDecoder().decode(Workspace.self, from: data) {
            loadedWorkspace = saved
            if defaults.data(forKey: persistenceKey) == nil {
                defaults.set(data, forKey: persistenceKey)
            }
        } else {
            loadedWorkspace = .empty
        }
        for appID in Array(loadedWorkspace.productsByApp.keys) {
            loadedWorkspace.productsByApp[appID] = splitCrossStoreProducts(
                loadedWorkspace.productsByApp[appID, default: []]
            )
        }
        workspace = loadedWorkspace
        let savedSelectionValue = defaults.string(forKey: selectedAppKey)
            ?? defaults.string(forKey: legacySelectedAppKey)
            ?? legacyDomain[legacySelectedAppKey] as? String
        if defaults.string(forKey: selectedAppKey) == nil, let savedSelectionValue {
            defaults.set(savedSelectionValue, forKey: selectedAppKey)
        }
        let savedSelection = savedSelectionValue.flatMap(UUID.init(uuidString:))
        selectedAppID = savedSelection.flatMap { savedID in loadedWorkspace.apps.contains(where: { $0.id == savedID }) ? savedID : nil }
            ?? loadedWorkspace.apps.first?.id
        let onboardingComplete = Self.migratedBoolean(
            defaults: defaults,
            currentKey: onboardingKey,
            legacyKey: legacyOnboardingKey,
            legacyDomain: legacyDomain
        )
        isOnboardingPresented = !onboardingComplete
        isDemoMode = Self.migratedBoolean(
            defaults: defaults,
            currentKey: demoKey,
            legacyKey: legacyDemoKey,
            legacyDomain: legacyDomain
        )
        loadedAppIDs = cachedAppIDs(in: loadedWorkspace)
    }

    public func hasAccess(to feature: EscaleFeature) -> Bool {
        entitlements.hasAccess(to: feature)
    }

    @discardableResult
    public func requireAccess(to feature: EscaleFeature) -> Bool {
        guard hasAccess(to: feature) else {
            track(.proGateViewed(feature: feature))
            showToast(
                "Escale Pro required",
                detail: feature.upgradeDescription,
                kind: .neutral
            )
            return false
        }
        return true
    }

    public var isAnalyticsAvailable: Bool {
        analytics.isAvailable
    }

    public var analyticsServiceName: String {
        analytics.serviceName
    }

    public func setAnalyticsEnabled(_ enabled: Bool) {
        analytics.setEnabled(enabled)
        isAnalyticsEnabled = enabled && analytics.isAvailable
    }

    public func track(_ event: EscaleAnalyticsEvent) {
        analytics.capture(event, plan: entitlements.plan)
    }

    private static func migratedBoolean(
        defaults: UserDefaults,
        currentKey: String,
        legacyKey: String,
        legacyDomain: [String: Any]
    ) -> Bool {
        if defaults.object(forKey: currentKey) != nil {
            return defaults.bool(forKey: currentKey)
        }
        if defaults.object(forKey: legacyKey) != nil {
            let legacyValue = defaults.bool(forKey: legacyKey)
            defaults.set(legacyValue, forKey: currentKey)
            return legacyValue
        }
        if let legacyValue = legacyDomain[legacyKey] as? Bool {
            defaults.set(legacyValue, forKey: currentKey)
            return legacyValue
        }
        return false
    }

    public var selectedApp: UnifiedApp? { workspace.apps.first(where: { $0.id == selectedAppID }) }
    public var selectedLocalizations: [ListingLocalization] {
        let platforms = selectedEditingPlatforms
        return (selectedAppID.flatMap { workspace.localizationsByApp[$0] } ?? [])
            .map { listingLocalization($0, displaying: platforms) }
    }
    public var selectedScreenshots: [StoreScreenshot] { selectedAppID.flatMap { workspace.screenshotsByApp[$0] } ?? [] }
    public var selectedProducts: [StoreProduct] { selectedAppID.flatMap { workspace.productsByApp[$0] } ?? [] }
    public var selectedReviews: [CustomerReview] { selectedAppID.flatMap { workspace.reviewsByApp[$0] } ?? [] }
    public var isSelectedAppLoading: Bool { selectedAppID.map(loadingAppIDs.contains) ?? false }
    public var selectedAppSyncIssues: [String] { selectedAppID.flatMap { appSyncIssues[$0] } ?? [] }
    public var selectedAppHasLiveData: Bool { selectedAppID.map(loadedAppIDs.contains) ?? false }
    public var selectedAppRefreshProgress: AppRefreshProgress? { selectedAppID.flatMap { appRefreshProgressByID[$0] } }
    public var selectedAvailablePlatforms: Set<StorePlatform> { selectedAppID.map(availablePlatforms) ?? [] }
    public var selectedEditingPlatforms: Set<StorePlatform> {
        platformFilter.platforms.intersection(selectedAvailablePlatforms)
    }
    public var selectedPrimaryLocalization: ListingLocalization? {
        let preferredLocale: String? = if selectedEditingPlatforms == [.playStore] {
            selectedApp?.playStoreApp?.primaryLocale
        } else {
            selectedApp?.appStoreApp?.primaryLocale ?? selectedApp?.playStoreApp?.primaryLocale
        }
        return primaryLocalization(
            in: selectedLocalizations,
            preferredLocale: preferredLocale
        )
    }
    public var selectedGooglePrimaryLocalization: ListingLocalization? {
        guard let appID = selectedAppID else { return nil }
        let localizations = workspace.localizationsByApp[appID, default: []]
            .map { listingLocalization($0, displaying: [.playStore]) }
        return primaryLocalization(
            in: localizations,
            preferredLocale: selectedApp?.playStoreApp?.primaryLocale
        )
    }
    public var selectedGooglePlayReleaseNotesBlock: String {
        guard let appID = selectedAppID else { return "" }
        return workspace.googlePlayReleaseNotesByApp?[appID] ?? ""
    }

    public func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: onboardingKey)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) { isOnboardingPresented = false }
        showToast("Workspace ready", detail: isDemoMode ? "Demo workspace loaded." : "Connected stores are ready to sync.", kind: .success)
        track(.onboardingCompleted(
            connectedStoresBucket: EscaleAnalyticsEvent.countBucket(
                workspace.connections.filter { $0.state == .connected }.count
            ),
            linkedAppsBucket: EscaleAnalyticsEvent.countBucket(
                workspace.apps.filter { $0.linkedCount == 2 }.count
            )
        ))
    }

    public func startDemoMode() {
        isDemoMode = true
        UserDefaults.standard.set(true, forKey: demoKey)
        workspace = SampleData.workspace()
        selectedAppID = workspace.apps.first?.id
        persist()
        track(.demoModeStarted)
        completeOnboarding()
    }

    public func leaveDemoMode() {
        isDemoMode = false
        UserDefaults.standard.set(false, forKey: demoKey)
        workspace = .empty
        selectedAppID = nil
        persist()
        isOnboardingPresented = true
    }

    public func resetOnboarding() {
        UserDefaults.standard.set(false, forKey: onboardingKey)
        isOnboardingPresented = true
    }

    public func connectApple(issuerID: String, keyID: String, privateKeyPEM: String) async throws {
        let credentials = AppleCredentials(
            issuerID: issuerID.trimmingCharacters(in: .whitespacesAndNewlines),
            keyID: keyID.trimmingCharacters(in: .whitespacesAndNewlines),
            privateKeyPEM: privateKeyPEM
        )
        guard !credentials.issuerID.isEmpty, !credentials.keyID.isEmpty, credentials.privateKeyPEM.contains("PRIVATE KEY") else {
            throw APIError.invalidCredentials("Enter the issuer ID, key ID, and a valid .p8 private key.")
        }
        showToast("Connecting App Store Connect…", detail: "Signing a short-lived token and fetching apps.", kind: .progress)
        let apps = try await AppStoreConnectClient(credentials: credentials).listApps()
        try CredentialStore.saveApple(credentials)
        prepareLiveWorkspace()
        updateConnection(.appStore, name: "App Store Connect", detail: "Issuer \(credentials.issuerID.suffix(6)) · \(apps.count) apps")
        importApps(apps)
        persist()
        if let selectedAppID { await refreshApp(id: selectedAppID, showFeedback: false) }
        let detail = selectedAppSyncIssues.isEmpty
            ? "Imported \(apps.count) apps and loaded live data for the selected app."
            : "Imported \(apps.count) apps. Some selected-app data needs attention."
        showToast("App Store connected", detail: detail, kind: .success)
        track(.storeConnectionCompleted(
            platform: .appStore,
            result: .success,
            appCountBucket: EscaleAnalyticsEvent.countBucket(apps.count),
            failure: nil
        ))
    }

    public func connectGoogle(serviceAccountData: Data) async throws {
        let decoder = JSONDecoder()
        let credentials: GoogleServiceAccount
        do { credentials = try decoder.decode(GoogleServiceAccount.self, from: serviceAccountData) }
        catch { throw APIError.invalidCredentials("Choose a Google service-account JSON key: \(error.localizedDescription)") }
        guard !credentials.clientEmail.isEmpty, credentials.privateKey.contains("PRIVATE KEY"), !credentials.tokenURI.isEmpty else {
            throw APIError.invalidCredentials("The service-account JSON is missing its email, private key, or token URI.")
        }
        showToast("Connecting Google Play…", detail: "Exchanging a signed service-account assertion.", kind: .progress)
        try await GooglePlayClient(credentials: credentials).validateCredentials()
        try CredentialStore.saveGoogle(credentials)
        prepareLiveWorkspace()
        updateConnection(.playStore, name: credentials.projectID ?? "Google Play", detail: credentials.clientEmail)
        persist()
        showToast("Google credentials verified", detail: "Add a package name to verify Play Console access.", kind: .success)
        track(.storeConnectionCompleted(
            platform: .playStore,
            result: .success,
            appCountBucket: nil,
            failure: nil
        ))
    }

    public func disconnect(_ platform: StorePlatform) throws {
        try CredentialStore.remove(platform)
        if let index = workspace.connections.firstIndex(where: { $0.platform == platform }) {
            workspace.connections[index] = StoreConnection(platform: platform, accountName: platform.rawValue, detail: "Not connected", state: .disconnected, lastSync: nil)
        }
        persist()
    }

    public func refreshOpenAIConfigurationStatus() {
        do {
            isOpenAIKeyConfigured = try CredentialStore.openAIAPIKey() != nil
        } catch {
            isOpenAIKeyConfigured = false
            showToast("Could not read OpenAI settings", detail: error.localizedDescription, kind: .error)
        }
    }

    public func saveOpenAIAPIKey(_ apiKey: String) throws {
        try CredentialStore.saveOpenAIAPIKey(apiKey)
        isOpenAIKeyConfigured = true
        showToast("OpenAI key saved", detail: "The key is protected by macOS Keychain.", kind: .success)
    }

    public func removeOpenAIAPIKey() throws {
        try CredentialStore.removeOpenAIAPIKey()
        isOpenAIKeyConfigured = false
        showToast("OpenAI key removed", detail: "AI features are now disabled.", kind: .neutral)
    }

    public func testOpenAIConnection() async throws {
        guard let apiKey = try CredentialStore.openAIAPIKey() else { throw OpenAIClientError.missingAPIKey }
        try await OpenAIClient(apiKey: apiKey).validateConnection()
    }

    public func addAndroidPackage(_ packageName: String) async throws {
        let clean = packageName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw APIError.invalidCredentials("Enter an Android package name.") }
        guard !workspace.apps.contains(where: { $0.playStoreApp?.bundleID == clean }) else {
            throw APIError.unsupported("\(clean) is already in this workspace.")
        }
        if isDemoMode {
            addDemoAndroidPackage(clean)
            return
        }
        guard let credentials = try CredentialStore.google() else { throw APIError.missingCredentials(.playStore) }
        showToast("Verifying \(clean)…", detail: "Reading the live Google Play listing.", kind: .progress)
        let snapshot = try await GooglePlayClient(credentials: credentials).fetchSnapshot(packageName: clean)
        merge(snapshot)
        persist()
        showToast("Google Play app added", detail: "\(snapshot.app.name) is synced and ready.", kind: .success)
    }

    public func addAndLinkAndroidPackage(_ packageName: String, to appStoreAppID: UUID) async throws {
        let clean = packageName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw APIError.invalidCredentials("Enter an Android package name.") }
        guard let source = workspace.apps.first(where: { $0.id == appStoreAppID }),
              source.appStoreApp != nil else {
            throw APIError.unsupported("Choose an imported iOS app before linking Google Play.")
        }
        guard source.playStoreApp == nil else {
            throw APIError.unsupported("\(source.name) is already linked to Google Play.")
        }

        if let existing = workspace.apps.first(where: { $0.playStoreApp?.bundleID == clean }) {
            link(appStoreApp: appStoreAppID, toPlayStoreApp: existing.id)
            selectedAppID = appStoreAppID
            showToast("Android app linked", detail: "\(clean) is now part of this product workspace.", kind: .success)
            return
        }

        showToast("Fetching \(clean)…", detail: "Verifying access and loading the live Google Play workspace.", kind: .progress)
        if isDemoMode {
            let app = StoreApp(
                id: UUID(), platform: .playStore,
                name: clean.split(separator: ".").last.map(String.init)?.capitalized ?? clean,
                bundleID: clean, storeID: clean, version: "Draft", state: .draft,
                versionID: nil, appInfoID: nil
            )
            merge(
                StoreSnapshot(app: app, localizations: [], screenshots: [], products: [], reviews: []),
                preferredAppID: appStoreAppID
            )
        } else {
            guard let credentials = try CredentialStore.google() else { throw APIError.missingCredentials(.playStore) }
            let snapshot = try await GooglePlayClient(credentials: credentials).fetchSnapshot(packageName: clean)
            merge(snapshot, preferredAppID: appStoreAppID)
            appSyncIssues[appStoreAppID] = snapshot.warnings.map { "Google Play: \($0)" }
        }
        selectedAppID = appStoreAppID
        loadedAppIDs.insert(appStoreAppID)
        markConnectionSynced(.playStore)
        persist()
        showToast("Android app linked", detail: "\(clean) and its live Play data are ready in this workspace.", kind: .success)
        track(.applicationLinked(result: .success))
    }

    public func link(appStoreApp sourceID: UUID, toPlayStoreApp targetID: UUID) {
        guard let sourceIndex = workspace.apps.firstIndex(where: { $0.id == sourceID }),
              let targetIndex = workspace.apps.firstIndex(where: { $0.id == targetID }),
              let android = workspace.apps[targetIndex].playStoreApp else { return }
        workspace.apps[sourceIndex].playStoreApp = android
        if sourceIndex != targetIndex {
            let target = workspace.apps[targetIndex]
            workspace.apps.remove(at: targetIndex)
            mergeContent(from: target.id, into: sourceID)
            if loadedAppIDs.remove(target.id) != nil { loadedAppIDs.insert(sourceID) }
            let targetIssues = appSyncIssues.removeValue(forKey: target.id) ?? []
            if !targetIssues.isEmpty { appSyncIssues[sourceID, default: []].append(contentsOf: targetIssues) }
            if selectedAppID == target.id { selectedAppID = sourceID }
        }
        persist()
        track(.applicationLinked(result: .success))
    }

    public func localizationBinding(id: UUID) -> Binding<ListingLocalization> {
        Binding(
            get: { [weak self] in
                guard let self, let appID = self.selectedAppID,
                      let item = self.workspace.localizationsByApp[appID]?.first(where: { $0.id == id }) else {
                    return ListingLocalization(
                        id: id, locale: "", language: "", title: "", subtitle: "", promotionalText: "",
                        description: "", keywords: "", releaseNotes: "", dirtyPlatforms: [], lastSaved: nil,
                        appleVersionLocalizationID: nil, appleAppInfoLocalizationID: nil, googleLanguage: nil
                    )
                }
                return listingLocalization(item, displaying: self.selectedEditingPlatforms)
            },
            set: { [weak self] updated in
                guard let self, let appID = self.selectedAppID,
                      let index = self.workspace.localizationsByApp[appID]?.firstIndex(where: { $0.id == id }) else { return }
                let available = self.availablePlatforms(for: appID)
                let targets = self.platformFilter.platforms.intersection(available)
                let stored = self.workspace.localizationsByApp[appID]![index]
                var copy = applyingListingMetadata(from: updated, to: stored, platforms: targets)
                copy.dirtyPlatforms.formUnion(targets)
                self.workspace.localizationsByApp[appID]?[index] = copy
                self.scheduleEditorPersistence()
            }
        )
    }

    public func googlePlayReleaseNoteLocale(for localization: ListingLocalization) -> String {
        localization.googleLanguage ?? googleLocale(forAppleLocale: localization.locale)
    }

    public func googlePlayReleaseNoteBinding(locale: String) -> Binding<String> {
        Binding(
            get: { [weak self] in
                guard let self else { return "" }
                return googlePlayReleaseNote(in: self.selectedGooglePlayReleaseNotesBlock, locale: locale)
            },
            set: { [weak self] text in
                self?.setGooglePlayReleaseNote(text, locale: locale)
            }
        )
    }

    public func googlePlayReleaseNotesBlockBinding() -> Binding<String> {
        Binding(
            get: { [weak self] in self?.selectedGooglePlayReleaseNotesBlock ?? "" },
            set: { [weak self] block in
                guard let self, let appID = self.selectedAppID else { return }
                if self.workspace.googlePlayReleaseNotesByApp == nil {
                    self.workspace.googlePlayReleaseNotesByApp = [:]
                }
                self.workspace.googlePlayReleaseNotesByApp?[appID] = block
                self.scheduleEditorPersistence()
            }
        )
    }

    public func translateGooglePlayReleaseNotes(from sourceLocale: String, to targetLocale: String? = nil) async {
        if targetLocale == nil {
            guard requireAccess(to: .bulkTranslations) else { return }
        }
        guard let appID = selectedAppID else { return }
        let sourceText = googlePlayReleaseNote(in: selectedGooglePlayReleaseNotesBlock, locale: sourceLocale)
        guard !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showToast("Nothing to translate", detail: "Add the primary Google Play release note first.", kind: .error)
            return
        }

        let localizations = workspace.localizationsByApp[appID, default: []]
        let targets = localizations.filter { localization in
            let locale = googlePlayReleaseNoteLocale(for: localization)
            guard canonicalStoreLocale(locale) != canonicalStoreLocale(sourceLocale) else { return false }
            guard let targetLocale else { return true }
            return canonicalStoreLocale(locale) == canonicalStoreLocale(targetLocale)
        }
        guard !targets.isEmpty else {
            showToast("No target locales", detail: "Add another Google Play listing language first.", kind: .neutral)
            return
        }

        do {
            guard let apiKey = try CredentialStore.openAIAPIKey() else { throw OpenAIClientError.missingAPIKey }
            let client = OpenAIClient(apiKey: apiKey)
            showToast(
                "Translating Google Play release notes…",
                detail: "Preparing \(targets.count) tagged locale\(targets.count == 1 ? "" : "s") from the primary note.",
                kind: .progress
            )
            var completed = 0
            var failures: [String] = []
            for (offset, target) in targets.enumerated() {
                let locale = googlePlayReleaseNoteLocale(for: target)
                do {
                    let translation = try await client.translateField(
                        sourceText: sourceText,
                        field: .releaseNotes,
                        sourceLocale: sourceLocale,
                        targetLocale: locale,
                        targetLanguage: target.language,
                        characterLimit: googlePlayReleaseNoteCharacterLimit,
                        platforms: [.playStore]
                    )
                    setGooglePlayReleaseNote(translation, locale: locale)
                    completed += 1
                } catch {
                    failures.append("\(target.language): \(error.localizedDescription)")
                }
                if offset + 1 < targets.count {
                    showToast(
                        "Translating Google Play release notes…",
                        detail: "Completed \(offset + 1) of \(targets.count). Next: \(targets[offset + 1].language).",
                        kind: .progress
                    )
                }
            }

            if failures.isEmpty {
                showToast(
                    "Tagged release notes ready",
                    detail: "Generated and saved \(completed) translation\(completed == 1 ? "" : "s") locally. Copy the complete block into your Play release.",
                    kind: .success
                )
            } else {
                showToast(
                    "Translated \(completed) of \(targets.count) locales",
                    detail: "Completed translations were kept locally. \(failures[0])",
                    kind: .error
                )
            }
            track(.translationCompleted(
                kind: .releaseNotes,
                scope: targetLocale == nil ? .bulk : .single,
                result: failures.isEmpty ? .success : (completed > 0 ? .partial : .failure),
                targetCountBucket: EscaleAnalyticsEvent.countBucket(targets.count),
                failure: failures.isEmpty ? nil : .remoteAPI
            ))
        } catch {
            showToast("Translation failed", detail: error.localizedDescription, kind: .error)
            track(.translationCompleted(
                kind: .releaseNotes,
                scope: targetLocale == nil ? .bulk : .single,
                result: .failure,
                targetCountBucket: EscaleAnalyticsEvent.countBucket(targets.count),
                failure: EscaleAnalyticsEvent.failureCategory(for: error)
            ))
        }
    }

    private func setGooglePlayReleaseNote(_ text: String, locale: String) {
        guard let appID = selectedAppID else { return }
        let block = replacingGooglePlayReleaseNote(
            in: workspace.googlePlayReleaseNotesByApp?[appID] ?? "",
            locale: locale,
            text: text,
            orderedLocales: googlePlayReleaseNoteLocales(appID: appID)
        )
        if workspace.googlePlayReleaseNotesByApp == nil {
            workspace.googlePlayReleaseNotesByApp = [:]
        }
        workspace.googlePlayReleaseNotesByApp?[appID] = block
        scheduleEditorPersistence()
    }

    private func googlePlayReleaseNoteLocales(appID: UUID) -> [String] {
        var seen: Set<String> = []
        return workspace.localizationsByApp[appID, default: []].compactMap { localization in
            let locale = googlePlayReleaseNoteLocale(for: localization)
            return seen.insert(canonicalStoreLocale(locale)).inserted ? locale : nil
        }
    }

    public func addLocalization(locale: String, language: String) {
        guard let appID = selectedAppID,
              workspace.localizationsByApp[appID]?.contains(where: { $0.locale.caseInsensitiveCompare(locale) == .orderedSame }) != true else { return }
        let source = workspace.localizationsByApp[appID]?.first(where: { $0.locale.lowercased().hasPrefix("en") })
        let localization = ListingLocalization(
            id: UUID(), locale: locale, language: language,
            title: source?.title ?? selectedApp?.name ?? "", subtitle: "", promotionalText: "", description: "", keywords: "", releaseNotes: "",
            dirtyPlatforms: availablePlatforms(for: appID), lastSaved: nil,
            appleVersionLocalizationID: nil, appleAppInfoLocalizationID: nil, googleLanguage: googleLocale(forAppleLocale: locale),
            googleTitle: source?.googleTitle ?? source?.title ?? selectedApp?.name ?? "",
            googleSubtitle: "",
            googleDescription: ""
        )
        workspace.localizationsByApp[appID, default: []].append(localization)
        persist()
        showToast("Localization added", detail: "Complete the \(language) copy, then publish it to the stores.", kind: .success)
    }

    public func translateLocalization(id: UUID, from sourceID: UUID) async {
        guard let appID = selectedAppID,
              let storedSource = workspace.localizationsByApp[appID]?.first(where: { $0.id == sourceID }),
              let target = workspace.localizationsByApp[appID]?.first(where: { $0.id == id }) else { return }
        do {
            guard let apiKey = try CredentialStore.openAIAPIKey() else { throw OpenAIClientError.missingAPIKey }
            let targetPlatforms = platformFilter.platforms.intersection(availablePlatforms(for: appID))
            let source = listingLocalization(storedSource, displaying: targetPlatforms)
            let limits = OpenAITranslationLimits.storeListing(platforms: targetPlatforms)
            showToast(
                "Translating \(source.language) to \(target.language)…",
                detail: "Sending the listing directly to OpenAI and preserving store limits.",
                kind: .progress
            )
            let translation = try await OpenAIClient(apiKey: apiKey).translate(
                source: source,
                targetLocale: target.locale,
                targetLanguage: target.language,
                limits: limits
            )
            guard let targetIndex = workspace.localizationsByApp[appID]?.firstIndex(where: { $0.id == id }) else { return }
            let storedTarget = workspace.localizationsByApp[appID]![targetIndex]
            var displayedTarget = listingLocalization(storedTarget, displaying: targetPlatforms)
            displayedTarget.title = translation.title
            displayedTarget.subtitle = translation.subtitle
            displayedTarget.promotionalText = translation.promotionalText
            displayedTarget.description = translation.description
            displayedTarget.keywords = translation.keywords
            displayedTarget.releaseNotes = translation.releaseNotes
            var updated = applyingListingMetadata(
                from: displayedTarget,
                to: storedTarget,
                platforms: targetPlatforms
            )
            updated.dirtyPlatforms.formUnion(targetPlatforms)
            workspace.localizationsByApp[appID]?[targetIndex] = updated
            persist()
            showToast("Translation ready", detail: "Review the copy before publishing it to the stores.", kind: .success)
            track(.translationCompleted(
                kind: .listing,
                scope: .single,
                result: .success,
                targetCountBucket: "1",
                failure: nil
            ))
        } catch {
            showToast("Translation failed", detail: error.localizedDescription, kind: .error)
            track(.translationCompleted(
                kind: .listing,
                scope: .single,
                result: .failure,
                targetCountBucket: "1",
                failure: EscaleAnalyticsEvent.failureCategory(for: error)
            ))
        }
    }

    public func translateField(_ field: ListingMetadataField, from sourceID: UUID, to targetID: UUID) async {
        await translateField(field, from: sourceID, to: [targetID], announcesAllLocales: false)
    }

    public func translateFieldToAllLocales(_ field: ListingMetadataField, from sourceID: UUID) async {
        guard requireAccess(to: .bulkTranslations) else { return }
        guard let appID = selectedAppID else { return }
        let targetIDs = workspace.localizationsByApp[appID, default: []]
            .filter { $0.id != sourceID }
            .map(\.id)
        await translateField(field, from: sourceID, to: targetIDs, announcesAllLocales: true)
    }

    private func translateField(
        _ field: ListingMetadataField,
        from sourceID: UUID,
        to targetIDs: [UUID],
        announcesAllLocales: Bool
    ) async {
        guard let appID = selectedAppID,
              let storedSource = workspace.localizationsByApp[appID]?.first(where: { $0.id == sourceID }) else { return }
        let targetPlatforms = platformFilter.platforms.intersection(availablePlatforms(for: appID))
        let source = listingLocalization(storedSource, displaying: targetPlatforms)
        let sourceText = field.value(in: source)
        guard !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showToast("Nothing to translate", detail: "Add \(field.displayName.lowercased()) in the primary locale first.", kind: .error)
            return
        }
        let targets = targetIDs.compactMap { targetID in
            workspace.localizationsByApp[appID]?.first(where: { $0.id == targetID })
        }
        guard !targets.isEmpty else {
            showToast("No target locales", detail: "Add another localization before translating \(field.displayName.lowercased()).", kind: .neutral)
            return
        }

        do {
            guard let apiKey = try CredentialStore.openAIAPIKey() else { throw OpenAIClientError.missingAPIKey }
            guard !targetPlatforms.isEmpty else {
                throw APIError.unsupported("Select a connected store before translating metadata.")
            }
            let metadataLimits = ListingMetadataLimits(platforms: targetPlatforms)
            let characterLimit = field.characterLimit(in: metadataLimits)
            let client = OpenAIClient(apiKey: apiKey)
            let progressDetail = announcesAllLocales
                ? "Translating from \(source.language) into \(targets.count) locale\(targets.count == 1 ? "" : "s")."
                : "Translating from the \(source.language) primary listing."
            showToast("Translating \(field.displayName)…", detail: progressDetail, kind: .progress)

            var translatedCount = 0
            var failures: [String] = []
            for (offset, target) in targets.enumerated() {
                do {
                    let translatedText = try await client.translateField(
                        sourceText: sourceText,
                        field: field,
                        sourceLocale: source.locale,
                        targetLocale: target.locale,
                        targetLanguage: target.language,
                        characterLimit: characterLimit,
                        platforms: targetPlatforms
                    )
                    guard let targetIndex = workspace.localizationsByApp[appID]?.firstIndex(where: { $0.id == target.id }) else {
                        failures.append(target.language)
                        continue
                    }
                    let storedTarget = workspace.localizationsByApp[appID]![targetIndex]
                    var displayedTarget = listingLocalization(storedTarget, displaying: targetPlatforms)
                    field.set(translatedText, in: &displayedTarget)
                    var updated = applyingListingMetadata(
                        from: displayedTarget,
                        to: storedTarget,
                        platforms: targetPlatforms
                    )
                    updated.dirtyPlatforms.formUnion(targetPlatforms)
                    workspace.localizationsByApp[appID]?[targetIndex] = updated
                    translatedCount += 1
                } catch {
                    failures.append("\(target.language): \(error.localizedDescription)")
                }
                if offset + 1 < targets.count {
                    showToast(
                        "Translating \(field.displayName)…",
                        detail: "Completed \(offset + 1) of \(targets.count) locales. Next: \(targets[offset + 1].language).",
                        kind: .progress
                    )
                }
            }

            if translatedCount > 0 { persist() }
            if failures.isEmpty {
                let targetDescription = translatedCount == 1 ? "the selected locale" : "all \(translatedCount) locales"
                showToast(
                    "\(field.displayName) translated",
                    detail: "Updated \(targetDescription). Review the draft copy before saving it to the stores.",
                    kind: .success
                )
            } else {
                let firstFailure = failures.first ?? "Unknown error"
                showToast(
                    "Translated \(translatedCount) of \(targets.count) locales",
                    detail: "The completed drafts were kept. \(firstFailure)",
                    kind: .error
                )
            }
            track(.translationCompleted(
                kind: .field,
                scope: announcesAllLocales ? .bulk : .single,
                result: failures.isEmpty ? .success : (translatedCount > 0 ? .partial : .failure),
                targetCountBucket: EscaleAnalyticsEvent.countBucket(targets.count),
                failure: failures.isEmpty ? nil : .remoteAPI
            ))
        } catch {
            showToast("Translation failed", detail: error.localizedDescription, kind: .error)
            track(.translationCompleted(
                kind: .field,
                scope: announcesAllLocales ? .bulk : .single,
                result: .failure,
                targetCountBucket: EscaleAnalyticsEvent.countBucket(targets.count),
                failure: EscaleAnalyticsEvent.failureCategory(for: error)
            ))
        }
    }

    public func createAppStoreVersion(_ versionString: String) async -> Bool {
        guard entitlements.plan == .pro else {
            track(.proGateViewed(feature: .createAppStoreVersion))
            showToast(
                "Escale Pro required",
                detail: EscaleFeature.createAppStoreVersion.upgradeDescription,
                kind: .neutral
            )
            return false
        }
        guard let appID = selectedAppID,
              let appIndex = workspace.apps.firstIndex(where: { $0.id == appID }),
              let appleApp = workspace.apps[appIndex].appStoreApp else { return false }
        do {
            guard !isDemoMode else { throw APIError.unsupported("Creating remote versions is unavailable in demo mode.") }
            guard let credentials = try CredentialStore.apple() else { throw APIError.missingCredentials(.appStore) }
            let pendingLocalizationCount = workspace.localizationsByApp[appID, default: []]
                .filter { $0.dirtyPlatforms.contains(.appStore) }
                .count
            let pendingDetail = pendingLocalizationCount == 0
                ? "Loading the previous promotional text."
                : "Keeping \(pendingLocalizationCount) pending localization change\(pendingLocalizationCount == 1 ? "" : "s") for the new draft."
            showToast(
                "Creating version \(versionString)…",
                detail: "Creating an editable App Store draft. \(pendingDetail)",
                kind: .progress
            )
            let draft = try await AppStoreConnectClient(credentials: credentials).createVersion(for: appleApp, versionString: versionString)
            workspace.apps[appIndex].appStoreApp = draft.app
            workspace.localizationsByApp[appID] = localizationsAfterCreatingAppStoreVersion(
                cached: workspace.localizationsByApp[appID, default: []],
                draft: draft.localizations
            )
            workspace.screenshotsByApp[appID, default: []].removeAll(where: { $0.platform == .appStore })
            workspace.screenshotsByApp[appID, default: []].append(contentsOf: draft.screenshots)
            loadedAppIDs.insert(appID)
            persist()
            let successDetail = pendingLocalizationCount == 0
                ? "The draft is editable. It has not been submitted for review."
                : "Your pending localization changes are preserved and can now be saved. The draft was not submitted for review."
            showToast("Version \(draft.app.version) created", detail: successDetail, kind: .success)
            return true
        } catch {
            showError(error)
            return false
        }
    }

    public func createGooglePlayDraftRelease(
        bundleFileURL: URL,
        track: String,
        releaseName: String
    ) async -> Bool {
        guard entitlements.plan == .pro else {
            self.track(.proGateViewed(feature: .uploadGooglePlayBundle))
            showToast(
                "Escale Pro required",
                detail: EscaleFeature.uploadGooglePlayBundle.upgradeDescription,
                kind: .neutral
            )
            return false
        }
        guard let appID = selectedAppID,
              let appIndex = workspace.apps.firstIndex(where: { $0.id == appID }),
              var googleApp = workspace.apps[appIndex].playStoreApp else { return false }

        let access = bundleFileURL.startAccessingSecurityScopedResource()
        defer {
            if access { bundleFileURL.stopAccessingSecurityScopedResource() }
        }

        do {
            guard !isDemoMode else {
                throw APIError.unsupported("Uploading remote Android bundles is unavailable in demo mode.")
            }
            guard bundleFileURL.pathExtension.caseInsensitiveCompare("aab") == .orderedSame else {
                throw APIError.invalidCredentials("Choose a signed Android App Bundle with the .aab extension.")
            }
            let resourceValues = try bundleFileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard resourceValues.isRegularFile == true, (resourceValues.fileSize ?? 0) > 0 else {
                throw APIError.invalidCredentials("The selected Android App Bundle is empty or unreadable.")
            }
            guard let credentials = try CredentialStore.google() else {
                throw APIError.missingCredentials(.playStore)
            }

            let taggedReleaseNotes = workspace.googlePlayReleaseNotesByApp?[appID] ?? ""
            let releaseNotes: [StoreVersionReleaseNote]
            if googlePlayReleaseNotesValidationIssues(taggedReleaseNotes).isEmpty {
                releaseNotes = googlePlayReleaseNotes(in: taggedReleaseNotes)
                    .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .map { StoreVersionReleaseNote(language: $0.locale, text: $0.text) }
            } else {
                releaseNotes = []
            }

            showToast(
                "Preparing Android bundle…",
                detail: "Google Play will validate the package, signing key, and version code.",
                kind: .progress
            )
            let result = try await GooglePlayClient(credentials: credentials).createDraftRelease(
                bundleFileURL: bundleFileURL,
                packageName: googleApp.bundleID,
                track: track,
                releaseName: releaseName,
                releaseNotes: releaseNotes
            ) { [weak self] progress in
                self?.showToast(
                    "Uploading Android bundle…",
                    detail: progress.detail,
                    kind: .progress
                )
            }

            googleApp.version = "build \(result.versionCode)"
            googleApp.state = .draft
            googleApp.remoteState = "draft"
            googleApp.versionDetails = StoreVersionDetails(
                track: result.track,
                releaseName: result.releaseName,
                versionCodes: [String(result.versionCode)],
                releaseNotes: result.releaseNotes,
                bundleSHA1: result.sha1,
                bundleSHA256: result.sha256
            )
            workspace.apps[appIndex].playStoreApp = googleApp
            loadedAppIDs.insert(appID)
            persist()
            showToast(
                "Android draft \(result.versionCode) created",
                detail: "The signed bundle is on \(result.track) as a draft. It has not been submitted for review or released.",
                kind: .success
            )
            return true
        } catch {
            showError(error)
            return false
        }
    }

    public func saveLocalization(id: UUID) async {
        guard let appID = selectedAppID,
              let app = workspace.apps.first(where: { $0.id == appID }),
              let index = workspace.localizationsByApp[appID]?.firstIndex(where: { $0.id == id }) else { return }
        var localization = workspace.localizationsByApp[appID]![index]
        let targets = localization.dirtyPlatforms
        guard !targets.isEmpty else {
            showToast("Everything is up to date", detail: "No local changes to publish.", kind: .neutral)
            return
        }
        let violations = targets.flatMap { platform -> [String] in
            let platformSet: Set<StorePlatform> = [platform]
            let displayed = listingLocalization(localization, displaying: platformSet)
            return ListingMetadataLimits(platforms: platformSet)
                .violations(in: displayed, platforms: platformSet)
                .map { "\(platform.shortName): \($0)" }
        }
        guard violations.isEmpty else {
            showToast("Metadata is over the store limit", detail: violations.joined(separator: " · "), kind: .error)
            return
        }
        if isDemoMode {
            try? await Task.sleep(for: .milliseconds(500))
            localization.dirtyPlatforms = []
            localization.lastSaved = Date()
            workspace.localizationsByApp[appID]?[index] = localization
            persist()
            showToast("Demo listing updated", detail: "No remote store was changed in demo mode.", kind: .success)
            return
        }
        showToast("Publishing changes…", detail: targets.map(\.rawValue).sorted().joined(separator: " and "), kind: .progress)
        var completed: Set<StorePlatform> = []
        var googleCommitDisposition: GoogleEditCommitDisposition?
        do {
            if targets.contains(.appStore), let appleApp = app.appStoreApp {
                guard let credentials = try CredentialStore.apple() else { throw APIError.missingCredentials(.appStore) }
                localization = try await AppStoreConnectClient(credentials: credentials).saveLocalization(localization, app: appleApp)
                completed.insert(.appStore)
            }
            if targets.contains(.playStore), let googleApp = app.playStoreApp {
                guard let credentials = try CredentialStore.google() else { throw APIError.missingCredentials(.playStore) }
                let googleLocalization = listingLocalization(localization, displaying: [.playStore])
                googleCommitDisposition = try await GooglePlayClient(credentials: credentials).saveLocalization(
                    googleLocalization,
                    packageName: googleApp.bundleID
                )
                completed.insert(.playStore)
            }
            localization.dirtyPlatforms.subtract(completed)
            localization.lastSaved = Date()
            workspace.localizationsByApp[appID]?[index] = localization
            persist()
            showToast(
                "Listing saved",
                detail: listingSaveSuccessDetail(
                    completed: completed,
                    googleCommitDisposition: googleCommitDisposition
                ),
                kind: .success
            )
            track(.listingSaveCompleted(
                scope: EscaleAnalyticsEvent.scope(for: completed),
                result: .success,
                failure: nil
            ))
        } catch {
            localization.dirtyPlatforms.subtract(completed)
            workspace.localizationsByApp[appID]?[index] = localization
            persist()
            showError(error)
            track(.listingSaveCompleted(
                scope: EscaleAnalyticsEvent.scope(for: targets),
                result: completed.isEmpty ? .failure : .partial,
                failure: EscaleAnalyticsEvent.failureCategory(for: error)
            ))
        }
    }

    private func listingSaveSuccessDetail(
        completed: Set<StorePlatform>,
        googleCommitDisposition: GoogleEditCommitDisposition?
    ) -> String {
        if googleCommitDisposition == .sentForReviewAutomatically {
            let appleDetail = completed.contains(.appStore)
                ? " Apple metadata was saved without submitting the App Store version."
                : ""
            return "Google Play accepted the metadata and sent the edit for review automatically, as required by this Play account.\(appleDetail)"
        }
        if completed == [.playStore] {
            return "Google Play accepted the metadata and kept the edit out of review."
        }
        return "The remote stores accepted the metadata. Escale did not submit it for review."
    }

    public func uploadScreenshot(fileURL: URL, locale: String, device: String) async {
        guard let appID = selectedAppID, let app = selectedApp else { return }
        let access = fileURL.startAccessingSecurityScopedResource()
        defer { if access { fileURL.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: fileURL)
            let mimeType = fileURL.pathExtension.lowercased() == "png" ? "image/png" : "image/jpeg"
            let targets = platformFilter.platforms.intersection(availablePlatforms(for: appID))
            showToast("Uploading screenshot…", detail: targets.map(\.rawValue).joined(separator: " and "), kind: .progress)
            if isDemoMode {
                workspace.screenshotsByApp[appID, default: []].append(StoreScreenshot(id: UUID(), platform: targets.first ?? .appStore, locale: locale, device: "Phone", title: fileURL.deletingPathExtension().lastPathComponent, caption: "Local preview", gradientStartHex: 0x5367D8, gradientEndHex: 0x9F74E8, remoteID: nil, remoteURL: fileURL.absoluteString, screenshotSetID: nil))
            } else {
                if targets.contains(.appStore), let localization = workspace.localizationsByApp[appID]?.first(where: { $0.locale == locale }) {
                    guard let credentials = try CredentialStore.apple() else { throw APIError.missingCredentials(.appStore) }
                    let existingSet = workspace.screenshotsByApp[appID]?.first(where: { $0.platform == .appStore && $0.locale == locale })?.screenshotSetID
                    let displayType = switch device {
                    case "Tablet": "APP_IPAD_PRO_3GEN_129"
                    case "Desktop": "APP_DESKTOP"
                    case "TV": "APP_APPLE_TV"
                    default: "APP_IPHONE_67"
                    }
                    try await AppStoreConnectClient(credentials: credentials).uploadScreenshot(data: data, fileName: fileURL.lastPathComponent, localization: localization, existingSetID: existingSet, displayType: displayType)
                }
                if targets.contains(.playStore), let playApp = app.playStoreApp {
                    guard let credentials = try CredentialStore.google() else { throw APIError.missingCredentials(.playStore) }
                    let playLanguage = workspace.localizationsByApp[appID]?
                        .first(where: { canonicalStoreLocale($0.locale) == canonicalStoreLocale(locale) })?
                        .googleLanguage
                        ?? googleLocale(forAppleLocale: locale)
                    let imageType = switch device {
                    case "Tablet": "tenInchScreenshots"
                    case "TV": "tvScreenshots"
                    default: "phoneScreenshots"
                    }
                    try await GooglePlayClient(credentials: credentials).uploadScreenshot(
                        data: data,
                        fileName: fileURL.lastPathComponent,
                        mimeType: mimeType,
                        packageName: playApp.bundleID,
                        language: playLanguage,
                        imageType: imageType
                    )
                }
                await sync(appID: appID, platforms: targets)
            }
            persist()
            showToast("Screenshot uploaded", detail: "The selected stores accepted the asset.", kind: .success)
            track(.screenshotOperationCompleted(
                operation: .upload,
                scope: EscaleAnalyticsEvent.scope(for: targets),
                result: .success,
                failure: nil
            ))
        } catch {
            showError(error)
            track(.screenshotOperationCompleted(
                operation: .upload,
                scope: EscaleAnalyticsEvent.scope(
                    for: platformFilter.platforms.intersection(availablePlatforms(for: appID))
                ),
                result: .failure,
                failure: EscaleAnalyticsEvent.failureCategory(for: error)
            ))
        }
    }

    public func deleteScreenshot(_ id: UUID) {
        guard let appID = selectedAppID,
              let screenshot = workspace.screenshotsByApp[appID]?.first(where: { $0.id == id }) else { return }
        if isDemoMode || screenshot.remoteID == nil {
            workspace.screenshotsByApp[appID]?.removeAll(where: { $0.id == id })
            persist()
            track(.screenshotOperationCompleted(
                operation: .delete,
                scope: screenshot.platform == .appStore ? .apple : .google,
                result: .success,
                failure: nil
            ))
            return
        }
        Task {
            do {
                guard let remoteID = screenshot.remoteID else { return }
                if screenshot.platform == .appStore {
                    guard let credentials = try CredentialStore.apple() else { throw APIError.missingCredentials(.appStore) }
                    try await AppStoreConnectClient(credentials: credentials).deleteScreenshot(remoteID: remoteID)
                } else {
                    guard let credentials = try CredentialStore.google(), let package = selectedApp?.playStoreApp?.bundleID else { throw APIError.missingCredentials(.playStore) }
                    try await GooglePlayClient(credentials: credentials).deleteScreenshot(remoteID: remoteID, packageName: package, language: screenshot.locale, imageType: screenshot.screenshotSetID ?? "phoneScreenshots")
                }
                workspace.screenshotsByApp[appID]?.removeAll(where: { $0.id == id })
                persist()
                showToast("Screenshot deleted", detail: "The remote store was updated.", kind: .success)
                track(.screenshotOperationCompleted(
                    operation: .delete,
                    scope: screenshot.platform == .appStore ? .apple : .google,
                    result: .success,
                    failure: nil
                ))
            } catch {
                showError(error)
                track(.screenshotOperationCompleted(
                    operation: .delete,
                    scope: screenshot.platform == .appStore ? .apple : .google,
                    result: .failure,
                    failure: EscaleAnalyticsEvent.failureCategory(for: error)
                ))
            }
        }
    }

    public func productBinding(id: UUID) -> Binding<StoreProduct> {
        Binding(
            get: { [weak self] in
                guard let self, let appID = self.selectedAppID,
                      let product = self.workspace.productsByApp[appID]?.first(where: { $0.id == id }) else {
                    return StoreProduct(
                        id: id, name: "", productID: "", kind: "", basePrice: 0,
                        platforms: [], regions: [], appleProductID: nil, googleProductID: nil, googleBasePlanID: nil
                    )
                }
                return product
            },
            set: { [weak self] updated in
                guard let self, let appID = self.selectedAppID,
                      let index = self.workspace.productsByApp[appID]?.firstIndex(where: { $0.id == id }) else { return }
                self.workspace.productsByApp[appID]?[index] = updated
                self.persist()
            }
        )
    }

    public func recalculatePPP(productID: UUID) {
        guard let appID = selectedAppID,
              let index = workspace.productsByApp[appID]?.firstIndex(where: { $0.id == productID }) else { return }
        let base = workspace.productsByApp[appID]![index].basePrice
        for regionIndex in workspace.productsByApp[appID]![index].regions.indices {
            let indexValue = workspace.productsByApp[appID]![index].regions[regionIndex].pppIndex
            workspace.productsByApp[appID]![index].regions[regionIndex].suggestedPrice = roundedCharmPrice(base * indexValue)
        }
        persist()
    }

    public func calculatePPP(productID: UUID) async {
        guard let appID = selectedAppID,
              let app = selectedApp,
              let productIndex = workspace.productsByApp[appID]?.firstIndex(where: { $0.id == productID }),
              !calculatingProductIDs.contains(productID) else { return }
        calculatingProductIDs.insert(productID)
        defer { calculatingProductIDs.remove(productID) }
        var product = workspace.productsByApp[appID]![productIndex]
        showToast("Calculating regional pricing…", detail: "Loading \(product.effectivePricingIndex.title) and every available store market.", kind: .progress)
        do {
            if isDemoMode {
                try await Task.sleep(for: .milliseconds(450))
                for index in product.regions.indices {
                    product.regions[index].suggestedPrice = localizedCharmPrice(product.regions[index].currentPrice * product.regions[index].pppIndex, currency: product.regions[index].currency)
                }
                product.pricingSourceSummary = "Demo pricing data"
            } else {
                let indexResult = try await PricingIndexService().factors(for: product.effectivePricingIndex)
                var calculated: [PriceRegion] = []
                if product.platforms.contains(.playStore), let packageName = app.playStoreApp?.bundleID {
                    guard let credentials = try CredentialStore.google() else { throw APIError.missingCredentials(.playStore) }
                    calculated = try await GooglePlayClient(credentials: credentials)
                        .calculateRegionalPrices(product: product, factors: indexResult.factors, packageName: packageName).regions
                }
                if product.platforms.contains(.appStore), product.appleProductID != nil {
                    guard let credentials = try CredentialStore.apple() else { throw APIError.missingCredentials(.appStore) }
                    let appleCalculation = try await AppStoreConnectClient(credentials: credentials)
                        .calculateRegionalPrices(product: product, factors: indexResult.factors)
                    product.basePrice = appleCalculation.resolvedBasePrice
                    let existingCodes = Set(calculated.map(\.code))
                    calculated.append(contentsOf: appleCalculation.regions.filter { !existingCodes.contains($0.code) })
                }
                guard !calculated.isEmpty else { throw APIError.unsupported("No store returned regional pricing data for this product.") }
                product.regions = calculated.sorted { $0.country < $1.country }
                product.pricingSourceSummary = indexResult.sourceSummary
            }
            product.pricingCalculatedAt = Date()
            workspace.productsByApp[appID]?[productIndex] = product
            persist()
            showToast("Pricing calculated", detail: "Prepared \(product.regions.count) available markets. Review them before applying.", kind: .success)
            track(.pricingPreviewCompleted(
                index: product.effectivePricingIndex,
                result: .success,
                marketCountBucket: EscaleAnalyticsEvent.countBucket(product.regions.count),
                failure: nil
            ))
        } catch {
            showError(error)
            track(.pricingPreviewCompleted(
                index: product.effectivePricingIndex,
                result: .failure,
                marketCountBucket: "0",
                failure: EscaleAnalyticsEvent.failureCategory(for: error)
            ))
        }
    }

    public func applyPPP(productID: UUID) async {
        guard requireAccess(to: .applyRegionalPricing) else { return }
        guard let appID = selectedAppID,
              let app = selectedApp,
              let index = workspace.productsByApp[appID]?.firstIndex(where: { $0.id == productID }) else { return }
        let product = workspace.productsByApp[appID]![index]
        guard product.pricingCalculatedAt != nil else {
            showToast("Calculate pricing first", detail: "Choose an index and calculate the store-valid regional prices before applying them.", kind: .error)
            return
        }
        pricingApplyProgressByProductID[productID] = PricingApplyProgress(
            platform: product.platforms.contains(.appStore) ? .appStore : .playStore,
            completed: 0,
            total: 1,
            detail: "Validating product catalogs…"
        )
        defer { pricingApplyProgressByProductID.removeValue(forKey: productID) }
        showToast("Scheduling regional prices…", detail: "Validating product catalogs.", kind: .progress)
        if isDemoMode {
            try? await Task.sleep(for: .milliseconds(500))
            for regionIndex in workspace.productsByApp[appID]![index].regions.indices where workspace.productsByApp[appID]![index].regions[regionIndex].enabled {
                workspace.productsByApp[appID]![index].regions[regionIndex].currentPrice = workspace.productsByApp[appID]![index].regions[regionIndex].suggestedPrice
            }
            persist()
            showToast("Prices scheduled", detail: "Demo prices updated locally.", kind: .success)
            track(.pricingApplyCompleted(
                scope: EscaleAnalyticsEvent.scope(for: product.platforms),
                result: .success,
                failure: nil
            ))
            return
        }

        var completed: Set<StorePlatform> = []
        var failures: [String] = []
        if product.platforms.contains(.appStore), product.appleProductID != nil {
            do {
                guard let credentials = try CredentialStore.apple() else { throw APIError.missingCredentials(.appStore) }
                try await AppStoreConnectClient(credentials: credentials).applyRegionalPrices(product: product) { [weak self] progress in
                    self?.updatePricingApplyProgress(productID: productID, progress: progress)
                }
                completed.insert(.appStore)
            } catch { failures.append("App Store: \(error.localizedDescription)") }
        }
        if product.platforms.contains(.playStore), let package = app.playStoreApp?.bundleID {
            do {
                guard let credentials = try CredentialStore.google() else { throw APIError.missingCredentials(.playStore) }
                try await GooglePlayClient(credentials: credentials).applyRegionalPrices(product: product, packageName: package) { [weak self] progress in
                    self?.updatePricingApplyProgress(productID: productID, progress: progress)
                }
                completed.insert(.playStore)
            } catch { failures.append("Google Play: \(error.localizedDescription)") }
        }
        if failures.isEmpty {
            let schedulesAppleSubscription = product.isSubscription && product.platforms.contains(.appStore)
            if !schedulesAppleSubscription {
                for regionIndex in workspace.productsByApp[appID]![index].regions.indices where workspace.productsByApp[appID]![index].regions[regionIndex].enabled {
                    workspace.productsByApp[appID]![index].regions[regionIndex].currentPrice = workspace.productsByApp[appID]![index].regions[regionIndex].suggestedPrice
                }
            }
            workspace.productsByApp[appID]![index].pricingCalculatedAt = nil
            persist()
            let detail = schedulesAppleSubscription
                ? "App Store changes were scheduled two days ahead. Increases preserve existing prices when selected; Apple automatically passes decreases to existing subscribers."
                : "The connected stores accepted the regional catalog."
            showToast(schedulesAppleSubscription ? "Prices scheduled" : "Prices applied", detail: detail, kind: .success)
            track(.pricingApplyCompleted(
                scope: EscaleAnalyticsEvent.scope(for: product.platforms),
                result: .success,
                failure: nil
            ))
        } else if !completed.isEmpty {
            let names = completed.map(\.rawValue).sorted().joined(separator: " and ")
            showToast("Pricing partially applied", detail: names + " succeeded. " + failures.joined(separator: " · "), kind: .error)
            track(.pricingApplyCompleted(
                scope: EscaleAnalyticsEvent.scope(for: product.platforms),
                result: .partial,
                failure: .remoteAPI
            ))
        } else {
            showToast("Pricing was not applied", detail: failures.joined(separator: " · "), kind: .error)
            track(.pricingApplyCompleted(
                scope: EscaleAnalyticsEvent.scope(for: product.platforms),
                result: .failure,
                failure: .remoteAPI
            ))
        }
    }

    private func updatePricingApplyProgress(productID: UUID, progress: PricingApplyProgress) {
        pricingApplyProgressByProductID[productID] = progress
        let countDetail = progress.total > 1 ? " · \(progress.completed) of \(progress.total)" : ""
        showToast(
            "Scheduling \(progress.platform.shortName) prices…",
            detail: progress.detail + countDetail,
            kind: .progress
        )
    }

    public func reply(to reviewID: UUID, text: String) async {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let appID = selectedAppID,
              let app = selectedApp,
              let index = workspace.reviewsByApp[appID]?.firstIndex(where: { $0.id == reviewID }) else { return }
        var review = workspace.reviewsByApp[appID]![index]
        showToast("Sending reply…", detail: "Publishing to \(review.platform.rawValue).", kind: .progress)
        do {
            if isDemoMode { try? await Task.sleep(for: .milliseconds(500)) }
            else if review.platform == .appStore {
                guard let credentials = try CredentialStore.apple() else { throw APIError.missingCredentials(.appStore) }
                review.responseRemoteID = try await AppStoreConnectClient(credentials: credentials).reply(to: review, text: clean)
            } else {
                guard let credentials = try CredentialStore.google(), let package = app.playStoreApp?.bundleID else { throw APIError.missingCredentials(.playStore) }
                try await GooglePlayClient(credentials: credentials).reply(to: review, packageName: package, text: clean)
            }
            review.response = clean
            workspace.reviewsByApp[appID]?[index] = review
            persist()
            showToast("Reply sent", detail: "The store accepted your response.", kind: .success)
            track(.reviewReplyCompleted(platform: review.platform, result: .success, failure: nil))
        } catch {
            track(.reviewReplyCompleted(
                platform: review.platform,
                result: .failure,
                failure: EscaleAnalyticsEvent.failureCategory(for: error)
            ))
            showError(error)
        }
    }

    public func draftReviewReply(to reviewID: UUID) async -> String? {
        guard let appID = selectedAppID,
              let app = workspace.apps.first(where: { $0.id == appID }),
              let review = workspace.reviewsByApp[appID]?.first(where: { $0.id == reviewID }) else {
            return nil
        }

        do {
            guard let apiKey = try CredentialStore.openAIAPIKey() else {
                throw OpenAIClientError.missingAPIKey
            }
            let platform = review.platform
            let storedLocalizations = workspace.localizationsByApp[appID, default: []]
            let preferredLocale = platform == .appStore
                ? app.appStoreApp?.primaryLocale
                : app.playStoreApp?.primaryLocale
            let primary = primaryLocalization(
                in: storedLocalizations,
                preferredLocale: preferredLocale
            ).map { listingLocalization($0, displaying: [platform]) }
            let listingSummary = primary?.description ?? ""
            let currentReleaseNotes = primary?.releaseNotes ?? ""
            let appName = reviewReplyAppName(for: app, platform: platform)

            showToast(
                "Drafting reply…",
                detail: "Using \(appName) and this review as context.",
                kind: .progress
            )
            let draft = try await OpenAIClient(apiKey: apiKey).draftReviewReply(
                appName: appName,
                review: review,
                listingSummary: listingSummary,
                currentReleaseNotes: currentReleaseNotes
            )
            showToast(
                "Reply draft ready",
                detail: "Review and edit the AI-generated response before publishing it.",
                kind: .success
            )
            return draft
        } catch {
            showToast("Could not draft reply", detail: error.localizedDescription, kind: .error)
            return nil
        }
    }

    public func sync() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        let connectedPlatforms = Set(workspace.connections.map(\.platform))
        let analyticsScope = connectedPlatforms.isEmpty
            ? EscaleAnalyticsScope.both
            : EscaleAnalyticsEvent.scope(for: connectedPlatforms)
        if isDemoMode {
            try? await Task.sleep(for: .milliseconds(500))
            updateSyncDates()
            showToast("Demo refreshed", detail: "No remote stores were contacted.", kind: .success)
            track(.manualSyncCompleted(scope: analyticsScope, result: .success, failure: nil))
            return
        }
        showToast("Syncing stores…", detail: "Fetching live listings, products, screenshots, and reviews.", kind: .progress)
        var failures: [String] = []
        var firstFailureCategory: EscaleAnalyticsFailureCategory?
        do {
            if let credentials = try CredentialStore.apple() {
                let client = AppStoreConnectClient(credentials: credentials)
                let apps = try await client.listApps()
                importApps(apps)
                for app in apps {
                    do {
                        let snapshot = try await client.fetchSnapshot(for: app)
                        merge(snapshot)
                        if let id = workspace.apps.first(where: { $0.appStoreApp?.storeID == app.storeID })?.id {
                            loadedAppIDs.insert(id)
                            appSyncIssues[id] = snapshot.warnings.map { "App Store: \($0)" }
                        }
                    }
                    catch {
                        firstFailureCategory = firstFailureCategory ?? EscaleAnalyticsEvent.failureCategory(for: error)
                        failures.append("\(app.name): \(error.localizedDescription)")
                    }
                }
            }
        } catch {
            firstFailureCategory = firstFailureCategory ?? EscaleAnalyticsEvent.failureCategory(for: error)
            failures.append("App Store: \(error.localizedDescription)")
        }
        do {
            if let credentials = try CredentialStore.google() {
                let client = GooglePlayClient(credentials: credentials)
                let packages = workspace.apps.compactMap { $0.playStoreApp?.bundleID }
                for package in packages {
                    do { merge(try await client.fetchSnapshot(packageName: package)) }
                    catch {
                        firstFailureCategory = firstFailureCategory ?? EscaleAnalyticsEvent.failureCategory(for: error)
                        failures.append("\(package): \(error.localizedDescription)")
                    }
                }
            }
        } catch {
            firstFailureCategory = firstFailureCategory ?? EscaleAnalyticsEvent.failureCategory(for: error)
            failures.append("Google Play: \(error.localizedDescription)")
        }
        updateSyncDates()
        persist()
        if failures.isEmpty {
            showToast("Sync complete", detail: "Live store data is current.", kind: .success)
            track(.manualSyncCompleted(scope: analyticsScope, result: .success, failure: nil))
        } else {
            showToast("Sync completed with issues", detail: failures.prefix(2).joined(separator: " · "), kind: .error)
            track(.manualSyncCompleted(
                scope: analyticsScope,
                result: .partial,
                failure: firstFailureCategory ?? .unknown
            ))
        }
    }

    public func refreshSelectedApp() async {
        guard let selectedAppID else { return }
        await refreshApp(id: selectedAppID, showFeedback: true)
    }

    public func refreshAppIfNeeded(id: UUID) async {
        guard workspace.apps.contains(where: { $0.id == id }),
              !loadedAppIDs.contains(id),
              !loadingAppIDs.contains(id) else { return }
        await refreshApp(id: id, showFeedback: true)
    }

    private func refreshApp(id: UUID, showFeedback: Bool) async {
        guard !isDemoMode, !loadingAppIDs.contains(id),
              let app = workspace.apps.first(where: { $0.id == id }) else { return }

        loadingAppIDs.insert(id)
        appSyncIssues[id] = []
        let storeCount = max(1, [app.appStoreApp != nil, app.playStoreApp != nil].filter { $0 }.count)
        appRefreshProgressByID[id] = AppRefreshProgress(
            platform: app.appStoreApp != nil ? .appStore : .playStore,
            detail: "Preparing the live refresh…",
            fraction: 0
        )
        defer {
            loadingAppIDs.remove(id)
            appRefreshProgressByID.removeValue(forKey: id)
        }
        if showFeedback {
            showToast("Loading \(app.name)…", detail: "Fetching live listings, screenshots, products, pricing, and reviews.", kind: .progress)
        }

        var issues: [String] = []
        var successfulStores = 0
        var completedStores = 0

        if let appleApp = app.appStoreApp {
            let storeIndex = completedStores
            do {
                guard let credentials = try CredentialStore.apple() else { throw APIError.missingCredentials(.appStore) }
                let snapshot = try await AppStoreConnectClient(credentials: credentials).fetchSnapshot(for: appleApp) { [weak self] progress in
                    self?.updateRefreshProgress(id: id, platform: .appStore, storeIndex: storeIndex, storeCount: storeCount, progress: progress)
                }
                merge(snapshot)
                issues.append(contentsOf: snapshot.warnings.map { "App Store: \($0)" })
                successfulStores += 1
                markConnectionSynced(.appStore)
            } catch {
                issues.append("App Store: \(error.localizedDescription)")
            }
            completedStores += 1
        }

        if let packageName = app.playStoreApp?.bundleID {
            let storeIndex = completedStores
            do {
                guard let credentials = try CredentialStore.google() else { throw APIError.missingCredentials(.playStore) }
                let snapshot = try await GooglePlayClient(credentials: credentials).fetchSnapshot(packageName: packageName) { [weak self] progress in
                    self?.updateRefreshProgress(id: id, platform: .playStore, storeIndex: storeIndex, storeCount: storeCount, progress: progress)
                }
                merge(snapshot)
                issues.append(contentsOf: snapshot.warnings.map { "Google Play: \($0)" })
                successfulStores += 1
                markConnectionSynced(.playStore)
            } catch {
                issues.append("Google Play: \(error.localizedDescription)")
            }
            completedStores += 1
        }

        appRefreshProgressByID[id] = AppRefreshProgress(platform: app.playStoreApp != nil ? .playStore : .appStore, detail: "Saving the refreshed workspace…", fraction: 1)
        if successfulStores > 0 { loadedAppIDs.insert(id) }
        appSyncIssues[id] = issues
        persist()
        let result: EscaleAnalyticsResult = if successfulStores == 0 {
            .failure
        } else if issues.isEmpty {
            .success
        } else {
            .partial
        }
        track(.appRefreshCompleted(
            scope: EscaleAnalyticsEvent.scope(for: availablePlatforms(for: id)),
            result: result
        ))

        guard showFeedback else { return }
        if successfulStores == 0 {
            showToast("Could not load live app data", detail: issues.first ?? "No connected store is available for this app.", kind: .error)
        } else if issues.isEmpty {
            showToast("App data refreshed", detail: "The selected app now matches the connected stores.", kind: .success)
        } else {
            showToast("App loaded with some issues", detail: issues.first ?? "Some store resources were unavailable.", kind: .error)
        }
    }

    private func sync(appID: UUID, platforms: Set<StorePlatform>) async {
        guard let app = workspace.apps.first(where: { $0.id == appID }) else { return }
        if platforms.contains(.appStore), let remote = app.appStoreApp, let credentials = try? CredentialStore.apple() {
            if let snapshot = try? await AppStoreConnectClient(credentials: credentials).fetchSnapshot(for: remote) { merge(snapshot) }
        }
        if platforms.contains(.playStore), let package = app.playStoreApp?.bundleID, let credentials = try? CredentialStore.google() {
            if let snapshot = try? await GooglePlayClient(credentials: credentials).fetchSnapshot(packageName: package) { merge(snapshot) }
        }
    }

    public func showToast(_ title: String, detail: String, kind: ToastKind) {
        let message = ToastMessage(id: UUID(), title: title, detail: detail, kind: kind)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { toast = message }
        if kind != .progress {
            Task {
                try? await Task.sleep(for: .seconds(kind == .error ? 7 : 3))
                if toast?.id == message.id { withAnimation { toast = nil } }
            }
        }
    }

    private func showError(_ error: Error) {
        showToast("Store operation failed", detail: error.localizedDescription, kind: .error)
    }

    private func updateConnection(_ platform: StorePlatform, name: String, detail: String) {
        let connection = StoreConnection(platform: platform, accountName: name, detail: detail, state: .connected, lastSync: Date())
        if let index = workspace.connections.firstIndex(where: { $0.platform == platform }) { workspace.connections[index] = connection }
        else { workspace.connections.append(connection) }
    }

    private func markConnectionSynced(_ platform: StorePlatform) {
        if let index = workspace.connections.firstIndex(where: { $0.platform == platform }) {
            workspace.connections[index].lastSync = Date()
        }
    }

    private func updateRefreshProgress(
        id: UUID,
        platform: StorePlatform,
        storeIndex: Int,
        storeCount: Int,
        progress: StoreFetchProgress
    ) {
        let overallFraction = (Double(storeIndex) + progress.fraction) / Double(max(1, storeCount))
        appRefreshProgressByID[id] = AppRefreshProgress(
            platform: platform,
            detail: progress.detail,
            fraction: overallFraction
        )
    }

    private func prepareLiveWorkspace() {
        if isDemoMode {
            workspace = .empty
            selectedAppID = nil
            loadingAppIDs = []
            loadedAppIDs = []
            appSyncIssues = [:]
            appRefreshProgressByID = [:]
        }
        isDemoMode = false
        UserDefaults.standard.set(false, forKey: demoKey)
    }

    private func importApps(_ apps: [StoreApp]) {
        for remote in apps {
            if let index = workspace.apps.firstIndex(where: { $0.appStoreApp?.storeID == remote.storeID }) {
                workspace.apps[index].appStoreApp = remote
                workspace.apps[index].name = remote.name
            } else if let index = workspace.apps.firstIndex(where: { $0.playStoreApp?.bundleID == remote.bundleID }) {
                workspace.apps[index].appStoreApp = remote
            } else {
                let unified = UnifiedApp(id: UUID(), name: remote.name, symbol: "app.fill", tintHex: colorHex(for: remote.bundleID), appStoreApp: remote, playStoreApp: nil)
                workspace.apps.append(unified)
            }
        }
        if selectedAppID == nil { selectedAppID = workspace.apps.first?.id }
    }

    private func merge(_ snapshot: StoreSnapshot, preferredAppID: UUID? = nil) {
        let platform = snapshot.app.platform
        let preferredIndex = preferredAppID.flatMap { preferredID in
            workspace.apps.firstIndex(where: { $0.id == preferredID })
        }
        let existingIndex = preferredIndex ?? workspace.apps.firstIndex(where: { unified in
            if platform == .appStore { return unified.appStoreApp?.storeID == snapshot.app.storeID || unified.playStoreApp?.bundleID == snapshot.app.bundleID }
            return unified.playStoreApp?.storeID == snapshot.app.storeID || unified.appStoreApp?.bundleID == snapshot.app.bundleID
        })
        let appID: UUID
        if let index = existingIndex {
            appID = workspace.apps[index].id
            if platform == .appStore { workspace.apps[index].appStoreApp = snapshot.app }
            else { workspace.apps[index].playStoreApp = snapshot.app }
            if workspace.apps[index].name.isEmpty || platform == .appStore { workspace.apps[index].name = snapshot.app.name }
        } else {
            let unified = UnifiedApp(
                id: UUID(), name: snapshot.app.name, symbol: "app.fill", tintHex: colorHex(for: snapshot.app.bundleID),
                appStoreApp: platform == .appStore ? snapshot.app : nil,
                playStoreApp: platform == .playStore ? snapshot.app : nil
            )
            workspace.apps.append(unified)
            appID = unified.id
        }
        if !snapshot.unavailableSections.contains(.localizations) {
            mergeLocalizations(snapshot.localizations, platform: platform, appID: appID)
        }
        if !snapshot.unavailableSections.contains(.screenshots) {
            workspace.screenshotsByApp[appID, default: []].removeAll(where: { $0.platform == platform })
            workspace.screenshotsByApp[appID, default: []].append(contentsOf: snapshot.screenshots)
        }
        if !snapshot.unavailableSections.contains(.products) {
            mergeProducts(snapshot.products, platform: platform, appID: appID)
        }
        if !snapshot.unavailableSections.contains(.reviews) {
            workspace.reviewsByApp[appID, default: []].removeAll(where: { $0.platform == platform })
            workspace.reviewsByApp[appID, default: []].append(contentsOf: snapshot.reviews)
        }
        if selectedAppID == nil { selectedAppID = appID }
    }

    private func mergeLocalizations(_ incoming: [ListingLocalization], platform: StorePlatform, appID: UUID) {
        for remote in incoming {
            if let index = workspace.localizationsByApp[appID, default: []].firstIndex(where: { canonicalStoreLocale($0.locale) == canonicalStoreLocale(remote.locale) }) {
                var local = workspace.localizationsByApp[appID]![index]
                if local.dirtyPlatforms.contains(platform) { continue }
                if platform == .appStore {
                    local.title = remote.title
                    local.subtitle = remote.subtitle
                    local.description = remote.description
                }
                if platform == .appStore {
                    local.promotionalText = remote.promotionalText
                    local.keywords = remote.keywords
                    local.releaseNotes = remote.releaseNotes
                    local.appleVersionLocalizationID = remote.appleVersionLocalizationID
                    local.appleAppInfoLocalizationID = remote.appleAppInfoLocalizationID
                } else {
                    local.googleLanguage = remote.googleLanguage
                    local.googleTitle = remote.googleTitle ?? remote.title
                    local.googleSubtitle = remote.googleSubtitle ?? remote.subtitle
                    local.googleDescription = remote.googleDescription ?? remote.description
                }
                local.lastSaved = Date()
                workspace.localizationsByApp[appID]![index] = local
            } else {
                var added = remote
                if platform == .playStore {
                    added.title = ""
                    added.subtitle = ""
                    added.promotionalText = ""
                    added.description = ""
                    added.keywords = ""
                    added.releaseNotes = ""
                    added.appleVersionLocalizationID = nil
                    added.appleAppInfoLocalizationID = nil
                }
                workspace.localizationsByApp[appID, default: []].append(added)
            }
        }
    }

    private func mergeProducts(_ incoming: [StoreProduct], platform: StorePlatform, appID: UUID) {
        workspace.productsByApp[appID] = splitCrossStoreProducts(
            workspace.productsByApp[appID, default: []]
        )
        workspace.productsByApp[appID, default: []].removeAll { existing in
            existing.platforms == [platform]
                && !incoming.contains(where: {
                    storeProductsMatch(existing, $0, on: platform)
                })
        }
        for remote in incoming {
            if let index = workspace.productsByApp[appID, default: []].firstIndex(where: {
                storeProductsMatch($0, remote, on: platform)
            }) {
                workspace.productsByApp[appID]![index] = refreshedStoreProduct(
                    workspace.productsByApp[appID]![index],
                    with: remote,
                    from: platform
                )
            } else { workspace.productsByApp[appID, default: []].append(remote) }
        }
    }

    private func mergeContent(from sourceID: UUID, into destinationID: UUID) {
        let localizations = workspace.localizationsByApp.removeValue(forKey: sourceID) ?? []
        let screenshots = workspace.screenshotsByApp.removeValue(forKey: sourceID) ?? []
        let products = workspace.productsByApp.removeValue(forKey: sourceID) ?? []
        let reviews = workspace.reviewsByApp.removeValue(forKey: sourceID) ?? []
        let googlePlayReleaseNotes = workspace.googlePlayReleaseNotesByApp?.removeValue(forKey: sourceID)

        mergeLocalizations(localizations, platform: .playStore, appID: destinationID)
        workspace.screenshotsByApp[destinationID, default: []].append(contentsOf: screenshots)
        mergeProducts(products, platform: .playStore, appID: destinationID)
        workspace.reviewsByApp[destinationID, default: []].append(contentsOf: reviews)
        if let googlePlayReleaseNotes {
            if workspace.googlePlayReleaseNotesByApp == nil { workspace.googlePlayReleaseNotesByApp = [:] }
            workspace.googlePlayReleaseNotesByApp?[destinationID] = googlePlayReleaseNotes
        }
    }

    private func addDemoAndroidPackage(_ clean: String) {
        let app = StoreApp(id: UUID(), platform: .playStore, name: clean.split(separator: ".").last.map(String.init)?.capitalized ?? clean, bundleID: clean, storeID: clean, version: "Draft", state: .draft, versionID: nil, appInfoID: nil)
        merge(StoreSnapshot(app: app, localizations: [], screenshots: [], products: [], reviews: []))
        persist()
    }

    private func availablePlatforms(for appID: UUID) -> Set<StorePlatform> {
        guard let app = workspace.apps.first(where: { $0.id == appID }) else { return [] }
        var result: Set<StorePlatform> = []
        if app.appStoreApp != nil { result.insert(.appStore) }
        if app.playStoreApp != nil { result.insert(.playStore) }
        return result
    }

    private func updateSyncDates() {
        let now = Date()
        for index in workspace.connections.indices where workspace.connections[index].state == .connected { workspace.connections[index].lastSync = now }
        persist()
    }

    private func colorHex(for identifier: String) -> UInt {
        let palette: [UInt] = [0x6857E5, 0x2B7A78, 0xD77A45, 0x3178C6, 0xB05279, 0x4F7B4A]
        let value = identifier.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
        return palette[abs(value) % palette.count]
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(workspace) { UserDefaults.standard.set(data, forKey: persistenceKey) }
    }

    private func scheduleEditorPersistence() {
        guard pendingEditorPersistence == nil else { return }
        pendingEditorPersistence = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            pendingEditorPersistence = nil
            persist()
        }
    }
}

public func storeProductsMatch(
    _ existing: StoreProduct,
    _ remote: StoreProduct,
    on platform: StorePlatform
) -> Bool {
    guard existing.platforms.contains(platform) else { return false }
    switch platform {
    case .appStore:
        if let existingID = existing.appleProductID, let remoteID = remote.appleProductID {
            return existingID == remoteID
        }
        return existing.productID == remote.productID
    case .playStore:
        if let existingID = existing.googleProductID, let remoteID = remote.googleProductID {
            return existingID == remoteID && existing.googleBasePlanID == remote.googleBasePlanID
        }
        return existing.productID == remote.productID
            && existing.googleBasePlanID == remote.googleBasePlanID
    }
}

public func splitCrossStoreProducts(_ products: [StoreProduct]) -> [StoreProduct] {
    products.flatMap { product -> [StoreProduct] in
        guard product.platforms.contains(.appStore), product.platforms.contains(.playStore) else {
            return [product]
        }
        return [
            storeProductCopy(product, id: product.id, platform: .appStore),
            storeProductCopy(product, id: UUID(), platform: .playStore)
        ]
    }
}

private func storeProductCopy(
    _ product: StoreProduct,
    id: UUID,
    platform: StorePlatform
) -> StoreProduct {
    StoreProduct(
        id: id,
        name: product.name,
        productID: product.productID,
        kind: product.kind,
        basePrice: product.basePrice,
        platforms: [platform],
        regions: product.regions,
        appleProductID: platform == .appStore ? product.appleProductID : nil,
        googleProductID: platform == .playStore ? product.googleProductID : nil,
        googleBasePlanID: platform == .playStore ? product.googleBasePlanID : nil,
        pricingIndex: product.pricingIndex,
        subscriberPricePolicy: product.subscriberPricePolicy,
        pricingCalculatedAt: nil,
        pricingSourceSummary: nil
    )
}

public func cachedAppIDs(in workspace: Workspace) -> Set<UUID> {
    Set(workspace.apps.compactMap { app in
        let id = app.id
        let hasCachedCollections = workspace.localizationsByApp[id] != nil
            || workspace.screenshotsByApp[id] != nil
            || workspace.productsByApp[id] != nil
            || workspace.reviewsByApp[id] != nil
        let hasCachedVersion = app.appStoreApp?.versionID != nil
            || app.appStoreApp.map { $0.version != "—" } == true
            || app.playStoreApp.map { $0.version != "—" } == true
        return hasCachedCollections || hasCachedVersion ? id : nil
    })
}

/// Replaces store-owned pricing with the latest remote snapshot while retaining
/// the user's PPP index and subscriber migration policy on the local product.
public func refreshedStoreProduct(
    _ cached: StoreProduct,
    with remote: StoreProduct,
    from platform: StorePlatform
) -> StoreProduct {
    var result = cached
    result.name = remote.name
    result.productID = remote.productID
    result.kind = remote.kind
    result.platforms.insert(platform)

    if platform == .appStore {
        result.appleProductID = remote.appleProductID
    } else {
        result.googleProductID = remote.googleProductID
        result.googleBasePlanID = remote.googleBasePlanID
    }

    // A non-empty regional schedule is authoritative even when the base price
    // itself did not change. App Store Connect permits country-specific prices,
    // so comparing only the US base price leaves stale market values in place.
    if !remote.regions.isEmpty {
        result.regions = remote.regions
        result.basePrice = remote.basePrice
        result.pricingCalculatedAt = nil
        result.pricingSourceSummary = nil
    } else if remote.basePrice > 0 {
        result.basePrice = remote.basePrice
    }

    return result
}

/// Moves cached listing data onto a newly created App Store version. Unsaved
/// local copy wins over the fetched draft so edits made before version creation
/// remain available to publish once the draft exists.
public func localizationsAfterCreatingAppStoreVersion(
    cached: [ListingLocalization],
    draft: [ListingLocalization]
) -> [ListingLocalization] {
    var result = cached.map { localization in
        var copy = localization
        copy.appleVersionLocalizationID = nil
        return copy
    }

    for remote in draft {
        if let index = result.firstIndex(where: {
            canonicalStoreLocale($0.locale) == canonicalStoreLocale(remote.locale)
        }) {
            guard !result[index].dirtyPlatforms.contains(.appStore) else { continue }
            result[index].title = remote.title
            result[index].subtitle = remote.subtitle
            result[index].promotionalText = remote.promotionalText
            result[index].description = remote.description
            result[index].keywords = remote.keywords
            result[index].releaseNotes = remote.releaseNotes
            result[index].appleVersionLocalizationID = remote.appleVersionLocalizationID
            result[index].appleAppInfoLocalizationID = remote.appleAppInfoLocalizationID
            result[index].lastSaved = Date()
        } else {
            result.append(remote)
        }
    }
    return result
}

public enum ToastKind { case success, progress, neutral, error }

public struct AppRefreshProgress: Sendable {
    public var platform: StorePlatform
    public var detail: String
    public var fraction: Double
}

public struct ToastMessage: Identifiable {
    public let id: UUID
    public let title: String
    public let detail: String
    public let kind: ToastKind
}
