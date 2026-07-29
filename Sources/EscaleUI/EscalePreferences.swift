import EscaleCore

enum EscalePreferences {
    static let preferredPricingIndexKey = "escale.preferred-pricing-index.v1"

    static func preferredPricingIndex(from storedValue: String) -> PricingIndex {
        PricingIndex(rawValue: storedValue) ?? .worldwidePPP
    }
}
