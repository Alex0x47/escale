import CryptoKit
import Foundation

public enum StoreDataSection: Hashable, Sendable {
    case localizations
    case screenshots
    case products
    case reviews
}

public struct StoreFetchProgress: Sendable {
    public var completed: Int
    public var total: Int
    public var detail: String

    public var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(completed) / Double(total)))
    }
}

public typealias StoreFetchProgressHandler = @MainActor @Sendable (StoreFetchProgress) -> Void

public struct AppStoreScreenshotReference: Sendable {
    public let id: String
    public let setID: String
}

public struct StoreSnapshot: Sendable {
    public var app: StoreApp
    public var localizations: [ListingLocalization]
    public var screenshots: [StoreScreenshot]
    public var products: [StoreProduct]
    public var reviews: [CustomerReview]
    public var warnings: [String] = []
    public var unavailableSections: Set<StoreDataSection> = []
}

public struct AppStoreVersionDraft: Sendable {
    public var app: StoreApp
    public var localizations: [ListingLocalization]
    public var screenshots: [StoreScreenshot]
}

public struct ApplePriceCalculation: Sendable {
    public let resolvedBasePrice: Double
    public let regions: [PriceRegion]
}

private struct JSONObject: @unchecked Sendable {
    let value: [String: Any]
}

private struct ITunesLookupResponse: Decodable, Sendable {
    var results: [ITunesSoftwareResult]
}

private struct ITunesSoftwareResult: Decodable, Sendable {
    var trackId: Int?
    var bundleId: String?
    var artworkUrl512: String?
    var artworkUrl100: String?
    var averageUserRating: Double?
    var userRatingCount: Int?
}

private struct ITunesPublicMetadata: Sendable {
    var artworkURL: String?
    var ratingSummary: StoreRatingSummary?
}

public struct SubscriptionPriceCandidate: Sendable {
    public let pricePointID: String
    public let startDate: Date?
    public let preserved: Bool
    public let planType: String?
}

public struct AppleSubscriptionPriceChangePlan: Equatable, Sendable {
    public let startDate: String
    public let preserveCurrentPrice: Bool
}

public struct AppInfoCandidate: Equatable, Sendable {
    public let id: String
    public let state: String
}

public func preferredAppInfoID(
    from candidates: [AppInfoCandidate],
    editableStates: Set<String>
) -> String? {
    candidates.first(where: { editableStates.contains($0.state) })?.id
        ?? candidates.first(where: { !["REPLACED_WITH_NEW_VERSION", "DEVELOPER_REMOVED_FROM_SALE"].contains($0.state) })?.id
        ?? candidates.first?.id
}

public func changedAppInfoLocalizationAttributes(
    title: String,
    subtitle: String,
    remoteTitle: String,
    remoteSubtitle: String
) -> [String: String] {
    var attributes: [String: String] = [:]
    if title != remoteTitle { attributes["name"] = title }
    if subtitle != remoteSubtitle { attributes["subtitle"] = subtitle }
    return attributes
}

public func appleSubscriptionPriceChangeStartDate(now: Date = Date()) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let effectiveDate = calendar.date(byAdding: .day, value: 2, to: now) ?? now
    let components = calendar.dateComponents([.year, .month, .day], from: effectiveDate)
    return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
}

public func appleSubscriptionPriceChangePlan(
    currentPrice: Double,
    resolvedPrice: Double,
    policy: SubscriberPricePolicy,
    startDate: String
) -> AppleSubscriptionPriceChangePlan? {
    guard abs(currentPrice - resolvedPrice) > 0.000_001 else { return nil }
    return AppleSubscriptionPriceChangePlan(
        startDate: startDate,
        // Apple doesn't allow preserving a higher legacy price when the new
        // subscription price is a decrease; existing subscribers receive it.
        preserveCurrentPrice: resolvedPrice > currentPrice && policy == .preserve
    )
}

public func effectiveSubscriptionPriceCandidate(_ candidates: [SubscriptionPriceCandidate], on date: Date) -> SubscriptionPriceCandidate? {
    let today = Calendar(identifier: .gregorian).startOfDay(for: date)
    let effective = candidates.filter { $0.startDate == nil || $0.startDate! <= today }
    guard !effective.isEmpty else { return nil }
    let recurring = effective.filter { $0.planType != "UPFRONT" }
    let planCandidates = recurring.isEmpty ? effective : recurring
    let newSubscriberPrices = planCandidates.filter { !$0.preserved }
    if !newSubscriberPrices.isEmpty {
        return newSubscriberPrices.max { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
    }
    return planCandidates.first(where: { $0.startDate == nil })
        ?? planCandidates.max { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
}

public struct AppStoreConnectClient: Sendable {
    private let credentials: AppleCredentials
    private let baseURL = URL(string: "https://api.appstoreconnect.apple.com")!

    public init(credentials: AppleCredentials) {
        self.credentials = credentials
    }

    public func listApps() async throws -> [StoreApp] {
        var url: URL? = baseURL.appending(path: "/v1/apps").appendingQueryItems([
            URLQueryItem(name: "limit", value: "200"),
            URLQueryItem(name: "fields[apps]", value: "name,bundleId,sku,primaryLocale")
        ])
        var apps: [StoreApp] = []
        repeat {
            guard let currentURL = url else { break }
            let page = try await request(url: currentURL).value
            for resource in page.resources("data") {
                let attributes = resource.dictionary("attributes")
                let name = attributes.string("name") ?? "Untitled App"
                apps.append(StoreApp(
                    id: UUID(),
                    platform: .appStore,
                    name: name,
                    bundleID: attributes.string("bundleId") ?? "",
                    storeID: resource.string("id") ?? "",
                    version: "—",
                    state: .draft,
                    versionID: nil,
                    appInfoID: nil,
                    primaryLocale: attributes.string("primaryLocale")
                ))
            }
            url = page.dictionary("links").string("next").flatMap(URL.init(string:))
        } while url != nil
        let publicMetadata = await fetchPublicMetadata(for: apps)
        for index in apps.indices {
            let metadata = publicMetadata[apps[index].storeID] ?? publicMetadata[apps[index].bundleID]
            apps[index].iconURL = metadata?.artworkURL
            apps[index].ratingSummary = metadata?.ratingSummary
        }
        return apps
    }

    public func fetchSnapshot(for importedApp: StoreApp, progress: StoreFetchProgressHandler? = nil) async throws -> StoreSnapshot {
        var app = importedApp
        await progress?(StoreFetchProgress(completed: 0, total: 7, detail: "Resolving the public app icon…"))
        if app.primaryLocale == nil {
            app.primaryLocale = try? await appPrimaryLocale(appID: app.storeID)
        }
        let publicMetadata = await fetchPublicMetadata(for: [app])
        if let metadata = publicMetadata[app.storeID] ?? publicMetadata[app.bundleID] {
            if app.iconURL == nil {
                app.iconURL = metadata.artworkURL
            }
            if let ratingSummary = metadata.ratingSummary {
                app.ratingSummary = ratingSummary
            }
        }
        var warnings: [String] = []
        var unavailableSections: Set<StoreDataSection> = []
        var firstError: Error?
        var successfulReads = 0

        await progress?(StoreFetchProgress(completed: 1, total: 7, detail: "Fetching version and review status…"))
        do {
            let version = try await currentVersion(appID: app.storeID)
            app.version = version.version
            app.state = version.state
            app.versionID = version.id
            app.remoteState = version.remoteState
            app.versionDetails = version.details
            successfulReads += 1
        } catch {
            firstError = firstError ?? error
            warnings.append("Version status: \(error.localizedDescription)")
        }

        await progress?(StoreFetchProgress(completed: 2, total: 7, detail: "Fetching app information…"))
        do {
            app.appInfoID = try await currentAppInfoID(appID: app.storeID)
            successfulReads += 1
        } catch {
            firstError = firstError ?? error
            warnings.append("App information: \(error.localizedDescription)")
        }

        await progress?(StoreFetchProgress(completed: 3, total: 7, detail: "Fetching store listing localizations…"))
        let localizations: [ListingLocalization]
        do {
            localizations = try await fetchLocalizations(versionID: app.versionID, appInfoID: app.appInfoID)
            successfulReads += 1
        } catch {
            firstError = firstError ?? error
            warnings.append("Listings: \(error.localizedDescription)")
            unavailableSections.insert(.localizations)
            unavailableSections.insert(.screenshots)
            localizations = []
        }

        await progress?(StoreFetchProgress(completed: 4, total: 7, detail: "Fetching customer reviews and responses…"))
        let reviews: [CustomerReview]
        do {
            reviews = try await fetchReviews(appID: app.storeID, version: app.version)
            successfulReads += 1
        } catch {
            firstError = firstError ?? error
            warnings.append("Reviews: \(error.localizedDescription)")
            unavailableSections.insert(.reviews)
            reviews = []
        }

        await progress?(StoreFetchProgress(completed: 5, total: 7, detail: "Fetching products, subscriptions, and pricing…"))
        let products: [StoreProduct]
        do {
            products = try await fetchProducts(appID: app.storeID)
            successfulReads += 1
        } catch {
            firstError = firstError ?? error
            warnings.append("Products and subscriptions: \(error.localizedDescription)")
            unavailableSections.insert(.products)
            products = []
        }

        await progress?(StoreFetchProgress(completed: 6, total: 7, detail: "Fetching screenshot galleries…"))
        let screenshots: [StoreScreenshot]
        if localizations.isEmpty {
            screenshots = []
        } else {
            do {
                screenshots = try await fetchScreenshots(localizations: localizations)
                successfulReads += 1
            } catch {
                firstError = firstError ?? error
                warnings.append("Screenshots: \(error.localizedDescription)")
                unavailableSections.insert(.screenshots)
                screenshots = []
            }
        }

        if successfulReads == 0, let firstError { throw firstError }
        await progress?(StoreFetchProgress(completed: 7, total: 7, detail: "Applying the live App Store data…"))
        return StoreSnapshot(
            app: app,
            localizations: localizations,
            screenshots: screenshots,
            products: products,
            reviews: reviews,
            warnings: warnings,
            unavailableSections: unavailableSections
        )
    }

    public func saveLocalization(_ localization: ListingLocalization, app: StoreApp) async throws -> ListingLocalization {
        var updated = localization
        guard let versionID = app.versionID else { throw APIError.unsupported("No editable App Store version is available for this app.") }
        guard app.hasEditableMetadataVersion else {
            throw APIError.unsupported("Create or select an editable App Store version before changing version metadata. Escale never submits versions for review.")
        }

        let versionAttributes: [String: Any] = [
            "description": localization.description,
            "keywords": localization.keywords,
            "promotionalText": localization.promotionalText,
            "whatsNew": localization.releaseNotes
        ]
        if let id = localization.appleVersionLocalizationID {
            _ = try await jsonAPI(method: "PATCH", path: "/v1/appStoreVersionLocalizations/\(id)", type: "appStoreVersionLocalizations", id: id, attributes: versionAttributes)
        } else {
            let response = try await jsonAPICreate(
                path: "/v1/appStoreVersionLocalizations",
                type: "appStoreVersionLocalizations",
                attributes: versionAttributes.merging(["locale": localization.locale]) { _, new in new },
                relationships: ["appStoreVersion": versionID]
            )
            updated.appleVersionLocalizationID = response.dictionary("data").string("id")
        }

        let targetAppInfoID = try await currentAppInfoID(appID: app.storeID) ?? app.appInfoID
        if let appInfoID = targetAppInfoID {
            if let remote = try await appInfoLocalization(appInfoID: appInfoID, locale: localization.locale) {
                updated.appleAppInfoLocalizationID = remote.id
                let changes = changedAppInfoLocalizationAttributes(
                    title: localization.title,
                    subtitle: localization.subtitle,
                    remoteTitle: remote.name,
                    remoteSubtitle: remote.subtitle
                )
                if !changes.isEmpty {
                    _ = try await jsonAPI(
                        method: "PATCH",
                        path: "/v1/appInfoLocalizations/\(remote.id)",
                        type: "appInfoLocalizations",
                        id: remote.id,
                        attributes: changes
                    )
                }
            } else {
                let response = try await jsonAPICreate(
                    path: "/v1/appInfoLocalizations",
                    type: "appInfoLocalizations",
                    attributes: ["locale": localization.locale, "name": localization.title, "subtitle": localization.subtitle],
                    relationships: ["appInfo": appInfoID]
                )
                updated.appleAppInfoLocalizationID = response.dictionary("data").string("id")
            }
        }
        return updated
    }

    public func createVersion(for importedApp: StoreApp, versionString: String) async throws -> AppStoreVersionDraft {
        let cleanVersion = versionString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanVersion.isEmpty else { throw APIError.invalidCredentials("Enter a version number, for example 2.4.0.") }
        let versions = try await versionResources(appID: importedApp.storeID)
        if let editable = versions.first(where: { Self.editableStates.contains(appleVersionState($0.dictionary("attributes"))) }) {
            let value = editable.dictionary("attributes").string("versionString") ?? "the existing draft"
            throw APIError.unsupported("Version " + value + " is already editable. App Store Connect allows only one editable iOS version at a time.")
        }
        if versions.contains(where: { $0.dictionary("attributes").string("versionString") == cleanVersion }) {
            throw APIError.unsupported("Version " + cleanVersion + " already exists in App Store Connect.")
        }

        let previous = preferredLiveVersion(in: versions)
        let previousAppInfoID: String?
        if let existing = importedApp.appInfoID { previousAppInfoID = existing }
        else { previousAppInfoID = try await currentAppInfoID(appID: importedApp.storeID) }
        let previousLocalizations = try await fetchLocalizations(versionID: previous?.string("id"), appInfoID: previousAppInfoID)
        let response = try await jsonAPICreate(
            path: "/v1/appStoreVersions",
            type: "appStoreVersions",
            attributes: ["platform": "IOS", "versionString": cleanVersion, "releaseType": "MANUAL", "usesIdfa": false],
            relationships: ["app": importedApp.storeID]
        )
        guard let versionID = response.dictionary("data").string("id") else { throw APIError.invalidResponse }
        let editableAppInfoID = try await currentAppInfoID(appID: importedApp.storeID)
        var app = importedApp
        app.version = cleanVersion
        app.versionID = versionID
        app.appInfoID = editableAppInfoID
        app.state = .draft
        let createdAttributes = response.dictionary("data").dictionary("attributes")
        let createdState = appleVersionState(createdAttributes)
        app.remoteState = createdState.isEmpty ? "PREPARE_FOR_SUBMISSION" : createdState
        var createdDetails = appleVersionDetails(createdAttributes)
        if createdDetails.platformName == nil { createdDetails.platformName = "IOS" }
        if createdDetails.releaseType == nil { createdDetails.releaseType = "MANUAL" }
        if createdDetails.usesIDFA == nil { createdDetails.usesIDFA = false }
        app.versionDetails = createdDetails

        var draftLocalizations = (try? await fetchLocalizations(versionID: versionID, appInfoID: editableAppInfoID)) ?? []
        if draftLocalizations.isEmpty {
            draftLocalizations = previousLocalizations.map { previous in
                var copy = previous
                copy.appleVersionLocalizationID = nil
                copy.releaseNotes = ""
                copy.dirtyPlatforms = [.appStore]
                copy.lastSaved = nil
                return copy
            }
        } else {
            for index in draftLocalizations.indices {
                guard draftLocalizations[index].promotionalText.isEmpty,
                      let old = previousLocalizations.first(where: { $0.locale.caseInsensitiveCompare(draftLocalizations[index].locale) == .orderedSame }),
                      !old.promotionalText.isEmpty else { continue }
                draftLocalizations[index].promotionalText = old.promotionalText
                draftLocalizations[index].dirtyPlatforms.insert(.appStore)
            }
            for previous in previousLocalizations where !draftLocalizations.contains(where: { $0.locale.caseInsensitiveCompare(previous.locale) == .orderedSame }) {
                var copy = previous
                copy.appleVersionLocalizationID = nil
                copy.releaseNotes = ""
                copy.dirtyPlatforms = [.appStore]
                copy.lastSaved = nil
                draftLocalizations.append(copy)
            }
        }
        let screenshots = (try? await fetchScreenshots(localizations: draftLocalizations)) ?? []
        return AppStoreVersionDraft(app: app, localizations: draftLocalizations, screenshots: screenshots)
    }

    public func reply(to review: CustomerReview, text: String) async throws -> String {
        guard let reviewID = review.remoteID else { throw APIError.invalidResponse }
        if let responseID = review.responseRemoteID {
            _ = try await jsonAPI(
                method: "PATCH",
                path: "/v1/customerReviewResponses/\(responseID)",
                type: "customerReviewResponses",
                id: responseID,
                attributes: ["responseBody": text]
            )
            return responseID
        }
        let response = try await jsonAPICreate(
            path: "/v1/customerReviewResponses",
            type: "customerReviewResponses",
            attributes: ["responseBody": text],
            relationships: ["review": reviewID]
        )
        guard let id = response.dictionary("data").string("id") else { throw APIError.invalidResponse }
        return id
    }

    public func uploadScreenshot(
        data: Data,
        fileName: String,
        localization: ListingLocalization,
        existingSetID: String?,
        displayType: String = "APP_IPHONE_67"
    ) async throws -> AppStoreScreenshotReference {
        guard let localizationID = localization.appleVersionLocalizationID else {
            throw APIError.unsupported("Save this App Store localization before uploading screenshots.")
        }
        let setID: String
        if let existingSetID {
            setID = existingSetID
        } else {
            let set = try await jsonAPICreate(
                path: "/v1/appScreenshotSets",
                type: "appScreenshotSets",
                attributes: ["screenshotDisplayType": displayType],
                relationships: ["appStoreVersionLocalization": localizationID]
            )
            guard let id = set.dictionary("data").string("id") else { throw APIError.invalidResponse }
            setID = id
        }

        let reservation = try await jsonAPICreate(
            path: "/v1/appScreenshots",
            type: "appScreenshots",
            attributes: ["fileName": fileName, "fileSize": data.count],
            relationships: ["appScreenshotSet": setID]
        )
        let resource = reservation.dictionary("data")
        guard let screenshotID = resource.string("id") else { throw APIError.invalidResponse }
        let operations = resource.dictionary("attributes").array("uploadOperations")
        for operation in operations {
            guard let urlString = operation.string("url"), let uploadURL = URL(string: urlString) else { throw APIError.invalidResponse }
            let offset = operation.int("offset") ?? 0
            let length = operation.int("length") ?? data.count
            guard offset >= 0, length >= 0, offset + length <= data.count else { throw APIError.invalidResponse }
            let chunk = data.subdata(in: offset..<(offset + length))
            var headers: [String: String] = [:]
            for header in operation.array("requestHeaders") {
                if let name = header.string("name"), let value = header.string("value") { headers[name] = value }
            }
            _ = try await HTTPTransport.send(url: uploadURL, method: operation.string("method") ?? "PUT", headers: headers, body: chunk)
        }
        _ = try await jsonAPI(
            method: "PATCH",
            path: "/v1/appScreenshots/\(screenshotID)",
            type: "appScreenshots",
            id: screenshotID,
            attributes: [
                "uploaded": true,
                "sourceFileChecksum": Insecure.MD5.hash(data: data)
                    .map { String(format: "%02x", $0) }
                    .joined()
            ]
        )
        try await waitForScreenshotProcessing(screenshotID: screenshotID)
        return AppStoreScreenshotReference(id: screenshotID, setID: setID)
    }

    public func deleteScreenshot(remoteID: String) async throws {
        _ = try await request(path: "/v1/appScreenshots/\(remoteID)", method: "DELETE")
    }

    public func reorderScreenshots(setID: String, remoteIDs: [String]) async throws {
        let page = try await request(
            path: "/v1/appScreenshotSets/\(setID)/appScreenshots",
            query: [
                URLQueryItem(name: "fields[appScreenshots]", value: "assetDeliveryState"),
                URLQueryItem(name: "limit", value: "200")
            ]
        ).value
        let resources = page.resources("data")
        let currentIDs = resources.compactMap { $0.string("id") }
        guard currentIDs.count == remoteIDs.count,
              Set(currentIDs) == Set(remoteIDs) else {
            throw APIError.unsupported(
                "This screenshot gallery changed in App Store Connect. Refresh Escale before reordering it again."
            )
        }

        let deliveryStates = resources.compactMap {
            $0.dictionary("attributes").dictionary("assetDeliveryState").string("state")
        }
        if deliveryStates.contains("FAILED") {
            throw APIError.unsupported(
                "At least one screenshot failed Apple’s processing. Remove or replace that screenshot before changing the order."
            )
        }
        if deliveryStates.contains(where: { $0 != "COMPLETE" }) {
            throw APIError.unsupported(
                "Apple is still processing at least one screenshot. Wait a moment, refresh, and then reorder the gallery."
            )
        }
        guard currentIDs != remoteIDs else { return }

        let body: [String: Any] = [
            "data": remoteIDs.map { ["type": "appScreenshots", "id": $0] }
        ]
        do {
            _ = try await request(
                path: "/v1/appScreenshotSets/\(setID)/relationships/appScreenshots",
                method: "PATCH",
                body: HTTPTransport.jsonBody(body)
            )
        } catch APIError.http(let status, _) where status == 409 {
            throw APIError.unsupported(
                "Apple no longer allows changes to this screenshot set in its current version state. Refresh the app; if the version is in review or live, create an editable App Store version first."
            )
        }
    }

    private func waitForScreenshotProcessing(screenshotID: String) async throws {
        for attempt in 0..<30 {
            let resource = try await request(
                path: "/v1/appScreenshots/\(screenshotID)",
                query: [URLQueryItem(name: "fields[appScreenshots]", value: "assetDeliveryState")]
            ).value
                .dictionary("data")
                .dictionary("attributes")
                .dictionary("assetDeliveryState")
            switch resource.string("state") {
            case "COMPLETE":
                return
            case "FAILED":
                let detail = resource.array("errors").first?.string("description")
                    ?? "Apple could not process the uploaded screenshot."
                throw APIError.unsupported(detail)
            default:
                if attempt < 29 {
                    try await Task.sleep(for: .seconds(1))
                }
            }
        }
        throw APIError.unsupported(
            "The screenshot was uploaded, but Apple is still processing it. Refresh the app in a moment before reordering."
        )
    }

    public func applyRegionalPrices(
        product: StoreProduct,
        progress: PricingApplyProgressHandler? = nil
    ) async throws {
        guard let productID = product.appleProductID else {
            throw APIError.unsupported("This product is not linked to an App Store Connect product.")
        }
        if product.kind.localizedCaseInsensitiveContains("auto-renewable") {
            try await applySubscriptionPrices(product: product, subscriptionID: productID, progress: progress)
        } else {
            try await applyInAppPurchasePrices(product: product, inAppPurchaseID: productID, progress: progress)
        }
    }

    public func calculateRegionalPrices(product: StoreProduct, factors: [String: Double]) async throws -> ApplePriceCalculation {
        guard let productID = product.appleProductID else { throw APIError.unsupported("This product is not linked to App Store Connect.") }
        let existing = Dictionary(uniqueKeysWithValues: product.regions.map { ($0.code, $0) })
        let equalizations: [(territory: String, price: Double, currency: String)]
        let base: (id: String, price: Double)
        let currentBasePrice: Double
        if product.isSubscription {
            base = try await closestSubscriptionPricePoint(subscriptionID: productID, territory: "USA", desiredPrice: product.basePrice)
            let liveBase = try? await currentSubscriptionPriceRegions(subscriptionID: productID)
                .first(where: { $0.code == "US" })?
                .currentPrice
            currentBasePrice = liveBase ?? existing["US"]?.currentPrice ?? product.basePrice
            equalizations = try await equalizedPrices(path: "/v1/subscriptionPricePoints/\(base.id)/equalizations")
        } else {
            base = try await closestIAPPricePoint(productID: productID, territory: "USA", desiredPrice: product.basePrice)
            currentBasePrice = (try? await currentIAPBasePrice(productID: productID))
                ?? existing["US"]?.currentPrice
                ?? product.basePrice
            equalizations = try await equalizedPrices(path: "/v1/inAppPurchasePricePoints/\(base.id)/equalizations")
        }
        let regions = appleCalculatedPriceRegions(
            resolvedBasePrice: base.price,
            currentBasePrice: currentBasePrice,
            equalizations: equalizations,
            existing: existing,
            factors: factors
        )
        guard !regions.isEmpty else { throw APIError.unsupported("App Store Connect did not return equalized price points.") }
        return ApplePriceCalculation(resolvedBasePrice: base.price, regions: regions)
    }

    private static let editableStates: Set<String> = ["PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"]

    private func versionResources(appID: String) async throws -> [[String: Any]] {
        try await request(path: "/v1/apps/\(appID)/appStoreVersions", query: [
            URLQueryItem(name: "filter[platform]", value: "IOS"),
            URLQueryItem(name: "limit", value: "50")
        ]).value.resources("data")
    }

    private func appPrimaryLocale(appID: String) async throws -> String? {
        try await request(path: "/v1/apps/\(appID)", query: [
            URLQueryItem(name: "fields[apps]", value: "primaryLocale")
        ]).value
            .dictionary("data")
            .dictionary("attributes")
            .string("primaryLocale")
    }

    private func preferredLiveVersion(in resources: [[String: Any]]) -> [String: Any]? {
        resources.filter {
            ["READY_FOR_DISTRIBUTION", "READY_FOR_SALE"].contains(appleVersionState($0.dictionary("attributes")))
        }.max { lhs, rhs in
            (lhs.dictionary("attributes").string("versionString") ?? "0").compare(
                rhs.dictionary("attributes").string("versionString") ?? "0", options: .numeric
            ) == .orderedAscending
        }
    }

    private func currentVersion(appID: String) async throws -> (
        id: String,
        version: String,
        state: ReleaseState,
        remoteState: String,
        details: StoreVersionDetails
    ) {
        let resources = try await versionResources(appID: appID)
        let activeVersions = resources.filter { resource in
            let state = appleVersionState(resource.dictionary("attributes"))
            return !["REPLACED_WITH_NEW_VERSION", "DEVELOPER_REMOVED_FROM_SALE"].contains(state)
        }
        let editable = activeVersions.filter { Self.editableStates.contains(appleVersionState($0.dictionary("attributes"))) }
        let candidates = editable.isEmpty ? (activeVersions.isEmpty ? resources : activeVersions) : editable
        let preferred = candidates.max { lhs, rhs in
            let left = lhs.dictionary("attributes").string("versionString") ?? "0"
            let right = rhs.dictionary("attributes").string("versionString") ?? "0"
            return left.compare(right, options: .numeric) == .orderedAscending
        }
        guard let preferred,
              let id = preferred.string("id") else {
            throw APIError.unsupported("This app has no iOS App Store version yet. Create a version in Escale first.")
        }
        let attributes = preferred.dictionary("attributes")
        let remoteState = appleVersionState(attributes)
        return (
            id,
            attributes.string("versionString") ?? "—",
            mapAppleState(remoteState),
            remoteState,
            appleVersionDetails(attributes)
        )
    }

    private func currentAppInfoID(appID: String) async throws -> String? {
        let response = try await request(path: "/v1/apps/\(appID)/appInfos", query: [
            URLQueryItem(name: "fields[appInfos]", value: "state,appStoreState"),
            URLQueryItem(name: "limit", value: "200")
        ]).value
        let candidates = response.resources("data").compactMap { resource -> AppInfoCandidate? in
            guard let id = resource.string("id") else { return nil }
            let attributes = resource.dictionary("attributes")
            return AppInfoCandidate(
                id: id,
                state: attributes.string("state") ?? attributes.string("appStoreState") ?? ""
            )
        }
        return preferredAppInfoID(from: candidates, editableStates: Self.editableStates)
    }

    private func appInfoLocalization(
        appInfoID: String,
        locale: String
    ) async throws -> (id: String, name: String, subtitle: String)? {
        let response = try await request(path: "/v1/appInfos/\(appInfoID)/appInfoLocalizations", query: [
            URLQueryItem(name: "filter[locale]", value: locale),
            URLQueryItem(name: "fields[appInfoLocalizations]", value: "locale,name,subtitle"),
            URLQueryItem(name: "limit", value: "200")
        ]).value
        guard let resource = response.resources("data").first(where: {
            canonicalStoreLocale($0.dictionary("attributes").string("locale") ?? "") == canonicalStoreLocale(locale)
        }), let id = resource.string("id") else { return nil }
        let attributes = resource.dictionary("attributes")
        return (id, attributes.string("name") ?? "", attributes.string("subtitle") ?? "")
    }

    private func fetchLocalizations(versionID: String?, appInfoID: String?) async throws -> [ListingLocalization] {
        var versionByLocale: [String: (id: String, attributes: [String: Any])] = [:]
        if let versionID {
            let versionResponse = try await request(path: "/v1/appStoreVersions/\(versionID)/appStoreVersionLocalizations", query: [URLQueryItem(name: "limit", value: "200")]).value
            for resource in versionResponse.resources("data") {
                let attributes = resource.dictionary("attributes")
                if let locale = attributes.string("locale"), let id = resource.string("id") {
                    versionByLocale[locale] = (id, attributes)
                }
            }
        }
        var infoByLocale: [String: (id: String, attributes: [String: Any])] = [:]
        if let appInfoID {
            let infoResponse = try await request(path: "/v1/appInfos/\(appInfoID)/appInfoLocalizations", query: [URLQueryItem(name: "limit", value: "200")]).value
            for resource in infoResponse.resources("data") {
                let attributes = resource.dictionary("attributes")
                if let locale = attributes.string("locale"), let id = resource.string("id") {
                    infoByLocale[locale] = (id, attributes)
                }
            }
        }
        let locales = Set(versionByLocale.keys).union(infoByLocale.keys).sorted()
        return locales.map { locale in
            let version = versionByLocale[locale]
            let info = infoByLocale[locale]
            return ListingLocalization(
                id: UUID(),
                locale: locale,
                language: Locale.current.localizedString(forIdentifier: locale) ?? locale,
                title: info?.attributes.string("name") ?? "",
                subtitle: info?.attributes.string("subtitle") ?? "",
                promotionalText: version?.attributes.string("promotionalText") ?? "",
                description: version?.attributes.string("description") ?? "",
                keywords: version?.attributes.string("keywords") ?? "",
                releaseNotes: version?.attributes.string("whatsNew") ?? "",
                dirtyPlatforms: [],
                lastSaved: Date(),
                appleVersionLocalizationID: version?.id,
                appleAppInfoLocalizationID: info?.id,
                googleLanguage: nil
            )
        }
    }

    private func fetchScreenshots(localizations: [ListingLocalization]) async throws -> [StoreScreenshot] {
        var screenshots: [StoreScreenshot] = []
        for localization in localizations {
            guard let localizationID = localization.appleVersionLocalizationID else { continue }
            let sets = try await request(path: "/v1/appStoreVersionLocalizations/\(localizationID)/appScreenshotSets", query: [URLQueryItem(name: "limit", value: "50")]).value
            for set in sets.resources("data") {
                guard let setID = set.string("id") else { continue }
                let displayType = set.dictionary("attributes").string("screenshotDisplayType") ?? "iPhone"
                let page = try await request(path: "/v1/appScreenshotSets/\(setID)/appScreenshots", query: [URLQueryItem(name: "limit", value: "50")]).value
                for (index, resource) in page.resources("data").enumerated() {
                    let attributes = resource.dictionary("attributes")
                    let asset = attributes.dictionary("imageAsset")
                    let url = imageURL(from: asset)
                    screenshots.append(StoreScreenshot(
                        id: UUID(), platform: .appStore, locale: localization.locale,
                        device: readableDisplayType(displayType), title: "Screenshot \(index + 1)", caption: localization.language,
                        gradientStartHex: 0x5367D8, gradientEndHex: 0x9F74E8,
                        remoteID: resource.string("id"), remoteURL: url, screenshotSetID: setID
                    ))
                }
            }
        }
        return screenshots
    }

    private func fetchProducts(appID: String) async throws -> [StoreProduct] {
        let response = try await request(path: "/v1/apps/\(appID)/inAppPurchasesV2", query: [URLQueryItem(name: "limit", value: "200")]).value
        var products: [StoreProduct] = response.resources("data").compactMap { resource in
            let attributes = resource.dictionary("attributes")
            guard let id = resource.string("id"), let productID = attributes.string("productId") else { return nil }
            return StoreProduct(
                id: UUID(), name: attributes.string("name") ?? productID, productID: productID,
                kind: attributes.string("inAppPurchaseType") ?? "In-app purchase", basePrice: 0,
                platforms: [.appStore], regions: [],
                appleProductID: id, googleProductID: nil, googleBasePlanID: nil
            )
        }
        for index in products.indices {
            if let productID = products[index].appleProductID,
               let price = try? await currentIAPBasePrice(productID: productID) {
                products[index].basePrice = price
            }
        }
        let groups = try await request(path: "/v1/apps/\(appID)/subscriptionGroups", query: [URLQueryItem(name: "limit", value: "200")]).value
        for group in groups.resources("data") {
            guard let groupID = group.string("id") else { continue }
            let subscriptions = try await request(path: "/v1/subscriptionGroups/\(groupID)/subscriptions", query: [URLQueryItem(name: "limit", value: "200")]).value
            for resource in subscriptions.resources("data") {
                let attributes = resource.dictionary("attributes")
                guard let id = resource.string("id"), let productID = attributes.string("productId") else { continue }
                let currentRegions = (try? await currentSubscriptionPriceRegions(subscriptionID: id)) ?? []
                let price = currentRegions.first(where: { $0.code == "US" })?.currentPrice ?? 0
                products.append(StoreProduct(
                    id: UUID(), name: attributes.string("name") ?? productID, productID: productID,
                    kind: "Auto-renewable subscription", basePrice: price,
                    platforms: [.appStore], regions: currentRegions,
                    appleProductID: id, googleProductID: nil, googleBasePlanID: nil
                ))
            }
        }
        for index in products.indices where products[index].basePrice > 0 {
            if let calculated = try? await calculateRegionalPrices(product: products[index], factors: [:]) {
                products[index].regions = calculated.regions.map { region in
                    var current = region
                    current.suggestedPrice = current.currentPrice
                    return current
                }
            }
        }
        return products
    }

    private func currentIAPBasePrice(productID: String) async throws -> Double? {
        let response = try await request(path: "/v1/inAppPurchasePriceSchedules/\(productID)/manualPrices", query: [
            URLQueryItem(name: "filter[territory]", value: "USA"),
            URLQueryItem(name: "include", value: "inAppPurchasePricePoint"),
            URLQueryItem(name: "limit", value: "10")
        ]).value
        return response.resources("included").first(where: { $0.string("type") == "inAppPurchasePricePoints" })?.dictionary("attributes").decimal("customerPrice")
    }

    private func currentSubscriptionPriceRegions(subscriptionID: String, now: Date = Date()) async throws -> [PriceRegion] {
        var nextURL: URL? = baseURL.appending(path: "/v1/subscriptions/\(subscriptionID)/prices").appendingQueryItems([
            URLQueryItem(name: "include", value: "territory,subscriptionPricePoint"),
            URLQueryItem(name: "fields[subscriptionPrices]", value: "startDate,preserved,planType,territory,subscriptionPricePoint"),
            URLQueryItem(name: "fields[subscriptionPricePoints]", value: "customerPrice,territory"),
            URLQueryItem(name: "fields[territories]", value: "currency"),
            URLQueryItem(name: "limit", value: "200")
        ])
        var pricesByPoint: [String: Double] = [:]
        var currenciesByTerritory: [String: String] = [:]
        var candidatesByTerritory: [String: [SubscriptionPriceCandidate]] = [:]

        while let url = nextURL {
            let page = try await request(url: url).value
            for included in page.resources("included") {
                guard let id = included.string("id") else { continue }
                if included.string("type") == "subscriptionPricePoints",
                   let price = included.dictionary("attributes").decimal("customerPrice") {
                    pricesByPoint[id] = price
                } else if included.string("type") == "territories" {
                    currenciesByTerritory[id] = included.dictionary("attributes").string("currency") ?? "USD"
                }
            }
            for resource in page.resources("data") {
                let relationships = resource.dictionary("relationships")
                guard let territory = relationships.dictionary("territory").dictionary("data").string("id"),
                      let pointID = relationships.dictionary("subscriptionPricePoint").dictionary("data").string("id") else { continue }
                let attributes = resource.dictionary("attributes")
                candidatesByTerritory[territory, default: []].append(SubscriptionPriceCandidate(
                    pricePointID: pointID,
                    startDate: parseApplePriceDate(attributes.string("startDate")),
                    preserved: attributes["preserved"] as? Bool ?? false,
                    planType: attributes.string("planType")
                ))
            }
            nextURL = page.dictionary("links").string("next").flatMap(URL.init(string:))
        }

        var regions: [PriceRegion] = []
        for (territory, candidates) in candidatesByTerritory {
            guard let active = effectiveSubscriptionPriceCandidate(candidates, on: now),
                  let price = pricesByPoint[active.pricePointID], let code = iso2(fromISO3: territory) else { continue }
            let currency = currenciesByTerritory[territory]
                ?? Locale(identifier: "en_\(code)").currency?.identifier
                ?? "USD"
            regions.append(PriceRegion(
                code: code, country: countryName(for: code), flag: flag(for: code), currency: currency,
                pppIndex: 1, currentPrice: price, suggestedPrice: price,
                enabled: pricingRegionEnabledByDefault(code)
            ))
        }
        guard !regions.isEmpty else { throw APIError.unsupported("App Store Connect returned no effective subscription prices.") }
        return regions.sorted { $0.country < $1.country }
    }

    private func applyInAppPurchasePrices(
        product: StoreProduct,
        inAppPurchaseID: String,
        progress: PricingApplyProgressHandler?
    ) async throws {
        let changedRegions = regionsRequiringPriceChange(product.regions).filter { $0.code != "US" }
        let total = changedRegions.count + 2
        await progress?(PricingApplyProgress(
            platform: .appStore, completed: 0, total: total,
            detail: "Resolving the App Store base price point…"
        ))
        let usRegion = product.regions.first(where: { $0.code == "US" })
        let desiredBasePrice = usRegion.map { $0.enabled ? $0.suggestedPrice : $0.currentPrice } ?? product.basePrice
        let basePoint = try await closestIAPPricePoint(productID: inAppPurchaseID, territory: "USA", desiredPrice: desiredBasePrice)
        await progress?(PricingApplyProgress(
            platform: .appStore, completed: 1, total: total,
            detail: "Loading available App Store territories…"
        ))
        var selections: [(territory: String, pointID: String)] = [("USA", basePoint.id)]
        let territories = try await equalizedPrices(path: "/v1/inAppPurchasePricePoints/\(basePoint.id)/equalizations")
        let territoryByISO2 = Dictionary(uniqueKeysWithValues: territories.compactMap { item in iso2(fromISO3: item.territory).map { ($0, item.territory) } })
        for (offset, region) in changedRegions.enumerated() {
            guard let territory = territoryByISO2[region.code] else { continue }
            let point = try await closestIAPPricePoint(productID: inAppPurchaseID, territory: territory, desiredPrice: region.suggestedPrice)
            selections.append((territory, point.id))
            await progress?(PricingApplyProgress(
                platform: .appStore, completed: offset + 2, total: total,
                detail: "Resolved \(region.country) · \(offset + 1) of \(changedRegions.count) changed markets"
            ))
        }

        var included: [[String: Any]] = []
        var manualLinkages: [[String: String]] = []
        for selection in selections {
            let localID = UUID().uuidString
            manualLinkages.append(["type": "inAppPurchasePrices", "id": localID])
            included.append([
                "type": "inAppPurchasePrices",
                "id": localID,
                "attributes": [:],
                "relationships": [
                    "inAppPurchaseV2": ["data": ["type": "inAppPurchases", "id": inAppPurchaseID]],
                    "inAppPurchasePricePoint": ["data": ["type": "inAppPurchasePricePoints", "id": selection.pointID]]
                ]
            ])
        }
        let body: [String: Any] = [
            "data": [
                "type": "inAppPurchasePriceSchedules",
                "relationships": [
                    "inAppPurchase": ["data": ["type": "inAppPurchases", "id": inAppPurchaseID]],
                    "baseTerritory": ["data": ["type": "territories", "id": "USA"]],
                    "manualPrices": ["data": manualLinkages]
                ]
            ],
            "included": included
        ]
        await progress?(PricingApplyProgress(
            platform: .appStore, completed: max(1, total - 1), total: total,
            detail: "Submitting the App Store price schedule…"
        ))
        _ = try await request(path: "/v1/inAppPurchasePriceSchedules", method: "POST", body: HTTPTransport.jsonBody(body))
        await progress?(PricingApplyProgress(
            platform: .appStore, completed: total, total: total,
            detail: "App Store accepted the price schedule."
        ))
    }

    private func applySubscriptionPrices(
        product: StoreProduct,
        subscriptionID: String,
        progress: PricingApplyProgressHandler?
    ) async throws {
        let basePoint = try await closestSubscriptionPricePoint(subscriptionID: subscriptionID, territory: "USA", desiredPrice: product.basePrice)
        let territories = try await equalizedPrices(path: "/v1/subscriptionPricePoints/\(basePoint.id)/equalizations")
        let territoryByISO2 = appleTerritoryIdentifiers(equalizations: territories, includesUSBase: true)
        let startDate = appleSubscriptionPriceChangeStartDate()
        let changedRegions = regionsRequiringPriceChange(product.regions)
            .filter { territoryByISO2[$0.code] != nil }
        guard !changedRegions.isEmpty else {
            await progress?(PricingApplyProgress(
                platform: .appStore, completed: 1, total: 1,
                detail: "No App Store territory needs a new schedule."
            ))
            return
        }
        await progress?(PricingApplyProgress(
            platform: .appStore, completed: 0, total: changedRegions.count,
            detail: "Resolving legal price points for \(changedRegions.count) changed markets…"
        ))
        for (offset, region) in changedRegions.enumerated() {
            guard let territory = territoryByISO2[region.code] else { continue }
            let point = try await closestSubscriptionPricePoint(subscriptionID: subscriptionID, territory: territory, desiredPrice: region.suggestedPrice)
            guard let plan = appleSubscriptionPriceChangePlan(
                currentPrice: region.currentPrice,
                resolvedPrice: point.price,
                policy: product.effectiveSubscriberPricePolicy,
                startDate: startDate
            ) else {
                await progress?(PricingApplyProgress(
                    platform: .appStore, completed: offset + 1, total: changedRegions.count,
                    detail: "Validated \(region.country) · no schedule needed"
                ))
                continue
            }
            let body: [String: Any] = [
                "data": [
                    "type": "subscriptionPrices",
                    "attributes": [
                        "startDate": plan.startDate,
                        "preserveCurrentPrice": plan.preserveCurrentPrice
                    ],
                    "relationships": [
                        "subscription": ["data": ["type": "subscriptions", "id": subscriptionID]],
                        "territory": ["data": ["type": "territories", "id": territory]],
                        "subscriptionPricePoint": ["data": ["type": "subscriptionPricePoints", "id": point.id]]
                    ]
                ]
            ]
            _ = try await request(path: "/v1/subscriptionPrices", method: "POST", body: HTTPTransport.jsonBody(body))
            await progress?(PricingApplyProgress(
                platform: .appStore, completed: offset + 1, total: changedRegions.count,
                detail: "Scheduled \(region.country) · \(offset + 1) of \(changedRegions.count)"
            ))
        }
    }

    private func equalizedPrices(path: String) async throws -> [(territory: String, price: Double, currency: String)] {
        let response = try await request(path: path, query: [
            URLQueryItem(name: "include", value: "territory"),
            URLQueryItem(name: "fields[territories]", value: "currency"),
            URLQueryItem(name: "limit", value: "8000")
        ]).value
        let currencies = Dictionary(uniqueKeysWithValues: response.resources("included").compactMap { resource -> (String, String)? in
            guard resource.string("type") == "territories", let id = resource.string("id") else { return nil }
            return (id, resource.dictionary("attributes").string("currency") ?? "USD")
        })
        return response.resources("data").compactMap { resource in
            guard let price = resource.dictionary("attributes").decimal("customerPrice"),
                  let territory = resource.dictionary("relationships").dictionary("territory").dictionary("data").string("id") else { return nil }
            return (territory, price, currencies[territory] ?? "USD")
        }
    }

    private func closestIAPPricePoint(productID: String, territory: String, desiredPrice: Double) async throws -> (id: String, price: Double) {
        let response = try await request(path: "/v2/inAppPurchases/\(productID)/pricePoints", query: [
            URLQueryItem(name: "filter[territory]", value: territory),
            URLQueryItem(name: "fields[inAppPurchasePricePoints]", value: "customerPrice,territory"),
            URLQueryItem(name: "limit", value: "8000")
        ]).value
        return try closestPoint(in: response.resources("data"), desiredPrice: desiredPrice)
    }

    private func closestSubscriptionPricePoint(subscriptionID: String, territory: String, desiredPrice: Double) async throws -> (id: String, price: Double) {
        let response = try await request(path: "/v1/subscriptions/\(subscriptionID)/pricePoints", query: [
            URLQueryItem(name: "filter[territory]", value: territory),
            URLQueryItem(name: "fields[subscriptionPricePoints]", value: "customerPrice,territory"),
            URLQueryItem(name: "limit", value: "8000")
        ]).value
        return try closestPoint(in: response.resources("data"), desiredPrice: desiredPrice)
    }

    private func closestPoint(in resources: [[String: Any]], desiredPrice: Double) throws -> (id: String, price: Double) {
        let points = resources.compactMap { resource -> (String, Double)? in
            guard let id = resource.string("id"), let price = resource.dictionary("attributes").decimal("customerPrice") else { return nil }
            return (id, price)
        }
        guard let closest = points.min(by: { abs($0.1 - desiredPrice) < abs($1.1 - desiredPrice) }) else {
            throw APIError.unsupported("No valid App Store price point was returned for a selected territory.")
        }
        return closest
    }

    private func fetchReviews(appID: String, version: String) async throws -> [CustomerReview] {
        let response = try await request(path: "/v1/apps/\(appID)/customerReviews", query: [
            URLQueryItem(name: "limit", value: "200"),
            URLQueryItem(name: "sort", value: "-createdDate"),
            URLQueryItem(name: "include", value: "response")
        ]).value
        var responses: [String: (id: String, body: String)] = [:]
        for included in response.resources("included") where included.string("type") == "customerReviewResponses" {
            guard let id = included.string("id") else { continue }
            let reviewID = included.dictionary("relationships").dictionary("review").dictionary("data").string("id")
            if let reviewID { responses[reviewID] = (id, included.dictionary("attributes").string("responseBody") ?? "") }
        }
        return response.resources("data").compactMap { resource in
            guard let remoteID = resource.string("id") else { return nil }
            let attributes = resource.dictionary("attributes")
            return CustomerReview(
                id: UUID(), platform: .appStore,
                author: attributes.string("reviewerNickname") ?? "App Store customer",
                countryCode: attributes.string("territory") ?? "",
                rating: attributes.int("rating") ?? 0,
                title: attributes.string("title") ?? "Review",
                body: attributes.string("body") ?? "",
                date: parseISODate(attributes.string("createdDate")) ?? Date(),
                version: version,
                response: responses[remoteID]?.body,
                remoteID: remoteID,
                responseRemoteID: responses[remoteID]?.id
            )
        }
    }

    private func jsonAPI(method: String, path: String, type: String, id: String, attributes: [String: Any]) async throws -> [String: Any] {
        let body: [String: Any] = ["data": ["type": type, "id": id, "attributes": attributes]]
        return try await request(path: path, method: method, body: HTTPTransport.jsonBody(body)).value
    }

    private func jsonAPICreate(path: String, type: String, attributes: [String: Any], relationships: [String: String]) async throws -> [String: Any] {
        let relationshipObjects: [String: Any] = relationships.reduce(into: [:]) { result, item in
            result[item.key] = ["data": ["type": relationshipType(for: item.key), "id": item.value]]
        }
        let body: [String: Any] = ["data": ["type": type, "attributes": attributes, "relationships": relationshipObjects]]
        return try await request(path: path, method: "POST", body: HTTPTransport.jsonBody(body)).value
    }

    private func relationshipType(for key: String) -> String {
        switch key {
        case "app": "apps"
        case "review": "customerReviews"
        case "appStoreVersion": "appStoreVersions"
        case "appInfo": "appInfos"
        case "appStoreVersionLocalization": "appStoreVersionLocalizations"
        case "appScreenshotSet": "appScreenshotSets"
        default: key
        }
    }

    private func request(path: String, query: [URLQueryItem] = [], method: String = "GET", body: Data? = nil) async throws -> JSONObject {
        try await request(url: baseURL.appending(path: path).appendingQueryItems(query), method: method, body: body)
    }

    private func fetchPublicMetadata(for apps: [StoreApp]) async -> [String: ITunesPublicMetadata] {
        var metadataByIdentifier: [String: ITunesPublicMetadata] = [:]
        var unresolved: [String: String] = [:]
        for app in apps where !app.storeID.isEmpty {
            unresolved[app.storeID] = app.bundleID
        }
        let localCountry = Locale.current.region?.identifier.lowercased()
        let storefronts = [localCountry, "us"].compactMap { $0 }.reduce(into: [String]()) { result, country in
            if !result.contains(country) { result.append(country) }
        }

        for country in storefronts where !unresolved.isEmpty {
            let identifiers = Array(unresolved.keys)
            for start in stride(from: 0, to: identifiers.count, by: 50) {
                let end = min(start + 50, identifiers.count)
                var components = URLComponents(string: "https://itunes.apple.com/lookup")
                components?.queryItems = [
                    URLQueryItem(name: "id", value: identifiers[start..<end].joined(separator: ",")),
                    URLQueryItem(name: "country", value: country)
                ]
                guard let url = components?.url,
                      let response = try? await HTTPTransport.send(url: url, timeout: 15),
                      let lookup = try? JSONDecoder().decode(ITunesLookupResponse.self, from: response.data) else { continue }

                for result in lookup.results {
                    let ratingSummary: StoreRatingSummary? = if let averageRating = result.averageUserRating,
                                                                let ratingCount = result.userRatingCount,
                                                                ratingCount > 0,
                                                                averageRating.isFinite,
                                                                (0...5).contains(averageRating) {
                        StoreRatingSummary(averageRating: averageRating, ratingCount: ratingCount)
                    } else {
                        nil
                    }
                    let metadata = ITunesPublicMetadata(
                        artworkURL: result.artworkUrl512 ?? result.artworkUrl100,
                        ratingSummary: ratingSummary
                    )
                    let storeID = result.trackId.map(String.init)
                    if let storeID {
                        metadataByIdentifier[storeID] = metadata
                        unresolved.removeValue(forKey: storeID)
                    }
                    if let bundleID = result.bundleId {
                        metadataByIdentifier[bundleID] = metadata
                        if let matchingID = unresolved.first(where: { $0.value == bundleID })?.key {
                            metadataByIdentifier[matchingID] = metadata
                            unresolved.removeValue(forKey: matchingID)
                        }
                    }
                }
            }
        }
        return metadataByIdentifier
    }

    private func request(url: URL, method: String = "GET", body: Data? = nil) async throws -> JSONObject {
        let token = try JWTSigner.appleToken(credentials: credentials)
        var headers = ["Authorization": "Bearer \(token)", "Accept": "application/json"]
        if body != nil { headers["Content-Type"] = "application/json" }
        let response = try await HTTPTransport.send(url: url, method: method, headers: headers, body: body)
        if response.data.isEmpty { return JSONObject(value: [:]) }
        guard let object = try JSONSerialization.jsonObject(with: response.data) as? [String: Any] else { throw APIError.invalidResponse }
        return JSONObject(value: object)
    }
}

private extension Dictionary where Key == String, Value == Any {
    func string(_ key: String) -> String? { self[key] as? String }
    func int(_ key: String) -> Int? { self[key] as? Int }
    func bool(_ key: String) -> Bool? { (self[key] as? Bool) ?? (self[key] as? NSNumber)?.boolValue }
    func dictionary(_ key: String) -> [String: Any] { self[key] as? [String: Any] ?? [:] }
    func array(_ key: String) -> [[String: Any]] { self[key] as? [[String: Any]] ?? [] }
    func resources(_ key: String) -> [[String: Any]] { array(key) }
    func decimal(_ key: String) -> Double? {
        if let value = self[key] as? Double { return value }
        if let value = self[key] as? NSNumber { return value.doubleValue }
        if let value = self[key] as? String { return Double(value) }
        return nil
    }
}

private func appleVersionState(_ attributes: [String: Any]) -> String {
    attributes.string("appVersionState") ?? attributes.string("appStoreState") ?? ""
}

private func appleVersionDetails(_ attributes: [String: Any]) -> StoreVersionDetails {
    StoreVersionDetails(
        platformName: attributes.string("platform"),
        releaseType: attributes.string("releaseType"),
        earliestReleaseDate: parseISODate(attributes.string("earliestReleaseDate")),
        createdDate: parseISODate(attributes.string("createdDate")),
        copyright: attributes.string("copyright"),
        usesIDFA: attributes.bool("usesIdfa"),
        downloadable: attributes.bool("downloadable"),
        reviewType: attributes.string("reviewType")
    )
}

public func parseISODate(_ value: String?) -> Date? {
    guard let value else { return nil }
    let withFraction = ISO8601DateFormatter()
    withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return withFraction.date(from: value) ?? ISO8601DateFormatter().date(from: value)
}

private func parseApplePriceDate(_ value: String?) -> Date? {
    guard let value else { return nil }
    if let date = parseISODate(value) { return date }
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: value)
}

public func appleCalculatedPriceRegions(
    resolvedBasePrice: Double,
    currentBasePrice: Double,
    equalizations: [(territory: String, price: Double, currency: String)],
    existing: [String: PriceRegion],
    factors: [String: Double]
) -> [PriceRegion] {
    var regions = equalizations.compactMap { item -> PriceRegion? in
        guard let code = iso2(fromISO3: item.territory), code != "US" else { return nil }
        let factor = factors[code] ?? 1
        return PriceRegion(
            code: code,
            country: countryName(for: code),
            flag: flag(for: code),
            currency: item.currency,
            pppIndex: factor,
            currentPrice: existing[code]?.currentPrice ?? item.price,
            suggestedPrice: localizedCharmPrice(item.price * factor, currency: item.currency),
            enabled: pricingRegionEnabledByDefault(code)
        )
    }
    regions.append(PriceRegion(
        code: "US",
        country: countryName(for: "US"),
        flag: flag(for: "US"),
        currency: "USD",
        pppIndex: 1,
        currentPrice: currentBasePrice,
        suggestedPrice: resolvedBasePrice,
        enabled: pricingRegionEnabledByDefault("US")
    ))
    return regions.sorted { $0.country < $1.country }
}

public func appleTerritoryIdentifiers(
    equalizations: [(territory: String, price: Double, currency: String)],
    includesUSBase: Bool
) -> [String: String] {
    var result = Dictionary(uniqueKeysWithValues: equalizations.compactMap { item in
        iso2(fromISO3: item.territory).map { ($0, item.territory) }
    })
    if includesUSBase {
        result["US"] = "USA"
    }
    return result
}

public func defaultPriceRegions(basePrice: Double) -> [PriceRegion] {
    let data: [(String, String, String, String, Double)] = [
        ("US", "United States", "🇺🇸", "USD", 1), ("GB", "United Kingdom", "🇬🇧", "GBP", 0.86),
        ("DE", "Germany", "🇩🇪", "EUR", 0.91), ("BR", "Brazil", "🇧🇷", "BRL", 0.43),
        ("IN", "India", "🇮🇳", "INR", 0.28), ("JP", "Japan", "🇯🇵", "JPY", 0.74),
        ("MX", "Mexico", "🇲🇽", "MXN", 0.48), ("ZA", "South Africa", "🇿🇦", "ZAR", 0.45)
    ]
    return data.map { code, country, flag, currency, index in
        PriceRegion(
            code: code, country: country, flag: flag, currency: currency,
            pppIndex: index, currentPrice: basePrice, suggestedPrice: roundedCharmPrice(basePrice * index),
            enabled: pricingRegionEnabledByDefault(code)
        )
    }
}

private func mapAppleState(_ value: String?) -> ReleaseState {
    switch value {
    case "READY_FOR_DISTRIBUTION", "READY_FOR_SALE": .ready
    case "WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_DEVELOPER_RELEASE", "PENDING_APPLE_RELEASE", "PROCESSING_FOR_DISTRIBUTION": .review
    case "REJECTED", "METADATA_REJECTED", "INVALID_BINARY", "DEVELOPER_REJECTED": .rejected
    default: .draft
    }
}

private func readableDisplayType(_ value: String) -> String {
    value.replacingOccurrences(of: "APP_IPHONE_", with: "iPhone ").replacingOccurrences(of: "APP_IPAD_", with: "iPad ").replacingOccurrences(of: "_", with: ".")
}

private func imageURL(from asset: [String: Any]) -> String? {
    guard var template = asset.string("templateUrl") else { return nil }
    let width = asset.int("width") ?? 1290
    let height = asset.int("height") ?? 2796
    template = template.replacingOccurrences(of: "{w}", with: String(width))
        .replacingOccurrences(of: "{h}", with: String(height))
        .replacingOccurrences(of: "{f}", with: "png")
    return template
}
