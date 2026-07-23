import Testing
import CryptoKit
import Foundation
import Security
@testable import Gouvernail

@Test("Demo workspace links matching store identifiers")
func linkedStoreIdentifiers() {
    let workspace = SampleData.workspace()
    let app = workspace.apps.first
    #expect(app?.appStoreApp?.bundleID == app?.playStoreApp?.bundleID)
    #expect(app?.linkedCount == 2)
}

@Test("Persisted store data is treated as loaded after relaunch")
func persistedWorkspaceCache() {
    let cached = SampleData.workspace()
    #expect(cachedAppIDs(in: cached) == Set(cached.apps.map(\.id)))

    let imported = UnifiedApp(
        id: UUID(), name: "Not fetched", symbol: "app.fill", tintHex: 0x123456,
        appStoreApp: StoreApp(
            id: UUID(), platform: .appStore, name: "Not fetched", bundleID: "com.example.notfetched",
            storeID: "123", version: "—", state: .draft, versionID: nil, appInfoID: nil
        ),
        playStoreApp: nil
    )
    var workspace = Workspace.empty
    workspace.apps = [imported]
    #expect(cachedAppIDs(in: workspace).isEmpty)
}

@Test("PPP suggestions reduce prices in lower purchasing-power markets")
func pppSuggestions() {
    let product = SampleData.products()[0]
    let india = product.regions.first(where: { $0.code == "IN" })
    let unitedStates = product.regions.first(where: { $0.code == "US" })
    #expect(india != nil)
    #expect(unitedStates != nil)
    #expect(india!.suggestedPrice < unitedStates!.suggestedPrice)
    #expect(india!.suggestedPrice > 0)
}

@Test("Localization completion reflects missing metadata")
func localizationHealth() {
    let localizations = SampleData.localizations()
    #expect(localizations[0].completion == 1)
    #expect(localizations[2].completion < 0.5)
}

@Test("Metadata limits follow the selected store")
func metadataLimits() {
    var localization = SampleData.localizations()[0]
    localization.subtitle = String(repeating: "a", count: 31)
    let appleViolations = ListingMetadataLimits(platforms: [.appStore]).violations(in: localization, platforms: [.appStore])
    #expect(appleViolations.contains("Subtitle / short description exceeds 30 characters"))
    #expect(ListingMetadataLimits(platforms: [.playStore]).violations(in: localization, platforms: [.playStore]).isEmpty)
    localization.subtitle = String(repeating: "a", count: 81)
    #expect(!ListingMetadataLimits(platforms: [.playStore]).violations(in: localization, platforms: [.playStore]).isEmpty)
}

@Test("App Store editable states are explicit")
func editableAppStoreState() {
    let base = StoreApp(id: UUID(), platform: .appStore, name: "App", bundleID: "com.example.app", storeID: "1", version: "1.0", state: .ready, versionID: "v1", appInfoID: "i1")
    var draft = base
    draft.remoteState = "PREPARE_FOR_SUBMISSION"
    #expect(draft.hasEditableMetadataVersion)
    var live = base
    live.remoteState = "READY_FOR_DISTRIBUTION"
    #expect(!live.hasEditableMetadataVersion)
}

@Test("Store locale aliases merge without collapsing regional variants")
func localeCanonicalization() {
    #expect(canonicalStoreLocale("ja") == canonicalStoreLocale("ja-JP"))
    #expect(canonicalStoreLocale("he") == canonicalStoreLocale("iw-IL"))
    #expect(canonicalStoreLocale("zh-Hans") == canonicalStoreLocale("zh-CN"))
    #expect(canonicalStoreLocale("pt-BR") != canonicalStoreLocale("pt-PT"))
    #expect(googleLocale(forAppleLocale: "ja") == "ja-JP")
}

@Test("Store primary locale drives the AI translation source")
func primaryStoreLocalizationSelection() throws {
    let english = ListingLocalization(
        id: UUID(), locale: "en-US", language: "English", title: "English title", subtitle: "",
        promotionalText: "", description: "", keywords: "", releaseNotes: "", dirtyPlatforms: [],
        lastSaved: nil, appleVersionLocalizationID: nil, appleAppInfoLocalizationID: nil, googleLanguage: nil
    )
    let french = ListingLocalization(
        id: UUID(), locale: "fr-FR", language: "French", title: "Titre français", subtitle: "",
        promotionalText: "", description: "", keywords: "", releaseNotes: "", dirtyPlatforms: [],
        lastSaved: nil, appleVersionLocalizationID: nil, appleAppInfoLocalizationID: nil, googleLanguage: nil
    )

    #expect(primaryLocalization(in: [english, french], preferredLocale: "fr-FR")?.id == french.id)
    #expect(primaryLocalization(in: [english, french], preferredLocale: nil)?.id == english.id)
}

@Test("A metadata field reads, updates, and respects its store limit")
func listingMetadataFieldAccess() {
    var localization = SampleData.localizations()[0]
    ListingMetadataField.releaseNotes.set("A focused update.", in: &localization)
    #expect(ListingMetadataField.releaseNotes.value(in: localization) == "A focused update.")
    #expect(ListingMetadataField.subtitle.characterLimit(in: ListingMetadataLimits(platforms: [.appStore])) == 30)
    #expect(ListingMetadataField.subtitle.characterLimit(in: ListingMetadataLimits(platforms: [.playStore])) == 80)
}

@Test("Apple and Google listing copy remain independently editable")
func platformSpecificListingMetadata() {
    var stored = SampleData.localizations()[0]
    stored.title = "Apple title"
    stored.subtitle = "Apple subtitle"
    stored.description = "Apple description"
    stored.googleTitle = "Google title"
    stored.googleSubtitle = "Google short description"
    stored.googleDescription = "Google full description"

    var googleDisplay = listingLocalization(stored, displaying: [.playStore])
    #expect(googleDisplay.title == "Google title")
    #expect(googleDisplay.description == "Google full description")
    googleDisplay.title = "Updated Google title"

    let updated = applyingListingMetadata(from: googleDisplay, to: stored, platforms: [.playStore])
    #expect(updated.title == "Apple title")
    #expect(updated.googleTitle == "Updated Google title")
}

@Test("Google draft commits never submit or cancel an in-review change")
func googleDraftCommitSafety() {
    let query = Dictionary(uniqueKeysWithValues: googleDraftCommitQueryItems().map { ($0.name, $0.value) })
    #expect(query["changesNotSentForReview"] == "true")
    #expect(query["changesInReviewBehavior"] == "ERROR_IF_IN_REVIEW")
}

@Test("Google automatic-review fallback omits only the unsupported hold flag")
func googleAutomaticReviewCommitFallback() {
    let query = Dictionary(uniqueKeysWithValues: googleAutomaticReviewCommitQueryItems().map { ($0.name, $0.value) })
    #expect(query["changesNotSentForReview"] == nil)
    #expect(query["changesInReviewBehavior"] == "ERROR_IF_IN_REVIEW")

    let expected = APIError.http(
        status: 400,
        message: "Changes are sent for review automatically. The query parameter changesNotSentorReview must not be set."
    )
    #expect(googleRequiresAutomaticReviewSubmission(expected))
    #expect(!googleRequiresAutomaticReviewSubmission(APIError.http(status: 400, message: "Invalid listing title")))
    #expect(!googleRequiresAutomaticReviewSubmission(APIError.http(status: 409, message: "Changes are sent for review automatically. changesNotSentForReview must not be set.")))
}

@Test("Google Play release-note blocks preserve locale tags and multiline copy")
func googlePlayReleaseNoteBlocks() {
    let initial = """
    <en-US>
    Faster sync.
    Better search.
    </en-US>

    <fr-FR>
    Synchronisation accélérée.
    </fr-FR>
    """
    #expect(googlePlayReleaseNote(in: initial, locale: "en-US") == "Faster sync.\nBetter search.")
    #expect(googlePlayReleaseNote(in: initial, locale: "fr-FR") == "Synchronisation accélérée.")

    let updated = replacingGooglePlayReleaseNote(
        in: initial,
        locale: "de-DE",
        text: "Schnellere Synchronisierung.",
        orderedLocales: ["en-US", "de-DE", "fr-FR"]
    )
    #expect(updated.contains("<de-DE>\nSchnellere Synchronisierung.\n</de-DE>"))
    #expect(updated.range(of: "<de-DE>")!.lowerBound < updated.range(of: "<fr-FR>")!.lowerBound)
    #expect(googlePlayReleaseNotesValidationIssues(updated).isEmpty)
}

@Test("Google Play release-note validation enforces the per-language limit")
func googlePlayReleaseNoteLimits() {
    let oversized = "<en-US>\n\(String(repeating: "a", count: 501))\n</en-US>"
    #expect(googlePlayReleaseNotesValidationIssues(oversized) == ["en-US exceeds 500 characters."])
    #expect(!googlePlayReleaseNotesValidationIssues("not tagged").isEmpty)
}

@Test("Legacy Google Play prices use micros rather than Money")
func googleLegacyPriceEncoding() {
    let encoded = googleLegacyPriceObject(value: 4.99, currency: "USD")
    #expect(encoded["priceMicros"] as? String == "4990000")
    #expect(encoded["currency"] as? String == "USD")
    #expect(googleLegacyPriceValue(encoded) == 4.99)
    #expect(encoded["units"] == nil)
}

@Test("A migrated Google catalog ignores the expected legacy endpoint rejection")
func googleLegacyCatalogMigrationResponse() {
    #expect(googleLegacyCatalogRequiresMigration(APIError.http(
        status: 403,
        message: "Please migrate to the new publishing API."
    )))
    #expect(!googleLegacyCatalogRequiresMigration(APIError.http(
        status: 403,
        message: "The caller does not have permission"
    )))
    #expect(!googleLegacyCatalogRequiresMigration(APIError.http(
        status: 500,
        message: "Please migrate to the new publishing API."
    )))
}

@Test("Subscriptions preserve existing prices by default")
func subscriberPricingDefault() {
    let product = StoreProduct(
        id: UUID(), name: "Monthly", productID: "monthly", kind: "Auto-renewable subscription", basePrice: 9.99,
        platforms: [.appStore, .playStore], regions: [], appleProductID: "apple", googleProductID: "google", googleBasePlanID: "monthly"
    )
    #expect(product.isSubscription)
    #expect(product.effectiveSubscriberPricePolicy == .preserve)
    #expect(product.effectivePricingIndex == .worldwidePPP)
}

@Test("Google base plans remain distinct during refresh")
func googleBasePlanIdentity() {
    let appleOnly = StoreProduct(
        id: UUID(), name: "Monthly", productID: "pro", kind: "Auto-renewable subscription",
        basePrice: 9.99, platforms: [.appStore], regions: [], appleProductID: "apple-pro",
        googleProductID: nil, googleBasePlanID: nil
    )
    let monthly = StoreProduct(
        id: UUID(), name: "Monthly", productID: "pro", kind: "Subscription",
        basePrice: 9.99, platforms: [.playStore], regions: [], appleProductID: nil,
        googleProductID: "pro", googleBasePlanID: "monthly"
    )
    let annual = StoreProduct(
        id: UUID(), name: "Annual", productID: "pro", kind: "Subscription",
        basePrice: 79.99, platforms: [.playStore], regions: [], appleProductID: nil,
        googleProductID: "pro", googleBasePlanID: "annual"
    )
    #expect(!storeProductsMatch(appleOnly, monthly, on: .playStore))
    #expect(storeProductsMatch(monthly, monthly, on: .playStore))
    #expect(!storeProductsMatch(monthly, annual, on: .playStore))
}

@Test("Apple and Google regional catalogs never share pricing state")
func crossStoreProductsAreSplit() throws {
    let combined = StoreProduct(
        id: UUID(), name: "Pro", productID: "pro", kind: "Subscription",
        basePrice: 9.99, platforms: [.appStore, .playStore], regions: [],
        appleProductID: "apple-pro", googleProductID: "google-pro", googleBasePlanID: "monthly",
        pricingIndex: .bigMac, subscriberPricePolicy: .preserve, pricingCalculatedAt: Date(),
        pricingSourceSummary: "Combined stale pricing"
    )
    let split = splitCrossStoreProducts([combined])
    #expect(split.count == 2)
    let apple = try #require(split.first(where: { $0.platforms == [.appStore] }))
    let google = try #require(split.first(where: { $0.platforms == [.playStore] }))
    #expect(apple.googleProductID == nil)
    #expect(google.appleProductID == nil)
    #expect(google.googleBasePlanID == "monthly")
    #expect(apple.pricingCalculatedAt == nil)
    #expect(google.pricingCalculatedAt == nil)
}

@Test("App Store refresh replaces stale territory prices even when the base price is unchanged")
func appStoreRefreshReplacesTerritoryPrices() throws {
    let productID = UUID()
    let staleAfghanistan = PriceRegion(
        code: "AF", country: "Afghanistan", flag: "🇦🇫", currency: "USD",
        pppIndex: 1, currentPrice: 4.99, suggestedPrice: 4.99, enabled: true
    )
    let liveAfghanistan = PriceRegion(
        code: "AF", country: "Afghanistan", flag: "🇦🇫", currency: "USD",
        pppIndex: 1, currentPrice: 3.99, suggestedPrice: 3.99, enabled: true
    )
    var cached = StoreProduct(
        id: productID, name: "Weekly", productID: "weekly", kind: "Auto-renewable subscription",
        basePrice: 4.99, platforms: [.appStore], regions: [staleAfghanistan], appleProductID: "apple-old"
    )
    cached.pricingIndex = .bigMac
    cached.subscriberPricePolicy = .preserve
    cached.pricingCalculatedAt = Date()
    cached.pricingSourceSummary = "Stale calculation"

    let remote = StoreProduct(
        id: UUID(), name: "Weekly live name", productID: "weekly", kind: "Auto-renewable subscription",
        basePrice: 4.99, platforms: [.appStore], regions: [liveAfghanistan], appleProductID: "apple-live"
    )
    let refreshed = refreshedStoreProduct(cached, with: remote, from: .appStore)

    #expect(refreshed.basePrice == 4.99)
    #expect(refreshed.name == "Weekly live name")
    #expect(try #require(refreshed.regions.first(where: { $0.code == "AF" })).currentPrice == 3.99)
    #expect(refreshed.appleProductID == "apple-live")
    #expect(refreshed.pricingIndex == .bigMac)
    #expect(refreshed.subscriberPricePolicy == .preserve)
    #expect(refreshed.pricingCalculatedAt == nil)
    #expect(refreshed.pricingSourceSummary == nil)
}

@Test("Creating an App Store version preserves unsaved AI localization copy")
func creatingVersionPreservesPendingLocalization() throws {
    var pending = ListingLocalization(
        id: UUID(), locale: "fr-FR", language: "French", title: "Mon application",
        subtitle: "Sous-titre traduit", promotionalText: "Texte traduit",
        description: "Description traduite", keywords: "outil,productivité",
        releaseNotes: "Nouveautés traduites", dirtyPlatforms: [.appStore], lastSaved: nil,
        appleVersionLocalizationID: "old-live-version-localization",
        appleAppInfoLocalizationID: nil, googleLanguage: nil
    )
    pending.lastSaved = nil
    let fetchedDraft = ListingLocalization(
        id: UUID(), locale: "fr-FR", language: "French", title: "Remote title",
        subtitle: "Remote subtitle", promotionalText: "Previous promotional text",
        description: "Remote description", keywords: "remote", releaseNotes: "",
        dirtyPlatforms: [], lastSaved: Date(),
        appleVersionLocalizationID: "remote-draft-localization",
        appleAppInfoLocalizationID: "remote-app-info-localization", googleLanguage: nil
    )

    let result = localizationsAfterCreatingAppStoreVersion(cached: [pending], draft: [fetchedDraft])
    let preserved = try #require(result.first)

    #expect(preserved.title == "Mon application")
    #expect(preserved.promotionalText == "Texte traduit")
    #expect(preserved.description == "Description traduite")
    #expect(preserved.dirtyPlatforms.contains(.appStore))
    #expect(preserved.appleVersionLocalizationID == nil)
}

@Test("Editable App Info is selected instead of the locked live record")
func editableAppInfoSelection() {
    let candidates = [
        AppInfoCandidate(id: "live", state: "READY_FOR_DISTRIBUTION"),
        AppInfoCandidate(id: "draft", state: "PREPARE_FOR_SUBMISSION")
    ]
    #expect(preferredAppInfoID(
        from: candidates,
        editableStates: ["PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED"]
    ) == "draft")
    #expect(preferredAppInfoID(
        from: [candidates[0]],
        editableStates: ["PREPARE_FOR_SUBMISSION"]
    ) == "live")
}

@Test("Unchanged App Info fields are omitted from localization updates")
func unchangedAppInfoFieldsAreOmitted() {
    #expect(changedAppInfoLocalizationAttributes(
        title: "Gouvernail", subtitle: "Store operations",
        remoteTitle: "Gouvernail", remoteSubtitle: "Store operations"
    ).isEmpty)
    #expect(changedAppInfoLocalizationAttributes(
        title: "Gouvernail", subtitle: "Faster store operations",
        remoteTitle: "Gouvernail", remoteSubtitle: "Store operations"
    ) == ["subtitle": "Faster store operations"])
}

@Test("Active App Store subscription price ignores future and preserved cohorts")
func activeSubscriptionPrice() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let entries = [
        SubscriptionPriceCandidate(pricePointID: "original", startDate: nil, preserved: true, planType: "MONTHLY"),
        SubscriptionPriceCandidate(pricePointID: "active", startDate: now.addingTimeInterval(-86_400), preserved: false, planType: "MONTHLY"),
        SubscriptionPriceCandidate(pricePointID: "future", startDate: now.addingTimeInterval(86_400), preserved: false, planType: "MONTHLY"),
        SubscriptionPriceCandidate(pricePointID: "upfront", startDate: now.addingTimeInterval(-60), preserved: false, planType: "UPFRONT")
    ]
    #expect(effectiveSubscriptionPriceCandidate(entries, on: now)?.pricePointID == "active")
    #expect(effectiveSubscriptionPriceCandidate([entries[0]], on: now)?.pricePointID == "original")
}

@Test("Approved App Store subscriptions receive scheduled price changes")
func approvedSubscriptionPriceChangePlan() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
    let now = try #require(calendar.date(from: DateComponents(
        year: 2026, month: 7, day: 22, hour: 23, minute: 30
    )))
    let startDate = appleSubscriptionPriceChangeStartDate(now: now)

    #expect(startDate == "2026-07-24")
    #expect(appleSubscriptionPriceChangePlan(
        currentPrice: 4.99, resolvedPrice: 4.99, policy: .preserve, startDate: startDate
    ) == nil)
    #expect(appleSubscriptionPriceChangePlan(
        currentPrice: 3.99, resolvedPrice: 4.99, policy: .preserve, startDate: startDate
    ) == AppleSubscriptionPriceChangePlan(startDate: "2026-07-24", preserveCurrentPrice: true))
    #expect(appleSubscriptionPriceChangePlan(
        currentPrice: 3.99, resolvedPrice: 4.99, policy: .migrate, startDate: startDate
    ) == AppleSubscriptionPriceChangePlan(startDate: "2026-07-24", preserveCurrentPrice: false))
    #expect(appleSubscriptionPriceChangePlan(
        currentPrice: 4.99, resolvedPrice: 3.99, policy: .preserve, startDate: startDate
    ) == AppleSubscriptionPriceChangePlan(startDate: "2026-07-24", preserveCurrentPrice: false))
}

@Test("Pricing apply skips unchanged and disabled markets")
func pricingApplyFiltersNoOpMarkets() {
    let regions = [
        PriceRegion(
            code: "AF", country: "Afghanistan", flag: "🇦🇫", currency: "USD",
            pppIndex: 1, currentPrice: 3.99, suggestedPrice: 3.99, enabled: true
        ),
        PriceRegion(
            code: "AL", country: "Albania", flag: "🇦🇱", currency: "USD",
            pppIndex: 0.8, currentPrice: 4.99, suggestedPrice: 3.99, enabled: true
        ),
        PriceRegion(
            code: "DZ", country: "Algeria", flag: "🇩🇿", currency: "USD",
            pppIndex: 0.8, currentPrice: 4.99, suggestedPrice: 3.99, enabled: false
        )
    ]
    #expect(regionsRequiringPriceChange(regions).map(\.code) == ["AL"])
    #expect(PricingApplyProgress(platform: .appStore, completed: 2, total: 4, detail: "").fraction == 0.5)
}

@Test("Optional live pricing-index sources smoke test")
func livePricingIndexes() async throws {
    guard ProcessInfo.processInfo.environment["GOUVERNAIL_LIVE_PRICING_INDEX"] == "1" else { return }
    for index in PricingIndex.allCases {
        let result = try await PricingIndexService().factors(for: index)
        #expect(result.factors["US"] == 1)
        #expect(result.factors.count > 20)
        #expect(result.directMarketCount > 10)
    }
}

@Test("App Store Connect JWT is signed as ES256")
func appleJWT() throws {
    let key = P256.Signing.PrivateKey()
    let credentials = AppleCredentials(issuerID: "issuer", keyID: "key-id", privateKeyPEM: key.pemRepresentation)
    let token = try JWTSigner.appleToken(credentials: credentials, now: Date(timeIntervalSince1970: 1_700_000_000))
    #expect(token.split(separator: ".").count == 3)
}

@Test("Google service-account assertion is signed as RS256")
func googleJWT() throws {
    let attributes: [String: Any] = [
        kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
        kSecAttrKeySizeInBits as String: 2048
    ]
    var error: Unmanaged<CFError>?
    let key = try #require(SecKeyCreateRandomKey(attributes as CFDictionary, &error))
    let data = try #require(SecKeyCopyExternalRepresentation(key, &error) as Data?)
    let pem = "-----BEGIN RSA PRIVATE KEY-----\n\(data.base64EncodedString(options: .lineLength64Characters))\n-----END RSA PRIVATE KEY-----"
    let credentials = GoogleServiceAccount(
        type: "service_account", projectID: "project", privateKeyID: "key-id", privateKey: pem,
        clientEmail: "service@example.iam.gserviceaccount.com", tokenURI: "https://oauth2.googleapis.com/token"
    )
    let token = try JWTSigner.googleAssertion(credentials: credentials, now: Date(timeIntervalSince1970: 1_700_000_000))
    #expect(token.split(separator: ".").count == 3)
}

@Test("OpenAI Responses API structured translation is decoded")
func openAITranslationResponse() throws {
    let expected = OpenAITranslation(
        title: "Mon application",
        subtitle: "Un espace plus clair",
        promotionalText: "Avancez chaque jour.",
        description: "Une description complète.",
        keywords: "organisation,concentration",
        releaseNotes: "Nouveau cette semaine."
    )
    let translatedJSON = String(data: try JSONEncoder().encode(expected), encoding: .utf8)!
    let envelope: [String: Any] = [
        "status": "completed",
        "output": [[
            "type": "message",
            "content": [["type": "output_text", "text": translatedJSON]]
        ]]
    ]
    let decoded = try OpenAIClient.decodeTranslationResponse(JSONSerialization.data(withJSONObject: envelope))
    #expect(decoded == expected)
}

@Test("OpenAI Responses API field translation is decoded")
func openAIFieldTranslationResponse() throws {
    let translatedJSON = #"{"translatedText":"Nouveau cette semaine."}"#
    let envelope: [String: Any] = [
        "status": "completed",
        "output": [[
            "type": "message",
            "content": [["type": "output_text", "text": translatedJSON]]
        ]]
    ]
    let decoded = try OpenAIClient.decodeFieldTranslationResponse(JSONSerialization.data(withJSONObject: envelope))
    #expect(decoded == "Nouveau cette semaine.")
}

@Test("Optional live App Store Connect read smoke test")
func liveAppleRead() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let issuer = environment["GOUVERNAIL_APPLE_ISSUER_ID"],
          let keyID = environment["GOUVERNAIL_APPLE_KEY_ID"],
          let keyPath = environment["GOUVERNAIL_APPLE_P8_PATH"] else { return }
    let pem = try String(contentsOfFile: keyPath, encoding: .utf8)
    let apps = try await AppStoreConnectClient(credentials: AppleCredentials(issuerID: issuer, keyID: keyID, privateKeyPEM: pem)).listApps()
    #expect(apps.allSatisfy { !$0.storeID.isEmpty && !$0.bundleID.isEmpty })
}

@Test("Optional live Google Play package smoke test")
func liveGoogleRead() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let jsonPath = environment["GOUVERNAIL_GOOGLE_SERVICE_ACCOUNT_PATH"],
          let packageName = environment["GOUVERNAIL_GOOGLE_PACKAGE"] else { return }
    let data = try Data(contentsOf: URL(fileURLWithPath: jsonPath))
    let credentials = try JSONDecoder().decode(GoogleServiceAccount.self, from: data)
    let snapshot = try await GooglePlayClient(credentials: credentials).fetchSnapshot(packageName: packageName)
    #expect(snapshot.app.bundleID == packageName)
}

@Test("Optional live OpenAI credential smoke test")
func liveOpenAIRead() async throws {
    guard let apiKey = ProcessInfo.processInfo.environment["GOUVERNAIL_OPENAI_API_KEY"] else { return }
    try await OpenAIClient(apiKey: apiKey).validateConnection()
}
