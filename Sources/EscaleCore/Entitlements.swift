import Foundation

public enum EscalePlan: String, Codable, Sendable {
    case community
    case pro

    public var displayName: String {
        switch self {
        case .community: "Escale Community"
        case .pro: "Escale Pro"
        }
    }
}

public enum EscaleFeature: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case applyRegionalPricing
    case bulkTranslations
    case createAppStoreVersion
    case uploadGooglePlayBundle
    case releaseNoteTemplates

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .applyRegionalPricing: "Apply regional pricing"
        case .bulkTranslations: "Bulk translations"
        case .createAppStoreVersion: "Create iOS versions"
        case .uploadGooglePlayBundle: "Create Android versions"
        case .releaseNoteTemplates: "What’s New templates"
        }
    }

    public var upgradeDescription: String {
        switch self {
        case .applyRegionalPricing:
            "Calculate and preview PPP prices in Community, then use Pro to apply the reviewed prices directly to the stores."
        case .bulkTranslations:
            "Translate a selected locale in Community, or use Pro to translate fields and release notes across every locale in the current app."
        case .createAppStoreVersion:
            "Create a new editable iOS version directly in App Store Connect with Escale Community or Pro."
        case .uploadGooglePlayBundle:
            "Use Escale Pro to upload a signed Android App Bundle and create an editable Google Play draft release."
        case .releaseNoteTemplates:
            "Stop rewriting the same release notes. Save your recurring What’s New copy once, then apply it in one click across App Store and Google Play listings with Escale Pro."
        }
    }
}

public protocol EscaleEntitlementProviding: Sendable {
    var plan: EscalePlan { get }
    func hasAccess(to feature: EscaleFeature) -> Bool
}

public struct CommunityEntitlements: EscaleEntitlementProviding {
    public let plan = EscalePlan.community

    public init() {}

    public func hasAccess(to feature: EscaleFeature) -> Bool {
        feature == .createAppStoreVersion
    }
}
