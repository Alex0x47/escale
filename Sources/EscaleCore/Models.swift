import Foundation
import SwiftUI

public enum StorePlatform: String, Codable, CaseIterable, Identifiable, Sendable {
    case appStore = "App Store"
    case playStore = "Google Play"

    public var id: String { rawValue }
    public var shortName: String { self == .appStore ? "iOS" : "Android" }
    public var icon: String { self == .appStore ? "apple.logo" : "play.fill" }
    public var tint: Color { self == .appStore ? Color(hex: 0x2477F5) : Color(hex: 0x14A46D) }
    public var developerConsoleName: String {
        self == .appStore ? "App Store Connect" : "Google Play Console"
    }
}

public enum ConnectionState: String, Codable, Sendable {
    case connected
    case attention
    case disconnected

    public var label: String {
        switch self {
        case .connected: "Connected"
        case .attention: "Needs attention"
        case .disconnected: "Not connected"
        }
    }
}

public struct StoreConnection: Identifiable, Codable, Hashable, Sendable {
    public var id: StorePlatform { platform }
    public let platform: StorePlatform
    public var accountName: String
    public var detail: String
    public var state: ConnectionState
    public var lastSync: Date?
}

public enum ReleaseState: String, Codable, Sendable {
    case ready = "Ready for distribution"
    case review = "In review"
    case draft = "Draft"
    case rejected = "Action required"

    public var color: Color {
        switch self {
        case .ready: .green
        case .review: .orange
        case .draft: .secondary
        case .rejected: .red
        }
    }
}

public struct StoreApp: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var platform: StorePlatform
    public var name: String
    public var bundleID: String
    public var storeID: String
    public var version: String
    public var state: ReleaseState
    public var versionID: String?
    public var appInfoID: String?
    public var iconURL: String? = nil
    public var remoteState: String? = nil
    public var primaryLocale: String? = nil
    public var versionDetails: StoreVersionDetails? = nil
    public var ratingSummary: StoreRatingSummary? = nil

    public var hasEditableMetadataVersion: Bool {
        guard platform == .appStore else { return true }
        return Self.editableAppStoreStates.contains(remoteState ?? "")
    }

    public var developerConsoleURL: URL? {
        switch platform {
        case .appStore:
            let appID = storeID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !appID.isEmpty else { return nil }
            var components = URLComponents()
            components.scheme = "https"
            components.host = "appstoreconnect.apple.com"
            components.path = "/apps/\(appID)/distribution/ios/version/inflight"
            return components.url
        case .playStore:
            return URL(string: "https://play.google.com/console/")
        }
    }

    private static let editableAppStoreStates: Set<String> = [
        "PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"
    ]
}

public struct StoreRatingSummary: Codable, Hashable, Sendable {
    public var averageRating: Double
    public var ratingCount: Int

    public init(averageRating: Double, ratingCount: Int) {
        self.averageRating = averageRating
        self.ratingCount = ratingCount
    }
}

public func combinedStoreRatingSummary(_ summaries: [StoreRatingSummary]) -> StoreRatingSummary? {
    let validSummaries = summaries.filter {
        $0.ratingCount > 0 && $0.averageRating.isFinite && (0...5).contains($0.averageRating)
    }
    let ratingCount = validSummaries.reduce(0) { $0 + $1.ratingCount }
    guard ratingCount > 0 else { return nil }
    let weightedTotal = validSummaries.reduce(0.0) {
        $0 + ($1.averageRating * Double($1.ratingCount))
    }
    return StoreRatingSummary(
        averageRating: weightedTotal / Double(ratingCount),
        ratingCount: ratingCount
    )
}

public func suggestedNextAppStoreVersion(from version: String) -> String {
    var parts = version.split(separator: ".").compactMap { Int($0) }
    guard !parts.isEmpty else { return "1.0.0" }
    while parts.count < 3 { parts.append(0) }
    parts[parts.count - 1] += 1
    return parts.map(String.init).joined(separator: ".")
}

public func isValidAppStoreVersion(_ version: String) -> Bool {
    let cleanVersion = version.trimmingCharacters(in: .whitespacesAndNewlines)
    let parts = cleanVersion.split(separator: ".", omittingEmptySubsequences: false)
    guard (1...3).contains(parts.count) else { return false }
    return parts.allSatisfy { part in
        !part.isEmpty && part.allSatisfy { $0.isASCII && $0.isNumber }
    }
}

public struct StoreVersionDetails: Codable, Hashable, Sendable {
    public var platformName: String? = nil
    public var releaseType: String? = nil
    public var earliestReleaseDate: Date? = nil
    public var createdDate: Date? = nil
    public var copyright: String? = nil
    public var usesIDFA: Bool? = nil
    public var downloadable: Bool? = nil
    public var reviewType: String? = nil

    public var track: String? = nil
    public var releaseName: String? = nil
    public var versionCodes: [String]? = nil
    public var userFraction: Double? = nil
    public var inAppUpdatePriority: Int? = nil
    public var countryTargeting: StoreCountryTargeting? = nil
    public var releaseNotes: [StoreVersionReleaseNote]? = nil
    public var bundleSHA1: String? = nil
    public var bundleSHA256: String? = nil

    public init(
        platformName: String? = nil,
        releaseType: String? = nil,
        earliestReleaseDate: Date? = nil,
        createdDate: Date? = nil,
        copyright: String? = nil,
        usesIDFA: Bool? = nil,
        downloadable: Bool? = nil,
        reviewType: String? = nil,
        track: String? = nil,
        releaseName: String? = nil,
        versionCodes: [String]? = nil,
        userFraction: Double? = nil,
        inAppUpdatePriority: Int? = nil,
        countryTargeting: StoreCountryTargeting? = nil,
        releaseNotes: [StoreVersionReleaseNote]? = nil,
        bundleSHA1: String? = nil,
        bundleSHA256: String? = nil
    ) {
        self.platformName = platformName
        self.releaseType = releaseType
        self.earliestReleaseDate = earliestReleaseDate
        self.createdDate = createdDate
        self.copyright = copyright
        self.usesIDFA = usesIDFA
        self.downloadable = downloadable
        self.reviewType = reviewType
        self.track = track
        self.releaseName = releaseName
        self.versionCodes = versionCodes
        self.userFraction = userFraction
        self.inAppUpdatePriority = inAppUpdatePriority
        self.countryTargeting = countryTargeting
        self.releaseNotes = releaseNotes
        self.bundleSHA1 = bundleSHA1
        self.bundleSHA256 = bundleSHA256
    }
}

public struct StoreCountryTargeting: Codable, Hashable, Sendable {
    public var countries: [String]
    public var includesRestOfWorld: Bool

    public init(countries: [String], includesRestOfWorld: Bool) {
        self.countries = countries
        self.includesRestOfWorld = includesRestOfWorld
    }
}

public struct StoreVersionReleaseNote: Codable, Hashable, Sendable {
    public var language: String
    public var text: String

    public init(language: String, text: String) {
        self.language = language
        self.text = text
    }
}

public struct UnifiedApp: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var symbol: String
    public var tintHex: UInt
    public var appStoreApp: StoreApp?
    public var playStoreApp: StoreApp?

    public var tint: Color { Color(hex: tintHex) }
    public var linkedCount: Int { [appStoreApp, playStoreApp].compactMap { $0 }.count }
}

public struct ListingLocalization: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var locale: String
    public var language: String
    public var title: String
    public var subtitle: String
    public var promotionalText: String
    public var description: String
    public var keywords: String
    public var releaseNotes: String
    public var dirtyPlatforms: Set<StorePlatform>
    public var lastSaved: Date?
    public var appleVersionLocalizationID: String?
    public var appleAppInfoLocalizationID: String?
    public var googleLanguage: String?
    // These persisted names predate the explicit per-store editor. Keep them so
    // existing workspaces decode without migration; use the semantic accessors
    // below in new code.
    public var googleTitle: String? = nil
    public var googleSubtitle: String? = nil
    public var googleDescription: String? = nil

    public var playStoreTitle: String {
        get { googleTitle ?? title }
        set { googleTitle = newValue }
    }

    public var shortDescription: String {
        get { googleSubtitle ?? subtitle }
        set { googleSubtitle = newValue }
    }

    public var playStoreFullDescription: String {
        get { googleDescription ?? description }
        set { googleDescription = newValue }
    }

    public var completion: Double {
        let values = [title, subtitle, promotionalText, description, keywords, releaseNotes]
        return Double(values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count) / Double(values.count)
    }

    public func completion(for platforms: Set<StorePlatform>) -> Double {
        var values: [String] = []
        if platforms.contains(.appStore) {
            values += [title, subtitle, promotionalText, description, keywords, releaseNotes]
        }
        if platforms.contains(.playStore) {
            values += [playStoreTitle, shortDescription, playStoreFullDescription]
        }
        guard !values.isEmpty else { return 0 }
        return Double(values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count) / Double(values.count)
    }
}

public enum ListingMetadataField: String, CaseIterable, Identifiable, Sendable {
    case title
    case subtitle
    case shortDescription
    case promotionalText
    case description
    case keywords
    case releaseNotes

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .title: "App name"
        case .subtitle: "Subtitle"
        case .shortDescription: "Short description"
        case .promotionalText: "Promotional text"
        case .description: "Full description"
        case .keywords: "Keywords"
        case .releaseNotes: "What’s new"
        }
    }

    public var promptName: String {
        switch self {
        case .title: "app_name"
        case .subtitle: "app_store_subtitle"
        case .shortDescription: "google_play_short_description"
        case .promotionalText: "promotional_text"
        case .description: "full_description"
        case .keywords: "keywords"
        case .releaseNotes: "whats_new"
        }
    }

    public func value(in localization: ListingLocalization) -> String {
        switch self {
        case .title: localization.title
        case .subtitle: localization.subtitle
        case .shortDescription: localization.shortDescription
        case .promotionalText: localization.promotionalText
        case .description: localization.description
        case .keywords: localization.keywords
        case .releaseNotes: localization.releaseNotes
        }
    }

    public func set(_ value: String, in localization: inout ListingLocalization) {
        switch self {
        case .title: localization.title = value
        case .subtitle: localization.subtitle = value
        case .shortDescription: localization.shortDescription = value
        case .promotionalText: localization.promotionalText = value
        case .description: localization.description = value
        case .keywords: localization.keywords = value
        case .releaseNotes: localization.releaseNotes = value
        }
    }

    public func characterLimit(in limits: ListingMetadataLimits) -> Int {
        switch self {
        case .title: limits.title
        case .subtitle: limits.subtitle
        case .shortDescription: limits.shortDescription
        case .promotionalText: limits.promotionalText
        case .description: limits.description
        case .keywords: limits.keywords
        case .releaseNotes: limits.releaseNotes
        }
    }

    public var supportedPlatforms: Set<StorePlatform> {
        switch self {
        case .subtitle, .promotionalText, .keywords, .releaseNotes:
            [.appStore]
        case .shortDescription:
            [.playStore]
        case .title, .description:
            Set(StorePlatform.allCases)
        }
    }
}

public struct StoreScreenshot: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var platform: StorePlatform
    public var locale: String
    public var device: String
    public var title: String
    public var caption: String
    public var gradientStartHex: UInt
    public var gradientEndHex: UInt
    public var remoteID: String?
    public var remoteURL: String?
    public var screenshotSetID: String?
    public var localDraftURL: String? = nil
}

public func screenshotGalleryKey(_ screenshot: StoreScreenshot) -> String {
    let gallery = screenshot.screenshotSetID ?? screenshot.device.lowercased()
    return [
        screenshot.platform.rawValue,
        canonicalStoreLocale(screenshot.locale),
        gallery
    ].joined(separator: "|")
}

public func screenshotsShareGallery(_ lhs: StoreScreenshot, _ rhs: StoreScreenshot) -> Bool {
    guard lhs.platform == rhs.platform,
          canonicalStoreLocale(lhs.locale) == canonicalStoreLocale(rhs.locale) else {
        return false
    }
    if lhs.screenshotSetID != nil || rhs.screenshotSetID != nil {
        return lhs.screenshotSetID == rhs.screenshotSetID
    }
    return lhs.device.caseInsensitiveCompare(rhs.device) == .orderedSame
}

public func screenshotsByMoving(
    _ screenshots: [StoreScreenshot],
    screenshotID: UUID,
    before destinationID: UUID?
) -> [StoreScreenshot]? {
    guard let source = screenshots.first(where: { $0.id == screenshotID }) else {
        return nil
    }
    let galleryIndices = screenshots.indices.filter {
        screenshotsShareGallery(screenshots[$0], source)
    }
    guard galleryIndices.count > 1 else { return nil }

    var gallery = galleryIndices.map { screenshots[$0] }
    guard let sourceIndex = gallery.firstIndex(where: { $0.id == screenshotID }) else {
        return nil
    }
    let moved = gallery.remove(at: sourceIndex)
    if let destinationID {
        guard let destinationIndex = gallery.firstIndex(where: { $0.id == destinationID }) else {
            return nil
        }
        gallery.insert(moved, at: destinationIndex)
    } else {
        gallery.append(moved)
    }
    guard galleryIndices.map({ screenshots[$0].id }) != gallery.map(\.id) else {
        return nil
    }

    var result = screenshots
    for (index, screenshot) in zip(galleryIndices, gallery) {
        result[index] = screenshot
    }
    return result
}

public struct ScreenshotDraftState: Codable, Hashable, Sendable {
    public var dirtyGalleryKeys: Set<String>
    public var deletedScreenshots: [StoreScreenshot]

    public init(
        dirtyGalleryKeys: Set<String> = [],
        deletedScreenshots: [StoreScreenshot] = []
    ) {
        self.dirtyGalleryKeys = dirtyGalleryKeys
        self.deletedScreenshots = deletedScreenshots
    }

    public var isEmpty: Bool {
        dirtyGalleryKeys.isEmpty && deletedScreenshots.isEmpty
    }
}

public func googlePlayOriginalImageURL(from previewURL: URL) -> URL? {
    guard let host = previewURL.host?.lowercased(),
          host == "googleusercontent.com"
            || host.hasSuffix(".googleusercontent.com")
            || host == "ggpht.com"
            || host.hasSuffix(".ggpht.com"),
          var components = URLComponents(url: previewURL, resolvingAgainstBaseURL: false) else {
        return nil
    }
    let path = components.percentEncodedPath
    if let transform = path.range(of: #"=[^/]+$"#, options: .regularExpression) {
        components.percentEncodedPath.replaceSubrange(transform, with: "=s0")
    } else {
        components.percentEncodedPath += "=s0"
    }
    return components.url
}

public struct ScreenshotImageProperties: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let fileSize: Int
    public let hasAlpha: Bool

    public init(width: Int, height: Int, fileSize: Int, hasAlpha: Bool) {
        self.width = width
        self.height = height
        self.fileSize = fileSize
        self.hasAlpha = hasAlpha
    }
}

public func screenshotUploadValidationIssue(
    properties: ScreenshotImageProperties,
    platform: StorePlatform,
    device: String
) -> String? {
    guard properties.width > 0, properties.height > 0 else {
        return "The image dimensions could not be read."
    }
    guard !properties.hasAlpha else {
        return "\(platform.rawValue) screenshots cannot contain transparency or an alpha channel."
    }

    switch platform {
    case .appStore:
        guard appStoreScreenshotDisplayType(
            width: properties.width,
            height: properties.height,
            device: device
        ) != nil else {
            return "The \(properties.width) × \(properties.height) image is not an accepted App Store \(device.lowercased()) screenshot size."
        }
    case .playStore:
        let shortestSide = min(properties.width, properties.height)
        let longestSide = max(properties.width, properties.height)
        guard shortestSide >= 320 else {
            return "Google Play screenshots must be at least 320 px on their shortest side."
        }
        guard longestSide <= 3_840 else {
            return "Google Play screenshots cannot exceed 3,840 px on their longest side."
        }
        guard longestSide * 10 <= shortestSide * 23 else {
            return "Google Play requires the longest side to be no more than 2.3 times the shortest side."
        }
    }
    return nil
}

public func appStoreScreenshotDisplayType(width: Int, height: Int, device: String) -> String? {
    if ["Desktop", "TV"].contains(device), width <= height {
        return nil
    }
    let size = ScreenshotPixelSize(width, height)
    let accepted: [(type: String, devices: Set<String>, sizes: Set<ScreenshotPixelSize>)] = [
        ("APP_IPHONE_67", ["Phone"], [
            ScreenshotPixelSize(1_260, 2_736), ScreenshotPixelSize(1_290, 2_796),
            ScreenshotPixelSize(1_320, 2_868)
        ]),
        ("APP_IPHONE_65", ["Phone"], [
            ScreenshotPixelSize(1_284, 2_778), ScreenshotPixelSize(1_242, 2_688)
        ]),
        ("APP_IPHONE_61", ["Phone"], [
            ScreenshotPixelSize(1_179, 2_556), ScreenshotPixelSize(1_206, 2_622),
            ScreenshotPixelSize(1_170, 2_532), ScreenshotPixelSize(1_080, 2_340)
        ]),
        ("APP_IPHONE_58", ["Phone"], [ScreenshotPixelSize(1_125, 2_436)]),
        ("APP_IPHONE_55", ["Phone"], [ScreenshotPixelSize(1_242, 2_208)]),
        ("APP_IPHONE_47", ["Phone"], [ScreenshotPixelSize(750, 1_334)]),
        ("APP_IPHONE_40", ["Phone"], [
            ScreenshotPixelSize(640, 1_096), ScreenshotPixelSize(640, 1_136),
            ScreenshotPixelSize(600, 1_136)
        ]),
        ("APP_IPHONE_35", ["Phone"], [
            ScreenshotPixelSize(640, 920), ScreenshotPixelSize(640, 960),
            ScreenshotPixelSize(600, 960)
        ]),
        ("APP_IPAD_PRO_3GEN_129", ["Tablet"], [
            ScreenshotPixelSize(2_064, 2_752), ScreenshotPixelSize(2_048, 2_732)
        ]),
        ("APP_IPAD_PRO_3GEN_11", ["Tablet"], [
            ScreenshotPixelSize(1_488, 2_266), ScreenshotPixelSize(1_668, 2_420),
            ScreenshotPixelSize(1_668, 2_388), ScreenshotPixelSize(1_640, 2_360)
        ]),
        ("APP_IPAD_105", ["Tablet"], [ScreenshotPixelSize(1_668, 2_224)]),
        ("APP_IPAD_97", ["Tablet"], [
            ScreenshotPixelSize(1_536, 2_008), ScreenshotPixelSize(1_536, 2_048),
            ScreenshotPixelSize(1_496, 2_048), ScreenshotPixelSize(768, 1_004),
            ScreenshotPixelSize(768, 1_024), ScreenshotPixelSize(748, 1_024)
        ]),
        ("APP_DESKTOP", ["Desktop"], [
            ScreenshotPixelSize(1_280, 800), ScreenshotPixelSize(1_440, 900),
            ScreenshotPixelSize(2_560, 1_600), ScreenshotPixelSize(2_880, 1_800)
        ]),
        ("APP_APPLE_TV", ["TV"], [
            ScreenshotPixelSize(1_920, 1_080), ScreenshotPixelSize(3_840, 2_160)
        ])
    ]
    return accepted.first {
        $0.devices.contains(device) && $0.sizes.contains(size)
    }?.type
}

private struct ScreenshotPixelSize: Hashable {
    let shortSide: Int
    let longSide: Int

    init(_ width: Int, _ height: Int) {
        shortSide = min(width, height)
        longSide = max(width, height)
    }
}

public struct PriceRegion: Identifiable, Codable, Hashable, Sendable {
    public var id: String { code }
    public var code: String
    public var country: String
    public var flag: String
    public var currency: String
    public var pppIndex: Double
    public var currentPrice: Double
    public var suggestedPrice: Double
    public var enabled: Bool
}

public enum PricingIndex: String, Codable, CaseIterable, Identifiable, Sendable {
    case worldwidePPP
    case netflix
    case bigMac

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .worldwidePPP: "Worldwide PPP"
        case .netflix: "Netflix index"
        case .bigMac: "Big Mac index"
        }
    }
    public var detail: String {
        switch self {
        case .worldwidePPP: "World Bank purchasing-power and exchange-rate data"
        case .netflix: "Relative Standard-plan prices, with PPP fallback"
        case .bigMac: "The Economist’s local Big Mac prices, with PPP fallback"
        }
    }
}

public struct StoreProduct: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var productID: String
    public var kind: String
    public var basePrice: Double
    public var platforms: Set<StorePlatform>
    public var regions: [PriceRegion]
    public var appleProductID: String?
    public var googleProductID: String?
    public var googleBasePlanID: String?
    public var pricingIndex: PricingIndex? = nil
    public var pricingCalculatedAt: Date? = nil
    public var pricingSourceSummary: String? = nil

    public var effectivePricingIndex: PricingIndex { pricingIndex ?? .worldwidePPP }
    public var isSubscription: Bool { kind.localizedCaseInsensitiveContains("subscription") || kind.localizedCaseInsensitiveContains("auto-renewable") }
}

public struct ListingMetadataLimits: Sendable {
    public let title = 30
    public let subtitle = 30
    public let shortDescription = 80
    public let promotionalText = 170
    public let description = 4_000
    public let keywords = 100
    public let releaseNotes = 4_000

    public init(platforms _: Set<StorePlatform>) {}

    public func violations(in localization: ListingLocalization, platforms: Set<StorePlatform>) -> [String] {
        var result: [String] = []
        if platforms.contains(.appStore) {
            if localization.title.count > title { result.append("App Store app name exceeds " + String(title) + " characters") }
            if localization.subtitle.count > subtitle { result.append("App Store subtitle exceeds " + String(subtitle) + " characters") }
            if localization.promotionalText.count > promotionalText { result.append("Promotional text exceeds " + String(promotionalText) + " characters") }
            if localization.keywords.count > keywords { result.append("Keywords exceed " + String(keywords) + " characters") }
            if localization.releaseNotes.count > releaseNotes { result.append("What’s new exceeds " + String(releaseNotes) + " characters") }
            if localization.description.count > description { result.append("App Store description exceeds " + String(description) + " characters") }
        }
        if platforms.contains(.playStore) {
            if localization.playStoreTitle.count > title { result.append("Google Play app name exceeds " + String(title) + " characters") }
            if localization.shortDescription.count > shortDescription {
                result.append("Google Play short description exceeds " + String(shortDescription) + " characters")
            }
            if localization.playStoreFullDescription.count > description {
                result.append("Google Play full description exceeds " + String(description) + " characters")
            }
        }
        return result
    }
}

public struct CustomerReview: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var platform: StorePlatform
    public var author: String
    public var countryCode: String
    public var rating: Int
    public var title: String
    public var body: String
    public var date: Date
    public var version: String
    public var response: String?
    public var remoteID: String?
    public var responseRemoteID: String?
}

public struct Workspace: Codable, Sendable {
    public var connections: [StoreConnection]
    public var apps: [UnifiedApp]
    public var localizationsByApp: [UUID: [ListingLocalization]]
    public var screenshotsByApp: [UUID: [StoreScreenshot]]
    public var productsByApp: [UUID: [StoreProduct]]
    public var reviewsByApp: [UUID: [CustomerReview]]
    public var googlePlayReleaseNotesByApp: [UUID: String]? = nil
    public var screenshotDraftsByApp: [UUID: ScreenshotDraftState]? = nil
}

extension Workspace {
    public static var empty: Workspace {
        Workspace(
            connections: StorePlatform.allCases.map {
                StoreConnection(platform: $0, accountName: $0.rawValue, detail: "Not connected", state: .disconnected, lastSync: nil)
            },
            apps: [],
            localizationsByApp: [:],
            screenshotsByApp: [:],
            productsByApp: [:],
            reviewsByApp: [:]
        )
    }
}

public enum AppSection: String, CaseIterable, Identifiable, Sendable {
    case overview = "Overview"
    case listing = "Store listing"
    case screenshots = "Screenshots"
    case pricing = "PPP pricing"
    case reviews = "Customer reviews"

    public var id: String { rawValue }
    public var icon: String {
        switch self {
        case .overview: "rectangle.grid.2x2"
        case .listing: "text.document"
        case .screenshots: "photo.on.rectangle.angled"
        case .pricing: "globe.europe.africa"
        case .reviews: "quote.bubble"
        }
    }
}

public enum PlatformFilter: String, CaseIterable, Identifiable, Sendable {
    case both = "Both stores"
    case appStore = "App Store"
    case playStore = "Google Play"

    public var id: String { rawValue }
    public var platforms: Set<StorePlatform> {
        switch self {
        case .both: [.appStore, .playStore]
        case .appStore: [.appStore]
        case .playStore: [.playStore]
        }
    }
}

extension Color {
    public init(hex: UInt) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: 1
        )
    }
}

public func roundedCharmPrice(_ value: Double) -> Double {
    max(0.99, value.rounded(.down) + 0.99)
}

public func localizedCharmPrice(_ value: Double, currency: String) -> Double {
    guard value > 0 else { return 0 }
    let zeroDecimalCurrencies: Set<String> = [
        "BIF", "CLP", "DJF", "GNF", "IDR", "ISK", "JPY", "KMF", "KRW", "PYG", "RWF", "UGX", "VND", "VUV", "XAF", "XOF", "XPF"
    ]
    if zeroDecimalCurrencies.contains(currency) {
        return max(1, value.rounded())
    }
    return max(0.01, value.rounded(.down) + 0.99)
}

public func pricingRegionEnabledByDefault(_ code: String) -> Bool {
    true
}

public func storePriceValue(from input: String) -> Double? {
    let compact = String(
        input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { !$0.isWhitespace }
    )
    guard !compact.isEmpty,
          !(compact.contains(",") && compact.contains(".")) else {
        return nil
    }

    let normalized = compact.replacingOccurrences(of: ",", with: ".")
    guard normalized.filter({ $0 == "." }).count <= 1,
          normalized.allSatisfy({ $0.isNumber || $0 == "." }),
          let value = Double(normalized),
          value.isFinite,
          value > 0 else {
        return nil
    }
    return value
}

public func canonicalStoreLocale(_ locale: String) -> String {
    let normalized = locale.replacingOccurrences(of: "_", with: "-").lowercased()
    let components = normalized.split(separator: "-")
    guard let language = components.first else { return normalized }
    if language == "zh" {
        let variant = components.dropFirst().first.map(String.init) ?? "hans"
        return ["tw", "hk", "hant"].contains(variant) ? "zh-hant" : "zh-hans"
    }
    if language == "iw" { return "he" }
    if ["en", "es", "pt", "fr"].contains(String(language)) {
        return components.prefix(2).joined(separator: "-")
    }
    return String(language)
}

public func primaryLocalization(
    in localizations: [ListingLocalization],
    preferredLocale: String?
) -> ListingLocalization? {
    if let preferredLocale,
       let preferred = localizations.first(where: {
           canonicalStoreLocale($0.locale) == canonicalStoreLocale(preferredLocale)
       }) {
        return preferred
    }
    return localizations.first(where: { $0.locale.caseInsensitiveCompare("en-US") == .orderedSame })
        ?? localizations.first(where: { $0.locale.lowercased().hasPrefix("en") })
        ?? localizations.first
}

public func googleLocale(forAppleLocale locale: String) -> String {
    let map = [
        "ca": "ca-ES", "cs": "cs-CZ", "da": "da-DK", "el": "el-GR", "fi": "fi-FI",
        "he": "iw-IL", "hi": "hi-IN", "hr": "hr-HR", "hu": "hu-HU", "id": "id-ID",
        "it": "it-IT", "ja": "ja-JP", "ko": "ko-KR", "ms": "ms-MY", "no": "no-NO",
        "pl": "pl-PL", "ro": "ro-RO", "ru": "ru-RU", "sk": "sk-SK", "sv": "sv-SE",
        "th": "th-TH", "tr": "tr-TR", "uk": "uk-UA", "vi": "vi-VN",
        "zh-Hans": "zh-CN", "zh-Hant": "zh-TW"
    ]
    return map[locale] ?? locale
}

public struct GooglePlayReleaseNote: Equatable, Sendable {
    public var locale: String
    public var text: String
}

public let googlePlayReleaseNoteCharacterLimit = 500

public func googlePlayReleaseNotes(in taggedBlock: String) -> [GooglePlayReleaseNote] {
    let lines = taggedBlock.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
    var notes: [GooglePlayReleaseNote] = []
    var currentLocale: String?
    var currentLines: [String] = []

    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if let locale = currentLocale {
            if trimmed == "</\(locale)>" {
                let text = currentLines.joined(separator: "\n")
                notes.append(GooglePlayReleaseNote(locale: locale, text: text))
                currentLocale = nil
                currentLines = []
            } else {
                currentLines.append(line)
            }
        } else if trimmed.hasPrefix("<"), trimmed.hasSuffix(">"), !trimmed.hasPrefix("</") {
            let candidate = String(trimmed.dropFirst().dropLast())
            if isGooglePlayReleaseNoteLocale(candidate) {
                currentLocale = candidate
                currentLines = []
            }
        }
    }
    return notes
}

public func googlePlayReleaseNote(in taggedBlock: String, locale: String) -> String {
    googlePlayReleaseNotes(in: taggedBlock)
        .last(where: { canonicalStoreLocale($0.locale) == canonicalStoreLocale(locale) })?
        .text ?? ""
}

public func replacingGooglePlayReleaseNote(
    in taggedBlock: String,
    locale: String,
    text: String,
    orderedLocales: [String]
) -> String {
    var notes = googlePlayReleaseNotes(in: taggedBlock)
    notes.removeAll { canonicalStoreLocale($0.locale) == canonicalStoreLocale(locale) }
    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        notes.append(GooglePlayReleaseNote(locale: locale, text: text))
    }

    var ordered: [GooglePlayReleaseNote] = []
    for orderedLocale in orderedLocales {
        if let index = notes.firstIndex(where: {
            canonicalStoreLocale($0.locale) == canonicalStoreLocale(orderedLocale)
        }) {
            var note = notes.remove(at: index)
            note.locale = orderedLocale
            ordered.append(note)
        }
    }
    ordered.append(contentsOf: notes)
    return googlePlayReleaseNotesBlock(ordered)
}

public func googlePlayReleaseNotesValidationIssues(_ taggedBlock: String) -> [String] {
    let cleanBlock = taggedBlock.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanBlock.isEmpty else { return [] }
    let notes = googlePlayReleaseNotes(in: cleanBlock)
    var issues: [String] = []
    if notes.isEmpty {
        issues.append("Use a matching opening and closing language tag on separate lines.")
    }
    var seen: Set<String> = []
    for note in notes {
        let canonical = canonicalStoreLocale(note.locale)
        if !seen.insert(canonical).inserted {
            issues.append("\(note.locale) appears more than once.")
        }
        if note.text.count > googlePlayReleaseNoteCharacterLimit {
            issues.append("\(note.locale) exceeds \(googlePlayReleaseNoteCharacterLimit) characters.")
        }
    }
    return issues
}

private func googlePlayReleaseNotesBlock(_ notes: [GooglePlayReleaseNote]) -> String {
    notes.map { "<\($0.locale)>\n\($0.text)\n</\($0.locale)>" }.joined(separator: "\n\n")
}

private func isGooglePlayReleaseNoteLocale(_ value: String) -> Bool {
    value.range(
        of: #"^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$"#,
        options: .regularExpression
    ) != nil
}

public func listingLocalization(
    _ localization: ListingLocalization,
    displaying platforms: Set<StorePlatform>
) -> ListingLocalization {
    guard platforms.contains(.playStore), !platforms.contains(.appStore) else { return localization }
    var result = localization
    result.title = localization.playStoreTitle
    result.subtitle = localization.shortDescription
    result.description = localization.playStoreFullDescription
    return result
}

/// Returns whether the metadata currently shown in the editor differs from its
/// stored representation for the active store selection.
public func listingMetadataHasChanges(
    _ displayed: ListingLocalization,
    comparedTo stored: ListingLocalization,
    displaying platforms: Set<StorePlatform>
) -> Bool {
    let applied = applyingListingMetadata(from: displayed, to: stored, platforms: platforms)
    return applied.title != stored.title
        || applied.subtitle != stored.subtitle
        || applied.promotionalText != stored.promotionalText
        || applied.description != stored.description
        || applied.keywords != stored.keywords
        || applied.releaseNotes != stored.releaseNotes
        || applied.googleTitle != stored.googleTitle
        || applied.googleSubtitle != stored.googleSubtitle
        || applied.googleDescription != stored.googleDescription
}

public func applyingListingMetadata(
    from displayed: ListingLocalization,
    to stored: ListingLocalization,
    platforms: Set<StorePlatform>
) -> ListingLocalization {
    var result = stored
    if platforms.contains(.appStore) {
        result.title = displayed.title
        result.subtitle = displayed.subtitle
        result.promotionalText = displayed.promotionalText
        result.description = displayed.description
        result.keywords = displayed.keywords
        result.releaseNotes = displayed.releaseNotes
    }
    if platforms.contains(.playStore) {
        if platforms == [.playStore] {
            if displayed.title != stored.playStoreTitle {
                result.playStoreTitle = displayed.title
            }
            if displayed.description != stored.playStoreFullDescription {
                result.playStoreFullDescription = displayed.description
            }
        } else {
            result.googleTitle = displayed.googleTitle ?? stored.googleTitle
            result.googleDescription = displayed.googleDescription ?? stored.googleDescription
        }
        if displayed.shortDescription != stored.shortDescription {
            result.shortDescription = displayed.shortDescription
        }
    }
    return result
}
