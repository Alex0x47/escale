import Foundation
import SwiftUI

enum StorePlatform: String, Codable, CaseIterable, Identifiable, Sendable {
    case appStore = "App Store"
    case playStore = "Google Play"

    var id: String { rawValue }
    var shortName: String { self == .appStore ? "iOS" : "Android" }
    var icon: String { self == .appStore ? "apple.logo" : "play.fill" }
    var tint: Color { self == .appStore ? Color(hex: 0x2477F5) : Color(hex: 0x14A46D) }
}

enum ConnectionState: String, Codable, Sendable {
    case connected
    case attention
    case disconnected

    var label: String {
        switch self {
        case .connected: "Connected"
        case .attention: "Needs attention"
        case .disconnected: "Not connected"
        }
    }
}

struct StoreConnection: Identifiable, Codable, Hashable, Sendable {
    var id: StorePlatform { platform }
    let platform: StorePlatform
    var accountName: String
    var detail: String
    var state: ConnectionState
    var lastSync: Date?
}

enum ReleaseState: String, Codable, Sendable {
    case ready = "Ready for distribution"
    case review = "In review"
    case draft = "Draft"
    case rejected = "Action required"

    var color: Color {
        switch self {
        case .ready: .green
        case .review: .orange
        case .draft: .secondary
        case .rejected: .red
        }
    }
}

struct StoreApp: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var platform: StorePlatform
    var name: String
    var bundleID: String
    var storeID: String
    var version: String
    var state: ReleaseState
    var versionID: String?
    var appInfoID: String?
    var iconURL: String? = nil
    var remoteState: String? = nil
    var primaryLocale: String? = nil

    var hasEditableMetadataVersion: Bool {
        guard platform == .appStore else { return true }
        return Self.editableAppStoreStates.contains(remoteState ?? "")
    }

    private static let editableAppStoreStates: Set<String> = [
        "PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"
    ]
}

struct UnifiedApp: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var symbol: String
    var tintHex: UInt
    var appStoreApp: StoreApp?
    var playStoreApp: StoreApp?

    var tint: Color { Color(hex: tintHex) }
    var linkedCount: Int { [appStoreApp, playStoreApp].compactMap { $0 }.count }
}

struct ListingLocalization: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var locale: String
    var language: String
    var title: String
    var subtitle: String
    var promotionalText: String
    var description: String
    var keywords: String
    var releaseNotes: String
    var dirtyPlatforms: Set<StorePlatform>
    var lastSaved: Date?
    var appleVersionLocalizationID: String?
    var appleAppInfoLocalizationID: String?
    var googleLanguage: String?
    var googleTitle: String? = nil
    var googleSubtitle: String? = nil
    var googleDescription: String? = nil

    var completion: Double {
        let values = [title, subtitle, promotionalText, description, keywords, releaseNotes]
        return Double(values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count) / Double(values.count)
    }

    func completion(for platforms: Set<StorePlatform>) -> Double {
        var values = [title, subtitle, description]
        if platforms.contains(.appStore) {
            values += [promotionalText, keywords, releaseNotes]
        }
        return Double(values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count) / Double(values.count)
    }
}

enum ListingMetadataField: String, CaseIterable, Identifiable, Sendable {
    case title
    case subtitle
    case promotionalText
    case description
    case keywords
    case releaseNotes

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .title: "App name"
        case .subtitle: "Subtitle / short description"
        case .promotionalText: "Promotional text"
        case .description: "Full description"
        case .keywords: "Keywords"
        case .releaseNotes: "What’s new"
        }
    }

    var promptName: String {
        switch self {
        case .title: "app_name"
        case .subtitle: "subtitle_or_short_description"
        case .promotionalText: "promotional_text"
        case .description: "full_description"
        case .keywords: "keywords"
        case .releaseNotes: "whats_new"
        }
    }

    func value(in localization: ListingLocalization) -> String {
        switch self {
        case .title: localization.title
        case .subtitle: localization.subtitle
        case .promotionalText: localization.promotionalText
        case .description: localization.description
        case .keywords: localization.keywords
        case .releaseNotes: localization.releaseNotes
        }
    }

    func set(_ value: String, in localization: inout ListingLocalization) {
        switch self {
        case .title: localization.title = value
        case .subtitle: localization.subtitle = value
        case .promotionalText: localization.promotionalText = value
        case .description: localization.description = value
        case .keywords: localization.keywords = value
        case .releaseNotes: localization.releaseNotes = value
        }
    }

    func characterLimit(in limits: ListingMetadataLimits) -> Int {
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

struct StoreScreenshot: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var platform: StorePlatform
    var locale: String
    var device: String
    var title: String
    var caption: String
    var gradientStartHex: UInt
    var gradientEndHex: UInt
    var remoteID: String?
    var remoteURL: String?
    var screenshotSetID: String?
}

struct PriceRegion: Identifiable, Codable, Hashable, Sendable {
    var id: String { code }
    var code: String
    var country: String
    var flag: String
    var currency: String
    var pppIndex: Double
    var currentPrice: Double
    var suggestedPrice: Double
    var enabled: Bool
}

enum PricingIndex: String, Codable, CaseIterable, Identifiable, Sendable {
    case worldwidePPP
    case netflix
    case bigMac

    var id: String { rawValue }
    var title: String {
        switch self {
        case .worldwidePPP: "Worldwide PPP"
        case .netflix: "Netflix index"
        case .bigMac: "Big Mac index"
        }
    }
    var detail: String {
        switch self {
        case .worldwidePPP: "World Bank purchasing-power and exchange-rate data"
        case .netflix: "Relative Standard-plan prices, with PPP fallback"
        case .bigMac: "The Economist’s local Big Mac prices, with PPP fallback"
        }
    }
}

enum SubscriberPricePolicy: String, Codable, CaseIterable, Identifiable, Sendable {
    case preserve
    case migrate

    var id: String { rawValue }
    var title: String { self == .preserve ? "Preserve existing prices where allowed" : "Move subscribers to new prices" }
}

struct StoreProduct: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var productID: String
    var kind: String
    var basePrice: Double
    var platforms: Set<StorePlatform>
    var regions: [PriceRegion]
    var appleProductID: String?
    var googleProductID: String?
    var googleBasePlanID: String?
    var pricingIndex: PricingIndex? = nil
    var subscriberPricePolicy: SubscriberPricePolicy? = nil
    var pricingCalculatedAt: Date? = nil
    var pricingSourceSummary: String? = nil

    var effectivePricingIndex: PricingIndex { pricingIndex ?? .worldwidePPP }
    var effectiveSubscriberPricePolicy: SubscriberPricePolicy { subscriberPricePolicy ?? .preserve }
    var isSubscription: Bool { kind.localizedCaseInsensitiveContains("subscription") || kind.localizedCaseInsensitiveContains("auto-renewable") }
}

struct PricingApplyProgress: Equatable, Sendable {
    var platform: StorePlatform
    var completed: Int
    var total: Int
    var detail: String

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(completed) / Double(total)))
    }
}

typealias PricingApplyProgressHandler = @MainActor @Sendable (PricingApplyProgress) -> Void

struct ListingMetadataLimits: Sendable {
    let title = 30
    let subtitle: Int
    let promotionalText = 170
    let description = 4_000
    let keywords = 100
    let releaseNotes = 4_000

    init(platforms: Set<StorePlatform>) {
        subtitle = platforms.contains(.appStore) ? 30 : 80
    }

    func violations(in localization: ListingLocalization, platforms: Set<StorePlatform>) -> [String] {
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

struct CustomerReview: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var platform: StorePlatform
    var author: String
    var countryCode: String
    var rating: Int
    var title: String
    var body: String
    var date: Date
    var version: String
    var response: String?
    var remoteID: String?
    var responseRemoteID: String?
}

struct Workspace: Codable, Sendable {
    var connections: [StoreConnection]
    var apps: [UnifiedApp]
    var localizationsByApp: [UUID: [ListingLocalization]]
    var screenshotsByApp: [UUID: [StoreScreenshot]]
    var productsByApp: [UUID: [StoreProduct]]
    var reviewsByApp: [UUID: [CustomerReview]]
    var googlePlayReleaseNotesByApp: [UUID: String]? = nil
}

extension Workspace {
    static var empty: Workspace {
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

enum AppSection: String, CaseIterable, Identifiable, Sendable {
    case overview = "Overview"
    case listing = "Store listing"
    case screenshots = "Screenshots"
    case pricing = "PPP pricing"
    case reviews = "Customer reviews"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .overview: "rectangle.grid.2x2"
        case .listing: "text.document"
        case .screenshots: "photo.on.rectangle.angled"
        case .pricing: "globe.europe.africa"
        case .reviews: "quote.bubble"
        }
    }
}

enum PlatformFilter: String, CaseIterable, Identifiable, Sendable {
    case both = "Both stores"
    case appStore = "App Store"
    case playStore = "Google Play"

    var id: String { rawValue }
    var platforms: Set<StorePlatform> {
        switch self {
        case .both: [.appStore, .playStore]
        case .appStore: [.appStore]
        case .playStore: [.playStore]
        }
    }
}

extension Color {
    init(hex: UInt) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: 1
        )
    }
}

func roundedCharmPrice(_ value: Double) -> Double {
    max(0.99, value.rounded(.down) + 0.99)
}

func localizedCharmPrice(_ value: Double, currency: String) -> Double {
    guard value > 0 else { return 0 }
    let zeroDecimalCurrencies: Set<String> = [
        "BIF", "CLP", "DJF", "GNF", "IDR", "ISK", "JPY", "KMF", "KRW", "PYG", "RWF", "UGX", "VND", "VUV", "XAF", "XOF", "XPF"
    ]
    if zeroDecimalCurrencies.contains(currency) {
        return max(1, value.rounded())
    }
    return max(0.01, value.rounded(.down) + 0.99)
}

func regionsRequiringPriceChange(_ regions: [PriceRegion]) -> [PriceRegion] {
    regions.filter {
        $0.enabled && abs($0.suggestedPrice - $0.currentPrice) > 0.000_001
    }
}

func pricingRegionEnabledByDefault(_ code: String) -> Bool {
    true
}

func storePriceValue(from input: String) -> Double? {
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

func canonicalStoreLocale(_ locale: String) -> String {
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

func primaryLocalization(
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

func googleLocale(forAppleLocale locale: String) -> String {
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

struct GooglePlayReleaseNote: Equatable, Sendable {
    var locale: String
    var text: String
}

let googlePlayReleaseNoteCharacterLimit = 500

func googlePlayReleaseNotes(in taggedBlock: String) -> [GooglePlayReleaseNote] {
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

func googlePlayReleaseNote(in taggedBlock: String, locale: String) -> String {
    googlePlayReleaseNotes(in: taggedBlock)
        .last(where: { canonicalStoreLocale($0.locale) == canonicalStoreLocale(locale) })?
        .text ?? ""
}

func replacingGooglePlayReleaseNote(
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

func googlePlayReleaseNotesValidationIssues(_ taggedBlock: String) -> [String] {
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

func listingLocalization(
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

func applyingListingMetadata(
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
