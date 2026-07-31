import Foundation

private actor GoogleTokenCache {
    static let shared = GoogleTokenCache()
    private var tokens: [String: (value: String, expiry: Date)] = [:]

    public func token(for credentials: GoogleServiceAccount) async throws -> String {
        if let cached = tokens[credentials.clientEmail], cached.expiry > Date().addingTimeInterval(60) { return cached.value }
        let assertion = try JWTSigner.googleAssertion(credentials: credentials)
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "urn:ietf:params:oauth:grant-type:jwt-bearer"),
            URLQueryItem(name: "assertion", value: assertion)
        ]
        guard let body = components.percentEncodedQuery?.data(using: .utf8), let url = URL(string: credentials.tokenURI) else {
            throw APIError.invalidCredentials("The service account token URI is invalid.")
        }
        let response = try await HTTPTransport.send(
            url: url,
            method: "POST",
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            body: body
        )
        guard let object = try JSONSerialization.jsonObject(with: response.data) as? [String: Any],
              let accessToken = object["access_token"] as? String else { throw APIError.invalidResponse }
        let expiresIn = object["expires_in"] as? Double ?? 3_600
        tokens[credentials.clientEmail] = (accessToken, Date().addingTimeInterval(expiresIn))
        return accessToken
    }
}

private struct GoogleJSON: @unchecked Sendable {
    let value: [String: Any]
}

public enum GoogleEditCommitDisposition: Sendable, Equatable {
    case heldForManualReview
    case sentForReviewAutomatically
}

public struct GooglePriceCalculation: Sendable {
    public let regions: [PriceRegion]
    public let regionsVersion: String
}

public struct GooglePlayScreenshotUpload: Sendable {
    public let data: Data
    public let fileName: String
    public let mimeType: String

    public init(data: Data, fileName: String, mimeType: String) {
        self.data = data
        self.fileName = fileName
        self.mimeType = mimeType
    }
}

public struct GooglePlayScreenshotReference: Sendable {
    public let id: String
    public let url: String?
}

private struct GoogleProductsFetchResult: Sendable {
    let products: [StoreProduct]
    let warnings: [String]
    let allSourcesFailed: Bool
}

public struct GooglePlayClient: Sendable {
    private let credentials: GoogleServiceAccount
    private let baseURL = URL(string: "https://androidpublisher.googleapis.com/androidpublisher/v3")!
    private let uploadBaseURL = URL(string: "https://androidpublisher.googleapis.com/upload/androidpublisher/v3")!

    public init(credentials: GoogleServiceAccount) {
        self.credentials = credentials
    }

    public func validateCredentials() async throws {
        _ = try await GoogleTokenCache.shared.token(for: credentials)
    }

    public func fetchSnapshot(packageName: String, progress: StoreFetchProgressHandler? = nil) async throws -> StoreSnapshot {
        await progress?(StoreFetchProgress(completed: 0, total: 4, detail: "Opening a temporary Google Play edit…"))
        let editID = try await createEdit(packageName: packageName)
        do {
            await progress?(StoreFetchProgress(completed: 1, total: 4, detail: "Fetching listings, release status, reviews, and products…"))
            async let listingResult = fetchListings(packageName: packageName, editID: editID)
            async let reviews = fetchReviews(packageName: packageName)
            async let ratingSummary = fetchPublicRatingSummary(packageName: packageName)
            async let productsResult = fetchProducts(packageName: packageName)
            async let release = fetchRelease(packageName: packageName, editID: editID)
            async let defaultLanguage = fetchDefaultLanguage(packageName: packageName, editID: editID)
            let listings = try await listingResult
            let releaseInfo = try await release
            let reviewItems = try await reviews
            let publicRatingSummary = await ratingSummary
            let fetchedProducts = await productsResult
            let primaryLocale = try await defaultLanguage
            await progress?(StoreFetchProgress(completed: 2, total: 4, detail: "Fetching screenshot galleries…"))
            let screenshots = try await fetchScreenshots(packageName: packageName, editID: editID, localizations: listings)
            await progress?(StoreFetchProgress(completed: 3, total: 4, detail: "Closing the temporary Google Play edit…"))
            try? await deleteEdit(packageName: packageName, editID: editID)
            let appName = listings.first(where: { $0.locale.lowercased().hasPrefix("en") })?.title
                ?? listings.first?.title
                ?? packageName.split(separator: ".").last.map(String.init)?.capitalized
                ?? packageName
            let app = StoreApp(
                id: UUID(), platform: .playStore, name: appName, bundleID: packageName, storeID: packageName,
                version: releaseInfo.version, state: releaseInfo.state, versionID: nil, appInfoID: nil,
                remoteState: releaseInfo.remoteState, primaryLocale: primaryLocale,
                versionDetails: releaseInfo.details, ratingSummary: publicRatingSummary
            )
            await progress?(StoreFetchProgress(completed: 4, total: 4, detail: "Applying the live Google Play data…"))
            return StoreSnapshot(
                app: app,
                localizations: listings,
                screenshots: screenshots,
                products: fetchedProducts.products,
                reviews: reviewItems,
                warnings: fetchedProducts.warnings,
                unavailableSections: fetchedProducts.allSourcesFailed ? [.products] : []
            )
        } catch {
            try? await deleteEdit(packageName: packageName, editID: editID)
            throw error
        }
    }

    public func saveLocalization(_ localization: ListingLocalization, packageName: String) async throws -> GoogleEditCommitDisposition {
        let editID = try await createEdit(packageName: packageName)
        do {
            let language = localization.googleLanguage ?? localization.locale
            let body = googlePlayListingAttributes(localization, language: language)
            _ = try await request(
                path: "/applications/\(encoded(packageName))/edits/\(encoded(editID))/listings/\(encoded(language))",
                method: "PUT",
                body: HTTPTransport.jsonBody(body)
            )
            return try await commitEdit(packageName: packageName, editID: editID)
        } catch {
            try? await deleteEdit(packageName: packageName, editID: editID)
            throw error
        }
    }

    public func reply(to review: CustomerReview, packageName: String, text: String) async throws {
        guard let reviewID = review.remoteID else { throw APIError.invalidResponse }
        _ = try await request(
            path: "/applications/\(encoded(packageName))/reviews/\(encoded(reviewID)):reply",
            method: "POST",
            body: HTTPTransport.jsonBody(["replyText": text])
        )
    }

    public func uploadScreenshot(
        data: Data,
        fileName: String,
        mimeType: String,
        packageName: String,
        language: String,
        imageType: String = "phoneScreenshots"
    ) async throws {
        let editID = try await createEdit(packageName: packageName)
        do {
            _ = try await uploadScreenshot(
                GooglePlayScreenshotUpload(data: data, fileName: fileName, mimeType: mimeType),
                packageName: packageName,
                editID: editID,
                language: language,
                imageType: imageType
            )
            _ = try await commitEdit(packageName: packageName, editID: editID)
        } catch {
            try? await deleteEdit(packageName: packageName, editID: editID)
            throw error
        }
    }

    public func replaceScreenshots(
        _ screenshots: [GooglePlayScreenshotUpload],
        packageName: String,
        language: String,
        imageType: String
    ) async throws -> [GooglePlayScreenshotReference] {
        let editID = try await createEdit(packageName: packageName)
        do {
            let galleryPath = "/applications/\(encoded(packageName))/edits/\(encoded(editID))/listings/\(encoded(language))/\(encoded(imageType))"
            _ = try await request(path: galleryPath, method: "DELETE")
            var uploaded: [GooglePlayScreenshotReference] = []
            for screenshot in screenshots {
                let response = try await uploadScreenshot(
                    screenshot,
                    packageName: packageName,
                    editID: editID,
                    language: language,
                    imageType: imageType
                )
                let image = response.value.dictionary("image")
                guard let id = image.string("id") else { throw APIError.invalidResponse }
                uploaded.append(GooglePlayScreenshotReference(id: id, url: image.string("url")))
            }
            _ = try await commitEdit(packageName: packageName, editID: editID)
            return uploaded
        } catch {
            try? await deleteEdit(packageName: packageName, editID: editID)
            throw error
        }
    }

    public func deleteScreenshot(remoteID: String, packageName: String, language: String, imageType: String = "phoneScreenshots") async throws {
        let editID = try await createEdit(packageName: packageName)
        do {
            _ = try await request(path: "/applications/\(encoded(packageName))/edits/\(encoded(editID))/listings/\(encoded(language))/\(encoded(imageType))/\(encoded(remoteID))", method: "DELETE")
            _ = try await commitEdit(packageName: packageName, editID: editID)
        } catch {
            try? await deleteEdit(packageName: packageName, editID: editID)
            throw error
        }
    }

    private func uploadScreenshot(
        _ screenshot: GooglePlayScreenshotUpload,
        packageName: String,
        editID: String,
        language: String,
        imageType: String
    ) async throws -> GoogleJSON {
        let boundary = "escale-\(UUID().uuidString)"
        var body = Data()
        body.appendUTF8("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n{}\r\n")
        body.appendUTF8("--\(boundary)\r\nContent-Type: \(screenshot.mimeType)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(screenshot.fileName)\"\r\n\r\n")
        body.append(screenshot.data)
        body.appendUTF8("\r\n--\(boundary)--\r\n")
        let path = "/applications/\(encoded(packageName))/edits/\(encoded(editID))/listings/\(encoded(language))/\(encoded(imageType))"
        return try await request(
            url: uploadBaseURL.appending(path: path).appendingQueryItems([URLQueryItem(name: "uploadType", value: "multipart")]),
            method: "POST",
            additionalHeaders: ["Content-Type": "multipart/related; boundary=\(boundary)"],
            body: body
        )
    }

    public func calculateRegionalPrices(product: StoreProduct, factors: [String: Double], packageName: String) async throws -> GooglePriceCalculation {
        let response = try await convertRegionPrices(basePrice: product.basePrice, packageName: packageName)
        let existing = Dictionary(uniqueKeysWithValues: product.regions.map { ($0.code, $0) })
        var regions: [PriceRegion] = []
        for (code, raw) in response.converted {
            guard let convertedRegion = raw as? [String: Any] else { continue }
            let priceObject = convertedRegion.dictionary("price")
            let currency = priceObject.string("currencyCode") ?? existing[code]?.currency ?? "USD"
            let convertedPrice = moneyValue(priceObject)
            guard convertedPrice > 0 else { continue }
            let factor = factors[code] ?? 1
            regions.append(PriceRegion(
                code: code,
                country: countryName(for: code),
                flag: flag(for: code),
                currency: currency,
                pppIndex: factor,
                currentPrice: existing[code]?.currentPrice ?? convertedPrice,
                suggestedPrice: localizedCharmPrice(convertedPrice * factor, currency: currency),
                enabled: pricingRegionEnabledByDefault(code)
            ))
        }
        regions = googlePriceRegionsIncludingUSBase(
            regions,
            proposedBasePrice: product.basePrice,
            currentBasePrice: existing["US"]?.currentPrice ?? product.basePrice
        )
        guard !regions.isEmpty else { throw APIError.unsupported("Google Play did not return any available pricing regions.") }
        return GooglePriceCalculation(regions: regions.sorted { $0.country < $1.country }, regionsVersion: response.version)
    }

    private func createEdit(packageName: String) async throws -> String {
        let response = try await request(path: "/applications/\(encoded(packageName))/edits", method: "POST", body: Data("{}".utf8)).value
        guard let id = response.string("id") else { throw APIError.invalidResponse }
        return id
    }

    private func commitEdit(packageName: String, editID: String) async throws -> GoogleEditCommitDisposition {
        let path = "/applications/\(encoded(packageName))/edits/\(encoded(editID)):commit"
        do {
            _ = try await request(path: path, query: googleDraftCommitQueryItems(), method: "POST")
            return .heldForManualReview
        } catch {
            guard googleRequiresAutomaticReviewSubmission(error) else { throw error }
            _ = try await request(path: path, query: googleAutomaticReviewCommitQueryItems(), method: "POST")
            return .sentForReviewAutomatically
        }
    }

    private func deleteEdit(packageName: String, editID: String) async throws {
        _ = try await request(path: "/applications/\(encoded(packageName))/edits/\(encoded(editID))", method: "DELETE")
    }

    private func fetchListings(packageName: String, editID: String) async throws -> [ListingLocalization] {
        let response = try await request(path: "/applications/\(encoded(packageName))/edits/\(encoded(editID))/listings").value
        return response.array("listings").compactMap { listing in
            guard let language = listing.string("language") else { return nil }
            let title = listing.string("title") ?? ""
            let shortDescription = listing.string("shortDescription") ?? ""
            let description = listing.string("fullDescription") ?? ""
            return ListingLocalization(
                id: UUID(), locale: language, language: Locale.current.localizedString(forIdentifier: language) ?? language,
                title: title, subtitle: "",
                promotionalText: "", description: description, keywords: "", releaseNotes: "",
                dirtyPlatforms: [], lastSaved: Date(), appleVersionLocalizationID: nil, appleAppInfoLocalizationID: nil,
                googleLanguage: language, googleTitle: title, googleSubtitle: shortDescription, googleDescription: description
            )
        }
    }

    private func fetchDefaultLanguage(packageName: String, editID: String) async throws -> String? {
        let response = try await request(
            path: "/applications/\(encoded(packageName))/edits/\(encoded(editID))/details"
        ).value
        return response.string("defaultLanguage")
    }

    private func fetchRelease(packageName: String, editID: String) async throws -> (
        version: String,
        state: ReleaseState,
        remoteState: String?,
        details: StoreVersionDetails
    ) {
        let response = try await request(path: "/applications/\(encoded(packageName))/edits/\(encoded(editID))/tracks").value
        let bundlesResponse = try? await request(
            path: "/applications/\(encoded(packageName))/edits/\(encoded(editID))/bundles"
        ).value
        let tracks = response.array("tracks")
        let production = tracks.first(where: { $0.string("track") == "production" }) ?? tracks.first
        let release = production?.array("releases").first
        let versionCodes = release?.arrayValues("versionCodes").compactMap { $0 as? String } ?? []
        let selectedVersionCode = versionCodes.first.flatMap(Int.init)
        let selectedBundle = bundlesResponse?.array("bundles").first {
            $0.int("versionCode") == selectedVersionCode
        }
        let status = release?.string("status")
        let state: ReleaseState = switch status {
        case "completed": .ready
        case "inProgress", "halted": .review
        case "draft": .draft
        default: .draft
        }
        let countryTargeting = release?.dictionaryOptional("countryTargeting").map {
            StoreCountryTargeting(
                countries: $0.arrayValues("countries").compactMap { $0 as? String },
                includesRestOfWorld: $0.bool("includeRestOfWorld") ?? false
            )
        }
        let releaseNotes = release?.array("releaseNotes").compactMap { note -> StoreVersionReleaseNote? in
            guard let language = note.string("language"),
                  let text = note.string("text") else { return nil }
            return StoreVersionReleaseNote(language: language, text: text)
        }
        let details = StoreVersionDetails(
            track: production?.string("track"),
            releaseName: release?.string("name"),
            versionCodes: versionCodes.isEmpty ? nil : versionCodes,
            userFraction: release?.double("userFraction"),
            inAppUpdatePriority: release?.int("inAppUpdatePriority"),
            countryTargeting: countryTargeting,
            releaseNotes: releaseNotes?.isEmpty == false ? releaseNotes : nil,
            bundleSHA1: selectedBundle?.string("sha1"),
            bundleSHA256: selectedBundle?.string("sha256")
        )
        return (versionCodes.first.map { "build \($0)" } ?? "—", state, status, details)
    }

    private func fetchScreenshots(packageName: String, editID: String, localizations: [ListingLocalization]) async throws -> [StoreScreenshot] {
        var screenshots: [StoreScreenshot] = []
        let imageTypes: [(api: String, label: String)] = [
            ("phoneScreenshots", "Phone"), ("sevenInchScreenshots", "Tablet 7\""),
            ("tenInchScreenshots", "Tablet 10\""), ("tvScreenshots", "TV"), ("wearScreenshots", "Wear")
        ]
        for localization in localizations {
            let language = localization.googleLanguage ?? localization.locale
            for imageType in imageTypes {
                let response = try await request(path: "/applications/\(encoded(packageName))/edits/\(encoded(editID))/listings/\(encoded(language))/\(imageType.api)").value
                for (index, image) in response.array("images").enumerated() {
                    screenshots.append(StoreScreenshot(
                        id: UUID(), platform: .playStore, locale: language, device: imageType.label,
                        title: "Screenshot \(index + 1)", caption: localization.language,
                        gradientStartHex: 0x3D7C68, gradientEndHex: 0x62B494,
                        remoteID: image.string("id"), remoteURL: image.string("url"), screenshotSetID: imageType.api
                    ))
                }
            }
        }
        return screenshots
    }

    private func fetchReviews(packageName: String) async throws -> [CustomerReview] {
        let response = try await request(path: "/applications/\(encoded(packageName))/reviews", query: [URLQueryItem(name: "maxResults", value: "100")]).value
        return response.array("reviews").compactMap { review in
            guard let reviewID = review.string("reviewId") else { return nil }
            let comments = review.array("comments")
            guard let userComment = comments.compactMap({ $0.dictionaryOptional("userComment") }).first else { return nil }
            let developerComment = comments.compactMap({ $0.dictionaryOptional("developerComment") }).last
            let seconds = userComment.dictionary("lastModified").string("seconds").flatMap(Double.init) ?? 0
            return CustomerReview(
                id: UUID(), platform: .playStore,
                author: review.string("authorName") ?? "Google Play customer",
                countryCode: userComment.string("reviewerLanguage") ?? "",
                rating: userComment.int("starRating") ?? 0,
                title: "Google Play review",
                body: userComment.string("text") ?? "",
                date: seconds > 0 ? Date(timeIntervalSince1970: seconds) : Date(),
                version: userComment.string("appVersionName") ?? "—",
                response: developerComment?.string("text"),
                remoteID: reviewID,
                responseRemoteID: developerComment == nil ? nil : reviewID
            )
        }
    }

    private func fetchPublicRatingSummary(packageName: String) async -> StoreRatingSummary? {
        let localRegion = Locale.current.region?.identifier.uppercased()
        let regions = [localRegion, "US"].compactMap { $0 }.reduce(into: [String]()) { result, region in
            if !result.contains(region) { result.append(region) }
        }
        let language = Locale.current.language.languageCode?.identifier ?? "en"

        for region in regions {
            var components = URLComponents(string: "https://play.google.com/store/apps/details")
            components?.queryItems = [
                URLQueryItem(name: "id", value: packageName),
                URLQueryItem(name: "hl", value: language),
                URLQueryItem(name: "gl", value: region)
            ]
            guard let url = components?.url,
                  let response = try? await HTTPTransport.send(
                    url: url,
                    headers: ["Accept": "text/html"],
                    timeout: 15
                  ),
                  let summary = googlePlayRatingSummary(fromHTML: response.data) else {
                continue
            }
            return summary
        }
        return nil
    }

    private func fetchProducts(packageName: String) async -> GoogleProductsFetchResult {
        var result: [StoreProduct] = []
        var warnings: [String] = []
        var successfulSources = 0
        var deferredLegacyMigrationWarning: String?

        do {
            for item in try await legacyInAppProducts(packageName: packageName) {
                guard let sku = item.string("sku") else { continue }
                let defaultPrice = googleLegacyPriceValue(item.dictionary("defaultPrice"))
                let priceMap = item.dictionary("prices")
                var regions = priceMap.compactMap { code, raw -> PriceRegion? in
                    guard let price = raw as? [String: Any] else { return nil }
                    return priceRegion(
                        code: code,
                        price: googleLegacyPriceValue(price),
                        currency: price.string("currency") ?? "USD"
                    )
                }.sorted { $0.country < $1.country }
                if regions.isEmpty { regions = defaultPriceRegions(basePrice: defaultPrice) }
                let usBasePrice = regions.first(where: { $0.code == "US" })?.currentPrice ?? defaultPrice
                result.append(StoreProduct(
                    id: UUID(), name: item.dictionary("listings").values.compactMap { ($0 as? [String: Any])?["title"] as? String }.first ?? sku,
                    productID: sku, kind: item.string("purchaseType") ?? "In-app product", basePrice: usBasePrice,
                    platforms: [.playStore], regions: regions,
                    appleProductID: nil, googleProductID: sku, googleBasePlanID: nil
                ))
            }
            successfulSources += 1
        } catch {
            if googleLegacyCatalogRequiresMigration(error) {
                deferredLegacyMigrationWarning = "Legacy in-app products: \(error.localizedDescription)"
            } else {
                warnings.append("Legacy in-app products: \(error.localizedDescription)")
            }
        }

        do {
            for item in try await subscriptions(packageName: packageName) {
                guard let productID = item.string("productId") else { continue }
                let listingName = item.array("listings").first?.string("title") ?? productID
                result.removeAll {
                    $0.productID == productID
                        && $0.googleBasePlanID == nil
                        && $0.kind.localizedCaseInsensitiveContains("subscription")
                }
                for basePlan in item.array("basePlans") {
                    guard let basePlanID = basePlan.string("basePlanId") else { continue }
                    let configs = basePlan.array("regionalConfigs")
                    let usConfig = configs.first(where: { $0.string("regionCode") == "US" })
                    let price = usConfig.map { moneyValue($0.dictionary("price")) } ?? 0
                    let regions = configs.compactMap { config -> PriceRegion? in
                        guard let code = config.string("regionCode") else { return nil }
                        let money = config.dictionary("price")
                        return priceRegion(code: code, price: moneyValue(money), currency: money.string("currencyCode") ?? "USD")
                    }.sorted { $0.country < $1.country }
                    result.append(StoreProduct(
                        id: UUID(), name: "\(listingName) — \(basePlanID)", productID: productID,
                        kind: "Subscription", basePrice: price, platforms: [.playStore], regions: regions,
                        appleProductID: nil, googleProductID: productID, googleBasePlanID: basePlanID
                    ))
                }
            }
            successfulSources += 1
        } catch {
            warnings.append("Subscriptions: \(error.localizedDescription)")
        }

        var modernOneTimeProductsSucceeded = false
        do {
            for item in try await oneTimeProducts(packageName: packageName) {
                guard let productID = item.string("productId") else { continue }
                let listingName = item.array("listings").first?.string("title") ?? productID
                result.removeAll(where: { $0.productID == productID })
                for option in item.array("purchaseOptions") {
                    guard let optionID = option.string("purchaseOptionId") else { continue }
                    let configs = option.array("regionalPricingAndAvailabilityConfigs")
                    let usPrice = configs.first(where: { $0.string("regionCode") == "US" }).map { moneyValue($0.dictionary("price")) } ?? 0
                    let regions = configs.compactMap { config -> PriceRegion? in
                        guard let code = config.string("regionCode") else { return nil }
                        let money = config.dictionary("price")
                        return priceRegion(code: code, price: moneyValue(money), currency: money.string("currencyCode") ?? "USD")
                    }.sorted { $0.country < $1.country }
                    result.append(StoreProduct(
                        id: UUID(), name: "\(listingName) — \(optionID)", productID: productID,
                        kind: "One-time product", basePrice: usPrice, platforms: [.playStore], regions: regions,
                        appleProductID: nil, googleProductID: productID, googleBasePlanID: optionID
                    ))
                }
            }
            successfulSources += 1
            modernOneTimeProductsSucceeded = true
        } catch {
            warnings.append("One-time products: \(error.localizedDescription)")
        }
        if !modernOneTimeProductsSucceeded, let deferredLegacyMigrationWarning {
            warnings.append(deferredLegacyMigrationWarning)
        }
        return GoogleProductsFetchResult(
            products: result,
            warnings: warnings,
            allSourcesFailed: successfulSources == 0
        )
    }

    private func legacyInAppProducts(packageName: String) async throws -> [[String: Any]] {
        var products: [[String: Any]] = []
        var token: String?
        repeat {
            var query: [URLQueryItem] = []
            if let token { query.append(URLQueryItem(name: "token", value: token)) }
            let response = try await request(
                path: "/applications/\(encoded(packageName))/inappproducts",
                query: query
            ).value
            products.append(contentsOf: response.array("inappproduct"))
            token = response.dictionary("tokenPagination").string("nextPageToken")
                .flatMap { $0.isEmpty ? nil : $0 }
        } while token != nil
        return products
    }

    private func subscriptions(packageName: String) async throws -> [[String: Any]] {
        var products: [[String: Any]] = []
        var pageToken: String?
        repeat {
            var query = [URLQueryItem(name: "pageSize", value: "1000")]
            if let pageToken { query.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            let response = try await request(
                path: "/applications/\(encoded(packageName))/subscriptions",
                query: query
            ).value
            products.append(contentsOf: response.array("subscriptions"))
            pageToken = response.string("nextPageToken").flatMap { $0.isEmpty ? nil : $0 }
        } while pageToken != nil
        return products
    }

    private func oneTimeProducts(packageName: String) async throws -> [[String: Any]] {
        var products: [[String: Any]] = []
        var pageToken: String?
        repeat {
            var query = [URLQueryItem(name: "pageSize", value: "1000")]
            if let pageToken { query.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            let response = try await request(
                path: "/applications/\(encoded(packageName))/oneTimeProducts",
                query: query
            ).value
            products.append(contentsOf: response.array("oneTimeProducts"))
            pageToken = response.string("nextPageToken").flatMap { $0.isEmpty ? nil : $0 }
        } while pageToken != nil
        return products
    }

    private func convertRegionPrices(basePrice: Double, packageName: String) async throws -> (converted: [String: Any], version: String) {
        guard basePrice > 0 else {
            throw APIError.unsupported("PPP pricing requires this Google Play product to be available with a United States base price.")
        }
        let response = try await request(
            path: "/applications/\(encoded(packageName))/pricing:convertRegionPrices",
            method: "POST",
            body: HTTPTransport.jsonBody(["price": moneyObject(value: basePrice, currency: "USD")])
        ).value
        guard let version = response.dictionary("regionVersion").string("version") else { throw APIError.invalidResponse }
        return (response.dictionary("convertedRegionPrices"), version)
    }

    private func request(path: String, query: [URLQueryItem] = [], method: String = "GET", body: Data? = nil) async throws -> GoogleJSON {
        try await request(url: baseURL.appending(path: path).appendingQueryItems(query), method: method, body: body)
    }

    private func request(url: URL, method: String = "GET", additionalHeaders: [String: String] = [:], body: Data? = nil) async throws -> GoogleJSON {
        let token = try await GoogleTokenCache.shared.token(for: credentials)
        var headers = ["Authorization": "Bearer \(token)", "Accept": "application/json"]
        if body != nil && additionalHeaders["Content-Type"] == nil { headers["Content-Type"] = "application/json" }
        additionalHeaders.forEach { headers[$0.key] = $0.value }
        let response = try await HTTPTransport.send(url: url, method: method, headers: headers, body: body)
        if response.data.isEmpty { return GoogleJSON(value: [:]) }
        guard let object = try JSONSerialization.jsonObject(with: response.data) as? [String: Any] else { throw APIError.invalidResponse }
        return GoogleJSON(value: object)
    }

    private func encoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? value
    }
}

func googlePlayListingAttributes(
    _ localization: ListingLocalization,
    language: String
) -> [String: String] {
    [
        "language": language,
        "title": localization.playStoreTitle,
        "shortDescription": localization.shortDescription,
        "fullDescription": localization.playStoreFullDescription
    ]
}

func googlePlayRatingSummary(fromHTML data: Data) -> StoreRatingSummary? {
    guard let html = String(data: data, encoding: .utf8),
          let expression = try? NSRegularExpression(
            pattern: #"<script\b[^>]*type\s*=\s*["']application/ld\+json["'][^>]*>(.*?)</script>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
          ) else {
        return nil
    }

    let searchRange = NSRange(html.startIndex..<html.endIndex, in: html)
    for match in expression.matches(in: html, range: searchRange) {
        guard let jsonRange = Range(match.range(at: 1), in: html),
              let jsonData = String(html[jsonRange]).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let aggregate = object["aggregateRating"] as? [String: Any],
              let averageRating = storeRatingDouble(aggregate["ratingValue"]),
              let ratingCount = storeRatingInt(aggregate["ratingCount"]),
              ratingCount > 0,
              averageRating.isFinite,
              (0...5).contains(averageRating) else {
            continue
        }
        return StoreRatingSummary(averageRating: averageRating, ratingCount: ratingCount)
    }
    return nil
}

private func storeRatingDouble(_ value: Any?) -> Double? {
    if let value = value as? Double { return value }
    if let value = value as? NSNumber { return value.doubleValue }
    if let value = value as? String { return Double(value) }
    return nil
}

private func storeRatingInt(_ value: Any?) -> Int? {
    if let value = value as? Int { return value }
    if let value = value as? NSNumber { return value.intValue }
    if let value = value as? String { return Int(value) }
    return nil
}

public func googleDraftCommitQueryItems() -> [URLQueryItem] {
    [
        URLQueryItem(name: "changesNotSentForReview", value: "true"),
        URLQueryItem(name: "changesInReviewBehavior", value: "ERROR_IF_IN_REVIEW")
    ]
}

public func googleAutomaticReviewCommitQueryItems() -> [URLQueryItem] {
    [URLQueryItem(name: "changesInReviewBehavior", value: "ERROR_IF_IN_REVIEW")]
}

public func googleRequiresAutomaticReviewSubmission(_ error: Error) -> Bool {
    guard case let APIError.http(status, message) = error, status == 400 else { return false }
    let normalized = message.lowercased()
    return normalized.contains("changes are sent for review automatically")
        && normalized.contains("changesnotsent")
        && normalized.contains("review")
        && normalized.contains("must not be set")
}

private extension Dictionary where Key == String, Value == Any {
    func string(_ key: String) -> String? {
        if let value = self[key] as? String { return value }
        if let value = self[key] as? NSNumber { return value.stringValue }
        return nil
    }
    func int(_ key: String) -> Int? { (self[key] as? Int) ?? (self[key] as? NSNumber)?.intValue }
    func double(_ key: String) -> Double? { (self[key] as? Double) ?? (self[key] as? NSNumber)?.doubleValue }
    func bool(_ key: String) -> Bool? { (self[key] as? Bool) ?? (self[key] as? NSNumber)?.boolValue }
    func dictionary(_ key: String) -> [String: Any] { self[key] as? [String: Any] ?? [:] }
    func dictionaryOptional(_ key: String) -> [String: Any]? { self[key] as? [String: Any] }
    func array(_ key: String) -> [[String: Any]] { self[key] as? [[String: Any]] ?? [] }
    func arrayValues(_ key: String) -> [Any] { self[key] as? [Any] ?? [] }
}

private func moneyValue(_ object: [String: Any]) -> Double {
    let units = object.string("units").flatMap(Double.init) ?? 0
    let nanos = object.int("nanos") ?? 0
    return units + Double(nanos) / 1_000_000_000
}

public func googleLegacyPriceValue(_ object: [String: Any]) -> Double {
    let micros = object.string("priceMicros").flatMap(Double.init) ?? 0
    return micros / 1_000_000
}

public func googleLegacyCatalogRequiresMigration(_ error: Error) -> Bool {
    guard case let APIError.http(status, message) = error, status == 403 else { return false }
    return message.localizedCaseInsensitiveContains("migrate to the new publishing API")
}

public func googlePriceRegionsIncludingUSBase(
    _ regions: [PriceRegion],
    proposedBasePrice: Double,
    currentBasePrice: Double
) -> [PriceRegion] {
    var result = regions
    if let index = result.firstIndex(where: { $0.code == "US" }) {
        result[index].currentPrice = currentBasePrice
        result[index].suggestedPrice = proposedBasePrice
        result[index].pppIndex = 1
        result[index].enabled = pricingRegionEnabledByDefault("US")
    } else {
        result.append(PriceRegion(
            code: "US",
            country: countryName(for: "US"),
            flag: flag(for: "US"),
            currency: "USD",
            pppIndex: 1,
            currentPrice: currentBasePrice,
            suggestedPrice: proposedBasePrice,
            enabled: pricingRegionEnabledByDefault("US")
        ))
    }
    return result
}

private func moneyObject(value: Double, currency: String) -> [String: Any] {
    let units = Int64(value.rounded(.down))
    let nanos = Int(((value - Double(units)) * 1_000_000_000).rounded())
    return ["currencyCode": currency, "units": String(units), "nanos": nanos]
}

private func priceRegion(code: String, price: Double, currency: String) -> PriceRegion {
    PriceRegion(
        code: code, country: countryName(for: code), flag: flag(for: code), currency: currency,
        pppIndex: 1, currentPrice: price, suggestedPrice: price,
        enabled: pricingRegionEnabledByDefault(code)
    )
}

private extension Data {
    mutating func appendUTF8(_ string: String) {
        append(Data(string.utf8))
    }
}
