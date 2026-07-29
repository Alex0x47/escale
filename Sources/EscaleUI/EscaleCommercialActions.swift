import Foundation
import SwiftUI

enum EscaleLinks {
    static let officialWebsite = URL(string: "https://www.useescale.com/")!
    static let officialDownloadPage = officialWebsite
    static let supportPage = URL(string: "https://www.useescale.com/support")!
}

/// Optional actions supplied by a commercial distribution of Escale.
///
/// The Community app deliberately leaves this environment value unset. A separate
/// distribution can provide its own purchase and licence-management experience
/// without adding commercial implementation details to the open-source package.
public struct EscaleCommercialActions: Sendable {
    public let openLicenceManagement: @MainActor @Sendable () -> Void
    public let promotionCheckoutURL: (@MainActor @Sendable (_ startedAt: Date) async -> URL?)?

    public init(
        openLicenceManagement: @escaping @MainActor @Sendable () -> Void,
        promotionCheckoutURL: (@MainActor @Sendable (_ startedAt: Date) async -> URL?)? = nil
    ) {
        self.openLicenceManagement = openLicenceManagement
        self.promotionCheckoutURL = promotionCheckoutURL
    }
}

private struct EscaleCommercialActionsKey: EnvironmentKey {
    static let defaultValue: EscaleCommercialActions? = nil
}

public extension EnvironmentValues {
    var escaleCommercialActions: EscaleCommercialActions? {
        get { self[EscaleCommercialActionsKey.self] }
        set { self[EscaleCommercialActionsKey.self] = newValue }
    }
}

public extension View {
    func escaleCommercialActions(_ actions: EscaleCommercialActions?) -> some View {
        environment(\.escaleCommercialActions, actions)
    }
}
