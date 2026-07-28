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
    case multipleDeveloperAccounts
    case pricingHistoryAndAuditLog
    case scheduledSynchronizationAndAutomation
    case agencyWorkflows
    case createAppStoreVersion
    case uploadGooglePlayBundle

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .applyRegionalPricing: "Apply regional pricing"
        case .bulkTranslations: "Bulk translations"
        case .multipleDeveloperAccounts: "Multiple developer accounts"
        case .pricingHistoryAndAuditLog: "Pricing history and audit log"
        case .scheduledSynchronizationAndAutomation: "Scheduled synchronization and automation"
        case .agencyWorkflows: "Agency workflows"
        case .createAppStoreVersion: "Create iOS versions"
        case .uploadGooglePlayBundle: "Create Android versions"
        }
    }

    public var upgradeDescription: String {
        switch self {
        case .applyRegionalPricing:
            "Calculate and preview PPP prices in Community, then use Pro to apply the reviewed prices directly to the stores."
        case .bulkTranslations:
            "Translate a selected locale in Community, or use Pro to translate fields and release notes across every locale in the current app."
        case .multipleDeveloperAccounts:
            "Connect and switch between multiple App Store Connect and Google Play developer accounts."
        case .pricingHistoryAndAuditLog:
            "Keep a reviewable history of pricing calculations, remote changes, and their outcomes."
        case .scheduledSynchronizationAndAutomation:
            "Schedule store synchronization and automate recurring operational work."
        case .agencyWorkflows:
            "Organize clients, accounts, permissions, and repeatable workflows for agency use."
        case .createAppStoreVersion:
            "Use Escale Pro to create a new editable iOS version directly in App Store Connect."
        case .uploadGooglePlayBundle:
            "Use Escale Pro to upload a signed Android App Bundle and create an editable Google Play draft release."
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
        false
    }
}
