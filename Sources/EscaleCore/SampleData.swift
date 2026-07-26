import Foundation

public enum SampleData {
    public static let appID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    public static let secondAppID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    public static func workspace() -> Workspace {
        let app = UnifiedApp(
            id: appID,
            name: "Northstar Journal",
            symbol: "sparkles",
            tintHex: 0x6857E5,
            appStoreApp: StoreApp(
                id: UUID(), platform: .appStore, name: "Northstar Journal",
                bundleID: "com.acme.northstar", storeID: "6479357934",
                version: "2.4.0", state: .ready, versionID: nil, appInfoID: nil
            ),
            playStoreApp: StoreApp(
                id: UUID(), platform: .playStore, name: "Northstar Journal",
                bundleID: "com.acme.northstar", storeID: "com.acme.northstar",
                version: "2.4.0", state: .review, versionID: nil, appInfoID: nil
            )
        )
        let second = UnifiedApp(
            id: secondAppID,
            name: "Luma Habits",
            symbol: "sun.max.fill",
            tintHex: 0xF08A40,
            appStoreApp: StoreApp(
                id: UUID(), platform: .appStore, name: "Luma Habits",
                bundleID: "app.luma.habits", storeID: "6451102188",
                version: "1.8.2", state: .draft, versionID: nil, appInfoID: nil
            ),
            playStoreApp: nil
        )

        return Workspace(
            connections: [
                StoreConnection(platform: .appStore, accountName: "Acme Studio", detail: "Issuer …8A31 · 12 apps", state: .connected, lastSync: Date()),
                StoreConnection(platform: .playStore, accountName: "Acme Mobile", detail: "Service account · 8 apps", state: .connected, lastSync: Date())
            ],
            apps: [app, second],
            localizationsByApp: [
                appID: localizations(), secondAppID: localizations().map { item in
                    var copy = item
                    copy.title = "Luma Habits"
                    return copy
                }
            ],
            screenshotsByApp: [appID: screenshots()],
            productsByApp: [appID: products()],
            reviewsByApp: [appID: reviews()]
        )
    }

    public static func localizations() -> [ListingLocalization] {
        [
            ListingLocalization(
                id: UUID(), locale: "en-US", language: "English (US)", title: "Northstar Journal",
                subtitle: "Reflect. Focus. Grow.",
                promotionalText: "Turn small daily reflections into meaningful progress with a private journal built for clarity.",
                description: "Northstar is your calm space for daily journaling, guided reflection, and mindful goal setting. Capture thoughts in seconds, discover patterns over time, and keep your personal journey private across all your devices.",
                keywords: "journal,diary,mindfulness,habits,reflection,goals",
                releaseNotes: "A calmer writing experience, smarter weekly insights, and faster sync across devices.",
                dirtyPlatforms: [], lastSaved: Date(), appleVersionLocalizationID: nil, appleAppInfoLocalizationID: nil, googleLanguage: "en-US"
            ),
            ListingLocalization(
                id: UUID(), locale: "fr-FR", language: "French", title: "Northstar Journal",
                subtitle: "Réfléchissez. Avancez.",
                promotionalText: "Transformez de petites réflexions quotidiennes en progrès durables.",
                description: "Northstar est votre espace apaisant pour écrire, prendre du recul et avancer vers vos objectifs.",
                keywords: "journal,intime,bien-être,habitudes,objectifs",
                releaseNotes: "Une écriture plus fluide, de nouveaux bilans hebdomadaires et une synchronisation accélérée.",
                dirtyPlatforms: [], lastSaved: Date(), appleVersionLocalizationID: nil, appleAppInfoLocalizationID: nil, googleLanguage: "fr-FR"
            ),
            ListingLocalization(
                id: UUID(), locale: "de-DE", language: "German", title: "Northstar Journal",
                subtitle: "Reflektieren. Wachsen.", promotionalText: "", description: "",
                keywords: "", releaseNotes: "", dirtyPlatforms: [], lastSaved: nil, appleVersionLocalizationID: nil, appleAppInfoLocalizationID: nil, googleLanguage: "de-DE"
            ),
            ListingLocalization(
                id: UUID(), locale: "ja-JP", language: "Japanese", title: "Northstar Journal",
                subtitle: "振り返り、集中し、成長する。", promotionalText: "", description: "",
                keywords: "", releaseNotes: "", dirtyPlatforms: [], lastSaved: nil, appleVersionLocalizationID: nil, appleAppInfoLocalizationID: nil, googleLanguage: "ja-JP"
            )
        ]
    }

    public static func screenshots() -> [StoreScreenshot] {
        let data: [(StorePlatform, String, String, String, UInt, UInt)] = [
            (.appStore, "iPhone 6.9\"", "Make space for what matters", "A calmer daily journal", 0x6657D9, 0x9A8CFA),
            (.appStore, "iPhone 6.9\"", "See your week clearly", "Gentle patterns, not pressure", 0x285B8F, 0x59A7C9),
            (.appStore, "iPhone 6.9\"", "Your thoughts stay yours", "Private by design", 0x275F52, 0x69B69F),
            (.playStore, "Phone", "A journal that meets you here", "Capture a thought in seconds", 0xC56F42, 0xF0B36F)
        ]
        return data.map { platform, device, title, caption, start, end in
            StoreScreenshot(id: UUID(), platform: platform, locale: "en-US", device: device, title: title, caption: caption, gradientStartHex: start, gradientEndHex: end, remoteID: nil, remoteURL: nil, screenshotSetID: nil)
        }
    }

    public static func products() -> [StoreProduct] {
        let regionData: [(String, String, String, String, Double)] = [
            ("US", "United States", "🇺🇸", "USD", 1.00),
            ("GB", "United Kingdom", "🇬🇧", "GBP", 0.86),
            ("DE", "Germany", "🇩🇪", "EUR", 0.91),
            ("BR", "Brazil", "🇧🇷", "BRL", 0.43),
            ("IN", "India", "🇮🇳", "INR", 0.28),
            ("JP", "Japan", "🇯🇵", "JPY", 0.74),
            ("MX", "Mexico", "🇲🇽", "MXN", 0.48),
            ("ZA", "South Africa", "🇿🇦", "ZAR", 0.45)
        ]
        let regions: [PriceRegion] = regionData.map { code, country, flag, currency, index in
            PriceRegion(
                code: code, country: country, flag: flag, currency: currency,
                pppIndex: index, currentPrice: 59.99, suggestedPrice: roundedCharmPrice(59.99 * index),
                enabled: pricingRegionEnabledByDefault(code)
            )
        }
        return [
            StoreProduct(id: UUID(), name: "Northstar Plus — Annual", productID: "plus.annual", kind: "Auto-renewable subscription", basePrice: 59.99, platforms: [.appStore, .playStore], regions: regions, appleProductID: nil, googleProductID: "plus.annual", googleBasePlanID: "annual"),
            StoreProduct(id: UUID(), name: "Northstar Plus — Monthly", productID: "plus.monthly", kind: "Auto-renewable subscription", basePrice: 7.99, platforms: [.appStore, .playStore], regions: regions.map { var region = $0; region.currentPrice = 7.99; region.suggestedPrice = roundedCharmPrice(7.99 * region.pppIndex); return region }, appleProductID: nil, googleProductID: "plus.monthly", googleBasePlanID: "monthly")
        ]
    }

    public static func reviews() -> [CustomerReview] {
        [
            CustomerReview(id: UUID(), platform: .appStore, author: "Mia R.", countryCode: "US", rating: 5, title: "Finally a journal I keep using", body: "The weekly reflection is thoughtful without being overwhelming. The new sync feels instant too.", date: Date().addingTimeInterval(-7_200), version: "2.4.0", response: nil, remoteID: nil, responseRemoteID: nil),
            CustomerReview(id: UUID(), platform: .playStore, author: "Jonas", countryCode: "DE", rating: 4, title: "Beautiful and focused", body: "Very clean experience. I would love a homescreen widget for my daily prompt.", date: Date().addingTimeInterval(-86_400), version: "2.4.0", response: nil, remoteID: nil, responseRemoteID: nil),
            CustomerReview(id: UUID(), platform: .appStore, author: "Camille", countryCode: "FR", rating: 5, title: "Simple et apaisant", body: "J’aime beaucoup les bilans de la semaine. L’application est devenue un vrai rituel.", date: Date().addingTimeInterval(-172_800), version: "2.3.1", response: "Merci Camille — cela nous fait très plaisir. ✨", remoteID: nil, responseRemoteID: nil),
            CustomerReview(id: UUID(), platform: .playStore, author: "Aarav", countryCode: "IN", rating: 2, title: "Sync problem", body: "My last entry took a long time to appear on my tablet after the update.", date: Date().addingTimeInterval(-259_200), version: "2.3.1", response: nil, remoteID: nil, responseRemoteID: nil)
        ]
    }
}
