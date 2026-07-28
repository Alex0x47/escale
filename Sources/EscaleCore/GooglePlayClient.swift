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

private struct GoogleConvertedTargets: Sendable {
    let prices: [String: GoogleConvertedPrice]
    let regionsVersion: String
}

public enum GoogleEditCommitDisposition: Sendable, Equatable {
    case heldForManualReview
    case sentForReviewAutomatically
}

private struct GoogleConvertedPrice: Sendable {
    let value: Double
    let currency: String
}

public struct GooglePriceCalculation: Sendable {
    public let regions: [PriceRegion]
    public let regionsVersion: String
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
            async let productsResult = fetchProducts(packageName: packageName)
            async let release = fetchRelease(packageName: packageName, editID: editID)
            async let defaultLanguage = fetchDefaultLanguage(packageName: packageName, editID: editID)
            let listings = try await listingResult
            let releaseInfo = try await release
            let reviewItems = try await reviews
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
                versionDetails: releaseInfo.details
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
            let body: [String: Any] = [
                "language": language,
                "title": localization.title,
                "shortDescription": localization.subtitle,
                "fullDescription": localization.description
            ]
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
            let boundary = "escale-\(UUID().uuidString)"
            var body = Data()
            body.appendUTF8("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n{}\r\n")
            body.appendUTF8("--\(boundary)\r\nContent-Type: \(mimeType)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n\r\n")
            body.append(data)
            body.appendUTF8("\r\n--\(boundary)--\r\n")
            let path = "/applications/\(encoded(packageName))/edits/\(encoded(editID))/listings/\(encoded(language))/\(encoded(imageType))"
            _ = try await request(
                url: uploadBaseURL.appending(path: path).appendingQueryItems([URLQueryItem(name: "uploadType", value: "multipart")]),
                method: "POST",
                additionalHeaders: ["Content-Type": "multipart/related; boundary=\(boundary)"],
                body: body
            )
            _ = try await commitEdit(packageName: packageName, editID: editID)
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

    public func applyRegionalPrices(
        product: StoreProduct,
        packageName: String,
        progress: PricingApplyProgressHandler? = nil
    ) async throws {
        guard let productID = product.googleProductID ?? (product.platforms.contains(.playStore) ? product.productID : nil) else {
            throw APIError.unsupported("This product is not linked to a Google Play product.")
        }
        guard !regionsRequiringPriceChange(product.regions).isEmpty else {
            await progress?(PricingApplyProgress(
                platform: .playStore, completed: 1, total: 1,
                detail: "No Google Play region needs a price change."
            ))
            return
        }
        await progress?(PricingApplyProgress(
            platform: .playStore, completed: 0, total: 3,
            detail: "Validating Google Play regions and currencies…"
        ))
        let conversion = try await convertedPPPTargets(product: product, packageName: packageName)
        await progress?(PricingApplyProgress(
            platform: .playStore, completed: 1, total: 3,
            detail: "Updating the Google Play product catalog…"
        ))
        if product.kind.localizedCaseInsensitiveContains("subscription"), let basePlanID = product.googleBasePlanID {
            try await updateSubscriptionPrices(product: product, conversion: conversion, packageName: packageName, productID: productID, basePlanID: basePlanID)
        } else if product.kind == "One-time product", let purchaseOptionID = product.googleBasePlanID {
            try await updateOneTimeProductPrices(conversion: conversion, packageName: packageName, productID: productID, purchaseOptionID: purchaseOptionID)
        } else {
            try await updateInAppProductPrices(product: product, targets: conversion.prices, packageName: packageName, productID: productID)
        }
        await progress?(PricingApplyProgress(
            platform: .playStore, completed: 3, total: 3,
            detail: "Google Play accepted the regional catalog."
        ))
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
            let subtitle = listing.string("shortDescription") ?? ""
            let description = listing.string("fullDescription") ?? ""
            return ListingLocalization(
                id: UUID(), locale: language, language: Locale.current.localizedString(forIdentifier: language) ?? language,
                title: title, subtitle: subtitle,
                promotionalText: "", description: description, keywords: "", releaseNotes: "",
                dirtyPlatforms: [], lastSaved: Date(), appleVersionLocalizationID: nil, appleAppInfoLocalizationID: nil,
                googleLanguage: language, googleTitle: title, googleSubtitle: subtitle, googleDescription: description
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
        let tracks = response.array("tracks")
        let production = tracks.first(where: { $0.string("track") == "production" }) ?? tracks.first
        let release = production?.array("releases").first
        let versionCodes = release?.arrayValues("versionCodes").compactMap { $0 as? String } ?? []
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
            releaseNotes: releaseNotes?.isEmpty == false ? releaseNotes : nil
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

    private func convertedPPPTargets(product: StoreProduct, packageName: String) async throws -> GoogleConvertedTargets {
        let response = try await convertRegionPrices(basePrice: product.basePrice, packageName: packageName)
        var targets: [String: GoogleConvertedPrice] = [:]
        let availableCodes = Set(response.converted.keys)
        for region in googleRegionsRequiringPriceChange(product.regions, convertedRegionCodes: availableCodes) {
            targets[region.code] = GoogleConvertedPrice(value: region.suggestedPrice, currency: region.currency)
        }
        guard !targets.isEmpty else { throw APIError.unsupported("Google Play did not return converted prices for the selected regions.") }
        return GoogleConvertedTargets(prices: targets, regionsVersion: response.version)
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

    private func updateInAppProductPrices(product: StoreProduct, targets: [String: GoogleConvertedPrice], packageName: String, productID: String) async throws {
        let response = try await request(path: "/applications/\(encoded(packageName))/inappproducts/\(encoded(productID))").value
        var object = response
        var prices = object.dictionary("prices")
        for (regionCode, target) in targets {
            prices[regionCode] = googleLegacyPriceObject(value: target.value, currency: target.currency)
        }
        object["prices"] = prices
        _ = try await request(
            path: "/applications/\(encoded(packageName))/inappproducts/\(encoded(productID))",
            query: [URLQueryItem(name: "autoConvertMissingPrices", value: "true")],
            method: "PUT",
            body: HTTPTransport.jsonBody(object)
        )
    }

    private func updateSubscriptionPrices(product: StoreProduct, conversion: GoogleConvertedTargets, packageName: String, productID: String, basePlanID: String) async throws {
        let response = try await request(path: "/applications/\(encoded(packageName))/subscriptions/\(encoded(productID))").value
        var subscription = response
        var basePlans = subscription.array("basePlans")
        guard let index = basePlans.firstIndex(where: { $0.string("basePlanId") == basePlanID }) else {
            throw APIError.unsupported("The Google Play base plan \(basePlanID) was not found.")
        }
        var configs = basePlans[index].array("regionalConfigs")
        for (regionCode, target) in conversion.prices {
            if let configIndex = configs.firstIndex(where: { $0.string("regionCode") == regionCode }) {
                configs[configIndex]["price"] = moneyObject(value: target.value, currency: target.currency)
            } else {
                configs.append(["regionCode": regionCode, "price": moneyObject(value: target.value, currency: target.currency), "newSubscriberAvailability": true])
            }
        }
        basePlans[index]["regionalConfigs"] = configs
        let mutableBasePlans = basePlans.map { basePlan -> [String: Any] in
            var result = basePlan
            result.removeValue(forKey: "state")
            return result
        }
        subscription = [
            "packageName": packageName,
            "productId": productID,
            "basePlans": mutableBasePlans
        ]
        let batchBody: [String: Any] = [
            "requests": [[
                "subscription": subscription,
                "updateMask": "basePlans",
                "regionsVersion": ["version": conversion.regionsVersion]
            ]]
        ]
        _ = try await request(path: "/applications/\(encoded(packageName))/subscriptions:batchUpdate", method: "POST", body: HTTPTransport.jsonBody(batchBody))
        if product.effectiveSubscriberPricePolicy == .migrate {
            let legacyCohortCutoff = ISO8601DateFormatter().string(from: Date())
            let regionsByCode = Dictionary(uniqueKeysWithValues: product.regions.map { ($0.code, $0) })
            let migrations: [[String: Any]] = conversion.prices.keys.sorted().map { code in
                var migration: [String: Any] = [
                    "regionCode": code,
                    "oldestAllowedPriceVersionTime": legacyCohortCutoff
                ]
                if let region = regionsByCode[code], region.suggestedPrice > region.currentPrice {
                    migration["priceIncreaseType"] = "PRICE_INCREASE_TYPE_OPT_IN"
                }
                return migration
            }
            let body: [String: Any] = [
                "regionalPriceMigrations": migrations,
                "regionsVersion": ["version": conversion.regionsVersion]
            ]
            _ = try await request(
                path: "/applications/\(encoded(packageName))/subscriptions/\(encoded(productID))/basePlans/\(encoded(basePlanID)):migratePrices",
                method: "POST",
                body: HTTPTransport.jsonBody(body)
            )
        }
    }

    private func updateOneTimeProductPrices(conversion: GoogleConvertedTargets, packageName: String, productID: String, purchaseOptionID: String) async throws {
        let response = try await request(path: "/applications/\(encoded(packageName))/oneTimeProducts/\(encoded(productID))").value
        var product = response
        var options = product.array("purchaseOptions")
        guard let optionIndex = options.firstIndex(where: { $0.string("purchaseOptionId") == purchaseOptionID }) else {
            throw APIError.unsupported("The Google Play purchase option \(purchaseOptionID) was not found.")
        }
        var configs = options[optionIndex].array("regionalPricingAndAvailabilityConfigs")
        for (regionCode, target) in conversion.prices {
            if let index = configs.firstIndex(where: { $0.string("regionCode") == regionCode }) {
                configs[index]["price"] = moneyObject(value: target.value, currency: target.currency)
            } else {
                configs.append(["regionCode": regionCode, "price": moneyObject(value: target.value, currency: target.currency), "availability": "AVAILABLE"])
            }
        }
        options[optionIndex]["regionalPricingAndAvailabilityConfigs"] = configs
        let mutableOptions = options.map { option -> [String: Any] in
            var result = option
            result.removeValue(forKey: "state")
            return result
        }
        product = [
            "packageName": packageName,
            "productId": productID,
            "purchaseOptions": mutableOptions
        ]
        let body: [String: Any] = [
            "requests": [[
                "oneTimeProduct": product,
                "updateMask": "purchaseOptions",
                "regionsVersion": ["version": conversion.regionsVersion]
            ]]
        ]
        _ = try await request(path: "/applications/\(encoded(packageName))/oneTimeProducts:batchUpdate", method: "POST", body: HTTPTransport.jsonBody(body))
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

public func googleLegacyPriceObject(value: Double, currency: String) -> [String: Any] {
    [
        "priceMicros": String(Int64((value * 1_000_000).rounded())),
        "currency": currency
    ]
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

public func googleRegionsRequiringPriceChange(
    _ regions: [PriceRegion],
    convertedRegionCodes: Set<String>
) -> [PriceRegion] {
    regionsRequiringPriceChange(regions).filter {
        $0.code == "US" || convertedRegionCodes.contains($0.code)
    }
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
