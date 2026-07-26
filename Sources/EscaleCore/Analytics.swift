import Foundation

public enum EscaleAnalyticsResult: String, Sendable {
    case success
    case partial
    case failure
    case blocked
}

public enum EscaleAnalyticsFailureCategory: String, Sendable {
    case invalidInput = "invalid_input"
    case missingCredentials = "missing_credentials"
    case authentication
    case authorization
    case network
    case remoteAPI = "remote_api"
    case secureStorage = "secure_storage"
    case unavailable
    case licenceInvalid = "licence_invalid"
    case activationLimit = "activation_limit"
    case subscriptionEnded = "subscription_ended"
    case paymentReversed = "payment_reversed"
    case unknown
}

public enum EscaleAnalyticsTranslationKind: String, Sendable {
    case listing
    case field
    case releaseNotes = "release_notes"
}

public enum EscaleAnalyticsScope: String, Sendable {
    case apple
    case google
    case both
    case single
    case bulk
}

public enum EscaleAnalyticsScreenshotOperation: String, Sendable {
    case upload
    case delete
}

public enum EscaleCommercialPlan: String, Sendable {
    case yearly
    case lifetime
}

/// A deliberately bounded analytics schema.
///
/// Associated values contain only coarse operational metadata. Store content,
/// account identifiers, app identifiers, credentials, user text, file paths,
/// prices, and licence keys have no representation in this type.
public enum EscaleAnalyticsEvent: Sendable {
    case appLaunched
    case onboardingStepCompleted(step: Int)
    case onboardingCompleted(connectedStoresBucket: String, linkedAppsBucket: String)
    case demoModeStarted
    case storeConnectionCompleted(
        platform: StorePlatform,
        result: EscaleAnalyticsResult,
        appCountBucket: String?,
        failure: EscaleAnalyticsFailureCategory?
    )
    case applicationLinked(result: EscaleAnalyticsResult)
    case translationCompleted(
        kind: EscaleAnalyticsTranslationKind,
        scope: EscaleAnalyticsScope,
        result: EscaleAnalyticsResult,
        targetCountBucket: String,
        failure: EscaleAnalyticsFailureCategory?
    )
    case listingSaveCompleted(
        scope: EscaleAnalyticsScope,
        result: EscaleAnalyticsResult,
        failure: EscaleAnalyticsFailureCategory?
    )
    case screenshotOperationCompleted(
        operation: EscaleAnalyticsScreenshotOperation,
        scope: EscaleAnalyticsScope,
        result: EscaleAnalyticsResult,
        failure: EscaleAnalyticsFailureCategory?
    )
    case pricingPreviewCompleted(
        index: PricingIndex,
        result: EscaleAnalyticsResult,
        marketCountBucket: String,
        failure: EscaleAnalyticsFailureCategory?
    )
    case pricingApplyCompleted(
        scope: EscaleAnalyticsScope,
        result: EscaleAnalyticsResult,
        failure: EscaleAnalyticsFailureCategory?
    )
    case reviewReplyCompleted(
        platform: StorePlatform,
        result: EscaleAnalyticsResult,
        failure: EscaleAnalyticsFailureCategory?
    )
    case manualSyncCompleted(
        scope: EscaleAnalyticsScope,
        result: EscaleAnalyticsResult,
        failure: EscaleAnalyticsFailureCategory?
    )
    case appRefreshCompleted(
        scope: EscaleAnalyticsScope,
        result: EscaleAnalyticsResult
    )
    case proGateViewed(feature: EscaleFeature)
    case purchaseLinkOpened(plan: EscaleCommercialPlan)
    case licenceActivationCompleted(
        plan: EscaleCommercialPlan?,
        result: EscaleAnalyticsResult,
        failure: EscaleAnalyticsFailureCategory?
    )
    case licenceDeactivationCompleted(
        plan: EscaleCommercialPlan,
        result: EscaleAnalyticsResult,
        failure: EscaleAnalyticsFailureCategory?
    )

    public var name: String {
        switch self {
        case .appLaunched: "app_launched"
        case .onboardingStepCompleted: "onboarding_step_completed"
        case .onboardingCompleted: "onboarding_completed"
        case .demoModeStarted: "demo_mode_started"
        case .storeConnectionCompleted: "store_connection_completed"
        case .applicationLinked: "application_linked"
        case .translationCompleted: "translation_completed"
        case .listingSaveCompleted: "listing_save_completed"
        case .screenshotOperationCompleted: "screenshot_operation_completed"
        case .pricingPreviewCompleted: "pricing_preview_completed"
        case .pricingApplyCompleted: "pricing_apply_completed"
        case .reviewReplyCompleted: "review_reply_completed"
        case .manualSyncCompleted: "manual_sync_completed"
        case .appRefreshCompleted: "app_refresh_completed"
        case .proGateViewed: "pro_gate_viewed"
        case .purchaseLinkOpened: "purchase_link_opened"
        case .licenceActivationCompleted: "licence_activation_completed"
        case .licenceDeactivationCompleted: "licence_deactivation_completed"
        }
    }

    public var properties: [String: String] {
        switch self {
        case .appLaunched, .demoModeStarted:
            [:]
        case .onboardingStepCompleted(let step):
            ["step": String(step)]
        case .onboardingCompleted(let connectedStoresBucket, let linkedAppsBucket):
            [
                "connected_stores_bucket": connectedStoresBucket,
                "linked_apps_bucket": linkedAppsBucket
            ]
        case .storeConnectionCompleted(let platform, let result, let appCountBucket, let failure):
            Self.compact([
                "platform": platform.analyticsName,
                "result": result.rawValue,
                "app_count_bucket": appCountBucket,
                "failure_category": failure?.rawValue
            ])
        case .applicationLinked(let result):
            ["result": result.rawValue]
        case .translationCompleted(let kind, let scope, let result, let targetCountBucket, let failure):
            Self.compact([
                "kind": kind.rawValue,
                "scope": scope.rawValue,
                "result": result.rawValue,
                "target_count_bucket": targetCountBucket,
                "failure_category": failure?.rawValue
            ])
        case .listingSaveCompleted(let scope, let result, let failure):
            Self.resultProperties(scope: scope, result: result, failure: failure)
        case .screenshotOperationCompleted(let operation, let scope, let result, let failure):
            Self.compact([
                "operation": operation.rawValue,
                "scope": scope.rawValue,
                "result": result.rawValue,
                "failure_category": failure?.rawValue
            ])
        case .pricingPreviewCompleted(let index, let result, let marketCountBucket, let failure):
            Self.compact([
                "index": index.rawValue,
                "result": result.rawValue,
                "market_count_bucket": marketCountBucket,
                "failure_category": failure?.rawValue
            ])
        case .pricingApplyCompleted(let scope, let result, let failure),
             .manualSyncCompleted(let scope, let result, let failure):
            Self.resultProperties(scope: scope, result: result, failure: failure)
        case .reviewReplyCompleted(let platform, let result, let failure):
            Self.compact([
                "platform": platform.analyticsName,
                "result": result.rawValue,
                "failure_category": failure?.rawValue
            ])
        case .appRefreshCompleted(let scope, let result):
            ["scope": scope.rawValue, "result": result.rawValue]
        case .proGateViewed(let feature):
            ["feature": feature.rawValue]
        case .purchaseLinkOpened(let plan):
            ["commercial_plan": plan.rawValue]
        case .licenceActivationCompleted(let plan, let result, let failure):
            Self.compact([
                "commercial_plan": plan?.rawValue,
                "result": result.rawValue,
                "failure_category": failure?.rawValue
            ])
        case .licenceDeactivationCompleted(let plan, let result, let failure):
            Self.compact([
                "commercial_plan": plan.rawValue,
                "result": result.rawValue,
                "failure_category": failure?.rawValue
            ])
        }
    }

    public static func countBucket(_ count: Int) -> String {
        switch count {
        case ...0: "0"
        case 1: "1"
        case 2: "2"
        case 3...5: "3-5"
        case 6...10: "6-10"
        default: "11+"
        }
    }

    public static func scope(for platforms: Set<StorePlatform>) -> EscaleAnalyticsScope {
        if platforms == [.appStore] { return .apple }
        if platforms == [.playStore] { return .google }
        return .both
    }

    public static func failureCategory(for error: Error) -> EscaleAnalyticsFailureCategory {
        if let apiError = error as? APIError {
            switch apiError {
            case .missingCredentials: return .missingCredentials
            case .invalidCredentials: return .invalidInput
            case .invalidResponse: return .remoteAPI
            case .http(let status, _):
                if status == 401 { return .authentication }
                if status == 403 { return .authorization }
                return .remoteAPI
            case .keychain: return .secureStorage
            case .signing: return .authentication
            case .unsupported: return .unavailable
            }
        }
        if let openAIError = error as? OpenAIClientError {
            switch openAIError {
            case .missingAPIKey:
                return .missingCredentials
            case .api(let status, _):
                if status == 401 { return .authentication }
                if status == 403 { return .authorization }
                return .remoteAPI
            case .invalidResponse, .invalidStructuredOutput, .incomplete, .refused:
                return .remoteAPI
            }
        }
        if error is URLError { return .network }
        if error is DecodingError { return .remoteAPI }
        return .unknown
    }

    private static func resultProperties(
        scope: EscaleAnalyticsScope,
        result: EscaleAnalyticsResult,
        failure: EscaleAnalyticsFailureCategory?
    ) -> [String: String] {
        Self.compact([
            "scope": scope.rawValue,
            "result": result.rawValue,
            "failure_category": failure?.rawValue
        ])
    }

    private static func compact(_ values: [String: String?]) -> [String: String] {
        values.compactMapValues { $0 }
    }
}

public protocol EscaleAnalyticsProviding: Sendable {
    var isAvailable: Bool { get }
    var serviceName: String { get }
    var isEnabled: Bool { get }

    func setEnabled(_ enabled: Bool)
    func capture(_ event: EscaleAnalyticsEvent, plan: EscalePlan)
}

public struct NoOpEscaleAnalytics: EscaleAnalyticsProviding {
    public let isAvailable = false
    public let serviceName = ""
    public let isEnabled = false

    public init() {}

    public func setEnabled(_ enabled: Bool) {}
    public func capture(_ event: EscaleAnalyticsEvent, plan: EscalePlan) {}
}

private extension StorePlatform {
    var analyticsName: String {
        switch self {
        case .appStore: "apple"
        case .playStore: "google"
        }
    }
}
