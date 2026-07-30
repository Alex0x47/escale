import Testing
import CryptoKit
import Foundation
import Security
@testable import EscaleCore

private struct TestProEntitlements: EscaleEntitlementProviding {
    let plan = EscalePlan.pro
    let enabledFeatures: Set<EscaleFeature>

    func hasAccess(to feature: EscaleFeature) -> Bool {
        enabledFeatures.contains(feature)
    }
}

@Test("Community entitlements include iOS version creation but keep Pro capabilities locked")
func communityEntitlements() {
    let entitlements = CommunityEntitlements()

    #expect(entitlements.plan == .community)
    #expect(entitlements.hasAccess(to: .createAppStoreVersion))
    #expect(
        EscaleFeature.allCases
            .filter { $0 != .createAppStoreVersion }
            .allSatisfy { !entitlements.hasAccess(to: $0) }
    )
}

@Test("A private entitlement provider can unlock selected Pro capabilities")
func extensibleProEntitlements() {
    let entitlements = TestProEntitlements(
        enabledFeatures: [
            .applyRegionalPricing,
            .bulkTranslations,
            .createAppStoreVersion,
            .uploadGooglePlayBundle,
            .releaseNoteTemplates,
            .draftReviewReplies
        ]
    )

    #expect(entitlements.plan == .pro)
    #expect(entitlements.hasAccess(to: .applyRegionalPricing))
    #expect(entitlements.hasAccess(to: .bulkTranslations))
    #expect(entitlements.hasAccess(to: .createAppStoreVersion))
    #expect(entitlements.hasAccess(to: .uploadGooglePlayBundle))
    #expect(entitlements.hasAccess(to: .releaseNoteTemplates))
    #expect(entitlements.hasAccess(to: .draftReviewReplies))
}

@Test("Community cannot mutate What’s New templates")
@MainActor
func communityReleaseNoteTemplateGate() {
    let store = WorkspaceStore(entitlements: CommunityEntitlements())
    let originalTemplates = store.workspace.releaseNoteTemplates

    #expect(store.createReleaseNoteTemplate(name: "Maintenance", body: "Bug fixes.") == nil)
    #expect(store.workspace.releaseNoteTemplates == originalTemplates)
    #expect(store.toast?.title == "Escale Pro required")
}

@Test("Community cannot draft customer review replies with AI")
@MainActor
func communityReviewReplyDraftGate() async {
    let store = WorkspaceStore(entitlements: CommunityEntitlements())

    #expect(await store.draftReviewReply(to: UUID()) == nil)
    #expect(store.toast?.title == "Escale Pro required")
    #expect(store.toast?.detail == EscaleFeature.draftReviewReplies.upgradeDescription)
}

@Test("A hard reset targets every Escale-owned Keychain item")
func hardResetKeychainScope() {
    #expect(escaleResetKeychainItems == [
        EscaleKeychainItem(service: "app.escale.mac.credentials", account: "app-store-connect"),
        EscaleKeychainItem(service: "app.escale.mac.credentials", account: "google-play-service-account"),
        EscaleKeychainItem(service: "app.escale.mac.credentials", account: "openai-api-key"),
        EscaleKeychainItem(service: "app.gouvernail.mac.credentials", account: "app-store-connect"),
        EscaleKeychainItem(service: "app.gouvernail.mac.credentials", account: "google-play-service-account"),
        EscaleKeychainItem(service: "app.gouvernail.mac.credentials", account: "openai-api-key"),
        EscaleKeychainItem(service: "app.escale.mac.pro-license", account: "active-license"),
        EscaleKeychainItem(service: "app.escale.mac.pro-promotion", account: "installation-id")
    ])
}

@Test("A hard reset attempts every Keychain item and reports only failures")
func hardResetContinuesAfterKeychainFailure() {
    let items = [
        EscaleKeychainItem(service: "app.escale.mac.credentials", account: "app-store-connect"),
        EscaleKeychainItem(service: "app.gouvernail.mac.credentials", account: "app-store-connect"),
        EscaleKeychainItem(service: "app.escale.mac.pro-license", account: "active-license")
    ]
    var attempted: [EscaleKeychainItem] = []

    let failures = keychainDeletionFailures(for: items) { item in
        attempted.append(item)
        return item.service == "app.gouvernail.mac.credentials"
            ? errSecInvalidOwnerEdit
            : errSecItemNotFound
    }

    #expect(attempted == items)
    #expect(failures == [
        EscaleKeychainDeletionFailure(item: items[1], status: errSecInvalidOwnerEdit)
    ])
}

@Test("Demo workspace links matching store identifiers")
func linkedStoreIdentifiers() {
    let workspace = SampleData.workspace()
    let app = workspace.apps.first
    #expect(app?.appStoreApp?.bundleID == app?.playStoreApp?.bundleID)
    #expect(app?.linkedCount == 2)
}

@Test("Store rating summaries combine using rating counts")
func combinedStoreRatings() {
    let summary = combinedStoreRatingSummary([
        StoreRatingSummary(averageRating: 4.8, ratingCount: 900),
        StoreRatingSummary(averageRating: 3.0, ratingCount: 100)
    ])

    #expect(summary?.averageRating == 4.62)
    #expect(summary?.ratingCount == 1_000)
}

@Test("Google Play structured metadata provides the aggregate rating")
func googlePlayAggregateRating() throws {
    let html = """
    <html><head>
    <script type="application/ld+json">
    {
      "@type": "SoftwareApplication",
      "aggregateRating": {
        "@type": "AggregateRating",
        "ratingValue": "4.340425491333008",
        "ratingCount": "36020997"
      }
    }
    </script>
    </head></html>
    """

    let summary = googlePlayRatingSummary(fromHTML: try #require(html.data(using: .utf8)))
    #expect(summary?.averageRating == 4.340425491333008)
    #expect(summary?.ratingCount == 36_020_997)
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

@Test("Suggested App Store versions are valid without further editing")
func suggestedAppStoreVersionValidation() {
    let suggested = suggestedNextAppStoreVersion(from: "2.4")

    #expect(suggested == "2.4.1")
    #expect(isValidAppStoreVersion(suggested))
    #expect(isValidAppStoreVersion(" 3.0.0 "))
    #expect(!isValidAppStoreVersion(""))
    #expect(!isValidAppStoreVersion("3..0"))
    #expect(!isValidAppStoreVersion("3.0.beta"))
    #expect(!isValidAppStoreVersion("3.0.0.1"))
}

@Test("Store apps saved before version details remain decodable")
func legacyStoreAppDecoding() throws {
    let data = Data(
        """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "platform": "App Store",
          "name": "App",
          "bundleID": "com.example.app",
          "storeID": "123456789",
          "version": "1.0",
          "state": "Ready for distribution"
        }
        """.utf8
    )

    let app = try JSONDecoder().decode(StoreApp.self, from: data)
    #expect(app.versionDetails == nil)
    #expect(app.bundleID == "com.example.app")
}

@Test("Store apps link to their developer consoles")
func storeDeveloperConsoleURLs() {
    let apple = StoreApp(
        id: UUID(), platform: .appStore, name: "iOS App", bundleID: "com.example.ios",
        storeID: "1234567890", version: "2.0", state: .draft, versionID: nil, appInfoID: nil
    )
    let android = StoreApp(
        id: UUID(), platform: .playStore, name: "Android App", bundleID: "com.example.android",
        storeID: "com.example.android", version: "2.0", state: .draft, versionID: nil, appInfoID: nil
    )
    var missingAppleID = apple
    missingAppleID.storeID = "  "

    #expect(
        apple.developerConsoleURL?.absoluteString
            == "https://appstoreconnect.apple.com/apps/1234567890/distribution/ios/version/inflight"
    )
    #expect(android.developerConsoleURL?.absoluteString == "https://play.google.com/console/")
    #expect(missingAppleID.developerConsoleURL == nil)
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

@Test("What’s New templates validate reusable names and copy")
func releaseNoteTemplateValidation() {
    #expect(releaseNoteTemplateValidationIssue(name: "", body: "Bug fixes.") == "Give the template a name.")
    #expect(releaseNoteTemplateValidationIssue(name: "Maintenance", body: "  ") == "Add the release notes you want to reuse.")
    #expect(releaseNoteTemplateValidationIssue(name: "Maintenance", body: "Bug fixes and improvements.") == nil)
    #expect(
        releaseNoteTemplateValidationIssue(
            name: String(repeating: "a", count: releaseNoteTemplateNameCharacterLimit + 1),
            body: "Bug fixes."
        ) != nil
    )
    #expect(
        releaseNoteTemplateValidationIssue(
            name: "Long update",
            body: String(repeating: "a", count: releaseNoteTemplateBodyCharacterLimit + 1)
        ) != nil
    )
}

@Test("What’s New templates persist with the workspace while legacy workspaces remain decodable")
func releaseNoteTemplatePersistence() throws {
    let template = ReleaseNoteTemplate(
        id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
        name: "Maintenance update",
        body: "Bug fixes and performance improvements.",
        createdAt: Date(timeIntervalSince1970: 100),
        updatedAt: Date(timeIntervalSince1970: 200)
    )
    var workspace = Workspace.empty
    workspace.releaseNoteTemplates = [template]

    let decoded = try JSONDecoder().decode(
        Workspace.self,
        from: JSONEncoder().encode(workspace)
    )
    #expect(decoded.releaseNoteTemplates == [template])

    let emptyWorkspaceData = try JSONEncoder().encode(Workspace.empty)
    var legacyObject = try #require(
        JSONSerialization.jsonObject(with: emptyWorkspaceData) as? [String: Any]
    )
    legacyObject.removeValue(forKey: "releaseNoteTemplates")
    let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
    let legacyWorkspace = try JSONDecoder().decode(Workspace.self, from: legacyData)
    #expect(legacyWorkspace.releaseNoteTemplates == nil)
}

@Test("Screenshot reordering changes only the selected remote gallery")
func screenshotGalleryReordering() throws {
    let firstID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    let secondID = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
    let thirdID = UUID(uuidString: "10000000-0000-0000-0000-000000000003")!
    let googleID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
    func screenshot(
        id: UUID,
        platform: StorePlatform,
        setID: String
    ) -> StoreScreenshot {
        StoreScreenshot(
            id: id,
            platform: platform,
            locale: "en-US",
            device: "Phone",
            title: id.uuidString,
            caption: "",
            gradientStartHex: 0,
            gradientEndHex: 0,
            remoteID: id.uuidString,
            remoteURL: nil,
            screenshotSetID: setID
        )
    }
    let screenshots = [
        screenshot(id: firstID, platform: .appStore, setID: "apple-phone"),
        screenshot(id: googleID, platform: .playStore, setID: "phoneScreenshots"),
        screenshot(id: secondID, platform: .appStore, setID: "apple-phone"),
        screenshot(id: thirdID, platform: .appStore, setID: "apple-phone")
    ]

    let reordered = try #require(
        screenshotsByMoving(screenshots, screenshotID: thirdID, before: firstID)
    )
    #expect(reordered.map(\.id) == [thirdID, googleID, firstID, secondID])
    #expect(
        screenshotsByMoving(screenshots, screenshotID: firstID, before: googleID) == nil
    )

    let movedToEnd = try #require(
        screenshotsByMoving(reordered, screenshotID: thirdID, before: nil)
    )
    #expect(movedToEnd.map(\.id) == [firstID, googleID, secondID, thirdID])
}

@Test("Screenshot drafts persist while legacy workspaces remain decodable")
func screenshotDraftPersistence() throws {
    let appID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
    let screenshot = StoreScreenshot(
        id: UUID(uuidString: "30000000-0000-0000-0000-000000000002")!,
        platform: .playStore,
        locale: "en-US",
        device: "Phone",
        title: "Draft",
        caption: "",
        gradientStartHex: 0,
        gradientEndHex: 0,
        remoteID: "remote-image",
        remoteURL: "https://example.com/preview.png",
        screenshotSetID: "phoneScreenshots",
        localDraftURL: "file:///tmp/draft.png"
    )
    let galleryKey = screenshotGalleryKey(screenshot)
    var workspace = Workspace.empty
    workspace.screenshotsByApp[appID] = [screenshot]
    workspace.screenshotDraftsByApp = [
        appID: ScreenshotDraftState(
            dirtyGalleryKeys: [galleryKey],
            deletedScreenshots: [screenshot]
        )
    ]

    let encoded = try JSONEncoder().encode(workspace)
    let decoded = try JSONDecoder().decode(Workspace.self, from: encoded)
    #expect(decoded.screenshotDraftsByApp?[appID]?.dirtyGalleryKeys == [galleryKey])
    #expect(decoded.screenshotDraftsByApp?[appID]?.deletedScreenshots == [screenshot])
    #expect(decoded.screenshotsByApp[appID]?.first?.localDraftURL == "file:///tmp/draft.png")

    var legacyObject = try #require(
        JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    legacyObject.removeValue(forKey: "screenshotDraftsByApp")
    let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
    let legacyWorkspace = try JSONDecoder().decode(Workspace.self, from: legacyData)
    #expect(legacyWorkspace.screenshotDraftsByApp == nil)
}

@Test("Screenshot gallery identity includes store, locale, and remote gallery")
func screenshotGalleryIdentity() {
    let base = StoreScreenshot(
        id: UUID(),
        platform: .appStore,
        locale: "en-US",
        device: "Phone",
        title: "",
        caption: "",
        gradientStartHex: 0,
        gradientEndHex: 0,
        remoteID: nil,
        remoteURL: nil,
        screenshotSetID: "iphone-67"
    )
    var localized = base
    localized.locale = "fr-FR"
    var google = base
    google.platform = .playStore
    var anotherSet = base
    anotherSet.screenshotSetID = "iphone-65"

    #expect(screenshotGalleryKey(base) != screenshotGalleryKey(localized))
    #expect(screenshotGalleryKey(base) != screenshotGalleryKey(google))
    #expect(screenshotGalleryKey(base) != screenshotGalleryKey(anotherSet))
}

@Test("Google Play preview URLs resolve to their original-size rendition")
func googlePlayOriginalScreenshotURL() throws {
    let plainPreview = try #require(
        URL(string: "https://lh3.googleusercontent.com/preview-token")
    )
    #expect(
        googlePlayOriginalImageURL(from: plainPreview)?.absoluteString
            == "https://lh3.googleusercontent.com/preview-token=s0"
    )

    let sizedPreview = try #require(
        URL(string: "https://lh3.googleusercontent.com/preview-token=w288-h512-rw")
    )
    #expect(
        googlePlayOriginalImageURL(from: sizedPreview)?.absoluteString
            == "https://lh3.googleusercontent.com/preview-token=s0"
    )
    #expect(
        googlePlayOriginalImageURL(from: URL(string: "https://example.com/image.jpg")!) == nil
    )
}

@Test("Screenshot preflight validation follows each store's required dimensions")
func screenshotUploadValidation() {
    let appStorePhone = ScreenshotImageProperties(
        width: 1_290,
        height: 2_796,
        fileSize: 2_000_000,
        hasAlpha: false
    )
    #expect(
        screenshotUploadValidationIssue(
            properties: appStorePhone,
            platform: .appStore,
            device: "Phone"
        ) == nil
    )
    #expect(
        appStoreScreenshotDisplayType(width: 2_796, height: 1_290, device: "Phone")
            == "APP_IPHONE_67"
    )
    #expect(
        appStoreScreenshotDisplayType(width: 1_280, height: 800, device: "Desktop")
            == "APP_DESKTOP"
    )
    #expect(
        appStoreScreenshotDisplayType(width: 800, height: 1_280, device: "Desktop")
            == nil
    )
    #expect(
        screenshotUploadValidationIssue(
            properties: appStorePhone,
            platform: .appStore,
            device: "Tablet"
        ) != nil
    )

    let googlePortrait = ScreenshotImageProperties(
        width: 1_080,
        height: 1_920,
        fileSize: 2_000_000,
        hasAlpha: false
    )
    #expect(
        screenshotUploadValidationIssue(
            properties: googlePortrait,
            platform: .playStore,
            device: "Phone"
        ) == nil
    )
    #expect(
        screenshotUploadValidationIssue(
            properties: ScreenshotImageProperties(
                width: 300,
                height: 600,
                fileSize: 100_000,
                hasAlpha: false
            ),
            platform: .playStore,
            device: "Phone"
        ) != nil
    )
    #expect(
        screenshotUploadValidationIssue(
            properties: ScreenshotImageProperties(
                width: 1_000,
                height: 2_300,
                fileSize: 100_000,
                hasAlpha: false
            ),
            platform: .playStore,
            device: "Phone"
        ) == nil
    )
    #expect(
        screenshotUploadValidationIssue(
            properties: ScreenshotImageProperties(
                width: 1_000,
                height: 2_301,
                fileSize: 100_000,
                hasAlpha: false
            ),
            platform: .playStore,
            device: "Phone"
        ) != nil
    )
    #expect(
        screenshotUploadValidationIssue(
            properties: ScreenshotImageProperties(
                width: 1_080,
                height: 1_920,
                fileSize: 100_000,
                hasAlpha: true
            ),
            platform: .playStore,
            device: "Phone"
        ) != nil
    )
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

@Test("Listing metadata is dirty only after its displayed copy changes")
func listingMetadataDirtyState() {
    var stored = SampleData.localizations()[0]
    stored.title = "Apple title"
    stored.googleTitle = "Google title"

    let appleDisplay = listingLocalization(stored, displaying: [.appStore])
    let googleDisplay = listingLocalization(stored, displaying: [.playStore])
    let combinedDisplay = listingLocalization(stored, displaying: [.appStore, .playStore])

    #expect(!listingMetadataHasChanges(appleDisplay, comparedTo: stored, displaying: [.appStore]))
    #expect(!listingMetadataHasChanges(googleDisplay, comparedTo: stored, displaying: [.playStore]))
    #expect(!listingMetadataHasChanges(combinedDisplay, comparedTo: stored, displaying: [.appStore, .playStore]))

    var editedDisplay = googleDisplay
    editedDisplay.title = "Updated Google title"
    #expect(listingMetadataHasChanges(editedDisplay, comparedTo: stored, displaying: [.playStore]))
}

@Test("Google draft commits never submit or cancel an in-review change")
func googleDraftCommitSafety() {
    let query = Dictionary(uniqueKeysWithValues: googleDraftCommitQueryItems().map { ($0.name, $0.value) })
    #expect(query["changesNotSentForReview"] == "true")
    #expect(query["changesInReviewBehavior"] == "ERROR_IF_IN_REVIEW")
}

@Test("Android bundle uploads create an editable draft release payload")
func googleBundleDraftReleasePayload() throws {
    let payload = googleDraftReleasePayload(
        track: "production",
        versionCode: 240,
        releaseName: "  2.4.0  ",
        releaseNotes: [
            StoreVersionReleaseNote(language: "en-US", text: "Faster sync."),
            StoreVersionReleaseNote(language: "fr-FR", text: "Synchronisation accélérée.")
        ]
    )
    #expect(payload["track"] as? String == "production")
    let releases = try #require(payload["releases"] as? [[String: Any]])
    let release = try #require(releases.first)
    #expect(release["name"] as? String == "2.4.0")
    #expect(release["status"] as? String == "draft")
    #expect(release["versionCodes"] as? [String] == ["240"])
    let notes = try #require(release["releaseNotes"] as? [[String: String]])
    #expect(notes == [
        ["language": "en-US", "text": "Faster sync."],
        ["language": "fr-FR", "text": "Synchronisation accélérée."]
    ])
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

@Test("Google Play release-note editing preserves spaces")
func googlePlayReleaseNoteSpaces() {
    let text = "A faster sync with better search. "
    let updated = replacingGooglePlayReleaseNote(
        in: "",
        locale: "en-US",
        text: text,
        orderedLocales: ["en-US"]
    )

    #expect(googlePlayReleaseNote(in: updated, locale: "en-US") == text)
    #expect(updated.contains("better search. \n</en-US>"))
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
        title: "Escale", subtitle: "Store operations",
        remoteTitle: "Escale", remoteSubtitle: "Store operations"
    ).isEmpty)
    #expect(changedAppInfoLocalizationAttributes(
        title: "Escale", subtitle: "Faster store operations",
        remoteTitle: "Escale", remoteSubtitle: "Store operations"
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

@Test("App Store pricing includes the US base market and proposed price")
func appStorePricingIncludesUSBaseMarket() throws {
    let existingUS = PriceRegion(
        code: "US", country: "United States", flag: "🇺🇸", currency: "USD",
        pppIndex: 1, currentPrice: 1.99, suggestedPrice: 1.99, enabled: false
    )
    let regions = appleCalculatedPriceRegions(
        resolvedBasePrice: 2.99,
        currentBasePrice: 1.99,
        equalizations: [
            (territory: "AFG", price: 2.49, currency: "USD"),
            (territory: "ALB", price: 2.99, currency: "USD")
        ],
        existing: ["US": existingUS],
        factors: ["AF": 0.8, "AL": 0.9]
    )

    let unitedStates = try #require(regions.first(where: { $0.code == "US" }))
    #expect(unitedStates.country == "United States")
    #expect(unitedStates.currentPrice == 1.99)
    #expect(unitedStates.suggestedPrice == 2.99)
    #expect(unitedStates.pppIndex == 1)
    #expect(unitedStates.enabled)
    #expect(regions.filter { $0.code == "US" }.count == 1)
}

@Test("App Store subscription scheduling maps the US base market")
func appStoreSubscriptionTerritoryMapIncludesUS() {
    let map = appleTerritoryIdentifiers(
        equalizations: [(territory: "AFG", price: 2.49, currency: "USD")],
        includesUSBase: true
    )
    #expect(map["US"] == "USA")
    #expect(map["AF"] == "AFG")
}

@Test("US base pricing is enabled by default for both stores")
func usBasePricingEnabledByDefault() throws {
    #expect(pricingRegionEnabledByDefault("US"))
    let fallbackUS = try #require(defaultPriceRegions(basePrice: 1.99).first(where: { $0.code == "US" }))
    #expect(fallbackUS.enabled)

    let currentUS = PriceRegion(
        code: "US", country: "United States", flag: "🇺🇸", currency: "USD",
        pppIndex: 1, currentPrice: 1.99, suggestedPrice: 1.99, enabled: false
    )
    let googleRegions = googlePriceRegionsIncludingUSBase(
        [currentUS],
        proposedBasePrice: 2.99,
        currentBasePrice: 1.99
    )
    let googleUS = try #require(googleRegions.first(where: { $0.code == "US" }))
    #expect(googleUS.currentPrice == 1.99)
    #expect(googleUS.suggestedPrice == 2.99)
    #expect(googleUS.enabled)
}

@Test("Google applies a changed US base even when conversion data omits it")
func googleBasePriceChangeDoesNotDependOnConversionRow() {
    let unitedStates = PriceRegion(
        code: "US", country: "United States", flag: "🇺🇸", currency: "USD",
        pppIndex: 1, currentPrice: 1.99, suggestedPrice: 2.99, enabled: true
    )
    #expect(
        googleRegionsRequiringPriceChange([unitedStates], convertedRegionCodes: []).map(\.code)
            == ["US"]
    )
}

@Test("Base-price drafts accept decimal separators and reject invalid prices")
func basePriceDraftParsing() {
    #expect(storePriceValue(from: "2.99") == 2.99)
    #expect(storePriceValue(from: "2,99") == 2.99)
    #expect(storePriceValue(from: " 2.99 ") == 2.99)
    #expect(storePriceValue(from: "2.") == 2)
    #expect(storePriceValue(from: "") == nil)
    #expect(storePriceValue(from: "0") == nil)
    #expect(storePriceValue(from: "-2.99") == nil)
    #expect(storePriceValue(from: "2.9x") == nil)
    #expect(storePriceValue(from: "1,2.3") == nil)
}

@Test("Optional live pricing-index sources smoke test")
func livePricingIndexes() async throws {
    guard ProcessInfo.processInfo.environment["ESCALE_LIVE_PRICING_INDEX"] == "1" else { return }
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

@Test("Review replies use the selected store app name")
func reviewReplyUsesSelectedAppName() {
    let app = UnifiedApp(
        id: UUID(),
        name: "Unified fallback",
        symbol: "app",
        tintHex: 0,
        appStoreApp: StoreApp(
            id: UUID(), platform: .appStore, name: "Correct iOS Name",
            bundleID: "com.example.ios", storeID: "1", version: "1.0",
            state: .ready, versionID: nil, appInfoID: nil
        ),
        playStoreApp: StoreApp(
            id: UUID(), platform: .playStore, name: "Correct Android Name",
            bundleID: "com.example.android", storeID: "com.example.android", version: "1.0",
            state: .ready, versionID: nil, appInfoID: nil
        )
    )

    #expect(reviewReplyAppName(for: app, platform: .appStore) == "Correct iOS Name")
    #expect(reviewReplyAppName(for: app, platform: .playStore) == "Correct Android Name")
}

@Test("OpenAI Responses API structured review reply is decoded")
func openAIReviewReplyResponse() throws {
    let envelope: [String: Any] = [
        "status": "completed",
        "output": [[
            "type": "message",
            "content": [[
                "type": "output_text",
                "text": #"{"reply":"Thanks for sharing this specific sync issue."}"#
            ]]
        ]]
    ]

    let decoded = try OpenAIClient.decodeReviewReplyResponse(
        JSONSerialization.data(withJSONObject: envelope)
    )
    #expect(decoded == "Thanks for sharing this specific sync issue.")
}

@Test("Review reply instructions prevent wrong names and invented promises")
func openAIReviewReplyInstructions() {
    let instructions = OpenAIClient.reviewReplyInstructions(characterLimit: 350)

    #expect(instructions.contains("The exact product name is app_name"))
    #expect(instructions.contains("Never mention, infer, or substitute any other app"))
    #expect(instructions.contains("Do not invent fixes"))
    #expect(instructions.contains("without promising it will be built"))
    #expect(instructions.contains("same language as the review"))
    #expect(instructions.contains("hard maximum of 350 characters"))
}

@Test("Review replies are normalized and capped without cutting a word")
func openAIReviewReplyNormalization() {
    #expect(
        OpenAIClient.normalizedReviewReply(
            "  Thank you, Mia!\nWe appreciate the detail.  ",
            characterLimit: 350
        ) == "Thank you, Mia! We appreciate the detail."
    )
    let capped = OpenAIClient.normalizedReviewReply(
        "Thank you for the detailed feedback about your daily workflow and the way this feature could help every morning.",
        characterLimit: 60
    )
    #expect(capped.count <= 60)
    #expect(capped.hasSuffix("…"))
    #expect(!capped.contains("workf…"))
}

@Test("Full-listing AI instructions enforce ASO and selected-store limits")
func openAIListingASOInstructions() {
    let limits = OpenAITranslationLimits.storeListing(platforms: [.appStore, .playStore])
    let instructions = OpenAIClient.listingTranslationInstructions(limits: limits)

    #expect(instructions.contains("Apple App Store and Google Play"))
    #expect(instructions.contains("Target-locale ASO"))
    #expect(instructions.contains("natural search vocabulary"))
    #expect(instructions.contains("never keyword-stuff"))
    #expect(instructions.contains("title 30"))
    #expect(instructions.contains("subtitle 30"))
    #expect(instructions.contains("keywords 100"))
    #expect(instructions.contains("do not rely on downstream truncation"))
}

@Test("Field AI instructions apply field-specific ASO guidance and hard limits")
func openAIFieldASOInstructions() {
    let instructions = OpenAIClient.fieldTranslationInstructions(
        field: .keywords,
        characterLimit: 100,
        platforms: [.appStore]
    )

    #expect(instructions.contains("distinct, high-intent localized search terms"))
    #expect(instructions.contains("commas with no spaces"))
    #expect(instructions.contains("hard maximum of 100 characters"))
    #expect(instructions.contains("Do not return text cut off mid-word"))
}

@Test("AI output is capped locally even if a model exceeds store limits")
func openAIOutputLimits() {
    let limits = OpenAITranslationLimits.storeListing(platforms: [.appStore])
    var translation = OpenAITranslation(
        title: String(repeating: "a", count: 50),
        subtitle: String(repeating: "b", count: 50),
        promotionalText: String(repeating: "c", count: 200),
        description: String(repeating: "d", count: 4_100),
        keywords: String(repeating: "e", count: 120),
        releaseNotes: String(repeating: "f", count: 4_100)
    )
    translation.apply(limits: limits)

    #expect(translation.title.count == 30)
    #expect(translation.subtitle.count == 30)
    #expect(translation.promotionalText.count == 170)
    #expect(translation.description.count == 4_000)
    #expect(translation.keywords.count == 100)
    #expect(translation.releaseNotes.count == 4_000)
    #expect(OpenAIClient.enforcingCharacterLimit("Une mise à jour", limit: 8).count == 8)
}

@Test("Optional live App Store Connect read smoke test")
func liveAppleRead() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let issuer = environment["ESCALE_APPLE_ISSUER_ID"],
          let keyID = environment["ESCALE_APPLE_KEY_ID"],
          let keyPath = environment["ESCALE_APPLE_P8_PATH"] else { return }
    let pem = try String(contentsOfFile: keyPath, encoding: .utf8)
    let apps = try await AppStoreConnectClient(credentials: AppleCredentials(issuerID: issuer, keyID: keyID, privateKeyPEM: pem)).listApps()
    #expect(apps.allSatisfy { !$0.storeID.isEmpty && !$0.bundleID.isEmpty })
}

@Test("Optional live Google Play package smoke test")
func liveGoogleRead() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let jsonPath = environment["ESCALE_GOOGLE_SERVICE_ACCOUNT_PATH"],
          let packageName = environment["ESCALE_GOOGLE_PACKAGE"] else { return }
    let data = try Data(contentsOf: URL(fileURLWithPath: jsonPath))
    let credentials = try JSONDecoder().decode(GoogleServiceAccount.self, from: data)
    let snapshot = try await GooglePlayClient(credentials: credentials).fetchSnapshot(packageName: packageName)
    #expect(snapshot.app.bundleID == packageName)
}

@Test("Optional live OpenAI credential smoke test")
func liveOpenAIRead() async throws {
    guard let apiKey = ProcessInfo.processInfo.environment["ESCALE_OPENAI_API_KEY"] else { return }
    try await OpenAIClient(apiKey: apiKey).validateConnection()
}

@Test("Analytics events expose only bounded operational properties")
func analyticsEventSchema() {
    let event = EscaleAnalyticsEvent.translationCompleted(
        kind: .listing,
        scope: .both,
        result: .partial,
        targetCountBucket: EscaleAnalyticsEvent.countBucket(8),
        failure: .network
    )

    #expect(event.name == "translation_completed")
    #expect(event.properties == [
        "kind": "listing",
        "scope": "both",
        "result": "partial",
        "target_count_bucket": "6-10",
        "failure_category": "network"
    ])
}

@Test("Analytics count buckets never expose exact large counts")
func analyticsCountBuckets() {
    #expect(EscaleAnalyticsEvent.countBucket(0) == "0")
    #expect(EscaleAnalyticsEvent.countBucket(1) == "1")
    #expect(EscaleAnalyticsEvent.countBucket(4) == "3-5")
    #expect(EscaleAnalyticsEvent.countBucket(9) == "6-10")
    #expect(EscaleAnalyticsEvent.countBucket(5_000) == "11+")
}

@Test("Community analytics provider is unavailable and disabled")
func communityAnalyticsIsNoOp() {
    let analytics = NoOpEscaleAnalytics()

    #expect(!analytics.isAvailable)
    #expect(!analytics.isEnabled)
    #expect(analytics.serviceName.isEmpty)
    analytics.setEnabled(true)
    analytics.capture(.appLaunched, plan: .community)
    #expect(!analytics.isEnabled)
}
