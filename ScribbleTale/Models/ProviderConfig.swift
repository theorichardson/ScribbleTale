import Foundation

enum ImageProviderType: String, CaseIterable, Identifiable {
    case local
    case openAI

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .local:  return "Image Playground"
        case .openAI: return "OpenAI (gpt-image-1)"
        }
    }

    var icon: String {
        switch self {
        case .local:  return "apple.logo"
        case .openAI: return "cloud"
        }
    }
}

@Observable
@MainActor
final class ProviderConfig {
    static let shared = ProviderConfig()

    var openAIKey: String {
        didSet { Self.saveKey(openAIKey) }
    }

    var imageProvider: ImageProviderType {
        didSet { UserDefaults.standard.set(imageProvider.rawValue, forKey: "imageProvider") }
    }

    private init() {
        self.openAIKey = Self.loadKey()
        let imgRaw = UserDefaults.standard.string(forKey: "imageProvider") ?? ImageProviderType.local.rawValue
        self.imageProvider = ImageProviderType(rawValue: imgRaw) ?? .local
    }

    var hasOpenAIKey: Bool { !openAIKey.isEmpty }

    // MARK: - Keychain storage for API key

    private static let keychainService = "com.scribbletale.openai"
    private static let keychainAccount = "api-key"

    private static func saveKey(_ key: String) {
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
        guard !key.isEmpty else { return }
        var addQuery = query
        addQuery[kSecValueData as String] = data
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private static func loadKey() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
