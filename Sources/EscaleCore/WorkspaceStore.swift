import Foundation
import ImageIO
import SwiftUI

private struct ScreenshotUploadImage {
    let properties: ScreenshotImageProperties
    let mimeType: String
    let fileExtension: String

    func fileName(for sourceURL: URL) -> String {
        sourceURL.deletingPathExtension().lastPathComponent + "." + fileExtension
    }
}

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
    @Published public private(set) var savingScreenshotPlatforms: Set<StorePlatform> = []
    @Published public private(set) var deletingScreenshotIDs: Set<UUID> = []
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
        localizations(displaying: selectedEditingPlatforms)
    }
    public func localizations(displaying platforms: Set<StorePlatform>) -> [ListingLocalization] {
        return (selectedAppID.flatMap { workspace.localizationsByApp[$0] } ?? [])
            .map { listingLocalization($0, displaying: platforms) }
    }
    public var selectedScreenshots: [StoreScreenshot] { selectedAppID.flatMap { workspace.screenshotsByApp[$0] } ?? [] }
    public var selectedProducts: [StoreProduct] { selectedAppID.flatMap { workspace.productsByApp[$0] } ?? [] }
    public var selectedReviews: [CustomerReview] { selectedAppID.flatMap { workspace.reviewsByApp[$0] } ?? [] }

    public func pendingScreenshotChangeCount(for platform: StorePlatform) -> Int {
        guard let appID = selectedAppID,
              let draft = workspace.screenshotDraftsByApp?[appID] else {
            return 0
        }
        let dirtyCount = draft.dirtyGalleryKeys.filter {
            $0.hasPrefix(platform.rawValue + "|")
        }.count
        return dirtyCount
    }

    public func screenshotGalleryHasPendingChanges(_ screenshot: StoreScreenshot) -> Bool {
        guard let appID = selectedAppID else { return false }
        return workspace.screenshotDraftsByApp?[appID]?
            .dirtyGalleryKeys
            .contains(screenshotGalleryKey(screenshot)) == true
    }
    public var releaseNoteTemplates: [ReleaseNoteTemplate] {
        (workspace.releaseNoteTemplates ?? []).sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
    public func selectedRatingSummary(for platforms: Set<StorePlatform> = Set(StorePlatform.allCases)) -> StoreRatingSummary? {
        guard let app = selectedApp else { return nil }
        let summaries = [
            platforms.contains(.appStore) ? app.appStoreApp?.ratingSummary : nil,
            platforms.contains(.playStore) ? app.playStoreApp?.ratingSummary : nil
        ].compactMap { $0 }
        return combinedStoreRatingSummary(summaries)
    }
    public var isSelectedAppLoading: Bool { selectedAppID.map(loadingAppIDs.contains) ?? false }
    public var selectedAppSyncIssues: [String] { selectedAppID.flatMap { appSyncIssues[$0] } ?? [] }
    public var selectedAppHasLiveData: Bool { selectedAppID.map(loadedAppIDs.contains) ?? false }
    public var selectedAppRefreshProgress: AppRefreshProgress? { selectedAppID.flatMap { appRefreshProgressByID[$0] } }
    public var selectedAvailablePlatforms: Set<StorePlatform> { selectedAppID.map(availablePlatforms) ?? [] }
    public var selectedEditingPlatforms: Set<StorePlatform> {
        platformFilter.platforms.intersection(selectedAvailablePlatforms)
    }
    public var selectedPrimaryLocalization: ListingLocalization? {
        primarySelectedLocalization(displaying: selectedEditingPlatforms)
    }
    public func primarySelectedLocalization(
        displaying platforms: Set<StorePlatform>
    ) -> ListingLocalization? {
        let preferredLocale: String? = if platforms == [.playStore] {
            selectedApp?.playStoreApp?.primaryLocale
        } else {
            selectedApp?.appStoreApp?.primaryLocale ?? selectedApp?.playStoreApp?.primaryLocale
        }
        return primaryLocalization(
            in: localizations(displaying: platforms),
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

    public func resetAllData() throws {
        pendingEditorPersistence?.cancel()
        pendingEditorPersistence = nil

        var keychainError: Error?
        do {
            try CredentialStore.removeAllEscaleItems()
        } catch {
            keychainError = error
        }

        analytics.setEnabled(false)
        let defaults = UserDefaults.standard
        defaults.dictionaryRepresentation().keys.forEach(defaults.removeObject(forKey:))
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            defaults.removePersistentDomain(forName: bundleIdentifier)
        }
        defaults.removePersistentDomain(forName: legacyDefaultsDomain)

        URLCache.shared.removeAllCachedResponses()
        HTTPCookieStorage.shared.cookies?.forEach {
            HTTPCookieStorage.shared.deleteCookie($0)
        }

        workspace = .empty
        selectedAppID = nil
        selectedSection = .overview
        platformFilter = .both
        isOnboardingPresented = true
        isDemoMode = false
        isSyncing = false
        isOpenAIKeyConfigured = false
        loadingAppIDs.removeAll()
        loadedAppIDs.removeAll()
        appSyncIssues.removeAll()
        appRefreshProgressByID.removeAll()
        calculatingProductIDs.removeAll()
        pricingApplyProgressByProductID.removeAll()
        savingScreenshotPlatforms.removeAll()
        deletingScreenshotIDs.removeAll()
        isAnalyticsEnabled = false

        if let keychainError {
            throw keychainError
        }
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
        localizationBinding(id: id, displaying: selectedEditingPlatforms)
    }

    public func localizationBinding(
        id: UUID,
        displaying requestedPlatforms: Set<StorePlatform>
    ) -> Binding<ListingLocalization> {
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
                let targets = requestedPlatforms.intersection(self.availablePlatforms(for: appID))
                return listingLocalization(item, displaying: targets)
            },
            set: { [weak self] updated in
                guard let self, let appID = self.selectedAppID,
                      let index = self.workspace.localizationsByApp[appID]?.firstIndex(where: { $0.id == id }) else { return }
                let available = self.availablePlatforms(for: appID)
                let targets = requestedPlatforms.intersection(available)
                let stored = self.workspace.localizationsByApp[appID]![index]
                guard listingMetadataHasChanges(updated, comparedTo: stored, displaying: targets) else { return }
                var copy = applyingListingMetadata(from: updated, to: stored, platforms: targets)
                guard copy != stored else { return }
                let changedPlatforms = targets.filter { platform in
                    let platformCopy = listingLocalization(copy, displaying: [platform])
                    return listingMetadataHasChanges(
                        platformCopy,
                        comparedTo: stored,
                        displaying: [platform]
                    )
                }
                copy.dirtyPlatforms.formUnion(changedPlatforms)
                self.workspace.localizationsByApp[appID]?[index] = copy
                self.scheduleEditorPersistence()
            }
        )
    }

    @discardableResult
    public func createReleaseNoteTemplate(name: String, body: String) -> UUID? {
        guard requireAccess(to: .releaseNoteTemplates) else { return nil }
        guard let template = validatedReleaseNoteTemplate(name: name, body: body) else { return nil }
        if workspace.releaseNoteTemplates == nil {
            workspace.releaseNoteTemplates = []
        }
        workspace.releaseNoteTemplates?.append(template)
        persist()
        showToast(
            "Template saved",
            detail: "“\(template.name)” is ready in every store listing.",
            kind: .success
        )
        return template.id
    }

    @discardableResult
    public func updateReleaseNoteTemplate(id: UUID, name: String, body: String) -> Bool {
        guard requireAccess(to: .releaseNoteTemplates) else { return false }
        guard let index = workspace.releaseNoteTemplates?.firstIndex(where: { $0.id == id }),
              let template = validatedReleaseNoteTemplate(
                  id: id,
                  name: name,
                  body: body,
                  createdAt: workspace.releaseNoteTemplates?[index].createdAt ?? Date()
              ) else {
            return false
        }
        workspace.releaseNoteTemplates?[index] = template
        persist()
        showToast(
            "Template updated",
            detail: "“\(template.name)” is ready to reuse.",
            kind: .success
        )
        return true
    }

    @discardableResult
    public func deleteReleaseNoteTemplate(id: UUID) -> Bool {
        guard requireAccess(to: .releaseNoteTemplates) else { return false }
        guard let index = workspace.releaseNoteTemplates?.firstIndex(where: { $0.id == id }) else {
            return false
        }
        let template = workspace.releaseNoteTemplates?.remove(at: index)
        persist()
        showToast(
            "Template deleted",
            detail: template.map { "“\($0.name)” was removed. Existing listings were not changed." }
                ?? "The template was removed.",
            kind: .neutral
        )
        return true
    }

    @discardableResult
    public func applyReleaseNoteTemplate(id: UUID, toLocalization localizationID: UUID) -> Bool {
        guard requireAccess(to: .releaseNoteTemplates) else { return false }
        guard let template = workspace.releaseNoteTemplates?.first(where: { $0.id == id }),
              let appID = selectedAppID,
              let index = workspace.localizationsByApp[appID]?.firstIndex(where: { $0.id == localizationID }),
              availablePlatforms(for: appID).contains(.appStore) else {
            return false
        }
        var localization = workspace.localizationsByApp[appID]![index]
        guard localization.releaseNotes != template.body else {
            showToast("Template already applied", detail: "The What’s New field already uses “\(template.name)”.", kind: .neutral)
            return true
        }
        localization.releaseNotes = template.body
        localization.dirtyPlatforms.insert(.appStore)
        workspace.localizationsByApp[appID]?[index] = localization
        scheduleEditorPersistence()
        showToast(
            "Template applied",
            detail: "“\(template.name)” now fills the App Store What’s New field. Review it before saving.",
            kind: .success
        )
        return true
    }

    @discardableResult
    public func applyReleaseNoteTemplate(id: UUID, toGooglePlayLocale locale: String) -> Bool {
        guard requireAccess(to: .releaseNoteTemplates) else { return false }
        guard let template = workspace.releaseNoteTemplates?.first(where: { $0.id == id }) else {
            return false
        }
        guard template.body.count <= googlePlayReleaseNoteCharacterLimit else {
            showToast(
                "Template is too long for Google Play",
                detail: "Shorten it to \(googlePlayReleaseNoteCharacterLimit) characters before applying it to this locale.",
                kind: .error
            )
            return false
        }
        setGooglePlayReleaseNote(template.body, locale: locale)
        showToast(
            "Template applied",
            detail: "“\(template.name)” now fills the Google Play release notes for \(locale).",
            kind: .success
        )
        return true
    }

    private func validatedReleaseNoteTemplate(
        id: UUID = UUID(),
        name: String,
        body: String,
        createdAt: Date = Date()
    ) -> ReleaseNoteTemplate? {
        if let issue = releaseNoteTemplateValidationIssue(name: name, body: body) {
            showToast("Could not save template", detail: issue, kind: .error)
            return nil
        }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let duplicateName = workspace.releaseNoteTemplates?.contains {
            $0.id != id && $0.name.caseInsensitiveCompare(cleanName) == .orderedSame
        } == true
        guard !duplicateName else {
            showToast(
                "Choose another template name",
                detail: "A template named “\(cleanName)” already exists.",
                kind: .error
            )
            return nil
        }
        return ReleaseNoteTemplate(
            id: id,
            name: cleanName,
            body: body,
            createdAt: createdAt,
            updatedAt: Date()
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
        guard let appID = selectedAppID else { return }
        await translateLocalization(
            id: id,
            from: sourceID,
            platforms: platformFilter.platforms.intersection(availablePlatforms(for: appID))
        )
    }

    public func translateLocalization(
        id: UUID,
        from sourceID: UUID,
        platforms requestedPlatforms: Set<StorePlatform>
    ) async {
        guard let appID = selectedAppID,
              let storedSource = workspace.localizationsByApp[appID]?.first(where: { $0.id == sourceID }),
              let target = workspace.localizationsByApp[appID]?.first(where: { $0.id == id }) else { return }
        do {
            guard let apiKey = try CredentialStore.openAIAPIKey() else { throw OpenAIClientError.missingAPIKey }
            let targetPlatforms = requestedPlatforms.intersection(availablePlatforms(for: appID))
            guard !targetPlatforms.isEmpty else {
                throw APIError.unsupported("Select a connected store before translating metadata.")
            }
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
            displayedTarget.shortDescription = translation.shortDescription
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
        guard let appID = selectedAppID else { return }
        await translateField(
            field,
            from: sourceID,
            to: [targetID],
            platforms: platformFilter.platforms.intersection(availablePlatforms(for: appID)),
            announcesAllLocales: false
        )
    }

    public func translateField(
        _ field: ListingMetadataField,
        from sourceID: UUID,
        to targetID: UUID,
        platforms: Set<StorePlatform>
    ) async {
        await translateField(
            field,
            from: sourceID,
            to: [targetID],
            platforms: platforms,
            announcesAllLocales: false
        )
    }

    public func translateFieldToAllLocales(_ field: ListingMetadataField, from sourceID: UUID) async {
        guard let appID = selectedAppID else { return }
        await translateFieldToAllLocales(
            field,
            from: sourceID,
            platforms: platformFilter.platforms.intersection(availablePlatforms(for: appID))
        )
    }

    public func translateFieldToAllLocales(
        _ field: ListingMetadataField,
        from sourceID: UUID,
        platforms: Set<StorePlatform>
    ) async {
        guard requireAccess(to: .bulkTranslations) else { return }
        guard let appID = selectedAppID else { return }
        let targetIDs = workspace.localizationsByApp[appID, default: []]
            .filter { $0.id != sourceID }
            .map(\.id)
        await translateField(
            field,
            from: sourceID,
            to: targetIDs,
            platforms: platforms,
            announcesAllLocales: true
        )
    }

    private func translateField(
        _ field: ListingMetadataField,
        from sourceID: UUID,
        to targetIDs: [UUID],
        platforms requestedPlatforms: Set<StorePlatform>,
        announcesAllLocales: Bool
    ) async {
        guard let appID = selectedAppID,
              let storedSource = workspace.localizationsByApp[appID]?.first(where: { $0.id == sourceID }) else { return }
        let targetPlatforms = requestedPlatforms.intersection(availablePlatforms(for: appID))
        let fieldPlatforms = field.supportedPlatforms.intersection(targetPlatforms)
        let source = listingLocalization(storedSource, displaying: fieldPlatforms)
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
            guard !fieldPlatforms.isEmpty else {
                throw APIError.unsupported("Select a connected store before translating metadata.")
            }
            let metadataLimits = ListingMetadataLimits(platforms: fieldPlatforms)
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
                        platforms: fieldPlatforms
                    )
                    guard let targetIndex = workspace.localizationsByApp[appID]?.firstIndex(where: { $0.id == target.id }) else {
                        failures.append(target.language)
                        continue
                    }
                    let storedTarget = workspace.localizationsByApp[appID]![targetIndex]
                    var displayedTarget = listingLocalization(storedTarget, displaying: fieldPlatforms)
                    field.set(translatedText, in: &displayedTarget)
                    var updated = applyingListingMetadata(
                        from: displayedTarget,
                        to: storedTarget,
                        platforms: fieldPlatforms
                    )
                    updated.dirtyPlatforms.formUnion(fieldPlatforms)
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
        guard let appID = selectedAppID else { return }
        guard let localization = workspace.localizationsByApp[appID]?.first(where: { $0.id == id }) else { return }
        await saveLocalization(id: id, appID: appID, platforms: localization.dirtyPlatforms)
    }

    public func saveEditedLocalizations() async {
        guard let appID = selectedAppID else { return }
        let dirtyPlatforms = workspace.localizationsByApp[appID, default: []]
            .reduce(into: Set<StorePlatform>()) { $0.formUnion($1.dirtyPlatforms) }
        await saveEditedLocalizations(platforms: dirtyPlatforms)
    }

    public func saveEditedLocalizations(platforms requestedPlatforms: Set<StorePlatform>) async {
        guard let appID = selectedAppID else { return }
        let localizationIDs = workspace.localizationsByApp[appID, default: []]
            .filter { !$0.dirtyPlatforms.isDisjoint(with: requestedPlatforms) }
            .map(\.id)
        guard !localizationIDs.isEmpty else {
            showToast("Everything is up to date", detail: "No local changes to publish.", kind: .neutral)
            return
        }
        for id in localizationIDs {
            await saveLocalization(id: id, appID: appID, platforms: requestedPlatforms)
        }
    }

    private func saveLocalization(
        id: UUID,
        appID: UUID,
        platforms requestedPlatforms: Set<StorePlatform>
    ) async {
        guard let app = workspace.apps.first(where: { $0.id == appID }),
              let index = workspace.localizationsByApp[appID]?.firstIndex(where: { $0.id == id }) else { return }
        var localization = workspace.localizationsByApp[appID]![index]
        let targets = localization.dirtyPlatforms.intersection(requestedPlatforms)
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
            localization.dirtyPlatforms.subtract(targets)
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

    public func uploadScreenshot(
        fileURL: URL,
        locale: String,
        device: String,
        platform: StorePlatform? = nil
    ) async {
        guard let appID = selectedAppID,
              savingScreenshotPlatforms.isEmpty,
              deletingScreenshotIDs.isEmpty else {
            return
        }
        let access = fileURL.startAccessingSecurityScopedResource()
        defer { if access { fileURL.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: fileURL)
            guard let image = screenshotImageProperties(from: data) else {
                showToast(
                    "Screenshot not uploaded",
                    detail: "Choose a valid PNG or JPEG image.",
                    kind: .error
                )
                return
            }
            let targets: Set<StorePlatform> = if let platform {
                Set([platform]).intersection(availablePlatforms(for: appID))
            } else {
                platformFilter.platforms.intersection(availablePlatforms(for: appID))
            }
            guard !targets.isEmpty else {
                showToast("Screenshot not uploaded", detail: "The selected store is not linked to this app.", kind: .error)
                return
            }
            for target in targets {
                if let issue = screenshotUploadValidationIssue(
                    properties: image.properties,
                    platform: target,
                    device: device
                ) {
                    showToast("Screenshot not uploaded", detail: issue, kind: .error)
                    return
                }
            }
            let appleDisplayType = targets.contains(.appStore)
                ? appStoreScreenshotDisplayType(
                    width: image.properties.width,
                    height: image.properties.height,
                    device: device
                )
                : nil
            let googleImageType = targets.contains(.playStore)
                ? googleScreenshotImageType(for: device)
                : nil
            if targets.contains(.playStore), googleImageType == nil {
                showToast(
                    "Screenshot not uploaded",
                    detail: "Google Play does not provide a \(device.lowercased()) screenshot gallery through its API.",
                    kind: .error
                )
                return
            }
            if let displayType = appleDisplayType,
               screenshotCount(
                   appID: appID,
                   platform: .appStore,
                   locale: locale,
                   galleryType: displayType
               ) >= 10 {
                showToast(
                    "Screenshot not uploaded",
                    detail: "App Store galleries can contain up to 10 screenshots.",
                    kind: .error
                )
                return
            }
            if let imageType = googleImageType,
               screenshotCount(
                   appID: appID,
                   platform: .playStore,
                   locale: locale,
                   galleryType: imageType
               ) >= 8 {
                showToast(
                    "Screenshot not uploaded",
                    detail: "Google Play galleries can contain up to 8 screenshots.",
                    kind: .error
                )
                return
            }
            for target in targets {
                let screenshotID = UUID()
                let draftURL = try cacheScreenshotDraft(
                    data: data,
                    appID: appID,
                    screenshotID: screenshotID,
                    fileExtension: image.fileExtension
                )
                let targetLocale: String
                let setID: String?
                if target == .appStore {
                    targetLocale = locale
                    let visibleScreenshots = workspace.screenshotsByApp[appID] ?? []
                    let deletedScreenshots = workspace.screenshotDraftsByApp?[appID]?
                        .deletedScreenshots ?? []
                    setID = (visibleScreenshots + deletedScreenshots).first(where: { candidate in
                        candidate.platform == .appStore
                            && canonicalStoreLocale(candidate.locale) == canonicalStoreLocale(locale)
                            && appleDisplayType.map { displayType in
                                screenshotDevice(candidate.device, matchesDisplayType: displayType)
                            } == true
                    })?.screenshotSetID
                } else {
                    targetLocale = workspace.localizationsByApp[appID]?
                        .first(where: { canonicalStoreLocale($0.locale) == canonicalStoreLocale(locale) })?
                        .googleLanguage
                        ?? googleLocale(forAppleLocale: locale)
                    setID = googleImageType
                }
                let screenshot = StoreScreenshot(
                    id: screenshotID,
                    platform: target,
                    locale: targetLocale,
                    device: device,
                    title: fileURL.deletingPathExtension().lastPathComponent,
                    caption: "Unsaved screenshot",
                    gradientStartHex: target == .appStore ? 0x5367D8 : 0x3D7C68,
                    gradientEndHex: target == .appStore ? 0x9F74E8 : 0x62B494,
                    remoteID: nil,
                    remoteURL: draftURL.absoluteString,
                    screenshotSetID: setID,
                    localDraftURL: draftURL.absoluteString
                )
                workspace.screenshotsByApp[appID, default: []].append(screenshot)
                markScreenshotGalleryDirty(screenshot, appID: appID)
            }
            persist()
            showToast(
                "Screenshot added",
                detail: "Review your changes, then choose Save to store.",
                kind: .success
            )
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

    public func reorderScreenshot(_ screenshotID: UUID, before destinationID: UUID?) async {
        guard let appID = selectedAppID,
              savingScreenshotPlatforms.isEmpty,
              deletingScreenshotIDs.isEmpty,
              let original = workspace.screenshotsByApp[appID],
              let source = original.first(where: { $0.id == screenshotID }) else {
            return
        }
        if let destinationID,
           let destination = original.first(where: { $0.id == destinationID }),
           !screenshotsShareGallery(source, destination) {
            showToast(
                "Choose a screenshot in the same gallery",
                detail: "Screenshots can only be reordered within the same store, locale, and device type.",
                kind: .neutral
            )
            return
        }
        guard let reordered = screenshotsByMoving(
            original,
            screenshotID: screenshotID,
            before: destinationID
        ) else {
            return
        }
        workspace.screenshotsByApp[appID] = reordered
        markScreenshotGalleryDirty(source, appID: appID)
        persist()
        showToast(
            "Order changed",
            detail: "Review your changes, then choose Save to store.",
            kind: .success
        )
    }

    public func saveScreenshotChanges(for platform: StorePlatform) async {
        guard let appID = selectedAppID,
              savingScreenshotPlatforms.isEmpty,
              deletingScreenshotIDs.isEmpty,
              let app = workspace.apps.first(where: { $0.id == appID }),
              let draft = workspace.screenshotDraftsByApp?[appID] else {
            return
        }
        let galleryKeys = draft.dirtyGalleryKeys
            .filter { $0.hasPrefix(platform.rawValue + "|") }
            .sorted()
        guard !galleryKeys.isEmpty else { return }

        savingScreenshotPlatforms.insert(platform)
        defer { savingScreenshotPlatforms.remove(platform) }
        showToast(
            "Saving screenshots to \(platform.rawValue)…",
            detail: "Applying \(galleryKeys.count) changed \(galleryKeys.count == 1 ? "gallery" : "galleries").",
            kind: .progress
        )

        do {
            if isDemoMode {
                if let indices = workspace.screenshotsByApp[appID]?.indices {
                    for index in indices {
                        let screenshot = workspace.screenshotsByApp[appID]![index]
                        guard galleryKeys.contains(screenshotGalleryKey(screenshot)),
                              screenshot.remoteID == nil else {
                            continue
                        }
                        workspace.screenshotsByApp[appID]?[index].remoteID =
                            "demo-\(screenshot.id.uuidString)"
                    }
                }
                for key in galleryKeys {
                    completeScreenshotGalleryDraft(
                        key,
                        appID: appID,
                        removeLocalFiles: false
                    )
                }
            } else {
                switch platform {
                case .appStore:
                    guard app.appStoreApp?.hasEditableMetadataVersion == true else {
                        throw APIError.unsupported(
                            "Create or select an editable App Store version before saving its screenshots."
                        )
                    }
                    guard let credentials = try CredentialStore.apple() else {
                        throw APIError.missingCredentials(.appStore)
                    }
                    let client = AppStoreConnectClient(credentials: credentials)
                    for key in galleryKeys {
                        try await saveAppStoreScreenshotGallery(
                            key,
                            appID: appID,
                            client: client
                        )
                    }
                case .playStore:
                    guard let credentials = try CredentialStore.google(),
                          let packageName = app.playStoreApp?.bundleID else {
                        throw APIError.missingCredentials(.playStore)
                    }
                    let client = GooglePlayClient(credentials: credentials)
                    for key in galleryKeys {
                        try await saveGooglePlayScreenshotGallery(
                            key,
                            appID: appID,
                            packageName: packageName,
                            client: client
                        )
                    }
                }
                await sync(appID: appID, platforms: [platform])
            }
            persist()
            showToast(
                "Screenshots saved",
                detail: "\(platform.rawValue) now uses the updated galleries.",
                kind: .success
            )
        } catch {
            persist()
            showError(error)
        }
    }

    private func saveAppStoreScreenshotGallery(
        _ galleryKey: String,
        appID: UUID,
        client: AppStoreConnectClient
    ) async throws {
        var gallery = workspace.screenshotsByApp[appID, default: []].filter {
            screenshotGalleryKey($0) == galleryKey
        }
        let galleryScreenshotIDs = Set(gallery.map(\.id))
        let deleted = workspace.screenshotDraftsByApp?[appID]?
            .deletedScreenshots
            .filter { screenshotGalleryKey($0) == galleryKey } ?? []
        guard let representative = gallery.first ?? deleted.first,
              let localization = workspace.localizationsByApp[appID]?.first(where: {
                  canonicalStoreLocale($0.locale) == canonicalStoreLocale(representative.locale)
              }) else {
            throw APIError.unsupported("Refresh this App Store screenshot gallery before saving it.")
        }
        var setID = gallery.compactMap(\.screenshotSetID).first
            ?? deleted.compactMap(\.screenshotSetID).first
        var completionGalleryKeys = Set([galleryKey])

        for screenshot in deleted {
            if let remoteID = screenshot.remoteID {
                try await client.deleteScreenshot(remoteID: remoteID)
            }
            mutateScreenshotDraft(appID: appID) {
                $0.deletedScreenshots.removeAll { $0.id == screenshot.id }
            }
        }

        for screenshot in gallery where screenshot.remoteID == nil {
            guard let localURLString = screenshot.localDraftURL,
                  let localURL = URL(string: localURLString) else {
                throw APIError.unsupported("A local screenshot draft is missing. Add the screenshot again.")
            }
            let data = try Data(contentsOf: localURL)
            guard let image = screenshotImageProperties(from: data),
                  let displayType = appStoreScreenshotDisplayType(
                      width: image.properties.width,
                      height: image.properties.height,
                      device: screenshot.device
                  ) else {
                throw APIError.unsupported("A local App Store screenshot no longer has an accepted size.")
            }
            let reference = try await client.uploadScreenshot(
                data: data,
                fileName: localURL.lastPathComponent,
                localization: localization,
                existingSetID: setID,
                displayType: displayType
            )
            let createdSet = setID == nil
            setID = reference.setID
            if createdSet {
                for screenshotID in galleryScreenshotIDs {
                    guard let index = workspace.screenshotsByApp[appID]?.firstIndex(where: {
                        $0.id == screenshotID
                    }) else {
                        continue
                    }
                    workspace.screenshotsByApp[appID]?[index].screenshotSetID = reference.setID
                }
                if let migratedKey = workspace.screenshotsByApp[appID]?
                    .first(where: { galleryScreenshotIDs.contains($0.id) })
                    .map(screenshotGalleryKey) {
                    completionGalleryKeys.insert(migratedKey)
                    mutateScreenshotDraft(appID: appID) {
                        $0.dirtyGalleryKeys.remove(galleryKey)
                        $0.dirtyGalleryKeys.insert(migratedKey)
                    }
                }
            }
            guard let index = workspace.screenshotsByApp[appID]?.firstIndex(where: {
                $0.id == screenshot.id
            }) else {
                throw APIError.invalidResponse
            }
            workspace.screenshotsByApp[appID]?[index].remoteID = reference.id
            workspace.screenshotsByApp[appID]?[index].screenshotSetID = reference.setID
        }

        gallery = workspace.screenshotsByApp[appID, default: []].filter { screenshot in
            guard screenshot.platform == .appStore else { return false }
            if let setID {
                return screenshot.screenshotSetID == setID
            }
            return screenshotGalleryKey(screenshot) == galleryKey
        }
        if gallery.count > 1,
           let setID,
           gallery.compactMap(\.remoteID).count == gallery.count {
            try await client.reorderScreenshots(
                setID: setID,
                remoteIDs: gallery.compactMap(\.remoteID)
            )
        }
        for key in completionGalleryKeys {
            completeScreenshotGalleryDraft(
                key,
                appID: appID,
                screenshotIDs: galleryScreenshotIDs
            )
        }
    }

    private func saveGooglePlayScreenshotGallery(
        _ galleryKey: String,
        appID: UUID,
        packageName: String,
        client: GooglePlayClient
    ) async throws {
        let gallery = workspace.screenshotsByApp[appID, default: []].filter {
            screenshotGalleryKey($0) == galleryKey
        }
        let deleted = workspace.screenshotDraftsByApp?[appID]?
            .deletedScreenshots
            .filter { screenshotGalleryKey($0) == galleryKey } ?? []
        guard let representative = gallery.first ?? deleted.first,
              let imageType = representative.screenshotSetID else {
            throw APIError.unsupported("Refresh this Google Play screenshot gallery before saving it.")
        }
        var uploads: [GooglePlayScreenshotUpload] = []
        for screenshot in gallery {
            uploads.append(try await googlePlayUpload(for: screenshot))
        }
        let references = try await client.replaceScreenshots(
            uploads,
            packageName: packageName,
            language: representative.locale,
            imageType: imageType
        )
        guard references.count == gallery.count else {
            throw APIError.invalidResponse
        }
        for (screenshot, reference) in zip(gallery, references) {
            guard let index = workspace.screenshotsByApp[appID]?.firstIndex(where: {
                $0.id == screenshot.id
            }) else {
                continue
            }
            workspace.screenshotsByApp[appID]?[index].remoteID = reference.id
            workspace.screenshotsByApp[appID]?[index].remoteURL = reference.url
        }
        completeScreenshotGalleryDraft(galleryKey, appID: appID)
    }

    private func googlePlayUpload(for screenshot: StoreScreenshot) async throws -> GooglePlayScreenshotUpload {
        if let localDraftURL = screenshot.localDraftURL,
           let url = URL(string: localDraftURL) {
            let data = try Data(contentsOf: url)
            guard let image = screenshotImageProperties(from: data) else {
                throw APIError.unsupported("The local screenshot draft can no longer be read.")
            }
            return GooglePlayScreenshotUpload(
                data: data,
                fileName: url.lastPathComponent,
                mimeType: image.mimeType
            )
        }
        guard let urlString = screenshot.remoteURL,
              let previewURL = URL(string: urlString),
              previewURL.scheme?.hasPrefix("http") == true else {
            throw APIError.unsupported("Refresh this Google Play screenshot gallery before reordering it.")
        }
        guard let originalURL = googlePlayOriginalImageURL(from: previewURL) else {
            throw APIError.unsupported(
                "Google Play only returned a preview for this screenshot, so Escale cannot safely recover the original image for reordering."
            )
        }
        let response = try await HTTPTransport.send(url: originalURL, timeout: 120)
        let responseType = response.response.mimeType?.lowercased()
        let mimeType: String
        let fileExtension: String
        if responseType == "image/png" || response.data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            mimeType = "image/png"
            fileExtension = "png"
        } else if responseType == "image/jpeg" || response.data.starts(with: [0xFF, 0xD8, 0xFF]) {
            mimeType = "image/jpeg"
            fileExtension = "jpg"
        } else {
            throw APIError.unsupported("Google Play returned a screenshot format that cannot be safely re-uploaded.")
        }
        guard let image = screenshotImageProperties(from: response.data) else {
            throw APIError.unsupported("Google Play returned an unreadable original screenshot.")
        }
        if let issue = screenshotUploadValidationIssue(
            properties: image.properties,
            platform: .playStore,
            device: screenshot.device
        ) {
            throw APIError.unsupported(
                "Google Play’s recovered screenshot cannot be safely re-uploaded: \(issue)"
            )
        }
        return GooglePlayScreenshotUpload(
            data: response.data,
            fileName: "\(screenshot.remoteID ?? screenshot.id.uuidString).\(fileExtension)",
            mimeType: mimeType
        )
    }

    private func mutateScreenshotDraft(
        appID: UUID,
        _ mutation: (inout ScreenshotDraftState) -> Void
    ) {
        var drafts = workspace.screenshotDraftsByApp ?? [:]
        var draft = drafts[appID] ?? ScreenshotDraftState()
        mutation(&draft)
        if draft.isEmpty {
            drafts.removeValue(forKey: appID)
        } else {
            drafts[appID] = draft
        }
        workspace.screenshotDraftsByApp = drafts.isEmpty ? nil : drafts
    }

    private func markScreenshotGalleryDirty(_ screenshot: StoreScreenshot, appID: UUID) {
        mutateScreenshotDraft(appID: appID) {
            $0.dirtyGalleryKeys.insert(screenshotGalleryKey(screenshot))
        }
    }

    private func completeScreenshotGalleryDraft(
        _ galleryKey: String,
        appID: UUID,
        screenshotIDs: Set<UUID>? = nil,
        removeLocalFiles: Bool = true
    ) {
        let targetIDs = screenshotIDs ?? Set(
            workspace.screenshotsByApp[appID, default: []]
                .filter { screenshotGalleryKey($0) == galleryKey }
                .map(\.id)
        )
        for screenshotID in targetIDs {
            guard let index = workspace.screenshotsByApp[appID]?.firstIndex(where: {
                $0.id == screenshotID
            }) else {
                continue
            }
            if removeLocalFiles {
                removeScreenshotDraftFile(for: workspace.screenshotsByApp[appID]![index])
                workspace.screenshotsByApp[appID]?[index].localDraftURL = nil
            }
        }
        mutateScreenshotDraft(appID: appID) {
            $0.dirtyGalleryKeys.remove(galleryKey)
            $0.deletedScreenshots.removeAll {
                screenshotGalleryKey($0) == galleryKey
            }
        }
    }

    private func cacheScreenshotDraft(
        data: Data,
        appID: UUID,
        screenshotID: UUID,
        fileExtension: String
    ) throws -> URL {
        let directory = screenshotDraftDirectory
            .appending(path: appID.uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory.appending(
            path: screenshotID.uuidString + "." + fileExtension,
            directoryHint: .notDirectory
        )
        try data.write(to: url, options: .atomic)
        return url
    }

    private var screenshotDraftDirectory: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return base
            .appending(path: "Escale", directoryHint: .isDirectory)
            .appending(path: "ScreenshotDrafts", directoryHint: .isDirectory)
    }

    private func removeScreenshotDraftFile(for screenshot: StoreScreenshot) {
        guard let value = screenshot.localDraftURL,
              let url = URL(string: value) else {
            return
        }
        let rootPath = screenshotDraftDirectory.standardizedFileURL.path + "/"
        let target = url.standardizedFileURL
        guard target.path.hasPrefix(rootPath) else { return }
        try? FileManager.default.removeItem(at: target)
    }

    private func screenshotImageProperties(from data: Data) -> ScreenshotUploadImage? {
        let mimeType: String
        let fileExtension: String
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            mimeType = "image/png"
            fileExtension = "png"
        } else if data.starts(with: [0xFF, 0xD8, 0xFF]) {
            mimeType = "image/jpeg"
            fileExtension = "jpg"
        } else {
            return nil
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let values = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (values[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (values[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue else {
            return nil
        }
        let hasAlpha = (values[kCGImagePropertyHasAlpha] as? NSNumber)?.boolValue ?? false
        return ScreenshotUploadImage(
            properties: ScreenshotImageProperties(
                width: width,
                height: height,
                fileSize: data.count,
                hasAlpha: hasAlpha
            ),
            mimeType: mimeType,
            fileExtension: fileExtension
        )
    }

    private func googleScreenshotImageType(for device: String) -> String? {
        switch device {
        case "Phone": "phoneScreenshots"
        case "Tablet", "Tablet 10″": "tenInchScreenshots"
        case "Tablet 7″": "sevenInchScreenshots"
        case "TV": "tvScreenshots"
        default: nil
        }
    }

    private func screenshotCount(
        appID: UUID,
        platform: StorePlatform,
        locale: String,
        galleryType: String
    ) -> Int {
        workspace.screenshotsByApp[appID, default: []].filter {
            guard $0.platform == platform,
                  canonicalStoreLocale($0.locale) == canonicalStoreLocale(locale) else {
                return false
            }
            if platform == .appStore {
                return screenshotDevice($0.device, matchesDisplayType: galleryType)
            }
            return $0.screenshotSetID == galleryType
        }.count
    }

    private func screenshotDevice(_ remoteDevice: String, matchesDisplayType displayType: String) -> Bool {
        if remoteDevice.caseInsensitiveCompare("Phone") == .orderedSame,
           displayType.contains("IPHONE") {
            return true
        }
        if remoteDevice.caseInsensitiveCompare("Tablet") == .orderedSame,
           displayType.contains("IPAD") {
            return true
        }
        if displayType == "APP_DESKTOP" {
            return remoteDevice.localizedCaseInsensitiveContains("Desktop")
        }
        if displayType == "APP_APPLE_TV" {
            return remoteDevice.localizedCaseInsensitiveContains("TV")
        }
        let remote = remoteDevice.lowercased().filter { $0.isLetter || $0.isNumber }
        let display = displayType
            .replacingOccurrences(of: "APP_", with: "")
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        return remote == display
    }

    public func deleteScreenshot(_ id: UUID) {
        guard let appID = selectedAppID,
              savingScreenshotPlatforms.isEmpty,
              deletingScreenshotIDs.isEmpty,
              let app = workspace.apps.first(where: { $0.id == appID }),
              let screenshot = workspace.screenshotsByApp[appID]?.first(where: { $0.id == id }) else { return }

        guard let remoteID = screenshot.remoteID else {
            removeLocallyDeletedScreenshot(screenshot, appID: appID)
            persist()
            showToast(
                "Unsaved screenshot removed",
                detail: "The local draft was updated.",
                kind: .success
            )
            track(.screenshotOperationCompleted(
                operation: .delete,
                scope: screenshot.platform == .appStore ? .apple : .google,
                result: .success,
                failure: nil
            ))
            return
        }

        if !isDemoMode,
           screenshot.platform == .appStore,
           app.appStoreApp?.hasEditableMetadataVersion != true {
            showToast(
                "Screenshot not deleted",
                detail: "Create or select an editable App Store version before deleting its screenshots.",
                kind: .error
            )
            return
        }

        deletingScreenshotIDs.insert(id)
        showToast(
            "Deleting screenshot…",
            detail: "Updating \(screenshot.platform.rawValue) now.",
            kind: .progress
        )
        Task {
            defer { deletingScreenshotIDs.remove(id) }
            do {
                if !isDemoMode {
                    switch screenshot.platform {
                    case .appStore:
                        guard let credentials = try CredentialStore.apple() else {
                            throw APIError.missingCredentials(.appStore)
                        }
                        try await AppStoreConnectClient(credentials: credentials)
                            .deleteScreenshot(remoteID: remoteID)
                    case .playStore:
                        guard let credentials = try CredentialStore.google(),
                              let packageName = app.playStoreApp?.bundleID else {
                            throw APIError.missingCredentials(.playStore)
                        }
                        try await GooglePlayClient(credentials: credentials).deleteScreenshot(
                            remoteID: remoteID,
                            packageName: packageName,
                            language: screenshot.locale,
                            imageType: screenshot.screenshotSetID ?? "phoneScreenshots"
                        )
                    }
                }
                removeLocallyDeletedScreenshot(screenshot, appID: appID)
                persist()
                showToast(
                    "Screenshot deleted",
                    detail: "\(screenshot.platform.rawValue) was updated.",
                    kind: .success
                )
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

    private func removeLocallyDeletedScreenshot(
        _ screenshot: StoreScreenshot,
        appID: UUID
    ) {
        let galleryKey = screenshotGalleryKey(screenshot)
        workspace.screenshotsByApp[appID]?.removeAll(where: { $0.id == screenshot.id })
        removeScreenshotDraftFile(for: screenshot)
        mutateScreenshotDraft(appID: appID) {
            $0.deletedScreenshots.removeAll { $0.id == screenshot.id }
        }
        let galleryIsEmpty = workspace.screenshotsByApp[appID, default: []]
            .contains { screenshotGalleryKey($0) == galleryKey } == false
        let hasPendingDeletion = workspace.screenshotDraftsByApp?[appID]?
            .deletedScreenshots
            .contains { screenshotGalleryKey($0) == galleryKey } == true
        if galleryIsEmpty && !hasPendingDeletion {
            mutateScreenshotDraft(appID: appID) {
                $0.dirtyGalleryKeys.remove(galleryKey)
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
        guard requireAccess(to: .draftReviewReplies) else { return nil }
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
            var refreshedApp = snapshot.app
            let cachedRatingSummary = platform == .appStore
                ? workspace.apps[index].appStoreApp?.ratingSummary
                : workspace.apps[index].playStoreApp?.ratingSummary
            if refreshedApp.ratingSummary == nil {
                refreshedApp.ratingSummary = cachedRatingSummary
            }
            if platform == .appStore { workspace.apps[index].appStoreApp = refreshedApp }
            else { workspace.apps[index].playStoreApp = refreshedApp }
            if workspace.apps[index].name.isEmpty || platform == .appStore { workspace.apps[index].name = refreshedApp.name }
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
            let dirtyGalleryKeys = workspace.screenshotDraftsByApp?[appID]?
                .dirtyGalleryKeys
                .filter { $0.hasPrefix(platform.rawValue + "|") } ?? []
            workspace.screenshotsByApp[appID, default: []].removeAll {
                $0.platform == platform
                    && !dirtyGalleryKeys.contains(screenshotGalleryKey($0))
            }
            workspace.screenshotsByApp[appID, default: []].append(
                contentsOf: snapshot.screenshots.filter {
                    !dirtyGalleryKeys.contains(screenshotGalleryKey($0))
                }
            )
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
                    local.playStoreTitle = remote.playStoreTitle
                    local.shortDescription = remote.shortDescription
                    local.playStoreFullDescription = remote.playStoreFullDescription
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
