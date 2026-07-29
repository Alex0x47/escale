import CryptoKit
import Foundation
import Security

public struct AppleCredentials: Codable, Sendable {
    public let issuerID: String
    public let keyID: String
    public let privateKeyPEM: String
}

public struct GoogleServiceAccount: Codable, Sendable {
    public let type: String?
    public let projectID: String?
    public let privateKeyID: String
    public let privateKey: String
    public let clientEmail: String
    public let tokenURI: String

    public enum CodingKeys: String, CodingKey {
        case type
        case projectID = "project_id"
        case privateKeyID = "private_key_id"
        case privateKey = "private_key"
        case clientEmail = "client_email"
        case tokenURI = "token_uri"
    }
}

@MainActor
public enum CredentialStore {
    private static let service = "app.escale.mac.credentials"
    private static let legacyService = "app.gouvernail.mac.credentials"
    private static let ownedServicePrefixes = [
        "app.escale.mac.",
        "app.gouvernail.mac."
    ]
    private static let appleAccount = "app-store-connect"
    private static let googleAccount = "google-play-service-account"
    private static let openAIAccount = "openai-api-key"

    // Keychain remains the persistent source of truth. These values avoid
    // asking macOS to authorize the same item again for every API operation in
    // one app session, and are discarded automatically when the app exits.
    private static var cachedApple: AppleCredentials?
    private static var hasLoadedApple = false
    private static var cachedGoogle: GoogleServiceAccount?
    private static var hasLoadedGoogle = false
    private static var cachedOpenAIAPIKey: String?
    private static var hasLoadedOpenAIAPIKey = false

    public static func saveApple(_ credentials: AppleCredentials) throws {
        try KeychainStore.save(try JSONEncoder().encode(credentials), service: service, account: appleAccount)
        cachedApple = credentials
        hasLoadedApple = true
    }

    public static func apple() throws -> AppleCredentials? {
        if hasLoadedApple { return cachedApple }
        guard let data = try readMigrating(account: appleAccount) else {
            hasLoadedApple = true
            return nil
        }
        let credentials = try JSONDecoder().decode(AppleCredentials.self, from: data)
        cachedApple = credentials
        hasLoadedApple = true
        return credentials
    }

    public static func saveGoogle(_ credentials: GoogleServiceAccount) throws {
        try KeychainStore.save(try JSONEncoder().encode(credentials), service: service, account: googleAccount)
        cachedGoogle = credentials
        hasLoadedGoogle = true
    }

    public static func google() throws -> GoogleServiceAccount? {
        if hasLoadedGoogle { return cachedGoogle }
        guard let data = try readMigrating(account: googleAccount) else {
            hasLoadedGoogle = true
            return nil
        }
        let credentials = try JSONDecoder().decode(GoogleServiceAccount.self, from: data)
        cachedGoogle = credentials
        hasLoadedGoogle = true
        return credentials
    }

    public static func saveOpenAIAPIKey(_ apiKey: String) throws {
        let clean = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 20 else {
            throw APIError.invalidCredentials("Enter a complete OpenAI API key.")
        }
        try KeychainStore.save(
            Data(clean.utf8),
            service: service,
            account: openAIAccount,
            accessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        )
        cachedOpenAIAPIKey = clean
        hasLoadedOpenAIAPIKey = true
    }

    public static func openAIAPIKey() throws -> String? {
        if hasLoadedOpenAIAPIKey { return cachedOpenAIAPIKey }
        guard let data = try readMigrating(
            account: openAIAccount,
            accessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ) else {
            hasLoadedOpenAIAPIKey = true
            return nil
        }
        guard let value = String(data: data, encoding: .utf8), !value.isEmpty else { return nil }
        cachedOpenAIAPIKey = value
        hasLoadedOpenAIAPIKey = true
        return value
    }

    public static func removeOpenAIAPIKey() throws {
        try KeychainStore.delete(service: service, account: openAIAccount)
        try KeychainStore.delete(service: legacyService, account: openAIAccount)
        cachedOpenAIAPIKey = nil
        hasLoadedOpenAIAPIKey = true
    }

    public static func remove(_ platform: StorePlatform) throws {
        let account = platform == .appStore ? appleAccount : googleAccount
        try KeychainStore.delete(service: service, account: account)
        try KeychainStore.delete(service: legacyService, account: account)
        if platform == .appStore {
            cachedApple = nil
            hasLoadedApple = true
        } else {
            cachedGoogle = nil
            hasLoadedGoogle = true
        }
    }

    public static func removeAllEscaleItems() throws {
        try KeychainStore.deleteServices(withPrefixes: ownedServicePrefixes)
        cachedApple = nil
        hasLoadedApple = true
        cachedGoogle = nil
        hasLoadedGoogle = true
        cachedOpenAIAPIKey = nil
        hasLoadedOpenAIAPIKey = true
    }

    private static func readMigrating(
        account: String,
        accessible: CFString = kSecAttrAccessibleAfterFirstUnlock
    ) throws -> Data? {
        if let data = try KeychainStore.read(service: service, account: account) {
            return data
        }
        guard let legacyData = try KeychainStore.read(service: legacyService, account: account) else {
            return nil
        }
        try KeychainStore.save(
            legacyData,
            service: service,
            account: account,
            accessible: accessible
        )
        return legacyData
    }
}

public enum KeychainStore {
    public static func save(
        _ data: Data,
        service: String,
        account: String,
        accessible: CFString = kSecAttrAccessibleAfterFirstUnlock
    ) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessible
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            attributes.forEach { add[$0.key] = $0.value }
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw APIError.keychain(addStatus) }
        } else if status != errSecSuccess {
            throw APIError.keychain(status)
        }
    }

    public static func read(service: String, account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw APIError.keychain(status) }
        return data
    }

    public static func delete(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw APIError.keychain(status) }
    }

    public static func deleteServices(withPrefixes prefixes: [String]) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return }
        guard status == errSecSuccess else { throw APIError.keychain(status) }

        let attributes = result as? [[String: Any]] ?? []
        let services = escaleOwnedKeychainServices(
            in: attributes.compactMap { $0[kSecAttrService as String] as? String },
            prefixes: prefixes
        )
        for service in services {
            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service
            ]
            let deleteStatus = SecItemDelete(deleteQuery as CFDictionary)
            guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
                throw APIError.keychain(deleteStatus)
            }
        }
    }
}

func escaleOwnedKeychainServices(in services: [String], prefixes: [String]) -> Set<String> {
    Set(services.filter { service in
        prefixes.contains(where: service.hasPrefix)
    })
}

public enum APIError: LocalizedError, Sendable {
    case missingCredentials(StorePlatform)
    case invalidCredentials(String)
    case invalidResponse
    case http(status: Int, message: String)
    case keychain(OSStatus)
    case signing(String)
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case .missingCredentials(let platform): "Connect \(platform.rawValue) before continuing."
        case .invalidCredentials(let message): "Invalid credentials: \(message)"
        case .invalidResponse: "The store returned an unreadable response."
        case .http(let status, let message): "Store request failed (HTTP \(status)): \(message)"
        case .keychain(let status): "Keychain operation failed (\(status))."
        case .signing(let message): "Could not sign the authorization token: \(message)"
        case .unsupported(let message): message
        }
    }
}

public enum JWTSigner {
    public static func appleToken(credentials: AppleCredentials, now: Date = Date()) throws -> String {
        let header: [String: Any] = ["alg": "ES256", "kid": credentials.keyID, "typ": "JWT"]
        let issuedAt = Int(now.timeIntervalSince1970)
        let claims: [String: Any] = [
            "iss": credentials.issuerID,
            "iat": issuedAt,
            "exp": issuedAt + 20 * 60,
            "aud": "appstoreconnect-v1"
        ]
        let signingInput = try jwtInput(header: header, claims: claims)
        do {
            let key = try P256.Signing.PrivateKey(pemRepresentation: credentials.privateKeyPEM)
            let signature = try key.signature(for: Data(signingInput.utf8))
            return signingInput + "." + signature.rawRepresentation.base64URLEncodedString()
        } catch {
            throw APIError.signing(error.localizedDescription)
        }
    }

    public static func googleAssertion(credentials: GoogleServiceAccount, now: Date = Date()) throws -> String {
        let header: [String: Any] = ["alg": "RS256", "typ": "JWT", "kid": credentials.privateKeyID]
        let issuedAt = Int(now.timeIntervalSince1970)
        let claims: [String: Any] = [
            "iss": credentials.clientEmail,
            "scope": "https://www.googleapis.com/auth/androidpublisher",
            "aud": credentials.tokenURI,
            "iat": issuedAt,
            "exp": issuedAt + 3_600
        ]
        let signingInput = try jwtInput(header: header, claims: claims)
        let key = try rsaPrivateKey(from: credentials.privateKey)
        var signingError: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            key,
            .rsaSignatureMessagePKCS1v15SHA256,
            Data(signingInput.utf8) as CFData,
            &signingError
        ) as Data? else {
            throw APIError.signing(signingError?.takeRetainedValue().localizedDescription ?? "RSA signing failed")
        }
        return signingInput + "." + signature.base64URLEncodedString()
    }

    private static func jwtInput(header: [String: Any], claims: [String: Any]) throws -> String {
        let options: JSONSerialization.WritingOptions = [.sortedKeys, .withoutEscapingSlashes]
        let headerData = try JSONSerialization.data(withJSONObject: header, options: options)
        let claimsData = try JSONSerialization.data(withJSONObject: claims, options: options)
        return headerData.base64URLEncodedString() + "." + claimsData.base64URLEncodedString()
    }

    private static func rsaPrivateKey(from pem: String) throws -> SecKey {
        let pemData = Data(pem.utf8)
        var format = SecExternalFormat.formatUnknown
        var itemType = SecExternalItemType.itemTypeUnknown
        var items: CFArray?
        let importStatus = SecItemImport(pemData as CFData, nil, &format, &itemType, [], nil, nil, &items)
        if importStatus == errSecSuccess, let imported = items as? [SecKey], let key = imported.first {
            return key
        }

        let stripped = pem
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        guard let der = Data(base64Encoded: stripped) else {
            throw APIError.invalidCredentials("The Google private key is not valid PEM.")
        }
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(der as CFData, attributes as CFDictionary, &error) else {
            throw APIError.signing(error?.takeRetainedValue().localizedDescription ?? "Unable to import the RSA key")
        }
        return key
    }
}

extension Data {
    public func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

public struct HTTPResponse: Sendable {
    public let data: Data
    public let response: HTTPURLResponse
}

public enum HTTPTransport {
    public static func send(
        url: URL,
        method: String = "GET",
        headers: [String: String] = [:],
        body: Data? = nil,
        timeout: TimeInterval = 60
    ) async throws -> HTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = timeout
        request.setValue("Escale/0.2 macOS", forHTTPHeaderField: "User-Agent")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard 200..<300 ~= http.statusCode else {
            throw APIError.http(status: http.statusCode, message: errorMessage(from: data))
        }
        return HTTPResponse(data: data, response: http)
    }

    public static func upload(
        url: URL,
        method: String = "POST",
        headers: [String: String] = [:],
        fileURL: URL,
        timeout: TimeInterval = 120
    ) async throws -> HTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue("Escale/0.2 macOS", forHTTPHeaderField: "User-Agent")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, response) = try await URLSession.shared.upload(for: request, fromFile: fileURL)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard 200..<300 ~= http.statusCode else {
            throw APIError.http(status: http.statusCode, message: errorMessage(from: data))
        }
        return HTTPResponse(data: data, response: http)
    }

    public static func jsonBody(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
    }

    private static func errorMessage(from data: Data) -> String {
        guard !data.isEmpty else { return "No error details were returned." }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let errors = object["errors"] as? [[String: Any]], let first = errors.first {
                return (first["detail"] as? String) ?? (first["title"] as? String) ?? "Unknown App Store Connect error"
            }
            if let error = object["error"] as? [String: Any] {
                return (error["message"] as? String) ?? (error["status"] as? String) ?? "Unknown Google Play error"
            }
            if let description = object["error_description"] as? String { return description }
        }
        return String(data: data, encoding: .utf8) ?? "Unknown store error"
    }
}

extension URL {
    public func appendingQueryItems(_ items: [URLQueryItem]) -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        components.queryItems = (components.queryItems ?? []) + items
        return components.url ?? self
    }
}
