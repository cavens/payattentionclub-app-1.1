import Foundation
import Security
import Auth

/// Secure Keychain-based localStorage implementation for Supabase Auth
/// Migrates from UserDefaults to Keychain for better security
final class KeychainManager: AuthLocalStorage, @unchecked Sendable {
    static let shared = KeychainManager()
    
    private let service: String
    
    /// Initialize KeychainManager
    /// - Parameter service: Keychain service identifier (defaults to app bundle ID)
    init(service: String? = nil) {
        // Use provided service or fallback to bundle ID
        if let service = service {
            self.service = service
        } else if let bundleId = Bundle.main.bundleIdentifier {
            self.service = bundleId
        } else {
            // Fallback if bundle ID not available
            self.service = "com.payattentionclub.app"
        }
    }
    
    /// Store data in Keychain
    /// - Parameters:
    ///   - key: The key to store the data under
    ///   - value: The data to store
    /// - Throws: KeychainError if storage fails
    func store(key: String, value: Data) throws {
        // Delete existing item if it exists (to update)
        try? remove(key: key)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: value,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw KeychainError.storeFailed(status: status)
        }
    }
    
    /// Retrieve data from Keychain
    /// - Parameter key: The key to retrieve
    /// - Returns: The stored data, or nil if not found
    /// - Throws: KeychainError if retrieval fails
    func retrieve(key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecItemNotFound {
            return nil
        }
        
        guard status == errSecSuccess else {
            throw KeychainError.retrieveFailed(status: status)
        }
        
        return result as? Data
    }
    
    /// Remove data from Keychain
    /// - Parameter key: The key to remove
    /// - Throws: KeychainError if removal fails
    func remove(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        // errSecItemNotFound is OK (item already deleted)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.removeFailed(status: status)
        }
    }
    
    /// Clear all items stored by this KeychainManager
    /// Useful for logout or testing
    func clearAll() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        // errSecItemNotFound is OK (no items to delete)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.removeFailed(status: status)
        }
    }
    
    /// Migrate data from UserDefaults to Keychain
    /// Call this once on app launch to migrate existing tokens
    /// - Parameter keys: Array of keys to migrate from UserDefaults
    static func migrateFromUserDefaults(keys: [String]) {
        let userDefaults = UserDefaults.standard
        
        for key in keys {
            // Check if already in Keychain
            if let _ = try? KeychainManager.shared.retrieve(key: key) {
                // Already migrated, skip
                continue
            }
            
            // Try to get from UserDefaults
            if let data = userDefaults.data(forKey: key) {
                do {
                    // Store in Keychain
                    try KeychainManager.shared.store(key: key, value: data)
                    
                    // Remove from UserDefaults after successful migration
                    userDefaults.removeObject(forKey: key)
                    NSLog("KEYCHAIN: ✅ Migrated key '\(key)' from UserDefaults to Keychain")
                } catch {
                    NSLog("KEYCHAIN: ⚠️ Failed to migrate key '\(key)': \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - Keychain Errors

enum KeychainError: LocalizedError {
    case storeFailed(status: OSStatus)
    case retrieveFailed(status: OSStatus)
    case removeFailed(status: OSStatus)
    
    var errorDescription: String? {
        switch self {
        case .storeFailed(let status):
            return "Failed to store item in Keychain. Status: \(status)"
        case .retrieveFailed(let status):
            return "Failed to retrieve item from Keychain. Status: \(status)"
        case .removeFailed(let status):
            return "Failed to remove item from Keychain. Status: \(status)"
        }
    }
    
    /// Human-readable description of OSStatus error codes
    static func description(for status: OSStatus) -> String {
        switch status {
        case errSecSuccess:
            return "Success"
        case errSecItemNotFound:
            return "Item not found"
        case errSecDuplicateItem:
            return "Duplicate item"
        case errSecAuthFailed:
            return "Authentication failed"
        case errSecParam:
            return "Invalid parameter"
        case errSecAllocate:
            return "Memory allocation failed"
        case errSecNotAvailable:
            return "Keychain not available"
        case errSecDecode:
            return "Decode error"
        case errSecInteractionNotAllowed:
            return "Interaction not allowed"
        case errSecReadOnly:
            return "Read-only attribute"
        default:
            return "Unknown error: \(status)"
        }
    }
}

