import Foundation
import SwiftUI

public enum StorePlatform: String, Codable, CaseIterable, Identifiable, Sendable {
    case appStore = "App Store"
    case playStore = "Google Play"

    public var id: String { rawValue }
    public var shortName: String { self == .appStore ? "iOS" : "Android" }
    public var icon: String { self == .appStore ? "apple.logo" : "play.fill" }
    public var tint: Color { self == .appStore ? Color(hex: 0x2477F5) : Color(hex: 0x14A46D) }
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

    public var hasEditableMetadataVersion: Bool {
        guard platform == .appStore else { return true }
        return Self.editableAppStoreStates.contains(remoteState ?? "")
    }

    private static let editableAppStoreStates: Set<String> = [
        "PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"
    ]
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
    public var googleTitle: String? = nil
    public var googleSubtitle: String? = nil
    public var googleDescription: String? = nil

    public var completion: Double {
        let values = [title, subtitle, promotionalText, description, keywords, releaseNotes]
        return Double(values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count) / Double(values.count)
    }

    public func completion(for platforms: Set<StorePlatform>) -> Double {
        var values = [title, subtitle, description]
        if platforms.contains(.appStore) {
            values += [promotionalText, keywords, releaseNotes]
        }
        return Double(values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count) / Double(values.count)
    }
}

public enum ListingMetadataField: String, CaseIterable, Identifiable, Sendable {
    case title
    case subtitle
    case promotionalText
    case description
    case keywords
    case releaseNotes

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .title: "App name"
        case .subtitle: "Subtitle / short description"
        case .promotionalText: "Promotional text"
        case .description: "Full description"
        case .keywords: "Keywords"
        case .releaseNotes: "What’s new"
        }
    }

    public var promptName: String {
        switch self {
        case .title: "app_name"
        case .subtitle: "subtitle_or_short_description"
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
        case .promotionalText: limits.promotionalText
        case .description: limits.description
        case .keywords: limits.keywords
        case .releaseNotes: limits.releaseNotes
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

public enum SubscriberPricePolicy: String, Codable, CaseIterable, Identifiable, Sendable {
    case preserve
    case migrate

    public var id: String { rawValue }
    public var title: String { self == .preserve ? "Preserve existing prices where allowed" : "Move subscribers to new prices" }
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
    public var subscriberPricePolicy: SubscriberPricePolicy? = nil
    public var pricingCalculatedAt: Date? = nil
    public var pricingSourceSummary: String? = nil

    public var effectivePricingIndex: PricingIndex { pricingIndex ?? .worldwidePPP }
    public var effectiveSubscriberPricePolicy: SubscriberPricePolicy { subscriberPricePolicy ?? .preserve }
    public var isSubscription: Bool { kind.localizedCaseInsensitiveContains("subscription") || kind.localizedCaseInsensitiveContains("auto-renewable") }
}

public struct PricingApplyProgress: Equatable, Sendable {
    public var platform: StorePlatform
    public var completed: Int
    public var total: Int
    public var detail: String

    public var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(completed) / Double(total)))
    }
}

public typealias PricingApplyProgressHandler = @MainActor @Sendable (PricingApplyProgress) -> Void

public struct ListingMetadataLimits: Sendable {
    public let title = 30
    public let subtitle: Int
    public let promotionalText = 170
    public let description = 4_000
    public let keywords = 100
    public let releaseNotes = 4_000

    public init(platforms: Set<StorePlatform>) {
        subtitle = platforms.contains(.appStore) ? 30 : 80
    }

    public func violations(in localization: ListingLocalization, platforms: Set<StorePlatform>) -> [String] {
        var result: [String] = []
        if localization.title.count > title { result.append("App name exceeds " + String(title) + " characters") }
        if localization.subtitle.count > subtitle { result.append("Subtitle / short description exceeds " + String(subtitle) + " characters") }
        if platforms.contains(.appStore) {
            if localization.promotionalText.count > promotionalText { result.append("Promotional text exceeds " + String(promotionalText) + " characters") }
            if localization.keywords.count > keywords { result.append("Keywords exceed " + String(keywords) + " characters") }
            if localization.releaseNotes.count > releaseNotes { result.append("What’s new exceeds " + String(releaseNotes) + " characters") }
        }
        if localization.description.count > description { result.append("Description exceeds " + String(description) + " characters") }
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

public func regionsRequiringPriceChange(_ regions: [PriceRegion]) -> [PriceRegion] {
    regions.filter {
        $0.enabled && abs($0.suggestedPrice - $0.currentPrice) > 0.000_001
    }
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
                let text = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
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
    let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if !cleanText.isEmpty {
        notes.append(GooglePlayReleaseNote(locale: locale, text: cleanText))
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
    result.title = localization.googleTitle ?? localization.title
    result.subtitle = localization.googleSubtitle ?? localization.subtitle
    result.description = localization.googleDescription ?? localization.description
    return result
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
        result.googleTitle = displayed.title
        result.googleSubtitle = displayed.subtitle
        result.googleDescription = displayed.description
    }
    return result
}
